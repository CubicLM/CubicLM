import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';
import '../../hive_service.dart';
import '../../mcp/mcp_registry_service.dart';
import '../../tools/tool_interface.dart';
import '../../tools/tool_registry.dart';

/// Anthropic provider implementation.
///
/// Uses Anthropic's native Messages API format, not OpenAI-compatible.
class AnthropicProvider extends CloudProvider {
  @override
  String get id => 'anthropic';

  @override
  String get name => 'Anthropic';

  @override
  String get description => 'Claude 4, Claude 3.5 Sonnet';

  @override
  IconData get icon => Icons.psychology_outlined;

  @override
  ProviderProtocol get protocol => ProviderProtocol.anthropic;

  @override
  bool get supportsStreaming => true;

  @override
  String get endpoint => 'https://api.anthropic.com/v1/messages';

  @override
  String? get modelListEndpoint => 'https://api.anthropic.com/v1/models';

  @override
  Map<String, String> buildAuthHeaders(String apiKey) {
    return {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };
  }

  /// Built-in + MCP tools in Anthropic format (built-in wins on collision).
  List<Map<String, dynamic>>? _anthropicToolsPayload() {
    try {
      List<Map<String, dynamic>>? builtIn;
      if (Get.isRegistered<ToolRegistry>()) {
        builtIn = Get.find<ToolRegistry>().getAnthropicTools();
      }
      List<Map<String, dynamic>>? mcp;
      if (Get.isRegistered<McpRegistryService>()) {
        final reg = Get.find<McpRegistryService>();
        final cfg = reg.config.value;
        if (cfg != null && cfg.enabled && reg.tools.isNotEmpty) {
          mcp = reg.tools.map((t) => t.toAnthropicTool()).toList();
        }
      }
      if (builtIn != null && builtIn.isNotEmpty) {
        if (mcp != null) {
          final names = builtIn
              .map((t) => t['name']?.toString() ?? '')
              .toSet();
          for (final m in mcp) {
            final name = m['name']?.toString() ?? '';
            if (name.isNotEmpty && !names.contains(name)) builtIn.add(m);
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

  /// Approval gate (mirrors OpenAICompatibleProvider; fail-closed).
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
      String argsText;
      try {
        final s = const JsonEncoder.withIndent('  ').convert(args);
        argsText = s.length > 800 ? '${s.substring(0, 800)}…(truncated)' : s;
      } catch (_) {
        argsText = args.toString();
      }
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

  /// Execute one tool call (built-in first, MCP fallback). Never throws.
  Future<String> _executeToolCall(
      String name, Map<String, dynamic> args) async {
    final allowed = await _approveToolCall(name, args);
    if (!allowed) return 'Tool $name was denied by the user.';
    try {
      if (Get.isRegistered<ToolRegistry>()) {
        final toolReg = Get.find<ToolRegistry>();
        if (toolReg.getTool(name) != null) {
          final result = await toolReg.executeApproved(
            name,
            args,
            ToolContext(
                workspacePath: '', approve: (n, a) => _approveToolCall(n, a)),
          );
          return result.output;
        }
      }
      if (Get.isRegistered<McpRegistryService>()) {
        final result =
            await Get.find<McpRegistryService>().callTool(name, args);
        final content = result['content'];
        if (content is List) {
          return content
              .map((c) => c is Map
                  ? c['text']?.toString() ?? jsonEncode(c)
                  : c.toString())
              .join('\n');
        }
        return jsonEncode(result);
      }
      return 'Tool $name not found.';
    } catch (e) {
      return 'Tool $name failed: $e';
    }
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
    final apiMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        systemPrompt = msg['content'];
      } else if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': imageBase64,
              },
            },
            {'type': 'text', 'text': msg['content']},
          ],
        });
      } else {
        apiMessages.add({'role': msg['role'], 'content': msg['content']});
      }
    }

    final tools = _anthropicToolsPayload();
    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      'max_tokens': maxTokens ?? 8192,
    };

    if (systemPrompt != null) body['system'] = systemPrompt;
    if (tools != null && tools.isNotEmpty) body['tools'] = tools;
    final cloudTemp = clampCloudTemperature(temperature);
    if (cloudTemp != null) body['temperature'] = cloudTemp;

    // Local helper to POST a body and decode the JSON response.
    Future<Map<String, dynamic>> callApi(
        Map<String, dynamic> payload) async {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              ...buildAuthHeaders(apiKey),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        throw Exception(
            'Anthropic API error: ${response.statusCode} ${response.body}');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final data = await callApi(body);
    final content = data['content'] as List? ?? [];
    if (content.isEmpty) return '';

    final toolUses = content.where((b) => b is Map && b['type'] == 'tool_use').toList();
    if (toolUses.isEmpty || tools == null || tools.isEmpty) {
      final textBlocks =
          content.where((b) => b is Map && b['type'] == 'text').map((b) => (b as Map)['text']);
      return textBlocks.join('\n');
    }

    // Execute tool calls, then follow up with tool_result blocks.
    final toolResults = <Map<String, dynamic>>[];
    for (final use in toolUses) {
      final block = use as Map;
      final id = block['id']?.toString() ??
          'toolu_${DateTime.now().microsecondsSinceEpoch}';
      final name = block['name']?.toString() ?? '';
      final rawInput = block['input'];
      final args = rawInput is Map
          ? Map<String, dynamic>.from(rawInput)
          : <String, dynamic>{};
      var resultText = await _executeToolCall(name, args);
      if (resultText.length > 18000) {
        resultText = '${resultText.substring(0, 18000)}\n…(truncated)';
      }
      toolResults.add({
        'type': 'tool_result',
        'tool_use_id': id,
        'content': resultText,
      });
    }

    final followUp = <String, dynamic>{
      'model': model,
      'messages': [
        ...apiMessages,
        {'role': 'assistant', 'content': content},
        {'role': 'user', 'content': toolResults},
      ],
      'max_tokens': maxTokens ?? 8192,
    };
    if (systemPrompt != null) followUp['system'] = systemPrompt;
    if (tools.isNotEmpty) followUp['tools'] = tools;
    if (cloudTemp != null) followUp['temperature'] = cloudTemp;

    final data2 = await callApi(followUp);
    final content2 = data2['content'] as List? ?? [];
    final textBlocks2 = content2
        .where((b) => b is Map && b['type'] == 'text')
        .map((b) => (b as Map)['text']);
    return textBlocks2.join('\n');
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
    final apiMessages = <Map<String, dynamic>>[];
    String? systemPrompt;

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        systemPrompt = msg['content'];
      } else if (msg['role'] == 'user' &&
          imageBase64 != null &&
          msg == messages.last) {
        apiMessages.add({
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': imageBase64,
              },
            },
            {'type': 'text', 'text': msg['content']},
          ],
        });
      } else {
        apiMessages.add({'role': msg['role'], 'content': msg['content']});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': apiMessages,
      'max_tokens': maxTokens ?? 8192,
      'stream': true,
    };

    if (systemPrompt != null) body['system'] = systemPrompt;
    final cloudTemp = clampCloudTemperature(temperature);
    if (cloudTemp != null) body['temperature'] = cloudTemp;

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
          'Anthropic streaming error: ${streamedResponse.statusCode} $errorBody');
    }

    String buffer = '';
    await for (final chunk
        in streamedResponse.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6);
        if (jsonStr == '[DONE]') return;

        try {
          final data = jsonDecode(jsonStr);
          if (data['type'] == 'content_block_delta') {
            final delta = data['delta']?['text'];
            if (delta != null) yield delta.toString();
          }
        } catch (_) {}
      }
    }
  }

  @override
  List<String> getModelListCandidates(String apiKey) => [
        'https://api.anthropic.com/v1/models',
      ];

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    final raw = data['data'] as List? ?? [];
    return raw
        .map((m) => m is Map ? m['id']?.toString() : null)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
}
