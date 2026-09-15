/// CubicLM Sandbox — backend selector for all command execution.
///
/// Prefers [ProotBackend] when the native Ubuntu runtime is installed,
/// otherwise [HostBackend]. [RunCommandTool] and [TerminalService] call
/// [run] so isolation arrives automatically once PRoot ships — no caller
/// changes needed.
library;

import 'package:get/get.dart';

import 'host_backend.dart';
import 'proot_backend.dart';
import 'sandbox_backend.dart';

/// Selects and exposes the active sandbox backend.
class SandboxManager extends GetxService {
  final ProotBackend proot = ProotBackend();
  final HostBackend host = HostBackend();

  /// Human label of the backend chosen for the last run.
  final activeBackendName = 'Host shell'.obs;

  Future<SandboxManager> init() async {
    await refresh();
    return this;
  }

  /// Re-probe backends (call after runtime install / uninstall).
  Future<void> refresh() async {
    proot.resetCache();
    activeBackendName.value =
        await proot.isAvailable() ? proot.name : host.name;
  }

  /// True when commands run inside isolated Ubuntu.
  Future<bool> get isIsolated async => await proot.isAvailable();

  /// Run [command] on the best available backend. Never throws.
  Future<SandboxResult> run(
    String command, {
    String? workDir,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    if (await proot.isAvailable()) {
      activeBackendName.value = proot.name;
      return proot.run(command,
          workDir: workDir, timeout: timeout, environment: environment);
    }
    activeBackendName.value = host.name;
    return host.run(command,
        workDir: workDir, timeout: timeout, environment: environment);
  }
}
