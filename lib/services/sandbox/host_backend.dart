/// CubicLM Sandbox — host-shell backend (current default).
///
/// Runs commands directly on the host OS (cmd.exe /c on Windows,
/// /bin/sh -c elsewhere). This is what the app uses until the PRoot
/// Ubuntu runtime is installed: convenient, but NOT isolated — every
/// command still passes through [SandboxService] screening first.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sandbox_backend.dart';

/// Host-shell backend. Always available where dart:io processes exist.
class HostBackend implements SandboxBackend {
  @override
  String get name => 'Host shell';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<SandboxResult> run(
    String command, {
    String? workDir,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    Process? process;
    try {
      final shell = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
      final shellArg = Platform.isWindows ? '/c' : '-c';
      process = await Process.start(
        shell,
        [shellArg, command],
        workingDirectory: (workDir == null || workDir.isEmpty) ? null : workDir,
        environment: environment ?? _cleanEnvironment(),
        runInShell: false,
      );

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        try {
          process?.kill();
        } catch (_) {}
        return -1;
      });
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      if (exitCode == -1) {
        return SandboxResult(
            stdout: stdout, stderr: stderr, exitCode: -1, timedOut: true);
      }
      return SandboxResult(
          stdout: stdout, stderr: stderr, exitCode: exitCode);
    } on ProcessException catch (e) {
      return SandboxResult(
          stderr: 'Cannot start shell: ${e.message}', exitCode: -1);
    } catch (e) {
      return SandboxResult(stderr: 'Command failed: $e', exitCode: -1);
    } finally {
      try {
        process?.kill();
      } catch (_) {}
    }
  }

  /// Default environment with API keys scrubbed so child processes can
  /// never inherit credentials from the app process.
  static Map<String, String> _cleanEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    env.remove('ANTHROPIC_API_KEY');
    env.remove('OPENAI_API_KEY');
    env.remove('GOOGLE_API_KEY');
    return env;
  }
}
