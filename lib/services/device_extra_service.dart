import 'package:flutter/services.dart';

/// Extra device telemetry for CubicDevice Info (Android native channel
/// `com.cubiclm.app/device`). Everything is best-effort: failures yield
/// null/-1 and the UI shows '—'. Cached briefly; refresh on demand.
class DeviceExtras {
  final List<int> cpuFreqsMHz;
  final int sensorCount;
  final int appCount;
  final int battVoltageMv;
  final double battTempC;
  final String battHealth;
  final String battTech;
  final int uptimeMs;
  final String kernelVersion;
  final String networkType;
  final String deviceName;
  final String androidId;
  final String phoneType; // or "PERMISSION"
  final String esim;
  final String mobileNet; // or "PERMISSION"

  const DeviceExtras({
    required this.cpuFreqsMHz,
    required this.sensorCount,
    required this.appCount,
    required this.battVoltageMv,
    required this.battTempC,
    required this.battHealth,
    required this.battTech,
    required this.uptimeMs,
    required this.kernelVersion,
    required this.networkType,
    required this.deviceName,
    required this.androidId,
    required this.phoneType,
    required this.esim,
    required this.mobileNet,
  });
}

class DeviceExtraService {
  static const _ch = MethodChannel('com.cubiclm.app/device');
  static DeviceExtras? _cache;
  static DateTime? _at;

  static Future<T?> _call<T>(String method) async {
    try {
      return await _ch.invokeMethod<T>(method);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _battCache;
  static DateTime? _battAt;

  /// Live battery snapshot for the graph (cached 5s — current moves).
  static Future<Map<String, dynamic>?> getBattLive(
      {bool force = false}) async {
    if (!force &&
        _battCache != null &&
        _battAt != null &&
        DateTime.now().difference(_battAt!).inSeconds < 5) {
      return _battCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('battLive');
      if (m == null) return _battCache;
      _battCache = Map<String, dynamic>.from(m);
      _battAt = DateTime.now();
      return _battCache;
    } catch (_) {
      return _battCache;
    }
  }

  static Map<String, dynamic>? _cpuCache;
  static DateTime? _cpuAt;

  /// CPU tab bundle: per-core min/max MHz, governor, EGL strings.
  /// Cached 15s (frequencies move constantly).
  static Future<Map<String, dynamic>?> getCpuInfo(
      {bool force = false}) async {
    if (!force &&
        _cpuCache != null &&
        _cpuAt != null &&
        DateTime.now().difference(_cpuAt!).inSeconds < 15) {
      return _cpuCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('cpuInfo');
      if (m == null) return _cpuCache;
      _cpuCache = Map<String, dynamic>.from(m);
      _cpuAt = DateTime.now();
      return _cpuCache;
    } catch (_) {
      return _cpuCache;
    }
  }

  static Map<String, dynamic>? _sysCache;
  static DateTime? _sysAt;

  /// Full System-tab bundle in one round-trip (cached 60s).
  static Future<Map<String, dynamic>?> getSystemInfo(
      {bool force = false}) async {
    if (!force &&
        _sysCache != null &&
        _sysAt != null &&
        DateTime.now().difference(_sysAt!).inSeconds < 60) {
      return _sysCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('systemInfo');
      if (m == null) return _sysCache;
      _sysCache = Map<String, dynamic>.from(m);
      _sysAt = DateTime.now();
      return _sysCache;
    } catch (_) {
      return _sysCache;
    }
  }

  static Future<DeviceExtras?> get({bool force = false}) async {
    if (!force &&
        _cache != null &&
        _at != null &&
        DateTime.now().difference(_at!).inSeconds < 15) {
      return _cache;
    }
    try {
      final freqs =
          await _ch.invokeListMethod<int>('cpuFreqsMHz') ?? const [];
      final ex = DeviceExtras(
        cpuFreqsMHz: freqs,
        sensorCount: (await _call<int>('sensorCount')) ?? -1,
        appCount: (await _call<int>('appCount')) ?? -1,
        battVoltageMv: (await _call<int>('battVoltageMv')) ?? -1,
        battTempC: (await _call<double>('battTempC')) ?? -1,
        battHealth: (await _call<String>('battHealth')) ?? '—',
        battTech: (await _call<String>('battTech')) ?? '—',
        uptimeMs: (await _call<int>('uptimeMs')) ?? 0,
        kernelVersion: (await _call<String>('kernelVersion')) ?? '—',
        networkType: (await _call<String>('networkType')) ?? '—',
        deviceName: (await _call<String>('deviceName')) ?? '—',
        androidId: (await _call<String>('androidId')) ?? '—',
        phoneType: (await _call<String>('phoneType')) ?? '—',
        esim: (await _call<String>('esim')) ?? '—',
        mobileNet: (await _call<String>('mobileNet')) ?? '—',
      );
      _cache = ex;
      _at = DateTime.now();
      return ex;
    } catch (_) {
      return _cache;
    }
  }
}
