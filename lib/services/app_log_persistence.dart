/// Crash-survivable persistence: device ctx, files, breadcrumbs, exit forensics.
///
/// Split from `app_log_service.dart` - behavior is unchanged.
/// Contains: _captureDeviceContext(), async, async, _cachedBreadcrumbFile, async, setBreadcrumb()
///   takeBreadcrumb(), _persistUnresolved(), _appendCrashHistory(), _loadPersistedUnresolved()
///   _loadPersistedCrashHistory(), _restorePersistedState(), _reportCrashFiles()
///   _reportProcessExits(), _reportUnresolvedBreadcrumb(), flush(), resolveCrashState()
///   _clearPersistentCrashState()
part of 'app_log_service.dart';

extension AppLogServicePersistence on AppLogService {
  Future<void> _captureDeviceContext() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        _deviceSummary =
            '${info.manufacturer} ${info.model} • Android ${info.version.release}';
      }
    } catch (_) {}
  }

  Future<File> get _lastErrorFile async {
    final cached = _cachedLastErrorFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_lasterror.json');
    _cachedLastErrorFile = f;
    return f;
  }

  Future<File> get _crashHistoryFile async {
    final cached = _cachedCrashHistoryFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_crash_history.json');
    _cachedCrashHistoryFile = f;
    return f;
  }

  Future<File> get _breadcrumbFile async {
    final cached = _cachedBreadcrumbFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_breadcrumb.json');
    _cachedBreadcrumbFile = f;
    return f;
  }

  /// Kill-proof breadcrumb: awaited flush:true write BEFORE a native call
  /// that can SIGKILL the process (model load). If the app dies, the next
  /// boot finds a `-start` step with no resolution and reports it — so a
  /// silent native death always leaves evidence.
  Future<void> setBreadcrumb(String step, [String detail = '']) async {
    try {
      final f = await _breadcrumbFile;
      await f.writeAsString(
          jsonEncode({
            'step': step,
            'detail': detail,
            'at': DateTime.now().toIso8601String(),
          }),
          flush: true);
    } catch (_) {}
  }

  /// Reads + clears the breadcrumb. Returns null when the previous
  /// session shut down cleanly (or never wrote one).
  Future<Map<String, String>?> takeBreadcrumb() async {
    try {
      final f = await _breadcrumbFile;
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      await f.delete();
      if (decoded is! Map) return null;
      return {
        'step': '${decoded['step'] ?? ''}',
        'detail': '${decoded['detail'] ?? ''}',
        'at': '${decoded['at'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  /// Persists the "unfixed" error immediately with a *synchronous* write so
  /// even an instant process kill (OOM, force-stop, low-battery death) right
  /// after the error cannot lose it. Errors are rare, so this is cheap.
  Future<void> _persistUnresolved(AppLogEntry entry) async {
    try {
      final f = await _lastErrorFile;
      final payload = jsonEncode({
        ...entry.toJson(),
        'appVersion': _appVersion,
        'device': _deviceSummary,
      });
      unresolvedErrorMeta = '$_appVersion • $_deviceSummary';
      if (entry.screen.isNotEmpty) {
        unresolvedErrorMeta = "$unresolvedErrorMeta • ${entry.screen}";
      }
      // ignore: avoid_slow_async_io
      f.writeAsStringSync(payload, flush: true);
    } catch (_) {}
  }

  Future<void> _appendCrashHistory(AppLogEntry entry) async {
    _pendingCrashRows.insert(0, entry);
    if (_pendingCrashRows.length > AppLogService._maxCrashHistory) {
      _pendingCrashRows.removeLast();
    }
    try {
      final f = await _crashHistoryFile;
      final list = crashHistory
          .map((e) => {
                ...e.toJson(),
                'appVersion': _appVersion,
                'device': _deviceSummary,
              })
          .toList();
      await f.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  Future<void> _loadPersistedUnresolved() async {
    try {
      final f = await _lastErrorFile;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final entry = AppLogEntry.fromJson(decoded);
      if (entry.level != 'ERROR' && entry.level != 'WARNING') return;

      unresolvedError.value = entry;
      unresolvedErrorMeta = [
        if (decoded['appVersion'] is String)
          decoded['appVersion'] as String,
        if (decoded['device'] is String) decoded['device'] as String,
        if (decoded['s'] is String) decoded['s'] as String,
      ].join(' • ');
      // Surface the previous session's unfixed issue at the very top of the
      // live list so it is visible immediately on the next launch.
      entries.insertAll(0, [
        AppLogEntry(
          level: entry.level,
          message: '[Previous session] ${entry.message}',
          details: entry.details,
          category: entry.category,
          screen: entry.screen,
          timestamp: entry.timestamp,
          lastAt: entry.lastAt,
          count: entry.count,
        ),
      ]);
    } catch (_) {}
  }

  Future<void> _loadPersistedCrashHistory() async {
    try {
      final f = await _crashHistoryFile;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) return;
      crashHistory.assignAll(decoded
          .map((j) => AppLogEntry.fromJson(Map<String, dynamic>.from(j))));
    } catch (_) {}
  }

  Future<void> _restorePersistedState() async {
    // Version/device MUST resolve before the old-death report below:
    // otherwise the persisted error is stamped "unknown" (PackageInfo
    // hadn't finished when onInit fired it unawaited).
    await _captureDeviceContext();
    await _loadPersistedLogs();
    await _loadPersistedUnresolved();
    await _loadPersistedCrashHistory();
    await _reportUnresolvedBreadcrumb();
    await _reportProcessExits();
    await _reportCrashFiles();
  }

  /// JVM crash files written by MainActivity's uncaught-exception handler
  /// (works on every API level — the answer for devices without the
  /// trace stream). One row per file, then deleted.
  Future<void> _reportCrashFiles() async {
    try {
      if (kIsWeb) return;
      final dir = await getApplicationDocumentsDirectory();
      final crashDir = Directory('${dir.path}/cubiclm_crashes');
      if (!await crashDir.exists()) return;
      final files = await crashDir
          .list()
          .where((e) => e is File && e.path.endsWith('.txt'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      var count = 0;
      for (final f in files) {
        String body = '';
        try {
          body = await f.readAsString();
        } catch (_) {}
        try {
          await f.delete();
        } catch (_) {}
        if (body.trim().isEmpty) continue;
        count++;
        if (count > 3) continue;
        final isNative = f.path.contains('native_crash_');
        // Native tombstones carry signal + PCs + modules + log tail
        // (~5KB): give them a bigger cap so the log tail survives.
        final cap = isNative ? 6000 : 2800;
        if (body.length > cap) body = '${body.substring(0, cap)}…';
        error(
          isNative
              ? '[Previous run] NATIVE CRASH — fatal signal inside the engine'
              : '[Previous run] JAVA CRASH — uncaught exception killed the app',
          details: '$body\nCopy this row + the rows above it and report.',
          category: LogCategory.model,
        );
      }
    } catch (_) {}
  }


  /// Previous-process forensics via ApplicationExitInfo (Android 11+,
  /// no logcat permission needed — own deaths only). Logs one row per
  /// abnormal death newer than the last seen timestamp, newest first,
  /// so a native SIGSEGV/SIGABRT or LMK kill is reportable from inside
  /// the app instead of needing adb.
  Future<void> _reportProcessExits() async {
    try {
      if (kIsWeb) return;
      bool forensics = false;
      try {
        forensics = await AppLogService._exitChannel
                .invokeMethod<bool>('forensicsReady') ??
            false;
      } catch (_) {}
      if (!forensics) {
        // One-shot per boot, debug-level: tells the user (and us, via
        // their log export) that this APK predates stack capture, so a
        // bare "crash" row means "update the app", not "unknown".
        debug('Crash forensics unavailable in this build — update the '
            'app to capture Java stacks for native-death diagnosis.');
      }
      List<dynamic>? raw;
      try {
        raw = await AppLogService._exitChannel.invokeListMethod<dynamic>(
            'getRecentExitReasons');
      } catch (_) {
        return; // Non-Android or old channel: nothing to report.
      }
      if (raw == null || raw.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      final seenFile = File('${dir.path}/${AppLogService._exitSeenFileName}');
      var seenMs = 0;
      try {
        if (await seenFile.exists()) {
          seenMs = int.tryParse(await seenFile.readAsString()) ?? 0;
        }
      } catch (_) {}
      var maxMs = seenMs;
      var fresh = 0;
      // Newest first: iterate reversed (channel returns newest first,
      // so keep order but skip seen).
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final reason = (m['reason'] as num?)?.toInt() ?? 0;
        final tsMs = (m['timestampMs'] as num?)?.toInt() ?? 0;
        if (tsMs > maxMs) maxMs = tsMs;
        if (tsMs <= seenMs) continue;
        if (!isCrashExitReason(reason)) continue;
        fresh++;
        if (fresh > 4) continue; // Cap rows; still advance maxMs above.
        final name = processExitReasonName(reason);
        final imp = processImportanceName(
            (m['importance'] as num?)?.toInt() ?? 0);
        final status = (m['status'] as num?)?.toInt() ?? 0;
        final at = tsMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(tsMs).toIso8601String()
            : 'unknown time';
        final pssMb = ((m['pssKb'] as num?)?.toDouble() ?? 0) / 1024;
        final rssMb = ((m['rssKb'] as num?)?.toDouble() ?? 0) / 1024;
        var desc = '${m['description'] ?? ''}';
        final trace = '${m['trace'] ?? ''}';
        // Trace head (Java stack / tombstone excerpt, API 31+) is the
        // actual diagnosis — keep up to ~2.5KB of it after the one-line
        // description so the row stays copy-paste friendly.
        final combined = (desc + (trace.isEmpty ? '' : '\n--- trace ---\n$trace')).trim();
        final details = combined.isEmpty
            ? AppLogService._exitHintFor(reason)
            : '${combined.length > 2800 ? '${combined.substring(0, 2800)}…' : combined}\n${AppLogService._exitHintFor(reason)}';
        error(
          '[Previous run] $name @ $at [$imp${status != 0 ? ' status=$status' : ''}]'
          '${pssMb > 0 ? ' (pss ${pssMb.toStringAsFixed(0)}MB, rss ${rssMb.toStringAsFixed(0)}MB)' : ''}',
          details: details,
          category: (reason == 4 || reason == 5)
              ? LogCategory.model
              : LogCategory.system,
        );
      }
      try {
        await seenFile.writeAsString('$maxMs', flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  /// chance to log. Report it as a persisted error so "no logs" deaths
  /// are visible + exportable on the next launch.
  Future<void> _reportUnresolvedBreadcrumb() async {
    try {
      final bc = await takeBreadcrumb();
      if (bc == null) return;
      final step = bc['step'] ?? '';
      if (!step.endsWith('-start')) return;
      final detail = bc['detail'] ?? '';
      error(
        'Previous session ended during: $step${detail.isNotEmpty ? ' ($detail)' : ''}',
        details:
            'The app died without shutting down (native abort or system kill — no Dart log possible). '
            'If this was a model load: re-download the file, free RAM, or try a smaller model. '
            'Breadcrumb from ${bc['at']}.',
        category: LogCategory.model,
      );
    } catch (_) {}
  }

  /// Force-write everything (main log + unresolved record) to disk.
  Future<void> flush() async {
    await _persistLogs();
    final un = unresolvedError.value;
    if (un != null) await _persistUnresolved(un);
  }

  /// Marks the stored crash state as fixed: clears the unfixed error banner,
  /// the previous-session marker row and the crash history, plus their files.
  Future<void> resolveCrashState() async {
    unresolvedError.value = null;
    entries.removeWhere((e) => e.message.startsWith('[Previous session]'));
    crashHistory.clear();
    try {
      final le = await _lastErrorFile;
      if (await le.exists()) await le.delete();
    } catch (_) {}
    try {
      final ch = await _crashHistoryFile;
      if (await ch.exists()) await ch.delete();
    } catch (_) {}
  }

  Future<void> _clearPersistentCrashState() async {
    try {
      final le = await _lastErrorFile;
      if (await le.exists()) await le.delete();
    } catch (_) {}
    try {
      final ch = await _crashHistoryFile;
      if (await ch.exists()) await ch.delete();
    } catch (_) {}
  }
}
