/// CubicLM Agentic Tool System — built-in shell command tools.
///
/// Provides run_command for executing shell commands in the workspace.
/// Execution routes through [SandboxManager] (PRoot Ubuntu when the native
/// runtime is installed, host shell otherwise); risk is classified per
/// command so harmless reads auto-approve while side effects stay gated.
library;

import 'package:get/get.dart';

import '../sandbox/host_backend.dart';
import '../sandbox/sandbox_manager.dart';
import '../security/sandbox_service.dart';
import 'tool_interface.dart';

/// Run a shell command and capture output.
class RunCommandTool extends Tool implements RiskAwareTool {
  @override
  String get name => 'run_command';

  @override
  String get description =>
      'Execute a shell command in the workspace directory. '
      'Returns stdout, stderr, and exit code. '
      'Use for: building, testing, installing packages, git operations.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description':
                'The shell command to execute (e.g. "npm install", "git status")',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Maximum seconds to wait for the command. Default: 30. Max: 300.',
          },
        },
        'required': ['command'],
      };

  @override
  ToolRisk get risk => ToolRisk.review;

  @override
  ToolRisk riskFor(Map<String, dynamic> args) {
    final command = (args['command'] as String? ?? '').trim();
    final verdict = SandboxService.classifyCommand(command);
    switch (verdict.risk) {
      case CommandRisk.safe:
        return ToolRisk.safe;
      case CommandRisk.review:
        return ToolRisk.review;
      case CommandRisk.high:
      case CommandRisk.blocked:
        return ToolRisk.high;
    }
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final command = args['command'] as String? ?? '';
    if (command.trim().isEmpty) {
      return ToolResult.error('Command is required.');
    }

    final timeout = ((args['timeout_seconds'] as num?) ?? 30).toInt().clamp(1, 300);

    // Dangerous command detection (shared with the terminal + sandbox).
    final verdict = SandboxService.classifyCommand(command);
    if (verdict.risk == CommandRisk.blocked) {
      return ToolResult.error('Blocked command: ${verdict.reason}');
    }

    final workDir =
        context.workspacePath.isEmpty ? null : context.workspacePath;
    try {
      // Prefer the sandbox manager (PRoot when installed); the direct
      // host backend keeps unit tests hermetic without GetX.
      final result = Get.isRegistered<SandboxManager>()
          ? await Get.find<SandboxManager>().run(
              command,
              workDir: workDir,
              timeout: Duration(seconds: timeout),
            )
          : await HostBackend().run(command,
              workDir: workDir, timeout: Duration(seconds: timeout));

      final output = StringBuffer();
      if (result.stdout.isNotEmpty) {
        output.write(result.stdout);
      }
      if (result.stderr.isNotEmpty) {
        if (output.isNotEmpty) output.write('\n--- stderr ---\n');
        output.write(result.stderr);
      }
      if (result.timedOut) {
        output.write('\n--- timed out after ${timeout}s ---');
      } else {
        output.write('\n--- exit code: ${result.exitCode} ---');
      }

      final text = output.toString();
      // Truncate very long output
      if (text.length > 50000) {
        return ToolResult.truncated(text.substring(0, 50000));
      }

      return ToolResult(
        output: text,
        success: result.success,
      );
    } catch (e) {
      return ToolResult.error('Command failed: $e');
    }
  }
}

/// Get all built-in shell tools.
List<Tool> shellTools() => [
      RunCommandTool(),
    ];
