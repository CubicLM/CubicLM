import 'dart:convert';

import 'package:cubiclm/services/cloud/providers/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeToolCalls', () {
    test('keeps valid ids and shape', () {
      final out = OpenAICompatibleProvider.normalizeToolCalls([
        {
          'id': 'call_abc',
          'type': 'function',
          'function': {'name': 'write_file', 'arguments': '{"path":"a"}'}
        }
      ]);
      expect(out, hasLength(1));
      expect(out[0]['id'], 'call_abc');
      expect(out[0]['type'], 'function');
      expect((out[0]['function'] as Map)['name'], 'write_file');
      expect((out[0]['function'] as Map)['arguments'], '{"path":"a"}');
    });

    test('generates unique ids for empty or missing ids', () {
      final out = OpenAICompatibleProvider.normalizeToolCalls([
        {
          'id': '',
          'type': 'function',
          'function': {'name': 'a', 'arguments': '{}'}
        },
        {
          'type': 'function',
          'function': {'name': 'b', 'arguments': '{}'}
        },
      ]);
      expect(out, hasLength(2));
      final id0 = out[0]['id'] as String;
      final id1 = out[1]['id'] as String;
      expect(id0.isNotEmpty, isTrue);
      expect(id1.isNotEmpty, isTrue);
      expect(id0, isNot(startsWith('call_0')));
      expect(id0, isNot(equals(id1)));
    });

    test('skips non-map entries and fills defaults', () {
      final out = OpenAICompatibleProvider.normalizeToolCalls([
        'garbage',
        {'id': 'x'},
      ]);
      expect(out, hasLength(1));
      expect(out[0]['id'], 'x');
      expect(out[0]['type'], 'function');
      expect((out[0]['function'] as Map)['name'], '');
      expect((out[0]['function'] as Map)['arguments'], '{}');
    });
  });

  group('buildFollowUpMessages', () {
    test('tool messages keep tool_call_id matching assistant tool_calls', () {
      final msgs = OpenAICompatibleProvider.buildFollowUpMessages(
        messages: [
          {'role': 'user', 'content': 'build a snake game'}
        ],
        assistantContent: '',
        normalizedCalls: [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'write_file', 'arguments': '{}'}
          },
          {
            'id': 'call_2',
            'type': 'function',
            'function': {'name': 'run_cmd', 'arguments': '{}'}
          },
        ],
        toolResults: [
          {'id': 'call_1', 'text': 'written'},
          {'id': 'call_2', 'text': 'exit 0'},
        ],
      );
      expect(msgs, hasLength(4));
      expect(msgs[0], {'role': 'user', 'content': 'build a snake game'});
      final assistant = msgs[1];
      expect(assistant['role'], 'assistant');
      final calls = (assistant['tool_calls'] as List).cast<Map>();
      expect(calls.map((c) => c['id']).toList(), ['call_1', 'call_2']);
      for (var i = 0; i < 2; i++) {
        final tool = msgs[2 + i];
        expect(tool['role'], 'tool');
        // THE regression: tool_call_id must survive the rebuild.
        expect(tool['tool_call_id'], calls[i]['id']);
      }
      // Whole payload must be JSON-serializable for the HTTP body.
      expect(() => jsonEncode(msgs), returnsNormally);
    });
  });
}
