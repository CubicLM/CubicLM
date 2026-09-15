import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/agent/agent_loop.dart';
import 'package:cubiclm/services/agent/agent_memory.dart';
import 'package:cubiclm/services/agent/agent_types.dart';
import 'package:cubiclm/services/tools/local_tool_parser.dart';

void main() {
  group('AgentLoop reasoning', () {
    test('thinking-aloud beside tool calls yields a reasoning event', () async {
      var llmCalls = 0;
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async {
          llmCalls++;
          if (llmCalls == 1) {
            return const AgentLlmResponse(
              reasoning: 'I should check the workspace first.',
              toolCalls: [
                AgentToolCall(id: 'c1', name: 'list_files', args: {}),
              ],
            );
          }
          return const AgentLlmResponse(text: 'All good.');
        },
        execTool: (_, __) async => const AgentToolOutcome(output: 'ok'),
      );
      final events = await loop.run('go').toList();
      expect(events.map((e) => e.kind), [
        AgentEventKind.reasoning,
        AgentEventKind.toolStarted,
        AgentEventKind.toolCompleted,
        AgentEventKind.text,
        AgentEventKind.complete,
      ]);
      expect(events.first.text, contains('workspace'));
    });

    test('AgentConfig planMode defaults to off', () {
      expect(const AgentConfig().planMode, isFalse);
      expect(const AgentConfig(planMode: true).planMode, isTrue);
    });
  });

  group('LocalToolParser.parseWithReasoning', () {
    test('splits calls from thinking text', () {
      const out = '''
Let me read the config first.
```json
{"name": "read_file", "arguments": {"path": "pubspec.yaml"}}
```''';
      final parsed = LocalToolParser.parseWithReasoning(out);
      expect(parsed.calls.length, 1);
      expect(parsed.calls.first.name, 'read_file');
      expect(parsed.reasoning, contains('config'));
      expect(parsed.reasoning, isNot(contains('```')));
    });

    test('plain answer has no calls and full reasoning', () {
      const out = 'Done, nothing to change.';
      final parsed = LocalToolParser.parseWithReasoning(out);
      expect(parsed.calls, isEmpty);
      expect(parsed.reasoning, out);
    });
  });
}
