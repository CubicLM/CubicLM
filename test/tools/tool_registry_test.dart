import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/tool_interface.dart';
import 'package:cubiclm/services/tools/tool_registry.dart';

class _EchoTool extends Tool {
  @override
  String get name => 'echo_tool';

  @override
  String get description => 'Test echo tool';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> args, ToolContext context) async {
    return ToolResult(output: 'echo:${args['text']}');
  }
}

class _DangerTool extends Tool {
  @override
  String get name => 'danger_tool';

  @override
  String get description => 'High-risk test tool';

  @override
  Map<String, dynamic> get parameters => {'type': 'object', 'properties': {}};

  @override
  ToolRisk get risk => ToolRisk.high;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> args, ToolContext context) async {
    return const ToolResult(output: 'should never run');
  }
}

ToolContext _ctx() => ToolContext(
      workspacePath: '',
      approve: (_, __) async => true,
    );

void main() {
  group('ToolRegistry registration', () {
    test('register / get / unregister round-trip', () {
      final reg = ToolRegistry();
      expect(reg.getTool('echo_tool'), isNull);
      reg.register(_EchoTool());
      expect(reg.getTool('echo_tool'), isNotNull);
      expect(reg.builtInToolNames, contains('echo_tool'));
      reg.unregister('echo_tool');
      expect(reg.getTool('echo_tool'), isNull);
    });

    test('registerAll registers every tool', () {
      final reg = ToolRegistry();
      reg.registerAll([_EchoTool(), _DangerTool()]);
      expect(reg.builtInTools.length, 2);
    });
  });

  group('ToolRegistry schemas', () {
    test('getOpenAITools wraps name + description + parameters', () {
      final reg = ToolRegistry()..register(_EchoTool());
      final schemas = reg.getOpenAITools();
      expect(schemas.length, 1);
      expect(schemas.first['type'], 'function');
      final fn = schemas.first['function'] as Map;
      expect(fn['name'], 'echo_tool');
      expect(fn['description'], isNotEmpty);
      expect((fn['parameters'] as Map)['type'], 'object');
    });

    test('getAnthropicTools uses input_schema shape', () {
      final reg = ToolRegistry()..register(_EchoTool());
      final schemas = reg.getAnthropicTools();
      expect(schemas.first['name'], 'echo_tool');
      expect(schemas.first['input_schema'], isNotNull);
    });

    test('mergeOpenAITools keeps built-in on name collision', () {
      final reg = ToolRegistry()..register(_EchoTool());
      final mcp = [
        {
          'type': 'function',
          'function': {
            'name': 'echo_tool',
            'description': 'mcp impostor',
            'parameters': {'type': 'object'},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'mcp_only',
            'description': 'external',
            'parameters': {'type': 'object'},
          },
        },
      ];
      final merged = reg.mergeOpenAITools(mcp);
      expect(merged.length, 2);
      final echo =
          merged.firstWhere((t) => (t['function'] as Map)['name'] == 'echo_tool');
      expect((echo['function'] as Map)['description'], 'Test echo tool');
    });
  });

  group('ToolRegistry dispatch', () {
    test('callTool executes a safe tool', () async {
      final reg = ToolRegistry()..register(_EchoTool());
      final result =
          await reg.callTool('echo_tool', {'text': 'hi'}, _ctx());
      expect(result.success, isTrue);
      expect(result.output, 'echo:hi');
    });

    test('callTool returns error for unknown tools', () async {
      final reg = ToolRegistry();
      final result = await reg.callTool('nope', {}, _ctx());
      expect(result.success, isFalse);
      expect(result.output, contains('Unknown tool'));
    });

    test('callTool emits an execution record', () async {
      final reg = ToolRegistry()..register(_EchoTool());
      final future = reg.executions.first;
      await reg.callTool('echo_tool', {'text': 'x'}, _ctx());
      final rec = await future;
      expect(rec.toolName, 'echo_tool');
      expect(rec.success, isTrue);
      expect(rec.outputChars, greaterThan(0));
    });

    test('executeApproved runs high-risk tools without a dialog', () async {
      final reg = ToolRegistry()..register(_DangerTool());
      final result = await reg.executeApproved('danger_tool', {}, _ctx());
      expect(result.success, isTrue);
      expect(result.output, 'should never run');
    });

    test('executeApproved errors on unknown tools', () async {
      final reg = ToolRegistry();
      final result = await reg.executeApproved('nope', {}, _ctx());
      expect(result.success, isFalse);
    });
  });
}
