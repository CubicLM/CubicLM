/// CubicLM Agentic Workspace — core agent types.
///
/// Shared vocabulary for the agent loop, runner, controller, and views.
/// Pure Dart — no Flutter dependencies, fully unit-testable.
library;

/// A tool call requested by the LLM.
class AgentToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  const AgentToolCall({
    required this.id,
    required this.name,
    required this.args,
  });
}

/// The LLM's reply for one loop iteration.
class AgentLlmResponse {
  final String text;
  final List<AgentToolCall> toolCalls;

  /// Thinking-aloud text shown as a reasoning block (not stored in memory).
  final String reasoning;

  const AgentLlmResponse({
    this.text = '',
    this.toolCalls = const [],
    this.reasoning = '',
  });

  bool get wantsTools => toolCalls.isNotEmpty;
}

/// Result of executing one tool inside the agent loop.
///
/// Mirrors the fields the loop needs from `ToolResult` without depending
/// on the tools package (keeps this file dependency-free).
class AgentToolOutcome {
  final String output;
  final bool success;
  final List<String> modifiedFiles;

  const AgentToolOutcome({
    required this.output,
    this.success = true,
    this.modifiedFiles = const [],
  });
}

/// Configuration for one agent run.
class AgentConfig {
  /// Maximum LLM ↔ tool round-trips before stopping.
  final int maxIterations;

  /// Max chars kept per tool result in memory (rest truncated).
  final int maxCharsPerToolResult;

  /// Max chars of conversation context sent to the LLM.
  final int maxContextChars;

  /// Use the on-device model instead of cloud.
  final bool useLocal;

  /// Agent workspace project id (files/tools jail to it). Null = no files.
  final String? projectId;

  /// Extra system instructions prepended to the default prompt.
  final String? systemPrompt;

  /// When true, the runner first asks for a numbered plan and shows an
  /// Approve/Reject dialog before any tool runs (plan mode).
  final bool planMode;

  const AgentConfig({
    this.maxIterations = 12,
    this.maxCharsPerToolResult = 12000,
    this.maxContextChars = 60000,
    this.useLocal = false,
    this.projectId,
    this.systemPrompt,
    this.planMode = false,
  });
}

/// Kinds of agent-loop events streamed to the UI.
enum AgentEventKind {
  text,
  reasoning,
  toolStarted,
  toolCompleted,
  checkpoint,
  complete,
  error,
  cancelled,
}

/// One event in an agent run's execution trace.
class AgentEvent {
  final AgentEventKind kind;
  final String text;
  final String toolName;
  final bool success;
  final int outputChars;
  final List<String> modifiedFiles;
  final String checkpointId;
  final bool maxIterations;
  final int timestampMs;

  const AgentEvent({
    required this.kind,
    this.text = '',
    this.toolName = '',
    this.success = true,
    this.outputChars = 0,
    this.modifiedFiles = const [],
    this.checkpointId = '',
    this.maxIterations = false,
    required this.timestampMs,
  });

  factory AgentEvent.text(String text) => AgentEvent(
        kind: AgentEventKind.text,
        text: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.reasoning(String text) => AgentEvent(
        kind: AgentEventKind.reasoning,
        text: text,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.toolStarted(String toolName) => AgentEvent(
        kind: AgentEventKind.toolStarted,
        toolName: toolName,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.toolCompleted(
    String toolName, {
    bool success = true,
    int outputChars = 0,
    List<String> modifiedFiles = const [],
  }) =>
      AgentEvent(
        kind: AgentEventKind.toolCompleted,
        toolName: toolName,
        success: success,
        outputChars: outputChars,
        modifiedFiles: modifiedFiles,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.checkpoint(String id) => AgentEvent(
        kind: AgentEventKind.checkpoint,
        checkpointId: id,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.complete({bool maxIterations = false}) => AgentEvent(
        kind: AgentEventKind.complete,
        maxIterations: maxIterations,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.error(String message) => AgentEvent(
        kind: AgentEventKind.error,
        text: message,
        success: false,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory AgentEvent.cancelled() => AgentEvent(
        kind: AgentEventKind.cancelled,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
}

/// One message in agent memory.
class AgentMessage {
  final String role; // user | assistant | tool
  final String content;
  final String? toolCallId;
  final String? toolName;

  const AgentMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
  });

  Map<String, String> toMap() => {'role': role, 'content': content};
}
