import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../services/device_extra_service.dart';
import '../services/device_info_service.dart';
import '../services/power_info_service.dart';
import '../services/storage_info_service.dart';

/// CubicDevice Info state: tab index, RAM sparkline sampling, refresh.
class DeviceInfoController extends GetxController {
  final tab = 0.obs; // 0 Dashboard … 5 Network
  final ramHistory = <double>[].obs; // used-fraction samples, cap 40
  final battHistory = <double>[].obs; // current-mA samples, cap 40
  final cpuCoreHistory = <int, List<double>>{}.obs; // coreIdx -> freq-fraction samples, cap 25
  final battLive = Rxn<Map<String, dynamic>>();
  final wifi = Rxn<Map<String, dynamic>>();
  final net = Rxn<Map<String, dynamic>>();
  final conn = Rxn<Map<String, dynamic>>();
  final display = Rxn<Map<String, dynamic>>();
  final mem = Rxn<Map<String, int>>();
  final sysParts = Rxn<Map<String, dynamic>>();
  final cameras = Rxn<List<Map<String, dynamic>>>();
  final sensors = Rxn<List<Map<String, dynamic>>>();
  final thermal = Rxn<Map<String, dynamic>>();
  final apps = Rxn<List<Map<String, dynamic>>>();
  final loading = true.obs;
  /// Bumped on every sampling pass. History Obxs read this FIRST —
  /// RxList/RxMap element reads alone have proven unreliable as the
  /// sole subscription (blank waves until remount), so this counter
  /// guarantees repaints on fresh data.
  final paintVersion = 0.obs;
  final extras = Rxn<DeviceExtras>();
  final storage = Rxn<StorageStats>();
  final batteryLevel = (-1).obs;
  final batteryCharging = false.obs;
  final cpu = Rxn<Map<String, dynamic>>();

  Timer? _timer;
  var _tick = 0;

  @override
  void onInit() {
    super.onInit();
    refreshAll();
    // Live sampling while the page is open. The fast tick (2s) touches
    // only cheap live values (RAM, battery, thermal, waves); the
    // 12-channel extras bundle refreshes on the slow tick (~16s) so
    // tab switches and scrolling never wait behind native collectors.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tick++;
      try {
        final dev = Get.find<DeviceInfoService>();
        unawaited(dev.refreshMemoryInfo());
        final t = dev.totalRamGB.value;
        final a = dev.availableRamGB.value;
        if (t > 0) {
          ramHistory.add(((t - a) / t).clamp(0.0, 1.0));
          if (ramHistory.length > 40) {
            ramHistory.removeRange(0, ramHistory.length - 40);
          }
        }
      } catch (_) {}
      if (_tick % 8 == 0) refreshExtras();
      refreshBattLive();
      unawaited(_refreshThermal());
      _updateCpuCoreHistory();
      paintVersion.value++;
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> refreshAll() async {
    loading.value = true;
    paintVersion.value++;
    try {
      await Get.find<DeviceInfoService>().refreshMemoryInfo();
    } catch (_) {}
    await refreshExtras(force: true);
    await refreshBattLive(force: true);
    try {
      final dev = Get.find<DeviceInfoService>();
      final t = dev.totalRamGB.value;
      final a = dev.availableRamGB.value;
      if (t > 0) {
        final usage = ((t - a) / t).clamp(0.0, 1.0);
        if (ramHistory.isEmpty) {
          for (var i = 0; i < 20; i++) {
            final jitter = ((i % 3) - 1) * 0.008;
            ramHistory.add((usage + jitter).clamp(0.0, 1.0));
          }
        } else {
          ramHistory.add(usage);
          if (ramHistory.length > 40) {
            ramHistory.removeRange(0, ramHistory.length - 40);
          }
        }
      }
    } catch (_) {}
    loading.value = false;
  }

  /// /proc/meminfo is world-readable: full RAM + swap accounting
  /// with zero permissions and ~1ms cost.
  Map<String, int> _readMeminfo() {
    final m = <String, int>{};
    try {
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          m[parts[0].replaceAll(':', '')] =
              int.tryParse(parts[1]) ?? 0; // kB
        }
      }
    } catch (_) {}
    return m;
  }

  Future<void> refreshBattLive({bool force = false}) async {
    try {
      final m = await DeviceExtraService.getBattLive(force: force);
      if (m != null) {
        if (force || !identical(m, battLive.value)) {
          battLive.value = m;
        }
        final ua = (m['currentUa'] as num?)?.toDouble() ?? 0;
        battHistory.add(ua / 1000.0);
        if (battHistory.length > 40) {
          battHistory.removeRange(0, battHistory.length - 40);
        }
      }
    } catch (_) {}
  }

  /// Thermal zones move constantly (5s cache) but live outside the
  /// heavy extras bundle — refreshed on the fast tick.
  Future<void> _refreshThermal() async {
    try {
      _set(thermal, await DeviceExtraService.getThermalInfo(),
          force: false);
    } catch (_) {}
  }

  /// Assign-only-if-new: services return the SAME cached instance
  /// while fresh, so identical() skips the notify — without this the
  /// 2s timer rebuilds every tab (even off-screen PageView pages)
  /// and the page feels laggy.
  void _set<T>(Rxn<T> rx, T? v, {required bool force}) {
    if (v == null) return;
    if (force || !identical(v, rx.value)) rx.value = v;
  }

  /// All channel calls are independent — fetch concurrently so one
  /// slow collector (app icons, system bundle) never head-blocks the
  /// fast ones. Each fetch is individually guarded.
  Future<T?> _guard<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshExtras({bool force = false}) async {
    final results = await Future.wait([
      _guard(DeviceExtraService.get(force: force)),
      _guard(DeviceExtraService.getCpuInfo(force: force)),
      _guard(DeviceExtraService.getWifiInfo(force: force)),
      _guard(DeviceExtraService.getNetExtra(force: force)),
      _guard(DeviceExtraService.getConnInfo(force: force)),
      _guard(DeviceExtraService.getDisplayInfo(force: force)),
      _guard(DeviceExtraService.getThermalInfo(force: force)),
      _guard(DeviceExtraService.getSysParts(force: force)),
      _guard(DeviceExtraService.getCameraInfo(force: force)),
      _guard(DeviceExtraService.getSensorList(force: force)),
      _guard(DeviceExtraService.getAppList(force: force)),
      _guard(StorageInfoService.getStats(force: force)),
    ]);
    _set(extras, results[0] as DeviceExtras?,
        force: force);
    _set(cpu, results[1] as Map<String, dynamic>?,
        force: force);
    _set(wifi, results[2] as Map<String, dynamic>?,
        force: force);
    _set(net, results[3] as Map<String, dynamic>?,
        force: force);
    _set(conn, results[4] as Map<String, dynamic>?,
        force: force);
    _set(display, results[5] as Map<String, dynamic>?,
        force: force);
    _set(thermal, results[6] as Map<String, dynamic>?,
        force: force);
    // Static-ish snapshots: load once, refresh on demand.
    if (force || mem.value == null) {
      try {
        mem.value = _readMeminfo();
      } catch (_) {}
    }
    final sp = results[7] as Map<String, dynamic>?;
    if (sp != null && (force || sysParts.value == null)) {
      sysParts.value = sp;
    }
    final cm = results[8] as List<Map<String, dynamic>>?;
    if (cm != null && (force || cameras.value == null)) {
      cameras.value = cm;
    }
    final sn = results[9] as List<Map<String, dynamic>>?;
    if (sn != null && (force || sensors.value == null)) {
      sensors.value = sn;
    }
    final ap = results[10] as List<Map<String, dynamic>>?;
    if (ap != null && (force || apps.value == null)) {
      apps.value = ap;
    }
    try {
      _set(storage,
          await StorageInfoService.getStats(force: force),
          force: force);
    } catch (_) {}
    try {
      final b = await PowerInfoService.getBattery(force: force);
      if (b != null) {
        if (force || b.level != batteryLevel.value) {
          batteryLevel.value = b.level;
        }
        if (force || b.charging != batteryCharging.value) {
          batteryCharging.value = b.charging;
        }
      }
    } catch (_) {}
    _updateCpuCoreHistory();
  }

  void _updateCpuCoreHistory() {
    final freqs = extras.value?.cpuFreqsMHz ?? const [];
    if (freqs.isEmpty) return;

    final maxF = (cpu.value?['maxFreqs'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [];

    final newHist = Map<int, List<double>>.from(cpuCoreHistory);
    for (var i = 0; i < freqs.length; i++) {
      final mhz = freqs[i];
      final coreMax = (i < maxF.length && maxF[i] > 0) ? maxF[i] : 2800;
      final frac = mhz > 0 ? (mhz / coreMax).clamp(0.05, 1.0) : 0.05;

      final list = List<double>.from(newHist[i] ?? []);
      if (list.isEmpty) {
        for (var k = 0; k < 15; k++) {
          final jitter = ((k % 3) - 1) * 0.02;
          list.add((frac + jitter).clamp(0.05, 1.0));
        }
      } else {
        list.add(frac);
        if (list.length > 25) {
          list.removeAt(0);
        }
      }
      newHist[i] = list;
    }
    cpuCoreHistory.value = newHist;
  }
}
