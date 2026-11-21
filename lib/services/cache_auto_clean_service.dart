/// CubicLM Cache Auto-Clean — keeps temporary/cached data in check.
///
/// Tracks the app's cache directories (temporary dir + application cache),
/// reports their size, and clears them automatically every N days when
/// enabled (Settings → Data). Manual "Clear now" is always available.
///
/// Settings (Hive):
///   cache_autoclean_enabled (bool, default false)
///   cache_autoclean_days    (int, default 7 — options 1/3/7/15/30)
///   cache_last_clean_ms     (int, epoch ms of the last successful clean)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_service.dart';
import 'hive_service.dart';

class CacheAutoCleanService extends GetxService {
  /// Observable state bound by Settings → Data.
  final enabled = false.obs;
  final days = 7.obs;
  final lastCleanMs = 0.obs;
  final cleaning = false.obs;

  /// Live cache size in bytes (refreshed on demand; not a stream).
  final cacheBytes = 0.obs;

  /// Bumped after every successful clean so UI listening on it refreshes.
  static final cleanedVersion = ValueNotifier<int>(0);

  static const _kEnabled = 'cache_autoclean_enabled';
  static const _kDays = 'cache_autoclean_days';
  static const _kLastClean = 'cache_last_clean_ms';

  static const intervalOptions = [1, 3, 7, 15, 30];

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  Future<CacheAutoCleanService> init() async {
    enabled.value = _hive?.getSetting<bool>(_kEnabled) ?? false;
    days.value = _hive?.getSetting<int>(_kDays) ?? 7;
    lastCleanMs.value = _hive?.getSetting<int>(_kLastClean) ?? 0;
    unawaited(refreshSize());
    unawaited(_maybeAutoClean());
    return this;
  }

  // ── Settings ──────────────────────────────────────────────────────

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    try {
      await _hive?.setSetting(_kEnabled, on);
    } catch (_) {}
    if (on) {
      // A fresh enable re-arms the schedule from now.
      await _markCleaned(clean: false);
      AppLogService.trailAction('cache auto-clean enabled (every ${days.value}d)');
    } else {
      AppLogService.trailAction('cache auto-clean disabled');
    }
  }

  Future<void> setDays(int d) async {
    days.value = d;
    try {
      await _hive?.setSetting(_kDays, d);
    } catch (_) {}
    await _markCleaned(clean: false);
    AppLogService.trailAction('cache auto-clean interval: every $d day(s)');
  }

  // ── Cache directories ─────────────────────────────────────────────

  Future<List<Directory>> _cacheDirs() async {
    final dirs = <Directory>[];
    try {
      if (kIsWeb) return dirs;
      final tmp = await getTemporaryDirectory();
      dirs.add(tmp);
      try {
        final cache = await getApplicationCacheDirectory();
        if (cache.path != tmp.path) dirs.add(cache);
      } catch (_) {}
    } catch (_) {}
    return dirs;
  }

  /// Sum of all file sizes inside the cache dirs. Never throws.
  Future<int> computeCacheBytes() async {
    var total = 0;
    for (final dir in await _cacheDirs()) {
      try {
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return total;
  }

  Future<void> refreshSize() async {
    cacheBytes.value = await computeCacheBytes();
  }

  // ── Cleaning ──────────────────────────────────────────────────────

  /// Deletes everything inside the cache dirs (files first, then empty
  /// dirs — contents only, never the dirs themselves). In-use files that
  /// the OS refuses to delete are skipped silently. Returns bytes freed.
  Future<int> cleanNow({bool silent = false}) async {
    if (cleaning.value || kIsWeb) return 0;
    cleaning.value = true;
    var freed = 0;
    try {
      for (final dir in await _cacheDirs()) {
        try {
          if (!await dir.exists()) continue;
          await for (final e in dir.list(recursive: false, followLinks: false)) {
            try {
              if (e is File) {
                final len = await e.length();
                await e.delete();
                freed += len;
              } else if (e is Directory) {
                final before = await _dirBytes(e);
                await e.delete(recursive: true);
                freed += before;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
      await _markCleaned(clean: true);
      cacheBytes.value = 0;
      cleanedVersion.value++;
      if (!silent) {
        AppLogService.trailAction(
            'cache cleaned — ${_fmt(freed)} freed');
      }
      return freed;
    } finally {
      cleaning.value = false;
    }
  }

  /// Sum of file sizes under [dir] (best effort). Never throws.
  Future<int> _dirBytes(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Runs the scheduled clean when the chosen interval has elapsed.
  Future<void> _maybeAutoClean() async {
    try {
      if (!enabled.value) return;
      final last = lastCleanMs.value;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last > 0 &&
          now - last < days.value * 24 * 60 * 60 * 1000) {
        return;
      }
      final freed = await cleanNow(silent: true);
      AppLogService.trailAction(
          'auto cache clean (every ${days.value}d) — ${_fmt(freed)} freed');
    } catch (_) {}
  }

  Future<void> _markCleaned({required bool clean}) async {
    lastCleanMs.value = DateTime.now().millisecondsSinceEpoch;
    try {
      await _hive?.setSetting(_kLastClean, lastCleanMs.value);
    } catch (_) {}
    if (clean) unawaited(refreshSize());
  }

  // ── Labels ────────────────────────────────────────────────────────

  String get cacheSizeLabel => _fmt(cacheBytes.value);

  String get lastCleanLabel {
    final ms = lastCleanMs.value;
    if (ms <= 0) return 'Never';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String intervalLabel(int d) =>
      d == 1 ? 'Every day' : d == 30 ? 'Every month' : 'Every $d days';

  static String _fmt(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
