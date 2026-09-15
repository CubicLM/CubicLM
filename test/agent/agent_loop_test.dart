import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/agent/agent_loop.dart';
import 'package:cubiclm/services/agent/agent_memory.dart';
import 'package:cubiclm/services/agent/agent_types.dart';

void main() {
  group('AgentLoop', () {
    test('tool call then final text yields the full trace', () async {
      var llmCalls = 0;
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (messages, system) async {
          llmCalls++;
          if (llmCalls == 1) {
            return const AgentLlmResponse(
              toolCalls: [
                AgentToolCall(
                    id: 'call_1',
                    name: 'read_file',
                    args: {'path': 'a.txt'}),
              ],
            );
          }
          return const AgentLlmResponse(text: 'File says hi.');
        },
        execTool: (name, args) async {
          expect(name, 'read_file');
          return const AgentToolOutcome(
              output: 'hi', modifiedFiles: ['a.txt']);
        },
      );

      final events = await loop
          .run('read a.txt', config: const AgentConfig(maxIterations: 5))
          .toList();

      expect(events.map((e) => e.kind), [
        AgentEventKind.toolStarted,
        AgentEventKind.toolCompleted,
        AgentEventKind.text,
        AgentEventKind.complete,
      ]);
      expect(events[1].modifiedFiles, contains('a.txt'));
      expect(events[2].text, 'File says hi.');
      expect(llmCalls, 2);
    });

    test('plain answer completes without tools', () async {
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async => const AgentLlmResponse(text: 'done'),
        execTool: (_, __) async =>
            const AgentToolOutcome(output: 'unused'),
      );
      final events =
          await loop.run('hi').toList();
      expect(events.map((e) => e.kind),
          [AgentEventKind.text, AgentEventKind.complete]);
    });

    test('LLM failure yields a single error event', () async {
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async => throw Exception('boom'),
        execTool: (_, __) async =>
            const AgentToolOutcome(output: 'unused'),
      );
      final events = await loop.run('hi').toList();
      expect(events.length, 1);
      expect(events.first.kind, AgentEventKind.error);
      expect(events.first.text, contains('boom'));
    });

    test('tool exception becomes a failed outcome, loop continues', () async {
      var llmCalls = 0;
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async {
          llmCalls++;
          if (llmCalls == 1) {
            return const AgentLlmResponse(
              toolCalls: [
                AgentToolCall(id: 'c1', name: 'bad', args: {}),
              ],
            );
          }
          return const AgentLlmResponse(text: 'recovered');
        },
        execTool: (_, __) async => throw Exception('tool boom'),
      );
      final events = await loop.run('go').toList();
      expect(
          events.where((e) => e.kind == AgentEventKind.toolCompleted).first.success,
          isFalse);
      expect(events.last.kind, AgentEventKind.complete);
    });

    test('cancellation stops the loop', () async {
      var cancelled = false;
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async {
          cancelled = true;
          return const AgentLlmResponse(text: 'never seen');
        },
        execTool: (_, __) async =>
            const AgentToolOutcome(output: 'unused'),
        isCancelled: () => cancelled,
      );
      // First call cancels before any LLM work.
      cancelled = true;
      final events = await loop.run('hi').toList();
      expect(events.map((e) => e.kind), [AgentEventKind.cancelled]);
    });

    test('iteration limit completes with maxIterations flag', () async {
      final loop = AgentLoop(
        memory: AgentMemory(),
        llmCall: (_, __) async => const AgentLlmResponse(
          toolCalls: [AgentToolCall(id: 'c', name: 't', args: {})],
        ),
        execTool: (_, __) async => const AgentToolOutcome(output: 'r'),
      );
      final events = await loop
          .run('loop', config: const AgentConfig(maxIterations: 2))
          .toList();
      expect(events.last.kind, AgentEventKind.complete);
      expect(events.last.maxIterations, isTrue);
    });
  });
}
