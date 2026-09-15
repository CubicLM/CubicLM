/// CubicLM Sandbox — PRoot Ubuntu backend (native work pending).
///
/// NATIVE CONTRACT (for the future Android implementation — mirrors
/// Mobile-Harness pocket_spawn.c):
/// - MethodChannel `com.cubiclm.app/proot` with methods:
///   - `ping` → bool (true when the Ubuntu rootfs is installed + runnable)
///   - `exec` {command: String, cwd: String, timeoutMs: int} →
///     {stdout: String, stderr: String, exitCode: int}
/// - Native side: JNI → fork/exec proot with the rootfs at
///   `<filesDir>/runtime/ubuntu`, guest cwd `/workspace/<slug>`,
///   bindings for /dev, /proc, /sys, and the project workspace.
/// - Bundles (core Ubuntu 20.04 ARM64 + node/npm/git; opt-in python,
///   android-sdk, cpp) download on demand like the reference app.
///
/// Until that native code ships, [isAvailable] returns false and the
/// [SandboxManager] transparently falls back to [HostBackend]. Callers
/// MUST go through the manager so the switch is automatic.
library;

import 'package:flutter/services.dart';

import 'sandbox_backend.dart';

/// PRoot Ubuntu backend. Unavailable until the native runtime ships.
class ProotBackend implements SandboxBackend {
  static const MethodChannel _channel =
      MethodChannel('com.cubiclm.app/proot');

  bool? _cachedAvailable;

  @override
  String get name => 'PRoot Ubuntu 20.04';

  @override
  Future<bool> isAvailable() async {
    if (_cachedAvailable != null) return _cachedAvailable!;
    try {
      final ok = await _channel
          .invokeMethod<bool>('ping')
          .timeout(const Duration(seconds: 3));
      _cachedAvailable = ok ?? false;
    } catch (_) {
      _cachedAvailable = false;
    }
    return _cachedAvailable!;
  }

  /// Forget the cached probe (e.g. after the user installs the runtime).
  void resetCache() {
    _cachedAvailable = null;
  }

  @override
  Future<SandboxResult> run(
    String command, {
    String? workDir,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    if (!await isAvailable()) {
      return const SandboxResult(
        stderr:
            'PRoot runtime not installed yet — enable it in setup to run commands in isolated Ubuntu.',
        exitCode: -1,
      );
    }
    try {
      final raw = await _channel.invokeMethod<Map>('exec', {
        'command': command,
        'cwd': workDir ?? '',
        'timeoutMs': timeout.inMilliseconds,
      }).timeout(timeout + const Duration(seconds: 5));
      final map = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
      return SandboxResult(
        stdout: (map['stdout'] ?? '').toString(),
        stderr: (map['stderr'] ?? '').toString(),
        exitCode: (map['exitCode'] as num?)?.toInt() ?? -1,
      );
    } catch (e) {
      return SandboxResult(
          stderr: 'PRoot exec failed: $e', exitCode: -1);
    }
  }
}
