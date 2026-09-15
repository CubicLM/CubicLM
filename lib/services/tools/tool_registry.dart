/// CubicLM Agentic Tool System — tool registration and dispatch.
///
/// The registry holds all built-in tools and merges them with external MCP
/// tools for LLM requests. It also handles the approval gate for tool calls.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../hive_service.dart';
import 'tool_interface.dart';

/// Central registry for all tools (built-in + MCP).
class ToolRegistry {
  final Map<String, Tool> _builtInTools = {};
  final Set<String> _alwaysAllow = {};
  bool _approvalEnabled = true;

  final _execController = StreamController<ToolExecutionRecord>.broadcast();

  /// Broadcast of completed tool executions (for agent-loop tracing).
  Stream<ToolExecutionRecord> get executions => _execController.stream;

  /// Close the execution stream. Called on app shutdown (best-effort).
  void dispose() {
    try {
      _execController.close();
    } catch (_) {}
  }

  /// Initialize the registry. Call once at app startup.
  Future<ToolRegistry> init() async {
    _loadApprovalSettings();
    return this;
  }

  // ── Registration ──────────────────────────────────────────────────

  /// Register a built-in tool. Overwrites if name already exists.
  void register(Tool tool) => _builtInTools[tool.name] = tool;

  /// Register multiple tools at once.
  void registerAll(List<Tool> tools) {
    for (final tool in tools) {
      _builtInTools[tool.name] = tool;
    }
  }

  /// Unregister a tool by name.
  void unregister(String name) => _builtInTools.remove(name);

  /// Get a tool by name.
  Tool? getTool(String name) => _builtInTools[name];

  /// All registered built-in tools.
  List<Tool> get builtInTools => _builtInTools.values.toList();

  /// All built-in tool names.
  List<String> get builtInToolNames => _builtInTools.keys.toList();

  // ── Schema Generation ────────────────────────────────────────────

  /// Generate OpenAI-format tool schemas for all built-in tools.
  List<Map<String, dynamic>> getOpenAITools() =>
      _builtInTools.values.map(toolToOpenAI).toList();

  /// Generate Anthropic-format tool schemas for all built-in tools.
  List<Map<String, dynamic>> getAnthropicTools() =>
      _builtInTools.values.map(toolToAnthropic).toList();

  /// Merge built-in tools with external MCP tools (for OpenAI format).
  /// Built-in tools take priority on name collision.
  List<Map<String, dynamic>> mergeOpenAITools(List<Map<String, dynamic>>? mcpTools) {
    final result = getOpenAITools();
    if (mcpTools != null) {
      final builtInNames = _builtInTools.keys.toSet();
      for (final mcp in mcpTools) {
        final fn = mcp['function'] as Map<String, dynamic>?;
        final name = fn?['name'] as String?;
        if (name != null && !builtInNames.contains(name)) {
          result.add(mcp);
        }
      }
    }
    return result;
  }

  /// Merge built-in tools with external MCP tools (for Anthropic format).
  List<Map<String, dynamic>> mergeAnthropicTools(List<Map<String, dynamic>>? mcpTools) {
    final result = getAnthropicTools();
    if (mcpTools != null) {
      final builtInNames = _builtInTools.keys.toSet();
      for (final mcp in mcpTools) {
        final name = mcp['name'] as String?;
        if (name != null && !builtInNames.contains(name)) {
          result.add(mcp);
        }
      }
    }
    return result;
  }

  // ── Dispatch ─────────────────────────────────────────────────────

  /// Execute a tool by name. Handles approval gate.
  ///
  /// Returns a [ToolResult] — never throws.
  Future<ToolResult> callTool(
    String name,
    Map<String, dynamic> args,
    ToolContext context,
  ) async {
    final tool = _builtInTools[name];
    if (tool == null) {
      return ToolResult.error('Unknown tool: $name');
    }

    // Approval gate
    if (!await _approveToolCall(tool, args)) {
      _emit(name, false, 0, 0);
      return const ToolResult(
        output: 'Tool call denied by user.',
        success: false,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final result = await tool.execute(args, context);
      _emit(name, result.success, result.output.length, sw.elapsedMilliseconds);
      return result;
    } catch (e) {
      _emit(name, false, 0, sw.elapsedMilliseconds);
      return ToolResult.error('Tool execution failed: $e');
    }
  }

  /// Execute a tool WITHOUT the approval gate (caller already approved).
  ///
  /// Used by cloud providers that run their own approval dialog before
  /// dispatch. Still emits an execution record for agent tracing.
  /// Returns a [ToolResult] — never throws.
  Future<ToolResult> executeApproved(
    String name,
    Map<String, dynamic> args,
    ToolContext context,
  ) async {
    final tool = _builtInTools[name];
    if (tool == null) {
      return ToolResult.error('Unknown tool: $name');
    }
    final sw = Stopwatch()..start();
    try {
      final result = await tool.execute(args, context);
      _emit(name, result.success, result.output.length, sw.elapsedMilliseconds);
      return result;
    } catch (e) {
      _emit(name, false, 0, sw.elapsedMilliseconds);
      return ToolResult.error('Tool execution failed: $e');
    }
  }

  void _emit(String name, bool success, int outputChars, int elapsedMs) {
    try {
      if (!_execController.isClosed) {
        _execController.add(ToolExecutionRecord(
          toolName: name,
          success: success,
          outputChars: outputChars,
          elapsedMs: elapsedMs,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    } catch (_) {}
  }

  // ── Approval Gate ────────────────────────────────────────────────

  /// Check if a tool call should be approved.
  Future<bool> _approveToolCall(Tool tool, Map<String, dynamic> args) async {
    // Per-arguments risk for tools that classify their own calls.
    ToolRisk risk;
    if (tool is RiskAwareTool) {
      risk = tool.riskFor(args);
    } else {
      risk = tool.risk;
    }
    // Safe tools always pass
    if (risk == ToolRisk.safe) return true;

    // Always-allow list
    if (_alwaysAllow.contains(tool.name)) return true;

    // Approval toggle off
    if (!_approvalEnabled) return true;

    // Show approval dialog
    return _showApprovalDialog(tool, args, risk);
  }

  Future<bool> _showApprovalDialog(
      Tool tool, Map<String, dynamic> args, ToolRisk risk) async {
    final argsText = _truncateArgs(args);
    final decision = await Get.dialog<String>(
      AlertDialog(
        title: Row(
          children: [
            Icon(
              risk == ToolRisk.high ? Icons.warning_amber : Icons.build,
              color: risk == ToolRisk.high ? AppColors.warning : Dt.accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text('Allow tool call?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.name,
                style: GoogleFonts.firaCode(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tool.description,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(argsText,
                  style: GoogleFonts.firaCode(fontSize: 11)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: 'deny'),
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'always'),
            child: const Text('Always allow'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: 'once'),
            child: const Text('Allow once'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (decision == 'always') {
      _alwaysAllow.add(tool.name);
      _saveApprovalSettings();
      return true;
    }
    return decision == 'once';
  }

  String _truncateArgs(Map<String, dynamic> args) {
    try {
      final s = const JsonEncoder.withIndent('  ').convert(args);
      return s.length > 800 ? '${s.substring(0, 800)}…' : s;
    } catch (_) {
      final s = args.toString();
      return s.length > 800 ? '${s.substring(0, 800)}…' : s;
    }
  }

  // ── Persistence ──────────────────────────────────────────────────

  void _loadApprovalSettings() {
    try {
      final hive = Get.find<HiveService>();
      _approvalEnabled =
          hive.getSetting<bool>('tool_approval_enabled', defaultValue: true) ??
              true;
      final list = hive.getSetting<List>('tool_always_allow');
      if (list != null) {
        _alwaysAllow.addAll(list.map((e) => e.toString()));
      }
    } catch (_) {}
  }

  void _saveApprovalSettings() {
    try {
      final hive = Get.find<HiveService>();
      hive.setSetting('tool_approval_enabled', _approvalEnabled);
      hive.setSetting('tool_always_allow', _alwaysAllow.toList());
    } catch (_) {}
  }

  // ── Settings ─────────────────────────────────────────────────────

  /// Toggle the approval gate on/off.
  void setApprovalEnabled(bool enabled) {
    _approvalEnabled = enabled;
    _saveApprovalSettings();
  }

  /// Whether the approval gate is enabled.
  bool get isApprovalEnabled => _approvalEnabled;

  /// Clear the always-allow list.
  void clearAlwaysAllow() {
    _alwaysAllow.clear();
    _saveApprovalSettings();
  }
}
