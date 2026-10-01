import 'package:flutter/services.dart';

/// Battery level/charging from the platform power channel.
/// Returns null off-Android — callers show '—' gracefully.
class BatteryInfo {
  final int level; // 0..100
  final bool charging;
  const BatteryInfo({required this.level, required this.charging});
}

class PowerInfoService {
  static const _ch = MethodChannel('com.cubiclm.app/power');
  static BatteryInfo? _cache;
  static DateTime? _at;

  /// Cached 30s: battery moves slowly, bar rebuilds often.
  static Future<BatteryInfo?> getBattery({bool force = false}) async {
    if (!force &&
        _cache != null &&
        _at != null &&
        DateTime.now().difference(_at!).inSeconds < 30) {
      return _cache;
    }
    try {
      final level =
          await _ch.invokeMethod<int>('batteryLevel');
      final charging =
          await _ch.invokeMethod<bool>('batteryCharging');
      if (level == null || level < 0) return _cache;
      _cache = BatteryInfo(
        level: level.clamp(0, 100),
        charging: charging ?? false,
      );
      _at = DateTime.now();
      return _cache;
    } catch (_) {
      return _cache;
    }
  }
}
