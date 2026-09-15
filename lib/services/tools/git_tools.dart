/// CubicLM Agentic Tool System — built-in git tools.
///
/// Wraps the system `git` binary (when present) for status/diff/log/commit
/// inside the workspace. Read-only commands are safe; commit needs approval.
/// All output is capped for context safety.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool_interface.dart';

const _maxOutputChars = 20000;
const _gitTimeout = Duration(seconds: 30);

/// Shared git runner. Public for unit tests.
Future<ToolResult> runGit(
  List<String> args,
  String workDir, {
  Duration timeout = _gitTimeout,
}) async {
  if (workDir.isEmpty) {
    return ToolResult.error('No workspace selected for git operations.');
  }
  try {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: workDir,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
      try {
        process.kill();
      } catch (_) {}
      return -1;
    });
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (exitCode == -1) {
      return ToolResult.error('git timed out: git ${args.join(' ')}');
    }
    if (exitCode != 0) {
      final detail = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
      return ToolResult.error(
          'git ${args.join(' ')} failed (exit $exitCode): $detail');
    }
    final text = stdout.trim();
    if (text.isEmpty) return const ToolResult(output: '(no output)');
    if (text.length > _maxOutputChars) {
      return ToolResult.truncated(text.substring(0, _maxOutputChars));
    }
    return ToolResult(output: text);
  } on ProcessException catch (e) {
    return ToolResult.error('git is not available: ${e.message}');
  } catch (e) {
    return ToolResult.error('git failed: $e');
  }
}

/// `git status --short --branch`
class GitStatusTool extends Tool {
  @override
  String get name => 'git_status';

  @override
  String get description =>
      'Show git working-tree status (branch + short file list) for the workspace.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) {
    return runGit(['status', '--short', '--branch'], context.workspacePath);
  }
}

/// `git diff` (unstaged by default, `--staged` optional, path optional).
class GitDiffTool extends Tool {
  @override
  String get name => 'git_diff';

  @override
  String get description =>
      'Show git diff for the workspace. Unstaged changes by default; '
      'set staged=true for staged changes; path limits to one file.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'staged': {
            'type': 'boolean',
            'description': 'Show staged (cached) diff instead of unstaged.',
          },
          'path': {
            'type': 'string',
            'description': 'Optional relative file path to limit the diff.',
          },
        },
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) {
    final cmd = ['diff', '--no-color'];
    if (args['staged'] == true) cmd.add('--cached');
    final path = (args['path'] as String? ?? '').trim();
    if (path.isNotEmpty) {
      if (path.startsWith('/') || path.contains('..')) {
        return Future.value(
            ToolResult.error('Invalid path (traversal not allowed).'));
      }
      cmd.addAll(['--', path]);
    }
    return runGit(cmd, context.workspacePath);
  }
}

/// `git log --oneline -n <limit>`
class GitLogTool extends Tool {
  @override
  String get name => 'git_log';

  @override
  String get description =>
      'Show recent commit history (one line per commit) for the workspace.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Number of commits. Default: 10. Max: 50.',
          },
        },
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) {
    final limit = ((args['limit'] as num?) ?? 10).toInt().clamp(1, 50);
    return runGit(
        ['log', '--oneline', '-n', '$limit'], context.workspacePath);
  }
}

/// Stage-all + commit with a message.
class GitCommitTool extends Tool {
  @override
  String get name => 'git_commit';

  @override
  String get description =>
      'Stage all changes and create a git commit with the given message.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'message': {
            'type': 'string',
            'description': 'Commit message (required, non-empty).',
          },
        },
        'required': ['message'],
      };

  @override
  ToolRisk get risk => ToolRisk.review;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final message = (args['message'] as String? ?? '').trim();
    if (message.isEmpty) return ToolResult.error('Commit message is required.');
    if (message.length > 500) {
      return ToolResult.error('Commit message too long (max 500 chars).');
    }
    final add = await runGit(['add', '-A'], context.workspacePath);
    if (!add.success) return add;
    return runGit(['commit', '-m', message], context.workspacePath);
  }
}

/// Get all built-in git tools.
List<Tool> gitTools() => [
      GitStatusTool(),
      GitDiffTool(),
      GitLogTool(),
      GitCommitTool(),
    ];
