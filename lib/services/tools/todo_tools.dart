/// CubicLM Agentic Tool System — task-plan tools (TodoWrite parity).
///
/// Gives the agent a visible plan: `todo_write` replaces the whole task
/// list, `todo_list` reads it back. Statuses mirror the reference app:
/// pending → in_progress → completed. The agent UI renders the list as a
/// checklist from the tool's observable state.
library;

import 'package:get/get.dart';

import 'tool_interface.dart';

/// Valid task states.
const List<String> kTodoStatuses = ['pending', 'in_progress', 'completed'];

/// One plan item. Public for the UI + tests.
class TodoItem {
  final String content;
  final String status;

  const TodoItem({required this.content, this.status = 'pending'});

  Map<String, dynamic> toMap() => {'content': content, 'status': status};

  static TodoItem? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final content = (raw['content'] ?? '').toString().trim();
    if (content.isEmpty) return null;
    var status = (raw['status'] ?? 'pending').toString().trim();
    if (!kTodoStatuses.contains(status)) status = 'pending';
    return TodoItem(content: content, status: status);
  }
}

/// Replace the agent's whole task plan.
class TodoWriteTool extends Tool {
  /// Current plan (observable for the trace UI).
  final current = <TodoItem>[].obs;

  @override
  String get name => 'todo_write';

  @override
  String get description =>
      'Set the task plan (replaces the whole list). Break work into small '
      'steps, mark exactly one in_progress at a time, flip to completed as '
      'you finish. The user sees this list live.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'todos': {
            'type': 'array',
            'description': 'The full task list',
            'items': {
              'type': 'object',
              'properties': {
                'content': {
                  'type': 'string',
                  'description': 'Imperative task summary',
                },
                'status': {
                  'type': 'string',
                  'description': 'pending | in_progress | completed',
                },
              },
              'required': ['content', 'status'],
            },
          },
        },
        'required': ['todos'],
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> args, ToolContext context) async {
    final raw = args['todos'];
    if (raw is! List) return ToolResult.error('todos must be an array.');
    if (raw.length > 50) {
      return ToolResult.error('Too many tasks (max 50).');
    }
    final items = <TodoItem>[];
    for (final entry in raw) {
      final item = TodoItem.fromMap(entry);
      if (item == null) {
        return ToolResult.error(
            'Each todo needs non-empty content + status.');
      }
      items.add(item);
    }
    if (items.where((t) => t.status == 'in_progress').length > 1) {
      return ToolResult.error('Only one task may be in_progress.');
    }
    current.assignAll(items);
    return ToolResult(output: _format(items));
  }

  /// Human-readable rendering. Public for tests + UI.
  static String formatTodos(List<TodoItem> items) => _format(items);

  static String _format(List<TodoItem> items) {
    if (items.isEmpty) return '(empty plan)';
    final buf = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final t = items[i];
      final mark = t.status == 'completed'
          ? '[x]'
          : t.status == 'in_progress'
              ? '[>]'
              : '[ ]';
      buf.writeln('${i + 1}. $mark ${t.content}');
    }
    return buf.toString().trim();
  }
}

/// Read back the current task plan.
class TodoListTool extends Tool {
  final TodoWriteTool writer;

  TodoListTool(this.writer);

  @override
  String get name => 'todo_list';

  @override
  String get description => 'Read the current task plan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> args, ToolContext context) async {
    return ToolResult(output: TodoWriteTool.formatTodos(writer.current));
  }
}

/// Get the todo tool pair (writer first — the reader needs it).
List<Tool> todoTools() {
  final writer = TodoWriteTool();
  return [writer, TodoListTool(writer)];
}
