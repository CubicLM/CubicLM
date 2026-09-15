/// CubicLM Agentic Workspace — conversation memory + context budgeting.
///
/// Keeps per-session messages and builds a char-budgeted context window for
/// the LLM: the first user message (the task) is always kept, then the most
/// recent messages that fit. Pure Dart — fully unit-testable.
library;

import 'agent_types.dart';

/// In-memory session store with budget-aware context building.
class AgentMemory {
  final Map<String, List<AgentMessage>> _sessions = {};

  /// Start (or restart) a session.
  void startSession(String sessionId) {
    _sessions[sessionId] = [];
  }

  /// Drop a session entirely.
  void clearSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  /// Append a user or assistant message.
  void addMessage(String sessionId, String role, String content) {
    final list = _sessions.putIfAbsent(sessionId, () => []);
    list.add(AgentMessage(role: role, content: content));
  }

  /// Append a tool result (stored as a `tool` message, rendered for the
  /// next LLM call with its call id + name for traceability).
  void addToolResult(
    String sessionId,
    String toolCallId,
    String toolName,
    String output, {
    int maxChars = 12000,
  }) {
    final list = _sessions.putIfAbsent(sessionId, () => []);
    var capped = output;
    if (capped.length > maxChars) {
      capped = '${capped.substring(0, maxChars)}\n…(truncated)';
    }
    list.add(AgentMessage(
      role: 'tool',
      content: 'Result of $toolName ($toolCallId):\n$capped',
      toolCallId: toolCallId,
      toolName: toolName,
    ));
  }

  /// Number of stored messages (for tests / UI counters).
  int messageCount(String sessionId) => _sessions[sessionId]?.length ?? 0;

  /// Build the budgeted context for the next LLM call.
  ///
  /// Keeps the first user message plus the newest messages that fit inside
  /// [maxChars]. Tool messages are mapped to `user` role (most chat APIs
  /// only accept user/assistant/system).
  List<Map<String, String>> getContext(String sessionId,
      {int maxChars = 60000}) {
    final all = _sessions[sessionId] ?? const <AgentMessage>[];
    if (all.isEmpty) return const [];

    var used = 0;
    final picked = <AgentMessage>[];
    for (var i = all.length - 1; i >= 0; i--) {
      final m = all[i];
      final cost = m.content.length;
      if (picked.isNotEmpty && used + cost > maxChars) break;
      picked.add(m);
      used += cost;
      if (used >= maxChars) break;
    }
    final ordered = picked.reversed.toList();

    // Always keep the task (first user message) when trimming dropped it.
    final firstUser = _firstUser(all);
    if (firstUser != null &&
        ordered.isNotEmpty &&
        !_sameMessage(ordered.first, firstUser)) {
      ordered.insert(0, firstUser);
    }

    return [
      for (final m in ordered)
        {
          'role': m.role == 'assistant' ? 'assistant' : 'user',
          'content': m.content,
        }
    ];
  }

  AgentMessage? _firstUser(List<AgentMessage> all) {
    for (final m in all) {
      if (m.role == 'user') return m;
    }
    return null;
  }

  bool _sameMessage(AgentMessage a, AgentMessage b) =>
      a.role == b.role && a.content == b.content;
}
