import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/runtime_installer.dart';
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

    test('core extracts to root (ubuntu/ + bin/proot), overlays to rootfs',
        () {
      expect(RuntimeInstaller.extractSubdirFor(ToolchainId.core), '');
      for (final id in [
        ToolchainId.node,
        ToolchainId.python,
        ToolchainId.android,
        ToolchainId.cpp,
        ToolchainId.php,
      ]) {
        expect(RuntimeInstaller.extractSubdirFor(id), 'ubuntu');
      }
    });

    test('splitTarMember separates symlink targets', () {
      expect(ToolchainCatalog.splitTarMember('ubuntu/a/b').path,
          'ubuntu/a/b');
      expect(ToolchainCatalog.splitTarMember('ubuntu/a/b').target, isNull);
      final link = ToolchainCatalog.splitTarMember(
          'ubuntu/a/b -> ../../c/d');
      expect(link.path, 'ubuntu/a/b');
      expect(link.target, '../../c/d');
    });

    test('resolveInside pops in-root dotdots, rejects escapes', () {
      expect(ToolchainCatalog.resolveInside('/r', 'a/b'), '/r/a/b');
      expect(ToolchainCatalog.resolveInside('/r', 'a/./b'), '/r/a/b');
      expect(ToolchainCatalog.resolveInside('/r', 'a/x/../b'), '/r/a/b');
      expect(ToolchainCatalog.resolveInside('/r', '../evil'), isNull);
      expect(ToolchainCatalog.resolveInside('/r', 'a/../../evil'), isNull);
      // Leading slashes map inside (same as safeJoin; absolute symlink
      // targets resolve against the guest root at runtime).
      expect(ToolchainCatalog.resolveInside('/r', '/absolute'),
          '/r/absolute');
      expect(ToolchainCatalog.resolveInside('/r', 'C:/win'), isNull);
      expect(ToolchainCatalog.resolveInside('/r', ''), isNull);
    });

    test('unsafeMemberReason allows the real Ubuntu fstab link', () {
      // Exact device failure (Redmi, core install): legit in-root link.
      expect(
          ToolchainCatalog.unsafeMemberReason('/r',
              'ubuntu/usr/share/doc/mount/examples/fstab -> ../../util-linux/examples/fstab'),
          isNull);
      // Distro absolute links resolve inside the guest.
      expect(
          ToolchainCatalog.unsafeMemberReason(
              '/r', 'ubuntu/etc/alternatives/awk -> /usr/bin/mawk'),
          isNull);
      expect(
          ToolchainCatalog.unsafeMemberReason(
              '/r', 'ubuntu/etc/os-release -> ../usr/lib/os-release'),
          isNull);
      // True escapes still blocked.
      expect(
          ToolchainCatalog.unsafeMemberReason('/r', '../evil'),
          isNotNull);
      expect(
          ToolchainCatalog.unsafeMemberReason(
              '/r', 'ubuntu/x -> ../../../etc/passwd'),
          isNotNull);
      expect(
          ToolchainCatalog.unsafeMemberReason('/r', 'ubuntu/../../evil'),
          isNotNull);
      // …but in-root dotdots are fine (lexical containment is enough).
      expect(
          ToolchainCatalog.unsafeMemberReason(
              '/r', 'ubuntu/a/../../evil'),
          isNull);
    });
  });
}
