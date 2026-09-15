/// CubicLM Agentic Workspace — the general-purpose agent event loop.
///
/// Runs: prompt → LLM → (tool calls → execute → results) × N → done.
/// The LLM call and tool execution are injected callbacks so the loop stays
/// UI- and service-free (unit-testable with fakes). The [AgentRunner]
/// wires in the real Cloud/Inference services + ToolRegistry.
///
/// Pure Dart — no Flutter dependencies.
library;

import 'agent_memory.dart';
import 'agent_types.dart';

/// LLM call: given budgeted messages + optional system prompt, return text
/// plus any requested tool calls.
typedef AgentLlmCall = Future<AgentLlmResponse> Function(
  List<Map<String, String>> messages,
  String? systemPrompt,
);

/// Tool execution: run one named tool, never throws (errors → outcome).
typedef AgentToolExec = Future<AgentToolOutcome> Function(
  String name,
  Map<String, dynamic> args,
);

/// Cancellation probe: return true to stop after the current step.
typedef AgentCancelCheck = bool Function();

/// General agent loop.
class AgentLoop {
  final AgentMemory memory;
  final AgentLlmCall llmCall;
  final AgentToolExec execTool;
  final AgentCancelCheck? isCancelled;

  AgentLoop({
    required this.memory,
    required this.llmCall,
    required this.execTool,
    this.isCancelled,
  });

  /// Run the loop for [prompt], yielding trace events.
  Stream<AgentEvent> run(
    String prompt, {
    AgentConfig config = const AgentConfig(),
    String? systemPrompt,
    List<Map<String, String>>? history,
  }) async* {
    final sessionId = 'agent_${DateTime.now().microsecondsSinceEpoch}';
    memory.startSession(sessionId);
    if (history != null) {
      for (final h in history) {
        memory.addMessage(
            sessionId, h['role'] ?? 'user', h['content'] ?? '');
      }
    }
    memory.addMessage(sessionId, 'user', prompt);

    final effectiveSystem = _composeSystem(systemPrompt, config.systemPrompt);

    for (var i = 0; i < config.maxIterations; i++) {
      if (isCancelled?.call() ?? false) {
        yield AgentEvent.cancelled();
        return;
      }

      final context = memory.getContext(sessionId,
          maxChars: config.maxContextChars);

      AgentLlmResponse response;
      try {
        response = await llmCall(context, effectiveSystem);
      } catch (e) {
        yield AgentEvent.error('LLM call failed: $e');
        return;
      }

      // Thinking-aloud blocks render as reasoning (display-only, like the
      // reference app's ReasoningSummary — never stored in memory).
      if (response.reasoning.isNotEmpty) {
        yield AgentEvent.reasoning(response.reasoning);
      }

      if (response.text.isNotEmpty) {
        memory.addMessage(sessionId, 'assistant', response.text);
        yield AgentEvent.text(response.text);
      }

      if (!response.wantsTools) {
        yield AgentEvent.complete();
        return;
      }

      for (final call in response.toolCalls) {
        if (isCancelled?.call() ?? false) {
          yield AgentEvent.cancelled();
          return;
        }
        yield AgentEvent.toolStarted(call.name);
        AgentToolOutcome outcome;
        try {
          outcome = await execTool(call.name, call.args);
        } catch (e) {
          outcome = AgentToolOutcome(output: 'Error: $e', success: false);
        }
        memory.addToolResult(
          sessionId,
          call.id,
          call.name,
          outcome.output,
          maxChars: config.maxCharsPerToolResult,
        );
        yield AgentEvent.toolCompleted(
          call.name,
          success: outcome.success,
          outputChars: outcome.output.length,
          modifiedFiles: outcome.modifiedFiles,
        );
      }
    }

    yield AgentEvent.complete(maxIterations: true);
  }

  static String? _composeSystem(String? a, String? b) {
    final parts = [a, b]
        .where((s) => s != null && s.trim().isNotEmpty)
        .cast<String>()
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }
}
