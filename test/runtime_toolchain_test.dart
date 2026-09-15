import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/toolchain_catalog.dart';

void main() {
  group('ToolchainCatalog', () {
    test('stacks list core first with six stacks', () {
      final stacks = ToolchainCatalog.stacks();
      expect(stacks.length, 6);
      expect(stacks.first.id, ToolchainId.core);
      expect(stacks.first.needsCore, isFalse);
      for (final s in stacks.skip(1)) {
        expect(s.needsCore, isTrue);
        expect(s.bundles, isNotEmpty);
      }
    });

    test('bundleUrl joins base + file', () {
      final bundle = ToolchainCatalog.stackOf(ToolchainId.core).bundles.first;
      expect(
        ToolchainCatalog.bundleUrl('https://x.test/r/', bundle),
        'https://x.test/r/${bundle.fileName}',
      );
      expect(
        ToolchainCatalog.checksumUrl('https://x.test/r', bundle),
        endsWith('.sha256'),
      );
    });

    test('safeJoin blocks escapes, allows normal entries', () {
      expect(ToolchainCatalog.safeJoin('/r', 'usr/bin/bash'),
          '/r/usr/bin/bash');
      expect(ToolchainCatalog.safeJoin('/r', './a/./b'), '/r/a/b');
      expect(ToolchainCatalog.safeJoin('/r', '../evil'), isNull);
      expect(ToolchainCatalog.safeJoin('/r', 'a/../../evil'), isNull);
      expect(ToolchainCatalog.safeJoin('/r', '/absolute'), '/r/absolute');
      expect(ToolchainCatalog.safeJoin('/r', ''), isNull);
      expect(ToolchainCatalog.safeJoin('/r', 'C:/win'), isNull);
    });

    test('formatBytes renders human sizes', () {
      expect(ToolchainCatalog.formatBytes(0), '0 B');
      expect(ToolchainCatalog.formatBytes(1536), '1.5 KB');
      expect(ToolchainCatalog.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(ToolchainCatalog.formatBytes(-5), '—');
    });
  });
}
