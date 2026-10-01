import 'dart:async';

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
  final battLive = Rxn<Map<String, dynamic>>();
  final loading = true.obs;
  final extras = Rxn<DeviceExtras>();
  final storage = Rxn<StorageStats>();
  final batteryLevel = (-1).obs;
  final batteryCharging = false.obs;
  final cpu = Rxn<Map<String, dynamic>>();

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    refreshAll();
    // Live sampling while the page is open (RAM sparkline + CPU).
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
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
      refreshExtras();
      refreshBattLive();
    });
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> refreshAll() async {
    loading.value = true;
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
        ramHistory.add(((t - a) / t).clamp(0.0, 1.0));
      }
    } catch (_) {}
    loading.value = false;
  }

  Future<void> refreshBattLive({bool force = false}) async {
    try {
      final m = await DeviceExtraService.getBattLive(force: force);
      if (m != null) {
        battLive.value = m;
        final ua = (m['currentUa'] as num?)?.toDouble() ?? 0;
        battHistory.add(ua / 1000.0);
        if (battHistory.length > 40) {
          battHistory.removeRange(0, battHistory.length - 40);
        }
      }
    } catch (_) {}
  }

  Future<void> refreshExtras({bool force = false}) async {
    try {
      extras.value = await DeviceExtraService.get(force: force);
    } catch (_) {}
    try {
      cpu.value = await DeviceExtraService.getCpuInfo(force: force);
    } catch (_) {}
    try {
      storage.value =
          await StorageInfoService.getStats(force: force);
    } catch (_) {}
    try {
      final b = await PowerInfoService.getBattery(force: force);
      if (b != null) {
        batteryLevel.value = b.level;
        batteryCharging.value = b.charging;
      }
    } catch (_) {}
  }
}
