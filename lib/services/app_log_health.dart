/// Queries, crash patterns, health summary, diagnosis, stack parse.
///
/// Split from `app_log_service.dart` - behavior is unchanged.
/// Contains: filteredEntries, importantEntries, errorCount, uniqueErrorCount, lastError, detectedPatterns
///   categoryBreakdown, untrackedErrors, healthSummary, diagnosisFor(), _sectionOf(), _stackTop()
part of 'app_log_service.dart';

extension AppLogServiceHealth on AppLogService {
  // --- Search & Filter ---

  List<AppLogEntry> get filteredEntries {
    var result = entries.toList();

    if (selectedLevel.value != 'ALL') {
      result = result.where((e) => e.level == selectedLevel.value).toList();
    }
    if (selectedCategory.value != null) {
      result =
          result.where((e) => e.category == selectedCategory.value).toList();
    }
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isNotEmpty) {
      result = result
          .where((e) =>
              e.message.toLowerCase().contains(q) ||
              (e.details?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return result;
  }

  List<AppLogEntry> get importantEntries =>
      entries.where((entry) => entry.isImportant).toList();

  // --- Health Diagnostics ---

  /// Total occurrences (repeats counted), not just unique rows.
  int get errorCount =>
      entries.where((e) => e.level == 'ERROR').fold(0, (s, e) => s + e.count);
  int get warningCount => entries
      .where((e) => e.level == 'WARNING')
      .fold(0, (s, e) => s + e.count);

  /// Unique error rows (after dedup).
  int get uniqueErrorCount =>
      entries.where((e) => e.level == 'ERROR').length;

  DateTime? get lastError {
    DateTime? latest;
    for (final e in entries) {
      if (e.level != 'ERROR') continue;
      if (latest == null || e.lastAt.isAfter(latest)) latest = e.lastAt;
    }
    return latest;
  }

  List<CrashPattern> get detectedPatterns {
    final detected = <CrashPattern>[];
    for (final pattern in crashPatterns) {
      final matches = entries.where((e) => pattern.matcher(e)).toList();
      if (matches.isNotEmpty) {
        pattern.occurrences = matches.fold(0, (s, e) => s + e.count);
        DateTime? last;
        for (final m in matches) {
          if (last == null || m.lastAt.isAfter(last)) last = m.lastAt;
        }
        pattern.lastSeen = last ?? matches.first.timestamp;
        detected.add(pattern);
      }
    }
    detected.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return detected;
  }

  Map<String, int> get categoryBreakdown {
    final map = <String, int>{};
    for (final cat in LogCategory.values) {
      final count = entries.where((e) => e.category == cat).length;
      if (count > 0) map[cat.label] = count;
    }
    return map;
  }

  /// ERROR/WARNING rows no pattern claims — so no red row ever goes
  /// untracked again. Sorted newest-first (entries order).
  List<AppLogEntry> get untrackedErrors {
    final out = <AppLogEntry>[];
    outer:
    for (final e in entries) {
      if (e.level != 'ERROR' && e.level != 'WARNING') continue;
      for (final p in crashPatterns) {
        try {
          if (p.matcher(e)) continue outer;
        } catch (_) {}
      }
      out.add(e);
    }
    return out;
  }

  String get healthSummary {
    final patterns = detectedPatterns;
    final buf = StringBuffer();
    buf.writeln('=== CubicLM System Health ===');
    buf.writeln('Total rows: ${entries.length}');
    buf.writeln('Errors: $errorCount  |  Warnings: $warningCount');
    if (currentScreen.isNotEmpty) {
      buf.writeln('Screen now: $currentScreen');
    }
    if (_screenTrail.length > 1) {
      buf.writeln('Recent screens: ${_screenTrail.take(5).join(' ← ')}');
    }
    if (_actionTrail.isNotEmpty) {
      buf.writeln('Recent actions:');
      for (final a in _actionTrail.take(8)) {
        buf.writeln('  • $a');
      }
    }
    if (_routeTrail.isNotEmpty) {
      buf.writeln('Recent routes:');
      for (final r in _routeTrail.take(6)) {
        buf.writeln('  • $r');
      }
    }
    if (uniqueErrorCount != errorCount) {
      buf.writeln('(unique error rows: $uniqueErrorCount)');
    }
    if (lastError != null) {
      buf.writeln('Last error: ${_fmtTime(lastError!)}');
    }
    final un = unresolvedError.value;
    if (un != null) {
      buf.writeln('Unresolved (unfixed) ${un.level}: ${un.message.split('\n').first}');
      buf.writeln('  persisted: ${_fmtTime(un.lastAt)}, app $_appVersion, $_deviceSummary');
    }
    buf.writeln('');
    if (patterns.isEmpty) {
      buf.writeln('✓ No crash patterns detected.');
    } else {
      buf.writeln('Crash patterns detected (${patterns.length}):');
      for (final p in patterns) {
        buf.writeln('  • ${p.title} (${p.occurrences}x)');
        buf.writeln('    Fix: ${p.fix}');
      }
    }
    final untracked = untrackedErrors;
    if (untracked.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Untracked errors/warnings (${untracked.length} rows):');
      for (final e in untracked.take(5)) {
        final firstLine = e.message.split('\n').first.trim();
        final short = firstLine.length > 120
            ? '${firstLine.substring(0, 120)}…'
            : firstLine;
        buf.writeln('  • [${e.level}] $short${e.count > 1 ? ' (×${e.count})' : ''}');
      }
      if (untracked.length > 5) {
        buf.writeln('  …and ${untracked.length - 5} more');
      }
    }
    buf.writeln('');
    buf.writeln('Category breakdown:');
    for (final entry in categoryBreakdown.entries) {
      buf.writeln('  ${entry.key}: ${entry.value}');
    }
    return buf.toString();
  }

  /// Compact AI-ready diagnosis block for one row (Copy-diagnosis button
  /// + Fix-with-Agent task). Everything a fixer needs, nothing more:
  /// first line, widget path, environment, screen, recent actions, top
  /// stack frames. Secrets scrubbed — safe to paste anywhere.
  /// Never throws.
  String diagnosisFor(AppLogEntry e, {bool forAgent = false}) {
    try {
      final buf = StringBuffer();
      if (forAgent) {
        buf.writeln(
            'You are working in the CubicLM Flutter codebase (Dart/Flutter, GetX). '
            'Diagnose the issue below and fix it with a minimal change. '
            'Reply with the file path, the exact edit, and how you verified it.');
        buf.writeln('');
      }
      buf.writeln('### CubicLM issue report');
      buf.writeln('- App: $_appVersion · $_deviceSummary');
      buf.writeln(
          '- When: ${e.lastAt.toIso8601String()}${e.count > 1 ? ' (×${e.count})' : ''}');
      if (e.screen.isNotEmpty) buf.writeln('- Screen: ${e.screen}');
      buf.writeln('- Level: ${e.level} [${e.category.label}]');
      final first = e.message.split('\n').first.trim();
      buf.writeln('- Error: $first');
      final path = _sectionOf(e.message, '--- full widget path');
      if (path.isNotEmpty) {
        buf.writeln('- Widget path:');
        buf.writeln('```');
        buf.writeln(path);
        buf.writeln('```');
      }
      final env = _sectionOf(e.message, '--- environment ---');
      if (env.isNotEmpty) buf.writeln('- Env: $env');
      if (_actionTrail.isNotEmpty) {
        buf.writeln('- Recent actions: ${_actionTrail.take(5).join(' | ')}');
      }
      final stackTop = _stackTop(e.details, 15);
      if (stackTop.isNotEmpty) {
        buf.writeln('- Stack (top):');
        buf.writeln('```');
        buf.writeln(stackTop);
        buf.writeln('```');
      }
      return scrubExportSecrets(buf.toString());
    } catch (_) {
      return 'CubicLM issue: ${e.message.split('\n').first}';
    }
  }

  /// Text under a `--- marker ---` header up to the next `---` header or
  /// end, trimmed to [maxChars].
  String _sectionOf(String message, String marker, {int maxChars = 2000}) {
    try {
      final lines = message.split('\n');
      final start = lines.indexWhere((l) => l.trim().startsWith(marker));
      if (start < 0) return '';
      final out = <String>[];
      for (var i = start + 1; i < lines.length; i++) {
        final t = lines[i].trimRight();
        if (t.trimLeft().startsWith('---') && out.isNotEmpty) break;
        out.add(t);
      }
      var text = out.join('\n').trim();
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars)}…';
      }
      return text;
    } catch (_) {
      return '';
    }
  }

  /// First [maxFrames] `#N` stack lines from details (details already
  /// trimmed at capture; this keeps the diagnosis block compact).
  String _stackTop(String? details, int maxFrames) {
    try {
      if (details == null || details.isEmpty) return '';
      final frames =
          details.split('\n').where((l) => l.startsWith('#')).toList();
      if (frames.isEmpty) return '';
      return frames.take(maxFrames).join('\n');
    } catch (_) {
      return '';
    }
  }
}
