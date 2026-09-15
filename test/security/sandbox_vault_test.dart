import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/security/api_key_vault.dart';
import 'package:cubiclm/services/security/sandbox_service.dart';

void main() {
  group('SandboxService.isPathAllowed', () {
    test('allows normal relative paths', () {
      expect(SandboxService.isPathAllowed('src/main.dart'), isTrue);
      expect(SandboxService.isPathAllowed('a/b/c.txt'), isTrue);
    });

    test('rejects absolute, traversal, and drive paths', () {
      expect(SandboxService.isPathAllowed('/etc/passwd'), isFalse);
      expect(SandboxService.isPathAllowed('../evil'), isFalse);
      expect(SandboxService.isPathAllowed('a/../../b'), isFalse);
      expect(SandboxService.isPathAllowed('C:\\win'), isFalse);
      expect(SandboxService.isPathAllowed(''), isFalse);
    });
  });

  group('SandboxService.isCommandBlocked', () {
    test('allows ordinary commands', () {
      expect(SandboxService.isCommandBlocked('git status'), isNull);
      expect(SandboxService.isCommandBlocked('npm test'), isNull);
      expect(SandboxService.isCommandBlocked('echo hi'), isNull);
    });

    test('blocks destructive operations with a reason', () {
      expect(SandboxService.isCommandBlocked('rm -rf /'), isNotNull);
      expect(SandboxService.isCommandBlocked('rm -rf ~/'), isNotNull);
      expect(SandboxService.isCommandBlocked('mkfs.ext4 /dev/sda1'), isNotNull);
      expect(SandboxService.isCommandBlocked('dd if=/dev/zero of=/dev/sda'),
          isNotNull);
    });
  });

  group('SandboxService.redactSecrets', () {
    test('redacts key=value, bearer, query keys, and vendor tokens', () {
      expect(SandboxService.redactSecrets('api_key=abc123 xyz'),
          isNot(contains('abc123')));
      expect(SandboxService.redactSecrets('Bearer mytoken123'),
          isNot(contains('mytoken123')));
      expect(
          SandboxService.redactSecrets(
              'https://x.com/?key=SECRET123 hello'),
          isNot(contains('SECRET123')));
      expect(SandboxService.redactSecrets('key sk-abcdefgh12345678 end'),
          isNot(contains('sk-abcdefgh12345678')));
    });

    test('leaves ordinary text untouched', () {
      const plain = 'hello world, nothing secret here';
      expect(SandboxService.redactSecrets(plain), plain);
    });
  });

  group('ApiKeyVault (memory backend)', () {
    test('put / read / has / delete round-trip', () async {
      final vault = ApiKeyVault(backend: MemoryVaultBackend());
      await vault.init();
      expect(vault.has('openai'), isFalse);
      await vault.put('openai', '  key-1 ');
      expect(vault.read('openai'), 'key-1');
      expect(vault.has('openai'), isTrue);
      await vault.delete('openai');
      expect(vault.has('openai'), isFalse);
      expect(vault.read('openai'), '');
    });

    test('migrateFromMap moves only non-empty, non-duplicate keys', () async {
      final vault = ApiKeyVault(backend: MemoryVaultBackend());
      await vault.init();
      await vault.put('a', 'existing');
      final moved = await vault.migrateFromMap({
        'a': 'other',
        'b': 'new-key',
        'c': '   ',
      });
      expect(moved, 1);
      expect(vault.read('a'), 'existing');
      expect(vault.read('b'), 'new-key');
    });
  });
}
