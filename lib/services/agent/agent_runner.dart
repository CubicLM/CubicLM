/// CubicLM Agentic Workspace — agent loop orchestrator.
///
/// Wires the pure [AgentLoop] to real services:
/// - Cloud path: [CloudService.sendMessage] (providers execute built-in +
///   MCP tools internally); per-tool progress is surfaced by subscribing to
///   [ToolRegistry.executions] during the call.
/// - Local path: [InferenceService.generate] with tool schemas injected
///   into the system prompt; replies parsed by [LocalToolParser] and
///   executed via [ToolRegistry.callTool] (with approval gate).
///
/// File tools are jailed to the run's project directory (resolved via
/// [AgentWorkspaceService]). A checkpoint is saved before each project run
/// so the UI can offer rollback.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../agent_workspace.dart';
import '../cloud_service.dart';
import '../inference_service.dart';
import '../tools/local_tool_parser.dart';
import '../tools/tool_interface.dart';
import '../tools/tool_registry.dart';
import 'agent_loop.dart';
import 'agent_memory.dart';
import 'agent_types.dart';

/// System instructions for plan-mode: numbered plan only, no tools.
const String _kPlanSystemPrompt = '''
You are a senior engineer scoping a task. Reply with ONLY a short numbered plan (5-10 concrete steps): what to explore, what to change, how to verify. No code, no tool calls, no JSON, no commentary outside the plan.
''';

/// Default system instructions for the general agent.
const String kAgentSystemPrompt = '''
You are CubicLM's coding agent running on-device. Work step by step:
1. Explore first (list_files, read_file, search_code) before changing anything.
2. Make the smallest change that solves the task (edit_file over write_file).
3. Verify with tests or builds (run_command) when the project supports it.
4. Summarize what you changed and how to verify. Never invent file contents you have not read.
''';

/// Orchestrator facade (registered in main deferred init).
class AgentRunner extends GetxService {
  final AgentMemory memory = AgentMemory();
  bool _cancelled = false;

  Future<AgentRunner> init() async => this;

  /// Cancel the in-flight run (checked between loop steps).
  void cancel() {
    _cancelled = true;
  }

  /// Run the agent for [prompt] with [config], yielding trace events.
  Stream<AgentEvent> run(String prompt, {AgentConfig? config}) async* {
    final cfg = config ?? const AgentConfig();
    _cancelled = false;
    final workspacePath = await _workspacePathFor(cfg.projectId);

    // Plan mode: agree on the plan with the user before any tool runs.
    var effectivePrompt = prompt;
    if (cfg.planMode) {
      final plan = await _requestPlanApproval(prompt, cfg);
      if (plan == null || _cancelled) {
        yield AgentEvent.cancelled();
        return;
      }
      yield AgentEvent.reasoning(plan);
      effectivePrompt = 'Approved plan:\n$plan\n\nOriginal task: $prompt';
    }

    // Pre-run checkpoint for project runs (rollback safety net).
    if (cfg.projectId != null && cfg.projectId!.isNotEmpty) {
      final cpId = await _saveCheckpoint(cfg.projectId!);
      if (cpId != null) yield AgentEvent.checkpoint(cpId);
    }

    if (cfg.useLocal) {
      yield* _runLocal(effectivePrompt, cfg, workspacePath);
    } else {
      yield* _runCloud(effectivePrompt, cfg, workspacePath);
    }
  }

  /// Ask the LLM for a numbered plan, then the user to approve it.
  /// Returns the approved plan text, or null on reject/failure.
  Future<String?> _requestPlanApproval(
      String prompt, AgentConfig config) async {
    String? plan;
    try {
      if (config.useLocal) {
        if (!Get.isRegistered<InferenceService>()) return null;
        final inference = Get.find<InferenceService>();
        if (!inference.isModelLoaded.value) return null;
        final raw = await inference.generate(
          prompt: prompt,
          systemPrompt: _kPlanSystemPrompt,
          source: 'agent-plan',
        );
        if (raw.startsWith('ERROR:')) return null;
        plan = raw;
      } else {
        if (!Get.isRegistered<CloudService>()) return null;
        plan = await Get.find<CloudService>().sendMessage(messages: [
          {'role': 'system', 'content': _kPlanSystemPrompt},
          {'role': 'user', 'content': prompt},
        ]);
      }
    } catch (_) {
      return null;
    }
    var text = plan.trim();
    if (text.isEmpty) return null;
    text = LocalToolParser.stripToolBlocks(text).trim();
    if (text.isEmpty) return null;
    if (text.length > 4000) text = '${text.substring(0, 4000)}…';
    final approved = await _showPlanDialog(text);
    return approved == true ? text : null;
  }

  Future<bool?> _showPlanDialog(String plan) async {
    try {
      return await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Approve agent plan?'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(plan),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Approve & run'),
            ),
          ],
        ),
        barrierDismissible: false,
      );
    } catch (_) {
      return false;
    }
  }

  // ── Cloud path ───────────────────────────────────────────────────

  Stream<AgentEvent> _runCloud(
    String prompt,
    AgentConfig config,
    String workspacePath,
  ) async* {
    if (!Get.isRegistered<CloudService>()) {
      yield AgentEvent.error('CloudService is not running.');
      return;
    }
    if (!Get.isRegistered<ToolRegistry>()) {
      yield AgentEvent.error('ToolRegistry is not running.');
      return;
    }

    final sessionId = 'cloud_${DateTime.now().microsecondsSinceEpoch}';
    memory.startSession(sessionId);
    memory.addMessage(sessionId, 'user', prompt);

    final registry = Get.find<ToolRegistry>();
    final cloud = Get.find<CloudService>();

    // Cloud providers resolve their own tool loop internally and return
    // the final answer, so the cloud path is a single pass (per-tool
    // progress arrives via ToolRegistry.executions, subscribed below).
    if (_cancelled) {
      yield AgentEvent.cancelled();
      return;
    }
    final context =
        memory.getContext(sessionId, maxChars: config.maxContextChars);

    // Collect tool executions that fire during this LLM call.
    final executed = <ToolExecutionRecord>[];
    final sub = registry.executions.listen(executed.add);
    String reply;
    try {
      final system = _cloudSystem(config);
      final messages = system == null
          ? context
          : [
              {'role': 'system', 'content': system},
              ...context,
            ];
      reply = await cloud.sendMessage(messages: messages);
    } catch (e) {
      await sub.cancel();
      yield AgentEvent.error('Cloud call failed: $e');
      return;
    }
    await sub.cancel();

    if (_cancelled) {
      yield AgentEvent.cancelled();
      return;
    }

    // Surface each executed tool as trace events.
    for (final rec in executed) {
      yield AgentEvent.toolStarted(rec.toolName);
      yield AgentEvent.toolCompleted(
        rec.toolName,
        success: rec.success,
        outputChars: rec.outputChars,
      );
      memory.addToolResult(
        sessionId,
        'cloud_${rec.timestampMs}',
        rec.toolName,
        rec.success
            ? '(tool ran, result folded into reply)'
            : '(tool failed — see reply)',
        maxChars: config.maxCharsPerToolResult,
      );
    }

    if (reply.trim().isNotEmpty) {
      memory.addMessage(sessionId, 'assistant', reply);
      yield AgentEvent.text(reply);
    }

    yield AgentEvent.complete();
  }

  String? _cloudSystem(AgentConfig config) {
    final extra = config.systemPrompt?.trim() ?? '';
    if (extra.isEmpty) return kAgentSystemPrompt.trim();
    return '${kAgentSystemPrompt.trim()}\n\n$extra';
  }

  // ── Local path ───────────────────────────────────────────────────

  Stream<AgentEvent> _runLocal(
    String prompt,
    AgentConfig config,
    String workspacePath,
  ) async* {
    if (!Get.isRegistered<InferenceService>()) {
      yield AgentEvent.error('InferenceService is not running.');
      return;
    }
    if (!Get.isRegistered<ToolRegistry>()) {
      yield AgentEvent.error('ToolRegistry is not running.');
      return;
    }
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      yield AgentEvent.error(
          'No local model loaded. Go to Models tab to download and load one.');
      return;
    }
    final registry = Get.find<ToolRegistry>();
    final schemas = registry.getOpenAITools();

    final loop = AgentLoop(
      memory: memory,
      isCancelled: () => _cancelled,
      llmCall: (messages, system) async {
        final toolPrompt = schemas.isEmpty
            ? (system ?? '')
            : '${LocalToolParser.buildToolSystemPrompt(schemas)}\n\n${system ?? ''}';
        final last = messages.isNotEmpty ? messages.last : {'content': prompt};
        final history =
            messages.length > 1 ? messages.sublist(0, messages.length - 1) : null;
        final raw = await inference.generate(
          prompt: (last['content'] ?? '').toString(),
          conversationHistory: history,
          systemPrompt: toolPrompt.isEmpty ? null : toolPrompt,
          source: 'agent',
        );
        if (raw.startsWith('ERROR:')) {
          throw Exception(raw);
        }
        final parsed = LocalToolParser.parseWithReasoning(raw);
        final toolCalls = [
          for (final c in parsed.calls)
            AgentToolCall(id: c.id, name: c.name, args: c.args),
        ];
        // Thinking-aloud beside tool calls renders as reasoning; without
        // calls it is the final answer.
        if (toolCalls.isNotEmpty) {
          return AgentLlmResponse(
              reasoning: parsed.reasoning, toolCalls: toolCalls);
        }
        return AgentLlmResponse(text: parsed.reasoning);
      },
      execTool: (name, args) async {
        final result = await registry.callTool(
          name,
          args,
          ToolContext(
            workspacePath: workspacePath,
            approve: (_, __) async => true,
          ),
        );
        return AgentToolOutcome(
          output: result.output,
          success: result.success,
          modifiedFiles: result.modifiedFiles,
        );
      },
    );

    yield* loop.run(
      prompt,
      config: config,
      systemPrompt: kAgentSystemPrompt,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<String> _workspacePathFor(String? projectId) async {
    try {
      if (projectId == null ||
          projectId.isEmpty ||
          !Get.isRegistered<AgentWorkspaceService>()) {
        return '';
      }
      final dir =
          await Get.find<AgentWorkspaceService>().dirFor(projectId);
      return dir.path;
    } catch (_) {
      return '';
    }
  }

  Future<String?> _saveCheckpoint(String projectId) async {
    try {
      if (!Get.isRegistered<AgentWorkspaceService>()) return null;
      return await Get.find<AgentWorkspaceService>()
          .saveCheckpoint(projectId, label: 'Agent run');
    } catch (_) {
      return null;
    }
  }
}
