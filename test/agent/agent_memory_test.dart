import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/agent/agent_memory.dart';

void main() {
  group('AgentMemory', () {
    test('empty session yields empty context', () {
      final mem = AgentMemory();
      expect(mem.getContext('nope'), isEmpty);
      expect(mem.messageCount('nope'), 0);
    });

    test('messages round-trip in order', () {
      final mem = AgentMemory()..startSession('s');
      mem.addMessage('s', 'user', 'do the thing');
      mem.addMessage('s', 'assistant', 'on it');
      final ctx = mem.getContext('s');
      expect(ctx.length, 2);
      expect(ctx.first['role'], 'user');
      expect(ctx.last['content'], 'on it');
    });

    test('budget keeps the first task plus newest', () {
      final mem = AgentMemory()..startSession('s');
      mem.addMessage('s', 'user', 'TASK');
      mem.addMessage('s', 'assistant', 'x' * 100);
      mem.addMessage('s', 'assistant', 'y' * 100);
      final ctx = mem.getContext('s', maxChars: 110);
      expect(ctx.first['content'], 'TASK');
      expect(ctx.last['content'], 'y' * 100);
    });

    test('tool results are capped and mapped to user role', () {
      final mem = AgentMemory()..startSession('s');
      mem.addMessage('s', 'user', 'go');
      mem.addToolResult('s', 'call_1', 'read_file', 'z' * 50,
          maxChars: 10);
      final ctx = mem.getContext('s');
      expect(ctx.last['role'], 'user');
      expect(ctx.last['content']!, contains('…(truncated)'));
    });

    test('clearSession drops everything', () {
      final mem = AgentMemory()..startSession('s');
      mem.addMessage('s', 'user', 'hi');
      mem.clearSession('s');
      expect(mem.messageCount('s'), 0);
    });
  });
}
