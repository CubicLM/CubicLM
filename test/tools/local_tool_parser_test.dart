import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/local_tool_parser.dart';

void main() {
  group('LocalToolParser.parse', () {
    test('parses a fenced json block', () {
      const out = '''
Thinking… I will read the file.
```json
{"name": "read_file", "arguments": {"path": "src/main.dart"}}
```
''';
      final calls = LocalToolParser.parse(out);
      expect(calls, isNotNull);
      expect(calls!.length, 1);
      expect(calls.first.name, 'read_file');
      expect(calls.first.args['path'], 'src/main.dart');
    });

    test('parses multiple fenced blocks in order', () {
      const out = '''
```json
{"name": "list_files", "arguments": {}}
```
```json
{"name": "read_file", "arguments": {"path": "a.txt"}}
```
''';
      final calls = LocalToolParser.parse(out);
      expect(calls!.length, 2);
      expect(calls[0].name, 'list_files');
      expect(calls[1].name, 'read_file');
    });

    test('parses <tool> tagged blocks', () {
      const out =
          '<tool>{"name": "search_code", "arguments": {"pattern": "foo"}}</tool>';
      final calls = LocalToolParser.parse(out);
      expect(calls!.first.name, 'search_code');
    });

    test('parses a bare JSON document', () {
      const out = '{"name": "run_command", "arguments": {"command": "ls"}}';
      final calls = LocalToolParser.parse(out);
      expect(calls!.first.name, 'run_command');
    });

    test('parses tool_calls wrapper', () {
      const out = '''
```json
{"tool_calls": [{"name": "git_status", "arguments": {}}]}
```
''';
      final calls = LocalToolParser.parse(out);
      expect(calls!.first.name, 'git_status');
    });

    test('parses OpenAI function shape with string arguments', () {
      const out =
          '{"function": {"name": "read_file", "arguments": "{\\"path\\": \\"x\\"}"}}';
      final calls = LocalToolParser.parse(out);
      expect(calls!.first.args['path'], 'x');
    });

    test('plain text yields null', () {
      expect(LocalToolParser.parse('Just a normal reply.'), isNull);
      expect(LocalToolParser.parse(''), isNull);
    });

    test('garbage json yields null, not a throw', () {
      expect(LocalToolParser.parse('```json\nnot json at all\n```'), isNull);
    });
  });

  group('LocalToolParser helpers', () {
    test('stripToolBlocks removes fenced calls', () {
      const out = 'Hello\n```json\n{"name":"x","arguments":{}}\n```\nbye';
      final stripped = LocalToolParser.stripToolBlocks(out);
      expect(stripped, contains('Hello'));
      expect(stripped, isNot(contains('read_file')));
      expect(stripped, isNot(contains('```')));
    });

    test('buildToolSystemPrompt names each tool', () {
      final prompt = LocalToolParser.buildToolSystemPrompt([
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description': 'read',
            'parameters': {'type': 'object'},
          },
        },
      ]);
      expect(prompt, contains('read_file'));
      expect(prompt, contains('```json'));
    });
  });
}
