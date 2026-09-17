import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';
import '../../hive_service.dart';
import '../../mcp/mcp_registry_service.dart';
import '../../tools/tool_interface.dart';
import '../../tools/tool_registry.dart';

/// Abstract base class for providers that use OpenAI-compatible API format.
///
/// This includes OpenAI, DeepSeek, NVIDIA, OpenRouter, Z.AI, Kimi, and Custom.
/// Override specific methods for providers that need custom behavior.
/// Concrete subclasses must implement: id, name, description, icon, endpoint.
abstract class OpenAICompatibleProvider extends CloudProvider {
  @override
  ProviderProtocol get protocol => ProviderProtocol.openAICompatible;

  @override
  bool get supportsStreaming => true;

  List<Map<String, dynamic>>? _mcpToolsPayload() {
    try {
      // Built-in tools (always available if registered)
      List<Map<String, dynamic>>? builtIn;
      if (Get.isRegistered<ToolRegistry>()) {
        final reg = Get.find<ToolRegistry>();
        builtIn = reg.getOpenAITools();
      }

      // MCP tools (external servers)
      List<Map<String, dynamic>>? mcp;
      if (Get.isRegistered<McpRegistryService>()) {
        final reg = Get.find<McpRegistryService>();
        final cfg = reg.config.value;
        if (cfg != null && cfg.enabled) {
          final tools = reg.tools;
          if (tools.isNotEmpty) {
            mcp = tools.map((t) => t.toOpenAITool()).toList();
          }
        }
      }

      // Merge: built-in tools take priority on name collision
      if (builtIn != null && builtIn.isNotEmpty) {
        if (mcp != null) {
          final builtInNames = builtIn
              .map((t) => (t['function'] as Map?)?['name']?.toString() ?? '')
              .toSet();
          for (final m in mcp) {
            final fn = m['function'] as Map?;
            final name = fn?['name']?.toString() ?? '';
            if (name.isNotEmpty && !builtInNames.contains(name)) {
              builtIn.add(m);
            }
          }
        }
        return builtIn;
      }

      return mcp;
    } catch (_) {
      return null;
    }
  }

  static const _kMcpApprovalKey = 'mcp_require_approval';
  static const _kMcpAlwaysAllowKey = 'mcp_always_allow_tools';

  /// Approval gate for MCP tool calls. Returns true when the call may run.
  /// - Tools on the always-allow list run silently.
  /// - When the approval toggle is off, everything runs (old behavior).
  /// - Otherwise a blocking dialog asks: Deny / Allow once / Always allow.
  /// Never throws — on any UI failure the call is denied (fail-closed).
  Future<bool> _approveToolCall(String name, Map<String, dynamic> args) async {
    try {
      final hive = Get.find<HiveService>();
      final always =
          (hive.getSetting<List>(_kMcpAlwaysAllowKey) ?? const [])
              .map((e) => e.toString())
              .toSet();
      if (always.contains(name)) return true;
      final require =
          hive.getSetting<bool>(_kMcpApprovalKey, defaultValue: true) ?? true;
      if (!require) return true;
      final argsText = _truncateArgs(args);
      final decision = await Get.dialog<String>(
        AlertDialog(
          title: const Text('Allow tool call?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(argsText,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: 'deny'),
                child: const Text('Deny')),
            TextButton(
                onPressed: () => Get.back(result: 'always'),
                child: const Text('Always allow')),
            FilledButton(
                onPressed: () => Get.back(result: 'once'),
                child: const Text('Allow once')),
          ],
        ),
        barrierDismissible: false,
      );
      if (decision == 'always') {
        try {
          await hive.setSetting(
              _kMcpAlwaysAllowKey, [...always, name].toList());
        } catch (_) {}
        return true;
      }
      return decision == 'once';
    } catch (_) {
      return false;
    }
  }

  String _truncateArgs(Map<String, dynamic> args) {
    try {
      final s = const JsonEncoder.withIndent('  ').convert(args);
      return s.length > 800 ? '${s.substring(0, 800)}…(truncated)' : s;
    } catch (_) {
      final s = args.toString();
      return s.length > 800 ? '${s.substring(0, 800)}…(truncated)' : s;
    }
  }

  /// Normalizes raw tool calls from a first response into OpenAI shape
  /// with a guaranteed non-empty id per call. Streaming deltas often
  /// arrive with `id: ''`, and strict providers (NVIDIA et al.) 400 on
  /// missing ids — and on tool results that don't match them exactly.
  /// Pure — unit tested.
  static List<Map<String, dynamic>> normalizeToolCalls(
      List<dynamic> toolCalls) {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final tc in toolCalls) {
      if (tc is! Map) continue;
      var id = tc['id']?.toString() ?? '';
      if (id.isEmpty) {
        id = 'call_${DateTime.now().microsecondsSinceEpoch}_$i';
      }
      final fn = tc['function'] is Map
          ? Map<String, dynamic>.from(tc['function'] as Map)
          : <String, dynamic>{};
      out.add({
        'id': id,
        'type': tc['type']?.toString() ?? 'function',
        'function': {
          'name': fn['name']?.toString() ?? '',
          'arguments': fn['arguments']?.toString() ?? '{}',
        },
      });
      i++;
    }
    return out;
  }

  /// Builds the tool-follow-up message list: prior messages, the
  /// assistant message carrying the NORMALIZED tool_calls, then one
  /// tool message per result — each keeping its tool_call_id.
  /// Pure — unit tested.
  static List<Map<String, dynamic>> buildFollowUpMessages({
    required List<Map<String, String>> messages,
    required String assistantContent,
    required List<Map<String, dynamic>> normalizedCalls,
    required List<Map<String, String>> toolResults,
  }) {
    final apiMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      apiMessages.add({'role': m['role'], 'content': m['content']});
    }
    apiMessages.add({
      'role': 'assistant',
      'content': assistantContent,
      'tool_calls': normalizedCalls,
    });
    for (final r in toolResults) {
      apiMessages.add({
        'role': 'tool',
        'tool_call_id': r['id'],
        'content': r['text'],
      });
    }
    return apiMessages;
  }

  Future<String> _handleToolCalls(
    List<Map<String, String>> messages,
    String apiKey,
    String model,
    Map<String, dynamic> firstMessage,
    List<dynamic> toolCalls,
  ) async {
    final normalized = normalizeToolCalls(toolCalls);
    final toolResults = <Map<String, String>>[];
    for (final ntc in normalized) {
      final id = ntc['id'] as String;
      final fn =
          ntc['function'] is Map ? ntc['function'] as Map : <String, dynamic>{};
      final name = fn['name']?.toString() ?? '';
      final argsRaw = fn['arguments']?.toString() ?? '{}';
      Map<String, dynamic> args;
      try {
        args = jsonDecode(argsRaw) is Map
            ? Map<String, dynamic>.from(jsonDecode(argsRaw))
            : {};
      } catch (_) {
        args = {};
      }
      Map<String, dynamic> result;
      try {
        final allowed = await _approveToolCall(name, args);
        if (!allowed) {
          result = {
            'content': [
              {'type': 'text', 'text': 'Tool $name was denied by the user.'}
            ],
            'isError': true,
          };
        } else if (Get.isRegistered<ToolRegistry>()) {
          // Try built-in tool first
          final toolReg = Get.find<ToolRegistry>();
          final tool = toolReg.getTool(name);
          if (tool != null) {
            // Workspace path will be properly set by agent loop; for cloud
            // provider direct calls, use empty string (file tools will fail gracefully).
            // executeApproved: approval already happened above; emits a
            // trace record for the agent loop.
            final toolResult = await toolReg.executeApproved(name, args, ToolContext(
              workspacePath: '',
              approve: (n, a) => _approveToolCall(n, a),
            ));
            result = {
              'content': [
                {'type': 'text', 'text': toolResult.output}
              ],
              'isError': !toolResult.success,
            };
          } else if (Get.isRegistered<McpRegistryService>()) {
            // Fall back to MCP tools
            final mcpReg = Get.find<McpRegistryService>();
            result = await mcpReg.callTool(name, args);
          } else {
            result = {
              'content': [
                {'type': 'text', 'text': 'Tool $name not found.'}
              ],
              'isError': true,
            };
          }
        } else if (Get.isRegistered<McpRegistryService>()) {
          final mcpReg = Get.find<McpRegistryService>();
          result = await mcpReg.callTool(name, args);
        } else {
          result = {
            'content': [
              {'type': 'text', 'text': 'No tool registry available.'}
            ],
            'isError': true,
          };
        }
      } catch (e) {
        result = {
          'content': [
            {'type': 'text', 'text': 'Tool $name failed: $e'}
          ],
          'isError': true,
        };
      }
      // Cap result text for context safety.
      String resultText;
      try {
        final content = result['content'];
        if (content is List) {
          resultText = content
              .map((c) => c is Map ? c['text']?.toString() ?? jsonEncode(c) : c.toString())
              .join('\n');
        } else {
          resultText = jsonEncode(result);
        }
        if (resultText.length > 18000) {
          resultText = '${resultText.substring(0, 18000)}\n…(truncated)';
        }
      } catch (_) {
        resultText = result.toString();
      }
      toolResults.add({'id': id, 'text': resultText});
    }

    // Second request with tool results appended. The assistant message
    // carries the NORMALIZED tool_calls (same ids as the results) and
    // every tool message keeps its tool_call_id — strict providers
    // (NVIDIA et al.) 400 when either is missing or mismatched.
    final apiMessages2 = buildFollowUpMessages(
      messages: messages,
      assistantContent: firstMessage['content']?.toString() ?? '',
      normalizedCalls: normalized,
      toolResults: toolResults,
    );
    final mcpTools = _mcpToolsPayload();
    final body2Fixed = {
      'model': model,
      if (mcpTools != null) 'tools': mcpTools,
      if (mcpTools != null) 'tool_choice': 'auto',
      'messages': apiMessages2,
    };

    final resp2 = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            ...buildAuthHeaders(apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body2Fixed),
        )
        .timeout(const Duration(minutes: 3));

    if (resp2.statusCode != 200) {
      throw Exception(
          '${runtimeType.toString()} tool follow-up error: ${resp2.statusCode} ${resp2.body}');
    }
    final data2 = jsonDecode(resp2.body);
    return data2['choices'][0]['message']['content']?.toString() ?? '';
  }

  @override
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async {
    final mcpTools = _mcpToolsPayload();
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: false,
      mcpTools: mcpTools,
    );

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            ...buildAuthHeaders(apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      throw Exception(
          '${runtimeType.toString()} API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final message = data['choices'][0]['message'] as Map<String, dynamic>? ?? {};
    final toolCalls = message['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty && mcpTools != null) {
      return _handleToolCalls(messages, apiKey, model, message, toolCalls);
    }
    return message['content']?.toString() ?? '';
  }

  @override
  Stream<String> streamMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async* {
    final mcpTools = _mcpToolsPayload();
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: true,
      mcpTools: mcpTools,
    );

    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers.addAll({
      ...buildAuthHeaders(apiKey),
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode(body);

    final streamedResponse = await request.send().timeout(
          const Duration(minutes: 3),
        );

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw Exception(
          '${runtimeType.toString()} streaming error: ${streamedResponse.statusCode} $errorBody');
    }

    // If MCP tools are active, we need to detect tool_calls in the stream.
    final List<Map<String, dynamic>> pendingToolCalls = [];

    String buffer = '';
    await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6);
        if (jsonStr == '[DONE]') {
          // Tool handling will happen after loop if needed.
          if (pendingToolCalls.isNotEmpty) {
            final finalAnswer = await _handleToolCalls(
                messages, apiKey, model, {'content': ''}, pendingToolCalls);
            // Yield final answer chunked.
            for (final word in finalAnswer.split(' ')) {
              if (word.isNotEmpty) yield '$word ';
            }
          }
          return;
        }

        try {
          final data = jsonDecode(jsonStr);
          final choice = data['choices']?[0];
          final delta = choice?['delta'];
          if (delta == null) continue;
          final content = delta['content'];
          if (content != null) yield content.toString();

          // Tool calls in streaming delta.
          final toolCallsDelta = delta['tool_calls'] as List?;
          if (toolCallsDelta != null && mcpTools != null) {
            for (final tc in toolCallsDelta) {
              if (tc is! Map) continue;
              final idx = (tc['index'] as num?)?.toInt() ?? 0;
              while (pendingToolCalls.length <= idx) {
                pendingToolCalls.add({
                  'id': '',
                  'type': 'function',
                  'function': {'name': '', 'arguments': ''}
                });
              }
              final existing = pendingToolCalls[idx];
              if (tc['id'] != null) existing['id'] = tc['id'].toString();
              if (tc['type'] != null) existing['type'] = tc['type'].toString();
              final fn = tc['function'];
              if (fn is Map) {
                final existingFn = existing['function'] as Map<String, dynamic>;
                if (fn['name'] != null) {
                  existingFn['name'] = fn['name'].toString();
                }
                if (fn['arguments'] != null) {
                  existingFn['arguments'] =
                      (existingFn['arguments']?.toString() ?? '') +
                          fn['arguments'].toString();
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (buffer.trim().isNotEmpty) {
      final trimmed = buffer.trim();
      if (trimmed.startsWith('data: ') && trimmed.substring(6) != '[DONE]') {
        try {
          final data = jsonDecode(trimmed.substring(6));
          final delta = data['choices']?[0]?['delta']?['content'];
          if (delta != null) yield delta.toString();
        } catch (_) {}
      }
    }

    if (pendingToolCalls.isNotEmpty) {
      final finalAnswer = await _handleToolCalls(
          messages, apiKey, model, {'content': ''}, pendingToolCalls);
      for (final word in finalAnswer.split(' ')) {
        if (word.isNotEmpty) yield '$word ';
      }
    }
  }

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    List<String> tryExtract(Map root) {
      for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
        final raw = root[key];
        if (raw is List && raw.isNotEmpty) {
          final ids = raw
              .map((m) {
                if (m is! Map) return null;
                return m['id']?.toString() ??
                    m['name']?.toString() ??
                    m['model']?.toString();
              })
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          if (ids.isNotEmpty) return ids;
        }
      }
      return const [];
    }

    if (data is Map<String, dynamic>) {
      final ids = tryExtract(data);
      if (ids.isNotEmpty) return ids;
    }

    if (data is List) {
      final ids = data
          .map((m) {
            if (m is! Map) return null;
            return m['id']?.toString() ??
                m['name']?.toString() ??
                m['model']?.toString();
          })
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) return ids;
    }

    return const [];
  }
}
