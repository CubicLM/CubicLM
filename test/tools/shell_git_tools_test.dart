import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/git_tools.dart';
import 'package:cubiclm/services/tools/shell_tools.dart';
import 'package:cubiclm/services/tools/tool_interface.dart';

ToolContext _ctx(String workspace) => ToolContext(
      workspacePath: workspace,
      approve: (_, __) async => true,
    );

void main() {
  group('RunCommandTool', () {
    test('echo returns output with exit code', () async {
      final tmp = await Directory.systemTemp.createTemp('clm_shell_');
      try {
        final result = await RunCommandTool()
            .execute({'command': 'echo hello-clm'}, _ctx(tmp.path));
        expect(result.success, isTrue);
        expect(result.output, contains('hello-clm'));
        expect(result.output, contains('exit code: 0'));
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('destructive commands are blocked without spawning', () async {
      final result = await RunCommandTool()
          .execute({'command': 'rm -rf /'}, _ctx(''));
      expect(result.success, isFalse);
      expect(result.output, contains('Blocked command'));
    });

    test('empty command errors', () async {
      final result =
          await RunCommandTool().execute({'command': ''}, _ctx(''));
      expect(result.success, isFalse);
    });
  });

  group('git tools (hermetic)', () {
    test('status without workspace errors gracefully', () async {
      final result = await GitStatusTool().execute({}, _ctx(''));
      expect(result.success, isFalse);
    });

    test('diff rejects traversal paths', () async {
      final result = await GitDiffTool()
          .execute({'path': '../../evil'}, _ctx('/tmp'));
      expect(result.success, isFalse);
    });

    test('commit requires a message', () async {
      final result =
          await GitCommitTool().execute({'message': '   '}, _ctx('/tmp'));
      expect(result.success, isFalse);
    });

    test('commit rejects oversized messages', () async {
      final result = await GitCommitTool()
          .execute({'message': 'x' * 501}, _ctx('/tmp'));
      expect(result.success, isFalse);
    });
  });
}
