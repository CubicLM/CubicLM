/// Agent chat transcript, build steps, and terminal buffer.
///
/// Split from `agent_controller.dart` - behavior is unchanged.
/// Contains: _say(), _snapshotActivity(), _markLastAssistantWithBuild(), step(), _beginSteps()
///   _doneSummary(), term(), clearTerminal(), terminalTail()
part of 'agent_controller.dart';

extension AgentControllerChat on AgentController {
  void _say(String role, String text, {List<Map<String, String>>? activity}) {
    try {
      transcript.add({
        'role': role,
        'text': text,
        if (activity != null) 'activity': activity,
      });
      while (transcript.length > 100) {
        transcript.removeAt(0);
      }
    } catch (_) {}
  }

  void _snapshotActivity() {
    try {
      final idx = transcript.lastIndexWhere((m) => m['role'] == 'activity');
      if (idx != -1) {
        transcript[idx] = {
          'role': 'activity',
          'steps': buildSteps.toList(),
        };
      }
    } catch (_) {}
  }

  void _markLastAssistantWithBuild() {
    try {
      final idx = transcript.lastIndexWhere((m) => m['role'] == 'assistant');
      if (idx != -1) {
        transcript[idx] = {
          ...transcript[idx],
          'has_build': true,
        };
      }
    } catch (_) {}
  }

  /// Live build timeline (v0-style): thinking → files → errors → fixes.
  /// Rendered as an activity card in the chat pane. Cleared per task,
  /// kept across auto-fix rounds of the same task.

  /// Append one timeline step. Kinds: thinking | file | error | fix | done.
  void step(String kind, String text) {
    try {
      // Dynamic thinking messages for a more "lovable" experience
      String message = text;
      if (kind == 'thinking') {
        final messages = [
          'Analyzing requirements...',
          'Designing system architecture...',
          'Styling components with ${selectedLibrary.value}...',
          'Optimizing for ${selectedDesignSystem.value} style...',
          'Ensuring mobile responsiveness...',
          'Validating accessibility rules...',
        ];
        // Cycle through or pick based on context if we had more info
        if (text.toLowerCase().contains('planning')) message = messages[0];
        if (text.toLowerCase().contains('designing')) message = messages[1];
      }

      buildSteps.add({
        'kind': kind,
        'text': message.length > 140 ? '${message.substring(0, 140)}…' : message,
        'ms': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      while (buildSteps.length > 100) {
        buildSteps.removeAt(0);
      }
    } catch (_) {}
  }

  void _beginSteps() {
    try {
      buildSteps.clear();
    } catch (_) {}
    _announcedPaths.clear();
  }

  /// Rich completion summary: action line + changed-file list.
  String _doneSummary(String action, List<String> files) {
    final buf = StringBuffer(
        '$action — ${files.length} file${files.length == 1 ? '' : 's'} changed, preview reloaded.');
    for (final f in files.take(6)) {
      buf.write('\n• $f');
    }
    if (files.length > 6) buf.write('\n• …and ${files.length - 6} more');
    return buf.toString();
  }

  void term(String line) {
    try {
      final now = DateTime.now();
      final ts = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      // Strip TUI control codes for the log view (colors/cursor/
      // alternate-screen sequences would render as garbage here).
      terminal.add('[$ts] ${stripAnsi(line)}');
      while (terminal.length > 200) {
        terminal.removeAt(0);
      }
    } catch (_) {}
  }

  void clearTerminal() {
    try {
      terminal.clear();
    } catch (_) {}
  }

  /// Last N terminal lines for prompts (AI context).
  String terminalTail([int n = 30]) {
    try {
      final lines = terminal.toList();
      return lines.skip(lines.length > n ? lines.length - n : 0).join('\n');
    } catch (_) {
      return '';
    }
  }
}
