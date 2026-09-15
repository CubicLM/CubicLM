/// CubicLM Agentic Tool System — structured-output parser for local models.
///
/// Local models (llama.cpp / LiteRT) have no native function-calling API.
/// The agent loop injects tool schemas into the system prompt and the model
/// replies with JSON tool calls; this parser extracts them.
///
/// Accepted shapes (all optional, first match wins per block):
/// - ```json { ... } ``` fenced blocks (one call per block)
/// - <tool>{ ... }</tool> tagged blocks
/// - A bare `{ ... }` / `[ ... ]` document
///
/// Accepted call objects:
/// - `{"name": "read_file", "arguments": {"path": "..."}}`
/// - `{"function": "read_file", "args": {...}}` (lenient aliases)
/// - `{"tool_calls": [ ... ]}` wrapper
///
/// Pure Dart — no Flutter dependencies, fully unit-testable.
library;

import 'dart:convert';

/// A single parsed tool-call request from a local model.
class LocalToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  const LocalToolCall({
    required this.id,
    required this.name,
    required this.args,
  });

  @override
  String toString() => 'LocalToolCall($name, $args)';
}

/// Parsed reply: tool calls plus the model's thinking-aloud text.
class LocalParseResult {
  final List<LocalToolCall> calls;
  final String reasoning;

  const LocalParseResult({required this.calls, required this.reasoning});
}

/// Parser + prompt helpers for local-model tool calling.
class LocalToolParser {
  static final RegExp _fenceRe =
      RegExp(r'```(?:json)?\s*(.*?)```', dotAll: true);
  static final RegExp _tagRe =
      RegExp(r'<tool>(.*?)</tool>', dotAll: true);

  /// Extract tool calls from model [output]. Returns null when the output
  /// contains no parseable tool call (treat as a plain text reply).
  static List<LocalToolCall>? parse(String output) {
    // 1. Fenced blocks — collect calls from every block.
    final fenced = <LocalToolCall>[];
    for (final m in _fenceRe.allMatches(output)) {
      final calls = _parseDocument(m.group(1) ?? '', fenced.length);
      if (calls != null) fenced.addAll(calls);
    }
    if (fenced.isNotEmpty) return fenced;

    // 2. <tool> tags.
    final tagged = <LocalToolCall>[];
    for (final m in _tagRe.allMatches(output)) {
      final calls = _parseDocument(m.group(1) ?? '', tagged.length);
      if (calls != null) tagged.addAll(calls);
    }
    if (tagged.isNotEmpty) return tagged;

    // 3. Bare JSON document.
    final trimmed = output.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _parseDocument(trimmed, 0);
    }
    return null;
  }

  /// Parse [output] into tool calls + reasoning text in one pass.
  ///
  /// Text outside the tool blocks is the model's thinking-aloud: the loop
  /// renders it as a reasoning block when calls follow, or as the final
  /// answer when no calls exist.
  static LocalParseResult parseWithReasoning(String output) {
    final calls = parse(output);
    final reasoning = stripToolBlocks(output);
    if (calls == null || calls.isEmpty) {
      return LocalParseResult(calls: const [], reasoning: reasoning);
    }
    return LocalParseResult(calls: calls, reasoning: reasoning);
  }

  /// Remove tool-call blocks so the UI can show the model's visible text.
  static String stripToolBlocks(String output) {
    var s = output.replaceAll(_fenceRe, ' ');
    s = s.replaceAll(_tagRe, ' ');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  /// Build the system-prompt addition that teaches a local model the
  /// available tools and the exact reply format.
  static String buildToolSystemPrompt(
      List<Map<String, dynamic>> toolSchemas) {
    final buf = StringBuffer()
      ..writeln(
          'You have access to the following tools. To use a tool, reply with ONLY a fenced json block — one block per call:');
    for (final schema in toolSchemas) {
      try {
        buf.writeln('```json');
        buf.writeln(const JsonEncoder.withIndent('  ').convert(schema));
        buf.writeln('```');
      } catch (_) {}
    }
    buf
      ..writeln('Each block must be an object like:')
      ..writeln(
          '```json {"name": "<tool_name>", "arguments": {<args>}} ```')
      ..writeln(
          'Rules: call one tool per block; wait for the tool result before continuing; '
          'when no tool is needed, reply in plain text with no json block.');
    return buf.toString();
  }

  // ── Internals ────────────────────────────────────────────────────

  static List<LocalToolCall>? _parseDocument(String doc, int idOffset) {
    final text = doc.trim();
    if (text.isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // Try to salvage the largest {...} substring (trailing chatter).
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        decoded = jsonDecode(text.substring(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    if (decoded is List) {
      final out = <LocalToolCall>[];
      for (var i = 0; i < decoded.length; i++) {
        final call = _parseCallObject(decoded[i], idOffset + out.length);
        if (call != null) out.add(call);
      }
      return out.isEmpty ? null : out;
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      // Wrapper: {"tool_calls": [...]}
      if (map['tool_calls'] is List) {
        final out = <LocalToolCall>[];
        for (final item in (map['tool_calls'] as List)) {
          final call = _parseCallObject(item, idOffset + out.length);
          if (call != null) out.add(call);
        }
        return out.isEmpty ? null : out;
      }
      final call = _parseCallObject(map, idOffset);
      return call == null ? null : [call];
    }
    return null;
  }

  static LocalToolCall? _parseCallObject(dynamic obj, int index) {
    if (obj is! Map) return null;
    final map = Map<String, dynamic>.from(obj);
    // OpenAI delta shape: {"function": {"name": ..., "arguments": "..."}}
    if (map['function'] is Map) {
      final fn = Map<String, dynamic>.from(map['function'] as Map);
      final name = (fn['name'] ?? '').toString().trim();
      if (name.isEmpty) return null;
      return LocalToolCall(
        id: 'call_${index + 1}',
        name: name,
        args: _coerceArgs(fn['arguments']),
      );
    }
    final name = (map['name'] ?? map['function'] ?? map['tool'] ?? '')
        .toString()
        .trim();
    if (name.isEmpty || name.contains(' ')) return null;
    final rawArgs =
        map['arguments'] ?? map['args'] ?? map['input'] ?? <String, dynamic>{};
    return LocalToolCall(
      id: (map['id']?.toString().trim().isNotEmpty ?? false)
          ? map['id'].toString()
          : 'call_${index + 1}',
      name: name,
      args: _coerceArgs(rawArgs),
    );
  }

  static Map<String, dynamic> _coerceArgs(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }
}
