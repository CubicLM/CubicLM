/// CubicLM Runtime Toolchains — bundle catalog (pure Dart).
///
/// Mirrors the reference app's toolchain setup (core Ubuntu runtime +
/// opt-in Python / Android / C++ / PHP stacks) as data: what to download,
/// how big it is, and which marker file proves it is installed.
///
/// Bundles are `.tar.gz` archives published under a base URL (overrideable
/// in Settings for self-hosting). Sizes are discovered at download time via
/// `Content-Length` — the catalog carries file names + versions, never
/// faked byte counts. SHA-256 is verified from the embedded value when
/// present, otherwise from a `<file>.sha256` sidecar next to the bundle.
library;

/// Toolchain stack ids. `core` (Ubuntu rootfs + node/npm/git) is required
/// by every other stack.
enum ToolchainId { core, node, python, android, cpp, php }

/// Per-stack install state.
enum ToolchainState {
  unknown,
  notInstalled,
  downloading,
  verifying,
  extracting,
  ready,
  failed,
}

/// One downloadable archive.
class RuntimeBundle {
  final String fileName;
  final String version;
  final String sha256;
  final String title;

  const RuntimeBundle({
    required this.fileName,
    required this.version,
    this.sha256 = '',
    required this.title,
  });

  bool get hasEmbeddedChecksum =>
      sha256.trim().length >= 64;
}

/// One installable toolchain stack (MH "toolchain" picker row).
class ToolchainStack {
  final ToolchainId id;
  final String title;
  final String subtitle;
  final List<RuntimeBundle> bundles;
  final bool needsCore;
  final String downloadNote;

  /// False while no bundle is published: the UI shows "Coming soon"
  /// instead of a doomed Install button (failed taps used to spam the
  /// Runtime log lane).
  final bool available;

  const ToolchainStack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.bundles,
    this.needsCore = true,
    required this.downloadNote,
    this.available = true,
  });
}

/// Catalog + pure path helpers (unit-tested).
class ToolchainCatalog {
  /// Default bundle host. Override in Settings → Runtime for self-hosting.
  static const defaultBaseUrl =
      'https://github.com/abir2afridi/CubicLM/releases/download/runtime-2026.09';

  /// All installable stacks in setup-wizard order.
  static List<ToolchainStack> stacks() => const [
        ToolchainStack(
          id: ToolchainId.core,
          title: 'Core Ubuntu runtime',
          subtitle: 'Ubuntu 20.04 ARM64 userspace + shell tooling',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-core-arm64.tar.gz',
              version: 'ubuntu-20.04.5-arm64',
              title: 'Core rootfs',
            ),
          ],
          needsCore: false,
          downloadNote: 'One-time download, then everything runs on-device.',
        ),
        ToolchainStack(
          id: ToolchainId.node,
          title: 'Node.js LTS',
          subtitle: 'node, npm, npx for web builds + dev servers',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-node-arm64.tar.gz',
              version: 'node-24.21.0-arm64',
              title: 'Node.js overlay',
            ),
          ],
          downloadNote: 'Required for CubicWeb builds and preview servers.',
        ),
        ToolchainStack(
          id: ToolchainId.python,
          title: 'Python suite',
          subtitle: 'Python 3.8, pip, venv',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-python-arm64.tar.gz',
              version: 'python-3.8-arm64',
              title: 'Python overlay',
            ),
          ],
          downloadNote: 'For Python scripts, tooling and AI experiments.',
        ),
        ToolchainStack(
          id: ToolchainId.android,
          title: 'Android & JVM',
          subtitle: 'OpenJDK 17 + Gradle for on-device APK builds',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-android-arm64.tar.gz',
              version: 'android-sdk36-arm64',
              title: 'Android overlay',
            ),
          ],
          downloadNote:
              'Large download. Enables the build play button → direct install.',
          // Needs an ARM64 AAPT2 built from AOSP source — honest hold.
          available: false,
        ),
        ToolchainStack(
          id: ToolchainId.cpp,
          title: 'C / C++ suite',
          subtitle: 'GCC, Clang, Make, CMake',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-cpp-arm64.tar.gz',
              version: 'cpp-suite-arm64',
              title: 'Compiler overlay',
            ),
          ],
          downloadNote: 'For native compilation inside the runtime.',
          available: false,
        ),
        ToolchainStack(
          id: ToolchainId.php,
          title: 'PHP runtime',
          subtitle: 'PHP CLI + Composer',
          bundles: [
            RuntimeBundle(
              fileName: 'cubiclm-php-arm64.tar.gz',
              version: 'php-cli-arm64',
              title: 'PHP overlay',
            ),
          ],
          downloadNote: 'For PHP projects and Composer packages.',
          available: false,
        ),
      ];

  static ToolchainStack stackOf(ToolchainId id) =>
      stacks().firstWhere((s) => s.id == id);

  /// Full download URL for [bundle] under [baseUrl].
  static String bundleUrl(String baseUrl, RuntimeBundle bundle) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/${bundle.fileName}';
  }

  /// Sidecar checksum URL (`<file>.sha256`).
  static String checksumUrl(String baseUrl, RuntimeBundle bundle) =>
      '${bundleUrl(baseUrl, bundle)}.sha256';

  /// Join [entry] (tar member) under [root]. Returns null when the member
  /// would escape the root (absolute path, `..`, drive letter). Pure.
  /// Strict variant (rejects ANY `..`): kept for jail checks. Tar
  /// validation uses [unsafeMemberReason], which understands symlinks.
  static String? safeJoin(String root, String entry) {
    var p = entry.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.isEmpty) return null;
    if (RegExp(r'^[A-Za-z]:').hasMatch(p)) return null;
    final parts = <String>[];
    for (final seg in p.split('/')) {
      final s = seg.trim();
      if (s.isEmpty || s == '.') continue;
      if (s == '..') return null;
      parts.add(s);
    }
    if (parts.isEmpty) return null;
    final sep = root.endsWith('/') || root.endsWith('\\') ? '' : '/';
    return '$root$sep${parts.join('/')}';
  }

  /// Human byte count (`1.5 GB`). Pure.
  static String formatBytes(num bytes) {
    if (bytes < 0) return '—';
    if (bytes < 1024) return '${bytes.toInt()} B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble() / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[u]}';
  }

  /// Split a `tar -t` member line into path + link target. Toybox and GNU
  /// list symlinks as `<path> -> <target>` — the old guard fed the whole
  /// line to [safeJoin] and blocked legit distro links (e.g. Ubuntu's
  /// `doc/mount/examples/fstab -> ../../util-linux/…`). Pure.
  static ({String path, String? target}) splitTarMember(String raw) {
    final i = raw.indexOf(' -> ');
    if (i < 0) return (path: raw.trim(), target: null);
    return (
      path: raw.substring(0, i).trim(),
      target: raw.substring(i + 4).trim(),
    );
  }

  /// Lexically resolve [path] under [root], popping `..` segments.
  /// Returns null on escape (leading/`..`-past-root), absolute paths and
  /// drive letters. No I/O — dangling links are fine. Pure.
  static String? resolveInside(String root, String path) {
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.isEmpty) return null;
    if (RegExp(r'^[A-Za-z]:').hasMatch(p)) return null;
    final parts = <String>[];
    for (final seg in p.split('/')) {
      final s = seg.trim();
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (parts.isEmpty) return null;
        parts.removeLast();
        continue;
      }
      parts.add(s);
    }
    if (parts.isEmpty) return null;
    final sep = root.endsWith('/') || root.endsWith('\\') ? '' : '/';
    return '$root$sep${parts.join('/')}';
  }

  /// Validate one `tar -t` member line. Returns null when safe, else a
  /// human reason. Entry paths must stay in root (lexical `..` allowed
  /// while it resolves inside). Symlink targets: relative ones resolve
  /// against the link's directory; absolute ones (`/usr/bin/…`, normal
  /// in distro rootfs) resolve against the guest root, since proot maps
  /// them inside at runtime. Hash-pinned bundles are the real trust
  /// anchor; this stops corrupt archives from writing outside. Pure.
  static String? unsafeMemberReason(String root, String rawMember) {
    final split = splitTarMember(rawMember);
    if (resolveInside(root, split.path) == null) {
      return 'escapes the runtime: ${split.path}';
    }
    final target = split.target;
    if (target != null && target.isNotEmpty) {
      String rel;
      if (target.startsWith('/')) {
        rel = target;
      } else {
        final dir = split.path.contains('/')
            ? split.path.substring(0, split.path.lastIndexOf('/'))
            : '';
        rel = dir.isEmpty ? target : '$dir/$target';
      }
      if (resolveInside(root, rel) == null) {
        return 'link escapes the runtime: ${split.path} -> $target';
      }
    }
    return null;
  }
}
