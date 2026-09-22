/// Log writer API: warning/error/info/debug, dedup, flush.
///
/// Split from `app_log_service.dart` - behavior is unchanged.
/// Contains: warning(), error(), info(), debug(), _add(), _bumpPendingDuplicate()
part of 'app_log_service.dart';

extension AppLogServiceWriter on AppLogService {
  void warning(String message, {Object? details, LogCategory? category}) {
    _add('WARNING', message, details, category);
  }

  void error(String message, {Object? details, LogCategory? category}) {
    _add('ERROR', message, details, category);
  }

  void info(String message, {Object? details, LogCategory? category}) {
    _add('INFO', message, details, category);
  }

  void debug(String message, {Object? details, LogCategory? category}) {
    _add('DEBUG', message, details, category);
  }

  void _add(String level, String message, Object? details, LogCategory? cat) {
    // Demote GetX's empty-scope hint at every entry path (zone/platform
    // handlers bypass main's FlutterError filter). Same rationale: lint,
    // not failure — searchable, never an error/crash report.
    if ((level == 'ERROR' || level == 'WARNING') &&
        message.contains('improper use of a GetX')) {
      level = 'DEBUG';
    }
    final category = cat ?? LogCategory.system;
    final detailsStr = details?.toString();

    // Collapse exact repeats into one row (count + last-seen bump) instead
    // of appending N identical multi-KB bodies. Any single-symbol change
    // is a different key and stays its own row. Pending-only: touching the
    // shown RxList here would re-enter the build phase (see fields above).
    if (_bumpPendingDuplicate(level, message, detailsStr, category)) return;

    final entry = AppLogEntry(
      level: level,
      message: message,
      details: detailsStr,
      category: category,
      // Signal rows carry the open screen so a pasted log pinpoints
      // WHERE it happened (overflow reports without this are unfixable).
      // Info/debug stay blank to keep the buffer lean.
      screen: (level == 'ERROR' || level == 'WARNING') ? currentScreen : '',
    );
    _pendingEntries.insert(0, entry);

    // Write-through crash survival: every new ERROR/WARNING is persisted to
    // its own file immediately (synchronously for the unresolved record) so
    // a hard process kill right after the failure can't erase it.
    if (level == 'ERROR' || level == 'WARNING') {
      _pendingUnresolved = entry;
      unawaited(_persistUnresolved(entry));
      unawaited(_appendCrashHistory(entry));
    }

    if (!_flushScheduled) {
      _flushScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _flushScheduled = false;
        // Deferred UI state first (banner sees the latest error).
        final un = _pendingUnresolved;
        _pendingUnresolved = null;
        if (un != null) unresolvedError.value = un;
        if (_pendingCrashRows.isNotEmpty) {
          final rows = List<AppLogEntry>.from(_pendingCrashRows);
          _pendingCrashRows.clear();
          for (final r in rows.reversed) {
            crashHistory.insert(0, r);
          }
          while (crashHistory.length > AppLogService._maxCrashHistory) {
            crashHistory.removeRange(AppLogService._maxCrashHistory, crashHistory.length);
          }
        }
        final toAdd = List<AppLogEntry>.from(_pendingEntries);
        _pendingEntries.clear();
        // Fold into shown rows with the same dedup+move-to-top rule the
        // old synchronous path had — but safely outside the build phase.
        for (final e in toAdd.reversed) {
          final i = entries.indexWhere(
              (x) => x.sameAs(e.level, e.message, e.details, e.category));
          if (i >= 0) {
            final ex = entries[i];
            ex.count += e.count;
            ex.lastAt = e.lastAt;
            entries.removeAt(i);
            entries.insert(0, ex);
          } else {
            entries.insert(0, e);
          }
        }
        if (entries.length > AppLogService._maxEntries) {
          entries.removeRange(AppLogService._maxEntries, entries.length);
        }
        if (entries.length % AppLogService._persistBatch == 0) {
          _persistLogs();
        }
      });
    }

    if ((level == 'ERROR' || level == 'WARNING') &&
        Get.isRegistered<CrashReportingService>()) {
      Get.find<CrashReportingService>().recordNonFatal(
        details ?? message,
        reason: message,
        extra: {'app_log_level': level, 'category': (cat ?? LogCategory.system).name},
      );
    }
  }

  /// Pending-only duplicate collapse (synchronous-safe: touches no Rx —
  /// see the fields above). Shown-row folding happens in the post-frame
  /// flush. Returns true when an identical pending row was bumped instead.
  bool _bumpPendingDuplicate(String level, String message, String? detailsStr,
      LogCategory category) {
    final now = DateTime.now();
    for (final e in _pendingEntries) {
      if (e.sameAs(level, message, detailsStr, category)) {
        e.count++;
        e.lastAt = now;
        return true;
      }
    }
    return false;
  }

}
