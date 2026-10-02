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

  static Map<String, dynamic>? _wifiCache;
  static DateTime? _wifiAt;

  /// Wi-Fi details for the Network tab (cached 15s).
  static Future<Map<String, dynamic>?> getWifiInfo(
      {bool force = false}) async {
    if (!force &&
        _wifiCache != null &&
        _wifiAt != null &&
        DateTime.now().difference(_wifiAt!).inSeconds < 15) {
      return _wifiCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('wifiInfo');
      if (m == null) return _wifiCache;
      _wifiCache = Map<String, dynamic>.from(m);
      _wifiAt = DateTime.now();
      return _wifiCache;
    } catch (_) {
      return _wifiCache;
    }
  }

  static Map<String, dynamic>? _netCache;
  static DateTime? _netAt;

  /// Connectivity tab bundle (cached 15s).
  static Future<Map<String, dynamic>?> getNetExtra(
      {bool force = false}) async {
    if (!force &&
        _netCache != null &&
        _netAt != null &&
        DateTime.now().difference(_netAt!).inSeconds < 15) {
      return _netCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('netExtra');
      if (m == null) return _netCache;
      _netCache = Map<String, dynamic>.from(m);
      _netAt = DateTime.now();
      return _netCache;
    } catch (_) {
      return _netCache;
    }
  }

  static Map<String, dynamic>? _connCache;
  static DateTime? _connAt;

  /// Radio capabilities for the Connectivity tab (cached 60s).
  static Future<Map<String, dynamic>?> getConnInfo(
      {bool force = false}) async {
    if (!force &&
        _connCache != null &&
        _connAt != null &&
        DateTime.now().difference(_connAt!).inSeconds < 60) {
      return _connCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('connInfo');
      if (m == null) return _connCache;
      _connCache = Map<String, dynamic>.from(m);
      _connAt = DateTime.now();
      return _connCache;
    } catch (_) {
      return _connCache;
    }
  }

  static Map<String, dynamic>? _dispCache;
  static DateTime? _dispAt;

  /// Display tab bundle (cached 60s; orientation/timeout can change).
  static Future<Map<String, dynamic>?> getDisplayInfo(
      {bool force = false}) async {
    if (!force &&
        _dispCache != null &&
        _dispAt != null &&
        DateTime.now().difference(_dispAt!).inSeconds < 60) {
      return _dispCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('displayInfo');
      if (m == null) return _dispCache;
      _dispCache = Map<String, dynamic>.from(m);
      _dispAt = DateTime.now();
      return _dispCache;
    } catch (_) {
      return _dispCache;
    }
  }

  static Map<String, dynamic>? _sysParts;
  static DateTime? _sysPartsAt;

  /// System/vendor partition sizes (cached 5 min — static data).
  static Future<Map<String, dynamic>?> getSysParts(
      {bool force = false}) async {
    if (!force &&
        _sysParts != null &&
        _sysPartsAt != null &&
        DateTime.now().difference(_sysPartsAt!).inMinutes < 5) {
      return _sysParts;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('sysParts');
      if (m == null) return _sysParts;
      _sysParts = Map<String, dynamic>.from(m);
      _sysPartsAt = DateTime.now();
      return _sysParts;
    } catch (_) {
      return _sysParts;
    }
  }

  static List<Map<String, dynamic>>? _camCache;
  static DateTime? _camAt;

  /// Camera2 characteristics per camera (cached 5 min — static data).
  static Future<List<Map<String, dynamic>>> getCameraInfo(
      {bool force = false}) async {
    if (!force &&
        _camCache != null &&
        _camAt != null &&
        DateTime.now().difference(_camAt!).inMinutes < 5) {
      return _camCache!;
    }
    try {
      final list =
          await _ch.invokeListMethod<dynamic>('cameraInfo');
      final out = <Map<String, dynamic>>[];
      if (list != null) {
        for (final e in list) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
      }
      _camCache = out;
      _camAt = DateTime.now();
      return out;
    } catch (_) {
      return _camCache ?? const [];
    }
  }

  static List<Map<String, dynamic>>? _senCache;
  static DateTime? _senAt;

  /// Full sensor list (cached 5 min — static data).
  static Future<List<Map<String, dynamic>>> getSensorList(
      {bool force = false}) async {
    if (!force &&
        _senCache != null &&
        _senAt != null &&
        DateTime.now().difference(_senAt!).inMinutes < 5) {
      return _senCache!;
    }
    try {
      final list =
          await _ch.invokeListMethod<dynamic>('sensorList');
      final out = <Map<String, dynamic>>[];
      if (list != null) {
        for (final e in list) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
      }
      _senCache = out;
      _senAt = DateTime.now();
      return out;
    } catch (_) {
      return _senCache ?? const [];
    }
  }

  static Map<String, dynamic>? _thermCache;
  static DateTime? _thermAt;

  /// Thermal zones + status (cached 5s — temps move constantly).
  static Future<Map<String, dynamic>?> getThermalInfo(
      {bool force = false}) async {
    if (!force &&
        _thermCache != null &&
        _thermAt != null &&
        DateTime.now().difference(_thermAt!).inSeconds < 5) {
      return _thermCache;
    }
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('thermalInfo');
      if (m == null) return _thermCache;
      _thermCache = Map<String, dynamic>.from(m);
      _thermAt = DateTime.now();
      return _thermCache;
    } catch (_) {
      return _thermCache;
    }
  }

  static List<Map<String, dynamic>>? _appCache;
  static DateTime? _appAt;

  /// Visible installed packages (cached 60s — installs are rare).
  static Future<List<Map<String, dynamic>>> getAppList(
      {bool force = false}) async {
    if (!force &&
        _appCache != null &&
        _appAt != null &&
        DateTime.now().difference(_appAt!).inMinutes < 5) {
      return _appCache!;
    }
    try {
      final list =
          await _ch.invokeListMethod<dynamic>('appList');
      final out = <Map<String, dynamic>>[];
      if (list != null) {
        for (final e in list) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
      }
      _appCache = out;
      _appAt = DateTime.now();
      return out;
    } catch (_) {
      return _appCache ?? const [];
    }
  }

  static Future<Map<String, dynamic>> getAppDetail(
      String package) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
          'appDetail', {'package': package});
      if (m == null) return const {};
      return Map<String, dynamic>.from(m);
    } catch (_) {
      return const {};
    }
  }

  static Future<bool> launchApp(String package) async {
    try {
      return await _ch.invokeMethod<bool>(
              'launchApp', {'package': package}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the extracted APK path, or null on failure.
  static Future<String?> extractApk(String package) async {
    try {
      return await _ch.invokeMethod<String>(
          'extractApk', {'package': package});
    } catch (_) {
      return null;
    }
  }

  static Future<void> openAppSettings(String package) async {
    try {
      await _ch.invokeMethod<bool>(
          'openAppSettings', {'package': package});
    } catch (_) {}
  }

  static Future<void> openBtSettings() async {
    try {
      await _ch.invokeMethod<bool>('openBtSettings');
    } catch (_) {}
  }

  static Future<bool> openDataUsage() async {
    try {
      return await _ch.invokeMethod<bool>('openDataUsage') ?? false;
    } catch (_) {
      return false;
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
