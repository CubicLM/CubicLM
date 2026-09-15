/// CubicLM Runtime Toolchain Installer — downloads, verifies and extracts
/// the on-device Linux runtime + opt-in stacks (GetxService).
///
/// Mirrors the reference app's toolchain setup as our own cross-platform
/// implementation:
/// - Catalog: [ToolchainCatalog] (core Ubuntu rootfs + node/python/
///   android/cpp/php overlays, self-hostable base URL).
/// - Download: HTTP Range resume into `.part` files with progress.
/// - Verify: SHA-256 from the catalog or a `<file>.sha256` sidecar.
/// - Extract: system `tar -tzf` listing validated with
///   [ToolchainCatalog.safeJoin] (traversal guard), then `tar -xzf`.
/// - State: per-stack observables + Hive persistence + marker files.
/// - Keep-alive: `com.cubiclm.app/runtime` channel holds a foreground
///   service + wakelock during long installs (Android; no-op elsewhere).
///
/// When the core marker + `usr/bin/bash` exist, the native `proot`
/// channel reports ready and [SandboxManager] auto-switches the terminal
/// and agent shell into isolated Ubuntu — no caller changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../hive_service.dart';
import '../sandbox/sandbox_manager.dart';
import 'toolchain_catalog.dart';

/// Live install status of one stack (bound by the setup UI).
class StackStatus {
  final ToolchainState state;
  final double fraction;
  final int downloadedBytes;
  final int totalBytes;
  final String line;
  final String? error;

  const StackStatus({
    this.state = ToolchainState.unknown,
    this.fraction = 0,
    this.downloadedBytes = 0,
    this.totalBytes = -1,
    this.line = '',
    this.error,
  });

  StackStatus copyWith({
    ToolchainState? state,
    double? fraction,
    int? downloadedBytes,
    int? totalBytes,
    String? line,
    String? error,
  }) =>
      StackStatus(
        state: state ?? this.state,
        fraction: fraction ?? this.fraction,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        line: line ?? this.line,
        error: error,
      );
}

/// Toolchain bundle installer (registered in main deferred init).
class RuntimeInstaller extends GetxService {
  static const _channel = MethodChannel('com.cubiclm.app/runtime');
  static const _kInstalledKey = 'runtime_installed_stacks_v1';
  static const _kBaseUrlKey = 'runtime_base_url';

  /// Observable status per stack id.
  final statuses = <ToolchainId, StackStatus>{}.obs;

  /// Overall busy flag (one install at a time, like the CLI queue).
  final busy = false.obs;

  String _root = '';
  bool _cancelRequested = false;

  Future<RuntimeInstaller> init() async {
    for (final s in ToolchainCatalog.stacks()) {
      statuses[s.id] = const StackStatus();
    }
    await refresh();
    await _reportRuntimeRoot();
    return this;
  }

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  // ── Paths ──────────────────────────────────────────────────────────

  Future<String> get _runtimeRoot async {
    if (_root.isNotEmpty) return _root;
    final base = await getApplicationSupportDirectory();
    _root = '${base.path}/runtime';
    return _root;
  }

  Future<Directory> get _cacheDir async =>
      Directory('${await _runtimeRoot}/cache')..createSync(recursive: true);

  Future<Directory> get _rootfsDir async =>
      Directory('${await _runtimeRoot}/ubuntu');

  String _markerFor(ToolchainId id) => '$_root/.ready-${id.name}';

  String get baseUrl =>
      _hive?.getSetting<String>(_kBaseUrlKey) ??
      ToolchainCatalog.defaultBaseUrl;

  Future<void> setBaseUrl(String url) async {
    try {
      await _hive?.setSetting(_kBaseUrlKey, url.trim());
    } catch (_) {}
  }

  // ── State ──────────────────────────────────────────────────────────

  /// Re-probe marker files → statuses. Call on start + after changes.
  Future<void> refresh() async {
    if (kIsWeb) return;
    try {
      await _runtimeRoot;
      for (final s in ToolchainCatalog.stacks()) {
        final ready = await _isStackReady(s.id);
        final cur = statuses[s.id] ?? const StackStatus();
        // Never clobber an in-flight state.
        if (cur.state == ToolchainState.downloading ||
            cur.state == ToolchainState.verifying ||
            cur.state == ToolchainState.extracting) {
          continue;
        }
        statuses[s.id] = cur.copyWith(
          state: ready ? ToolchainState.ready : ToolchainState.notInstalled,
          error: null,
        );
      }
    } catch (_) {}
  }

  Future<bool> _isStackReady(ToolchainId id) async {
    try {
      if (!File(_markerFor(id)).existsSync()) return false;
      if (id == ToolchainId.core) {
        return File('$_root/ubuntu/usr/bin/bash').existsSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when the isolated Ubuntu runtime can execute commands.
  Future<bool> get isCoreReady async {
    if (kIsWeb) return false;
    try {
      await _runtimeRoot;
      return await _isStackReady(ToolchainId.core);
    } catch (_) {
      return false;
    }
  }

  /// Preflight warnings for installing [id]. Empty = good to go.
  /// Core needs Android + ARM64 (proot + rootfs are ARM64-only).
  Future<List<String>> preflight(ToolchainId id) async {
    final warnings = <String>[];
    if (kIsWeb) {
      return ['Toolchain install needs Android or desktop.'];
    }
    if (id == ToolchainId.core && !Platform.isAndroid) {
      warnings.add('Core Ubuntu runtime needs Android (PRoot).');
    }
    if (id == ToolchainId.core && Platform.isAndroid) {
      final abi = await _androidAbi();
      if (abi.isNotEmpty && !abi.contains('arm64')) {
        warnings.add('Core runtime needs an ARM64 device (found $abi).');
      }
    }
    final stack = ToolchainCatalog.stackOf(id);
    if (stack.needsCore && !await isCoreReady) {
      warnings.add('Install the Core Ubuntu runtime first.');
    }
    return warnings;
  }

  Future<String> _androidAbi() async {
    try {
      final r = await Process.run(
        'getprop',
        ['ro.product.cpu.abi'],
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
      return (r.stdout ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  // ── Install / remove ───────────────────────────────────────────────

  /// Install [id] (all its bundles in order). One at a time; returns null
  /// on success, else an error message. Never throws.
  Future<String?> install(ToolchainId id) async {
    if (kIsWeb) return 'Toolchain install needs Android or desktop.';
    if (busy.value) return 'Another install is already running.';
    final stack = ToolchainCatalog.stackOf(id);
    final blocks = await preflight(id);
    if (blocks.isNotEmpty) return blocks.join('\n');

    busy.value = true;
    _cancelRequested = false;
    await _setKeepAlive(true);
    try {
      for (final bundle in stack.bundles) {
        final err = await _installBundle(id, bundle);
        if (err != null) {
          _set(id, state: ToolchainState.failed, error: err);
          return err;
        }
        if (_cancelRequested) {
          _set(id, state: ToolchainState.notInstalled, line: 'Cancelled.');
          return 'Cancelled.';
        }
      }
      await _writeMarker(id, stack.bundles.map((b) => b.version).join(','));
      await _persistInstalled();
      _set(id, state: ToolchainState.ready, fraction: 1, line: 'Ready.');
      await _refreshSandbox();
      return null;
    } finally {
      busy.value = false;
      await _setKeepAlive(false);
    }
  }

  /// Cancel the in-flight install (checked between bundles/chunks).
  void cancel() {
    _cancelRequested = true;
  }

  /// Remove [id]. Core removal wipes the whole runtime tree (overlays live
  /// inside it); other stacks drop their marker for a clean reinstall.
  /// Never throws.
  Future<void> remove(ToolchainId id) async {
    if (busy.value) return;
    try {
      await _runtimeRoot;
      if (id == ToolchainId.core) {
        final dir = Directory(_root);
        if (await dir.exists()) await dir.delete(recursive: true);
      } else {
        final m = File(_markerFor(id));
        if (await m.exists()) await m.delete();
      }
      await _persistInstalled();
      await refresh();
      await _refreshSandbox();
    } catch (_) {}
  }

  Future<void> _refreshSandbox() async {
    try {
      if (Get.isRegistered<SandboxManager>()) {
        await Get.find<SandboxManager>().refresh();
      }
    } catch (_) {}
  }

  Future<String?> _installBundle(ToolchainId id, RuntimeBundle bundle) async {
    final cache = await _cacheDir;
    final dest = File('${cache.path}/${bundle.fileName}');

    // 1. Download (resume .part).
    _set(id, state: ToolchainState.downloading, line: 'Downloading ${bundle.title}…');
    final url = ToolchainCatalog.bundleUrl(baseUrl, bundle);
    final dlErr = await _downloadWithResume(url, dest, id);
    if (dlErr != null) return dlErr;
    if (_cancelRequested) return 'Cancelled.';

    // 2. Verify SHA-256.
    _set(id, state: ToolchainState.verifying, line: 'Verifying ${bundle.title}…');
    final sumErr = await _verifyChecksum(url, dest, bundle, id);
    if (sumErr != null) return sumErr;
    if (_cancelRequested) return 'Cancelled.';

    // 3. Extract into the rootfs.
    _set(id,
        state: ToolchainState.extracting,
        line: 'Extracting ${bundle.title}…');
    final rootfs = await _rootfsDir;
    await rootfs.create(recursive: true);
    final exErr = await _extractTarGz(dest, rootfs);
    if (exErr != null) return exErr;
    return null;
  }

  // ── Download ───────────────────────────────────────────────────────

  Future<String?> _downloadWithResume(String url, File dest, ToolchainId id) async {
    final part = File('${dest.path}.part');
    var startAt = 0;
    try {
      if (await part.exists()) startAt = await part.length();
      if (await dest.exists() && startAt == 0) {
        // Complete file from a previous run — keep it, verify next.
        _set(id, fraction: 1, line: 'Found cached download.');
        return null;
      }
    } catch (_) {}

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      var target = url;
      HttpClientResponse? resp;
      for (var redirects = 0; redirects < 5; redirects++) {
        final req = await client.getUrl(Uri.parse(target));
        req.headers.set('User-Agent', 'CubicLM-runtime-installer/1.0');
        if (startAt > 0) req.headers.set('Range', 'bytes=$startAt-');
        req.followRedirects = false;
        resp = await req.close().timeout(const Duration(seconds: 60));
        if (resp.isRedirect && resp.statusCode != 304) {
          final loc = resp.headers.value('location');
          await resp.drain();
          if (loc == null || loc.isEmpty) {
            return 'Download redirect without location.';
          }
          target = loc;
          continue;
        }
        break;
      }
      final r = resp!;
      if (r.statusCode == 416) {
        // Range beyond EOF — restart cleanly.
        try {
          await part.delete();
        } catch (_) {}
        startAt = 0;
        return _downloadWithResume(url, dest, id);
      }
      if (r.statusCode != 200 && r.statusCode != 206) {
        await r.drain();
        if (r.statusCode == 404) {
          return 'Bundle not published yet (${Uri.parse(url).pathSegments.last}). '
              'Core + stacks ship with the runtime release — check Settings → Runtime.';
        }
        return 'Download failed (HTTP ${r.statusCode}).';
      }
      if (r.statusCode == 200 && startAt > 0) {
        // Server ignored Range — restart from zero.
        startAt = 0;
        try {
          await part.delete();
        } catch (_) {}
      }
      final total = (r.contentLength < 0 ? -1 : r.contentLength + startAt);
      var received = startAt;
      final sink = part.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in r) {
          if (_cancelRequested) {
            await sink.flush();
            await sink.close();
            return 'Cancelled.';
          }
          sink.add(chunk);
          received += chunk.length;
          final frac = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          _set(
            id,
            fraction: frac,
            downloadedBytes: received,
            totalBytes: total,
            line:
                'Downloading… ${ToolchainCatalog.formatBytes(received)}${total > 0 ? ' / ${ToolchainCatalog.formatBytes(total)}' : ''}',
          );
          if (received % (4 * 1024 * 1024) < chunk.length) {
            await _pushProgress(id);
          }
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        rethrow;
      }
      try {
        if (await dest.exists()) await dest.delete();
        await part.rename(dest.path);
      } catch (e) {
        return 'Could not finalize download: $e';
      }
      _set(id, fraction: 1, line: 'Download complete.');
      return null;
    } catch (e) {
      return 'Download failed: $e';
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  // ── Verify ─────────────────────────────────────────────────────────

  Future<String?> _verifyChecksum(
    String url,
    File dest,
    RuntimeBundle bundle,
    ToolchainId id,
  ) async {
    var expected = bundle.sha256.trim().toLowerCase();
    if (!bundle.hasEmbeddedChecksum) {
      expected = await _fetchSidecarChecksum(
        ToolchainCatalog.checksumUrl(baseUrl, bundle),
      );
    }
    if (expected.isEmpty) {
      _set(id, line: 'No checksum published — skipping verify.');
      return null;
    }
    try {
      final digest = await _sha256File(dest, (done, total) {
        _set(
          id,
          fraction: total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
          line: 'Verifying… ${ToolchainCatalog.formatBytes(done)}',
        );
      });
      if (digest != expected) {
        try {
          await dest.delete();
        } catch (_) {}
        return 'Checksum mismatch — deleted the corrupt file, retry the install.';
      }
      return null;
    } catch (e) {
      return 'Verify failed: $e';
    }
  }

  Future<String> _fetchSidecarChecksum(String url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'CubicLM-runtime-installer/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        await resp.drain();
        return '';
      }
      final text = await resp.transform(utf8.decoder).join();
      final m = RegExp(r'[0-9a-fA-F]{64}').firstMatch(text);
      return (m?.group(0) ?? '').toLowerCase();
    } catch (_) {
      return '';
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  Future<String> _sha256File(
    File file,
    void Function(int done, int total) onProgress,
  ) async {
    final total = await file.length();
    var done = 0;
    // Stream the file through sha256 without holding it all in memory.
    // Report progress per chunk (matches Mobile-Harness verify UX).
    final digest = await sha256.bind(
      file.openRead().map((chunk) {
        done += chunk.length;
        onProgress(done, total);
        return chunk;
      }),
    ).first;
    return digest.toString();
  }

  // ── Extract ────────────────────────────────────────────────────────

  /// List-then-extract with a traversal guard. Uses system `tar`
  /// (Android toybox, desktop bsdtar/GNU) so multi-hundred-MB bundles never
  /// sit fully in memory.
  Future<String?> _extractTarGz(File archive, Directory dest) async {
    // 1. List members.
    List<String> members;
    try {
      final list = await Process.run(
        _tarBin(),
        ['-tzf', archive.path],
        runInShell: false,
      ).timeout(const Duration(minutes: 5));
      if (list.exitCode != 0) {
        return 'Could not list bundle: ${(list.stderr ?? '').toString().trim()}';
      }
      members = (list.stdout ?? '')
          .toString()
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      return 'Archive listing failed: $e';
    }
    // 2. Traversal guard (pure, no I/O).
    for (final m in members) {
      if (ToolchainCatalog.safeJoin(dest.path, m) == null) {
        return 'Blocked unsafe bundle entry: $m';
      }
    }
    if (members.isEmpty) return 'Bundle is empty.';
    // 3. Extract.
    try {
      final ex = await Process.run(
        _tarBin(),
        ['-xzf', archive.path, '-C', dest.path],
        runInShell: false,
      ).timeout(const Duration(minutes: 30));
      if (ex.exitCode != 0) {
        return 'Extract failed: ${(ex.stderr ?? '').toString().trim()}';
      }
      return null;
    } catch (e) {
      return 'Extract failed: $e';
    }
  }

  String _tarBin() =>
      Platform.isWindows ? 'tar.exe' : 'tar';

  // ── Markers + persistence ──────────────────────────────────────────

  Future<void> _writeMarker(ToolchainId id, String version) async {
    try {
      await _runtimeRoot;
      await File(_markerFor(id)).writeAsString(
        'version=$version\ninstalled=${DateTime.now().millisecondsSinceEpoch}\n',
      );
    } catch (_) {}
  }

  Future<void> _persistInstalled() async {
    try {
      final ready = <String>[];
      for (final s in ToolchainCatalog.stacks()) {
        if (await _isStackReady(s.id)) ready.add(s.id.name);
      }
      await _hive?.setSetting(_kInstalledKey, ready);
    } catch (_) {}
  }

  // ── Native keep-alive + progress ───────────────────────────────────

  /// Tell the native side where the runtime root lives (proot ping/exec).
  Future<void> _reportRuntimeRoot() async {
    try {
      if (kIsWeb) return;
      final root = await _runtimeRoot;
      await _channel.invokeMethod('setRuntimeRoot', {'path': root}).timeout(
            const Duration(seconds: 5),
          );
    } on MissingPluginException {
      // No native runtime channel (desktop/web tests) — ignore.
    } catch (_) {}
  }

  Future<void> _setKeepAlive(bool active) async {
    try {
      await _channel.invokeMethod('setKeepAlive', {'active': active}).timeout(
            const Duration(seconds: 5),
          );
    } on MissingPluginException {
      // Desktop/web — no foreground service needed.
    } catch (_) {}
  }

  Future<void> _pushProgress(ToolchainId id) async {
    try {
      final st = statuses[id] ?? const StackStatus();
      await _channel.invokeMethod('updateProgress', {
        'title': 'Installing ${ToolchainCatalog.stackOf(id).title}',
        'fraction': st.fraction.clamp(0.0, 1.0),
        'line': st.line,
      }).timeout(const Duration(seconds: 3));
    } on MissingPluginException {
      // Desktop/web — no native progress surface.
    } catch (_) {}
  }

  void _set(
    ToolchainId id, {
    ToolchainState? state,
    double? fraction,
    int? downloadedBytes,
    int? totalBytes,
    String? line,
    String? error,
  }) {
    final cur = statuses[id] ?? const StackStatus();
    statuses[id] = cur.copyWith(
      state: state ?? cur.state,
      fraction: fraction ?? cur.fraction,
      downloadedBytes: downloadedBytes ?? cur.downloadedBytes,
      totalBytes: totalBytes ?? cur.totalBytes,
      line: line ?? cur.line,
      error: error,
    );
  }
}
