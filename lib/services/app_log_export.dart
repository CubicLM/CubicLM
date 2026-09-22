/// File persist/load, export, share, clear, route-trail file sink.
///
/// Split from `app_log_service.dart` - behavior is unchanged.
/// Contains: async, _persistLogs(), _loadPersistedLogs(), copyImportantLogs(), exportFullLogs(), shareText
///   exportFileName(), clear(), _fmtTime()
part of 'app_log_service.dart';

extension AppLogServiceExport on AppLogService {
  Future<File> get _file async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/cubiclm_logs.json');
    return _logFile!;
  }

  Future<void> _persistLogs() async {
    try {
      final f = await _file;
      // Include still-pending (not yet frame-flushed) rows so even a kill in
      // the same frame as the error keeps that row on disk.
      final combined = <AppLogEntry>[
        ..._pendingEntries,
        ...entries,
      ];
      final toSave = combined.take(200).map((e) => e.toJson()).toList();
      await f.writeAsString(jsonEncode(toSave), flush: true);
    } catch (_) {}
  }

  Future<void> _loadPersistedLogs() async {
    try {
      final f = await _file;
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        final loaded = json.map((j) => AppLogEntry.fromJson(j)).toList();
        entries.assignAll(loaded);
      }
    } catch (_) {}
  }

  // --- Export ---

  Future<void> copyImportantLogs() async {
    await Clipboard.setData(ClipboardData(text: shareText));
  }

  Future<String> exportFullLogs() async {
    final buf = StringBuffer();
    buf.writeln(healthSummary);
    buf.writeln('');
    buf.writeln('=== Full Log (${entries.length} rows) ===');
    for (final e in entries) {
      buf.writeln(e.formatForExport());
      buf.writeln('');
    }
    return buf.toString();
  }

  String get shareText {
    final selected = importantEntries.isEmpty ? entries : importantEntries;
    return selected.map((entry) => entry.formatForExport()).join('\n\n');
  }

  /// Suggested filename for the .txt export (app version + timestamp).
  String exportFileName(String appVersion) {
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    final ver = appVersion.trim().isEmpty
        ? 'unknown'
        : appVersion.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return 'cubiclm_logs_${ver}_$stamp.txt';
  }

  void clear() {
    entries.clear();
    crashHistory.clear();
    unresolvedError.value = null;
    _persistLogs();
    unawaited(_clearPersistentCrashState());
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
