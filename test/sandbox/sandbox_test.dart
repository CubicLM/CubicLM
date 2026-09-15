import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/sandbox/host_backend.dart';
import 'package:cubiclm/services/sandbox/sandbox_manager.dart';
import 'package:cubiclm/services/security/sandbox_service.dart';

void main() {
  group('HostBackend', () {
    test('echo runs with exit code 0', () async {
      final result = await HostBackend().run('echo sandbox-hi');
      expect(result.success, isTrue);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('sandbox-hi'));
      expect(result.timedOut, isFalse);
    });

    test('failing command reports non-zero exit', () async {
      final result =
          await HostBackend().run('exit 3', timeout: const Duration(seconds: 10));
      expect(result.success, isFalse);
    });

    test('isAvailable is always true', () async {
      expect(await HostBackend().isAvailable(), isTrue);
    });
  });

  group('SandboxManager', () {
    test('falls back to host when PRoot is absent', () async {
      final manager = SandboxManager();
      // No native runtime in tests → host backend serves the call.
      final result = await manager.run('echo mgr-hi');
      expect(result.success, isTrue);
      expect(result.stdout, contains('mgr-hi'));
      expect(manager.activeBackendName.value, 'Host shell');
    });
  });

  group('SandboxService.classifyCommand', () {
    test('read-only commands are safe', () {
      for (final cmd in [
        'ls',
        'ls -la',
        'pwd',
        'whoami',
        'echo hello',
        'git status',
        'git diff',
        'git log --oneline',
        'git branch',
        'node --version',
      ]) {
        final verdict = SandboxService.classifyCommand(cmd);
        expect(verdict.risk, CommandRisk.safe, reason: cmd);
      }
    });

    test('side-effect commands need review', () {
      for (final cmd in [
        'npm test',
        'npm install',
        'git commit -m x',
        'flutter build apk',
        'node server.js',
        'ls && echo chained',
        'git status; echo done',
      ]) {
        final verdict = SandboxService.classifyCommand(cmd);
        expect(verdict.risk, CommandRisk.review, reason: cmd);
      }
    });

    test('egress and privilege commands are high', () {
      for (final cmd in [
        'git push',
        'git reset --hard',
        'sudo apt update',
        'curl https://example.com',
        'ssh user@host',
      ]) {
        final verdict = SandboxService.classifyCommand(cmd);
        expect(verdict.risk, CommandRisk.high, reason: cmd);
      }
    });

    test('destructive commands are blocked with a reason', () {
      for (final cmd in ['', 'rm -rf /', 'rm -rf ~/', 'mkfs.ext4 /dev/sda1']) {
        final verdict = SandboxService.classifyCommand(cmd);
        expect(verdict.risk, CommandRisk.blocked, reason: cmd);
        expect(verdict.reason, isNotEmpty);
      }
    });
  });
}
