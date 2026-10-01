import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app_log_service.dart';

/// Internal storage stats from the platform (StatFs on app files dir).
/// Non-Android platforms return null — callers fall back gracefully.
class StorageStats {
  final int totalBytes;
  final int freeBytes;
  const StorageStats({required this.totalBytes, required this.freeBytes});

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
  double get usedFraction =>
      totalBytes <= 0 ? 0 : usedBytes / totalBytes;
}

class StorageInfoService {
  static const _ch = MethodChannel('com.cubiclm.app/storage');
  static StorageStats? _cache;
  static DateTime? _at;

  /// Cached 10s: StatFs is cheap but the bar rebuilds often.
  static Future<StorageStats?> getStats({bool force = false}) async {
    if (!force &&
        _cache != null &&
        _at != null &&
        DateTime.now().difference(_at!).inSeconds < 10) {
      return _cache;
    }
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
          'getStorageStats');
      if (m == null) return _cache;
      _cache = StorageStats(
        totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
      );
      _at = DateTime.now();
      // Verifiable in System Logs: compare with Settings → Storage.
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().debug(
            '[Storage] StatFs total=${_cache!.totalBytes} '
            'free=${_cache!.freeBytes}',
            category: LogCategory.system,
          );
        }
      } catch (_) {}
      return _cache;
    } catch (_) {
      return _cache;
    }
  }
}
