/// CubicLM Sandbox — pluggable command-execution backends.
///
/// Every shell command in the app (agent tools, terminal) funnels through
/// [SandboxManager], which picks the best available [SandboxBackend]:
/// PRoot Ubuntu when the native runtime is installed, otherwise the host
/// shell. When the native PRoot work lands, only [ProotBackend] changes —
/// callers stay untouched.
///
/// Pure Dart types here; backends may use platform channels.
library;

/// Result of one sandboxed command run.
class SandboxResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  final bool timedOut;

  const SandboxResult({
    this.stdout = '',
    this.stderr = '',
    this.exitCode = -1,
    this.timedOut = false,
  });

  bool get success => !timedOut && exitCode == 0;
}

/// A place where shell commands can run.
abstract class SandboxBackend {
  /// Human label, e.g. 'PRoot Ubuntu 20.04' or 'Host shell'.
  String get name;

  /// True when this backend can run commands right now.
  Future<bool> isAvailable();

  /// Run [command] in [workDir] (null = backend default). Never throws —
  /// failures come back as a non-zero [SandboxResult].
  Future<SandboxResult> run(
    String command, {
    String? workDir,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  });
}
