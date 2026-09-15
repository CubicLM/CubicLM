import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/file_tools.dart';
import 'package:cubiclm/services/tools/tool_interface.dart';

ToolContext _ctx(String workspace) => ToolContext(
      workspacePath: workspace,
      approve: (_, __) async => true,
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clm_file_tools_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('file tools', () {
    test('write then read round-trips content', () async {
      final ctx = _ctx(tmp.path);
      final written =
          await WriteFileTool().execute({'path': 'a/b.txt', 'content': 'hello'}, ctx);
      expect(written.success, isTrue);
      expect(written.modifiedFiles, contains('a/b.txt'));

      final read = await ReadFileTool().execute({'path': 'a/b.txt'}, ctx);
      expect(read.success, isTrue);
      expect(read.output, 'hello');
    });

    test('read missing file errors', () async {
      final result =
          await ReadFileTool().execute({'path': 'missing.txt'}, _ctx(tmp.path));
      expect(result.success, isFalse);
    });

    test('edit replaces exact text', () async {
      final ctx = _ctx(tmp.path);
      await WriteFileTool()
          .execute({'path': 'e.txt', 'content': 'foo bar foo'}, ctx);
      final edited = await EditFileTool().execute(
          {'path': 'e.txt', 'old_text': 'bar', 'new_text': 'baz'}, ctx);
      expect(edited.success, isTrue);
      final read = await ReadFileTool().execute({'path': 'e.txt'}, ctx);
      expect(read.output, 'foo baz foo');
    });

    test('edit with absent old_text errors', () async {
      final ctx = _ctx(tmp.path);
      await WriteFileTool()
          .execute({'path': 'e2.txt', 'content': 'abc'}, ctx);
      final result = await EditFileTool().execute(
          {'path': 'e2.txt', 'old_text': 'zzz', 'new_text': 'q'}, ctx);
      expect(result.success, isFalse);
    });

    test('list shows files and directory markers', () async {
      final ctx = _ctx(tmp.path);
      await WriteFileTool()
          .execute({'path': 'sub/n.txt', 'content': 'x'}, ctx);
      final result =
          await ListFilesTool().execute({'path': ''}, ctx);
      expect(result.success, isTrue);
      expect(result.output, contains('sub/'));
    });

    test('search finds matching lines with numbers', () async {
      final ctx = _ctx(tmp.path);
      await WriteFileTool().execute(
          {'path': 's.dart', 'content': 'line one\nneedle here\nline three\n'},
          ctx);
      final result = await SearchCodeTool()
          .execute({'pattern': 'needle', 'include': '*.dart'}, ctx);
      expect(result.success, isTrue);
      expect(result.output, contains('s.dart:2:'));
    });

    test('absolute and traversal paths are rejected', () async {
      final ctx = _ctx(tmp.path);
      for (final bad in ['/etc/passwd', '../evil.txt', 'C:\\win.txt']) {
        final r = await ReadFileTool().execute({'path': bad}, ctx);
        expect(r.success, isFalse, reason: bad);
      }
    });
  });
}
