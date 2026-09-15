import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/todo_tools.dart';
import 'package:cubiclm/services/tools/tool_interface.dart';

ToolContext _ctx() => ToolContext(
      workspacePath: '',
      approve: (_, __) async => true,
    );

void main() {
  group('TodoWriteTool', () {
    test('write then list round-trips the plan', () async {
      final tools = todoTools();
      final writer = tools.first as TodoWriteTool;
      final reader = tools.last;
      final written = await writer.execute({
        'todos': [
          {'content': 'Explore repo', 'status': 'completed'},
          {'content': 'Write code', 'status': 'in_progress'},
          {'content': 'Run tests', 'status': 'pending'},
        ],
      }, _ctx());
      expect(written.success, isTrue);
      expect(written.output, contains('[x] Explore repo'));
      expect(written.output, contains('[>] Write code'));
      expect(written.output, contains('[ ] Run tests'));

      final listed = await reader.execute({}, _ctx());
      expect(listed.output, written.output);
    });

    test('two in_progress tasks are rejected', () async {
      final writer = TodoWriteTool();
      final result = await writer.execute({
        'todos': [
          {'content': 'a', 'status': 'in_progress'},
          {'content': 'b', 'status': 'in_progress'},
        ],
      }, _ctx());
      expect(result.success, isFalse);
    });

    test('empty content and non-array are rejected', () async {
      final writer = TodoWriteTool();
      expect(
          (await writer.execute({
            'todos': [
              {'content': '  ', 'status': 'pending'},
            ],
          }, _ctx()))
              .success,
          isFalse);
      expect((await writer.execute({'todos': 'nope'}, _ctx())).success,
          isFalse);
    });

    test('unknown status coerces to pending', () async {
      final writer = TodoWriteTool();
      final result = await writer.execute({
        'todos': [
          {'content': 'a', 'status': 'weird'},
        ],
      }, _ctx());
      expect(result.success, isTrue);
      expect(writer.current.single.status, 'pending');
    });

    test('oversized plans are rejected', () async {
      final writer = TodoWriteTool();
      final result = await writer.execute({
        'todos': [
          for (var i = 0; i < 51; i++)
            {'content': 'task $i', 'status': 'pending'},
        ],
      }, _ctx());
      expect(result.success, isFalse);
    });

    test('empty plan formats as empty', () {
      expect(TodoWriteTool.formatTodos(const []), '(empty plan)');
    });
  });
}
