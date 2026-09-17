/// CubicLM Terminal — sandboxed shell sessions.
///
/// One session per scope (`default` + one per agent project), each with its
/// own transcript, history, and working directory, persisted across
/// restarts. Commands route through [SandboxManager] (isolated PRoot
/// Ubuntu when the runtime is installed, screened host shell otherwise)
/// after [SandboxService] screening.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../hive_service.dart';
import '../app_log_service.dart';
import '../sandbox/sandbox_manager.dart';
import '../security/sandbox_service.dart';
import '../../utils/preview_guard.dart';
import '../../utils/text_sanitize.dart';

/// One terminal output line. Public for the view + tests.
class TerminalLine {
  final String text;
  final bool isError;
  final bool isCommand;

  const TerminalLine(this.text,
      {this.isError = false, this.isCommand = false});

  Map<String, dynamic> toMap() =>
      {'t': text, 'e': isError, 'c': isCommand};

  static TerminalLine? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    return TerminalLine(
      (raw['t'] ?? '').toString(),
      isError: raw['e'] == true,
      isCommand: raw['c'] == true,
    );
  }
}

/// Split a command into shell + args for the current platform.
/// Public (pure) for unit tests.
List<String> buildShellParts(String command) {
  if (Platform.isWindows) return ['cmd.exe', '/c', command];
  return ['/bin/sh', '-c', command];
}

/// Compact a working directory for the prompt line (Mobile-Harness
/// parity: the guest root shows as `~`). Empty stays empty (the view
/// shows the default `$` prompt then). Pure for unit tests.
String compactPromptPath(String cwd, {String? home}) {
  if (cwd.isEmpty) return '';
  final h = home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (h.isNotEmpty && (cwd == h || cwd.startsWith('$h/'))) {
    return '~${cwd.substring(h.length)}';
  }
  return cwd;
}

/// POSIX single-quote a shell word (Mobile-Harness `shellQuote` parity).
/// Pure for unit tests.
String shellQuote(String value) =>
    "'${value.replaceAll("'", "'\\''")}'";

/// Marker prefix for CWD tracking (random suffix per run, like the
/// reference app's `__POCKETDEV_CWD_<uuid>__`, so command output can
/// never collide with it).
const cwdMarkerPrefix = '__CLM_CWD__';

/// Wrap [command] so the shell reports its real working directory when
/// done: `cd` into [cwd], run, print `<marker><$PWD>`, preserve the exit
/// code. POSIX only — the caller keeps the legacy `cd` parser on
/// Windows. Pure for unit tests.
String wrapWithCwdTracking(String command, String cwd, String marker) {
  // Note: every shell `$` below is Dart-escaped (`\$`) — only
  // ${shellQuote(cwd)} and $marker interpolate.
  return 'cd -- ${shellQuote(cwd)} || exit 1\n'
      '$command\n'
      '__CLM_EXIT=\$?\n'
      "printf '\\n$marker%s\\n' \"\$PWD\"\n"
      'exit \$__CLM_EXIT';
}

/// Split tracked output into display text + reported cwd. Marker lines
/// are dropped from display; the LAST marker wins. Pure for unit tests.
({String clean, String cwd}) parseCwdMarker(String output, String marker) {
  String? cwd;
  final kept = <String>[];
  for (final line in const LineSplitter().convert(output)) {
    if (line.startsWith(marker)) {
      final rest = line.substring(marker.length).trim();
      if (rest.isNotEmpty) cwd = rest;
    } else {
      kept.add(line);
    }
  }
  return (clean: kept.join('\n'), cwd: cwd ?? '');
}

/// Live-output `[Y/n]` prompt sniff (Mobile-Harness `shouldAutoConfirm…`
/// parity): answered once with `y` while package commands run.
bool looksLikeConfirmPrompt(String tail) => RegExp(
      r'\[Y/n\]|Do you want to continue',
      caseSensitive: false,
    ).hasMatch(tail);

/// Make `apt`/`apt-get` non-interactive (Mobile-Harness parity).
///
/// Prepends `DEBIAN_FRONTEND=noninteractive` and injects `-y` plus
/// `--force-confold`/`--force-confdef` dpkg options so package installs
/// never stall on `y/n` or conffile prompts inside the runtime. Commands
/// that already opt out, or that are not package-manager invocations
/// (`install`/`remove`/`update`/… subcommands only), pass through
/// untouched. Pure for unit tests.
String withAutoConfirm(String command) {
  final cmd = command.trim();
  if (cmd.isEmpty || Platform.isWindows) return command;
  var rest = cmd;
  var sudo = '';
  if (rest == 'sudo' || rest.startsWith('sudo ')) {
    sudo = 'sudo ';
    rest = rest.substring(5).trimLeft();
  }
  final match = RegExp(r'^(apt|apt-get)(\s|$)').firstMatch(rest);
  if (match == null) return command;
  final bin = match.group(1)!;
  var tail = rest.substring(bin.length);
  const actionable = {
    'install',
    'remove',
    'purge',
    'update',
    'upgrade',
    'dist-upgrade',
    'full-upgrade',
    'autoremove',
  };
  final sub = tail
      .trimLeft()
      .split(RegExp(r'\s+'))
      .firstWhere((t) => !t.startsWith('-'), orElse: () => '');
  if (!actionable.contains(sub)) return command;
  if (!tail.contains(RegExp(r'(^|\s)(--yes|-y)\b'))) {
    tail = '$tail -y';
  }
  if (!tail.contains('force-confold')) {
    tail = '$tail -o Dpkg::Options::=--force-confdef '
        '-o Dpkg::Options::=--force-confold';
  }
  const env = 'DEBIAN_FRONTEND=noninteractive ';
  if (cmd.startsWith(env)) return command;
  return '$env$sudo$bin$tail';
}

/// Per-session stored state (mirrored into observables for the active one).
class _SessionState {
  final List<TerminalLine> lines = [];
  final List<String> history = [];
  String workingDir = '';
  int? lastExitCode;
}

/// Session-scoped terminal (registered in main deferred init).
class TerminalService extends GetxService {
  static const maxLines = 1000;
  static const maxHistory = 100;
  static const maxPersistedLines = 200;

  /// Live transcript byte cap (Mobile-Harness parity: 200 KB). One huge
  /// `cat` must not grow memory without bound; oldest lines drop first.
  static const maxLiveChars = 200 * 1024;
  static const defaultSessionId = 'default';

  /// Active session observables (the view binds to these).
  final lines = <TerminalLine>[].obs;
  final history = <String>[].obs;
  final isRunning = false.obs;
  final workingDir = ''.obs;
  final lastExitCode = RxnInt();
  final activeSessionId = defaultSessionId.obs;

  /// Latest loopback URL seen in output (Mobile-Harness parity: dev
  /// servers print `http://localhost:PORT`). Null when none this run.
  final previewUrl = RxnString();

  final Map<String, _SessionState> _sessions = {};
  Process? _process;

  Future<TerminalService> init() async {
    _loadSession(defaultSessionId);
    return this;
  }

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  // ── Sessions ─────────────────────────────────────────────────────

  _SessionState _stateFor(String id) =>
      _sessions.putIfAbsent(id, () => _SessionState());

  /// Switch to another session (persists the current one first).
  void switchSession(String id) {
    final target = id.isEmpty ? defaultSessionId : id;
    if (target == activeSessionId.value && _sessions.containsKey(target)) {
      return;
    }
    _stashActive();
    activeSessionId.value = target;
    if (!_sessions.containsKey(target)) _loadSession(target);
    _mirror(target);
    // Detection is per-run, not persisted.
    previewUrl.value = null;
  }

  void _stashActive() {
    final id = activeSessionId.value;
    final st = _stateFor(id);
    st.lines
      ..clear()
      ..addAll(lines);
    st.history
      ..clear()
      ..addAll(history);
    st.workingDir = workingDir.value;
    st.lastExitCode = lastExitCode.value;
    _persist(id, st);
  }

  void _mirror(String id) {
    final st = _stateFor(id);
    lines.assignAll(st.lines);
    history.assignAll(st.history);
    workingDir.value = st.workingDir;
    lastExitCode.value = st.lastExitCode;
  }

  void _loadSession(String id) {
    final hive = _hive;
    final st = _stateFor(id);
    if (hive == null) return;
    try {
      st.workingDir =
          hive.getSetting<String>('terminal_cwd_$id', defaultValue: '') ??
              '';
      final rawLines = hive.getSetting<List>('terminal_transcript_$id');
      if (rawLines != null) {
        st.lines
          ..clear()
          ..addAll(rawLines
              .map(TerminalLine.fromMap)
              .whereType<TerminalLine>()
              .take(maxPersistedLines));
      }
      final rawHistory = hive.getSetting<List>('terminal_history_$id');
      if (rawHistory != null) {
        st.history
          ..clear()
          ..addAll(rawHistory.map((e) => e.toString()).take(maxHistory));
      }
    } catch (_) {}
    if (id == activeSessionId.value) _mirror(id);
  }

  void _persist(String id, _SessionState st) {
    final hive = _hive;
    if (hive == null) return;
    try {
      hive.setSetting('terminal_cwd_$id', st.workingDir);
      hive.setSetting(
        'terminal_transcript_$id',
        st.lines
            .skip(st.lines.length > maxPersistedLines
                ? st.lines.length - maxPersistedLines
                : 0)
            .map((l) => l.toMap())
            .toList(),
      );
      hive.setSetting('terminal_history_$id', st.history.toList());
    } catch (_) {}
  }

  // ── Execution ────────────────────────────────────────────────────

  /// Set the working directory (must exist). Persists per session.
  Future<bool> setWorkingDir(String path) async {
    try {
      if (path.isEmpty) return false;
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      workingDir.value = dir.path;
      _stateFor(activeSessionId.value).workingDir = dir.path;
      _persist(activeSessionId.value, _stateFor(activeSessionId.value));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Run [command], streaming output into [lines]. Blocked commands are
  /// rejected without spawning a process. Returns the exit code.
  ///
  /// On POSIX shells with a known working directory the command runs
  /// wrapped in CWD tracking (Mobile-Harness marker protocol), so `cd`,
  /// `pushd`, subshells and scripts all update the prompt correctly —
  /// no fragile client-side `cd` parsing. Windows keeps the legacy path.
  Future<int> runCommand(String command, {Duration? timeout}) async {
    final raw = command.trim();
    if (raw.isEmpty) return -1;
    if (isRunning.value) return -1;

    final blocked = SandboxService.isCommandBlocked(raw);
    if (blocked != null) {
      _append(TerminalLine('Blocked: $blocked', isError: true));
      lastExitCode.value = -1;
      AppLogService.trailAction('terminal blocked ($blocked)');
      return -1;
    }

    // Package installs never stall on interactive prompts.
    final cmd = withAutoConfirm(raw);
    // Fresh detection scope per command; pre-seed from well-known
    // dev-server invocations (reference-app parity).
    previewUrl.value = findServerUrlFromCommand(cmd);

    // Marker-tracked runs (POSIX + known cwd). Everything else keeps the
    // legacy `cd` parser below.
    final tracked = !Platform.isWindows && workingDir.value.isNotEmpty;
    final marker =
        '${cwdMarkerPrefix}_${DateTime.now().microsecondsSinceEpoch}_${lines.length}_';
    final shellCmd =
        tracked ? wrapWithCwdTracking(cmd, workingDir.value, marker) : cmd;

    // CWD tracking for cd commands (legacy path: Windows, or no cwd yet).
    if (!tracked && _isCdCommand(cmd)) {
      final newDir = _resolveCdTarget(cmd);
      if (newDir != null) {
        final ok = await setWorkingDir(newDir);
        if (!ok) {
          _append(TerminalLine('cd: no such directory: $newDir', isError: true));
          lastExitCode.value = 1;
        } else {
          _append(TerminalLine('\$ $cmd', isCommand: true));
          lastExitCode.value = 0;
        }
        return lastExitCode.value!;
      }
    }

    _append(TerminalLine('\$ $cmd', isCommand: true));
    _pushHistory(cmd);
    isRunning.value = true;
    try {
      int exitCode;
      var shownChars = 0;
      if (Get.isRegistered<SandboxManager>()) {
        // Sandboxed run (isolated PRoot when installed): output lands
        // at once.
        final result = await Get.find<SandboxManager>().run(
          shellCmd,
          workDir: workingDir.value.isEmpty ? null : workingDir.value,
          timeout: timeout ?? const Duration(seconds: 60),
        );
        final parsed = tracked
            ? parseCwdMarker(result.stdout, marker)
            : (clean: result.stdout, cwd: '');
        final parsedErr = tracked
            ? parseCwdMarker(result.stderr, marker)
            : (clean: result.stderr, cwd: '');
        for (final line in const LineSplitter().convert(parsed.clean)) {
          if (line.isEmpty) continue;
          shownChars += line.length;
          _append(TerminalLine(SandboxService.redactSecrets(line)));
        }
        for (final line in const LineSplitter().convert(parsedErr.clean)) {
          if (line.isEmpty) continue;
          shownChars += line.length;
          _append(TerminalLine(SandboxService.redactSecrets(line),
              isError: true));
        }
        if (result.timedOut) {
          _append(const TerminalLine('(timed out)', isError: true));
        }
        exitCode = result.exitCode;
        _adoptCwd(parsed.cwd);
      } else {
        // Direct host run with live streaming (tests + fallback).
        final out = await _runDirect(
          shellCmd,
          rawCmd: raw,
          timeout: timeout,
          tracked: tracked,
          marker: marker,
        );
        exitCode = out.exitCode;
        shownChars = out.shownChars;
      }
      lastExitCode.value = exitCode;
      // Terminal lane: first token only, secrets scrubbed — never the
      // full command line.
      final head = SandboxService.redactSecrets(
          cmd.split(RegExp(r'\s+')).firstWhere((t) => t.isNotEmpty,
              orElse: () => 'cmd'));
      AppLogService.trailAction('terminal $head exit $exitCode');
      if (shownChars == 0 && exitCode != 0) {
        _append(TerminalLine('Process exited with code $exitCode',
            isError: true));
      }
      _append(TerminalLine('[exit $exitCode]', isError: exitCode != 0));
      return exitCode;
    } finally {
      isRunning.value = false;
      _stashActive();
    }
  }

  /// Export the current session transcript as plain text.
  String exportTranscript() {
    final buf = StringBuffer();
    buf.writeln('CubicLM Terminal — Session: ${activeSessionId.value}');
    buf.writeln('Working directory: ${workingDir.value}');
    buf.writeln('Exported: ${DateTime.now()}');
    buf.writeln('─' * 50);
    for (final l in lines) {
      buf.writeln(l.text);
    }
    return buf.toString();
  }

  /// Detect `cd` commands and resolve the target directory.
  static bool _isCdCommand(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    return parts.isNotEmpty && parts[0] == 'cd';
  }

  String? _resolveCdTarget(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    String target;
    if (parts.length < 2 || parts[1] == '~') {
      // cd alone or cd ~ goes home
      target = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          workingDir.value;
    } else {
      target = parts[1];
    }
    // Resolve relative to current working dir
    if (!target.startsWith('/') && !target.contains(r':')) {
      final base = workingDir.value.isEmpty
          ? (Platform.environment['PWD'] ?? '.')
          : workingDir.value;
      target = '$base${Platform.pathSeparator}$target';
    }
    // Normalize
    try {
      final dir = Directory(target);
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  /// Adopt a marker-reported cwd: host paths must exist (validated);
  /// guest paths (sandboxed runs) are trusted when absolute — the marker
  /// carries a per-run random suffix, like the reference app. The legacy
  /// `cd` parser stays as the fallback. Never throws.
  Future<void> _adoptCwd(String cwd) async {
    try {
      if (cwd.isEmpty || cwd == workingDir.value) return;
      if (await setWorkingDir(cwd)) return;
      if (!cwd.startsWith('/')) return;
      workingDir.value = cwd;
      _stateFor(activeSessionId.value).workingDir = cwd;
      _persist(activeSessionId.value, _stateFor(activeSessionId.value));
    } catch (_) {}
  }

  /// Send a line to the running process's stdin (reference-app `onInput`
  /// parity). True when delivered — only possible on direct host runs;
  /// sandboxed one-shot runs have no live stdin.
  bool sendInput(String text) {
    try {
      final proc = _process;
      if (proc == null) return false;
      proc.stdin.writeln(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<({int exitCode, int shownChars})> _runDirect(
    String cmd, {
    required String rawCmd,
    Duration? timeout,
    bool tracked = false,
    String marker = '',
  }) async {
    final parts = buildShellParts(cmd);
    // Watch apt-family commands for interactive [Y/n] prompts (the static
    // -y injection covers most cases; this is the live backstop).
    final lowerRaw = rawCmd.toLowerCase();
    final watchConfirm = !Platform.isWindows &&
        RegExp(r'(^|[;&|]\s*)(sudo\s+)?(apt|apt-get|dpkg)\b')
            .hasMatch(lowerRaw);
    var autoConfirmed = false;
    var tail = '';
    var shownChars = 0;
    final rawBuf = StringBuffer();
    void handleLine(String line, {required bool isError}) {
      rawBuf.writeln(line);
      if (tracked && marker.isNotEmpty && line.startsWith(marker)) return;
      if (line.isEmpty) return;
      shownChars += line.length;
      _append(TerminalLine(SandboxService.redactSecrets(line),
          isError: isError));
      if (watchConfirm && !autoConfirmed) {
        tail = '$tail\n$line';
        if (tail.length > 500) tail = tail.substring(tail.length - 500);
        if (looksLikeConfirmPrompt(tail)) {
          autoConfirmed = true;
          try {
            _process?.stdin.writeln('y');
          } catch (_) {}
        }
      }
    }

    try {
      _process = await Process.start(
        parts[0],
        parts.sublist(1),
        workingDirectory:
            workingDir.value.isEmpty ? null : workingDir.value,
        runInShell: false,
      );
      final proc = _process!;
      final stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, isError: false));
      final stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => handleLine(line, isError: true));
      int exitCode;
      try {
        if (timeout == null) {
          exitCode = await proc.exitCode;
        } else {
          exitCode = await proc.exitCode.timeout(timeout, onTimeout: () {
            kill();
            return -1;
          });
        }
      } finally {
        await stdoutSub.cancel();
        await stderrSub.cancel();
      }
      if (tracked && marker.isNotEmpty) {
        final parsed = parseCwdMarker(rawBuf.toString(), marker);
        await _adoptCwd(parsed.cwd);
      }
      return (exitCode: exitCode, shownChars: shownChars);
    } on ProcessException catch (e) {
      _append(TerminalLine('Failed to start: ${e.message}', isError: true));
      return (exitCode: -1, shownChars: shownChars);
    } catch (e) {
      _append(TerminalLine('Error: $e', isError: true));
      return (exitCode: -1, shownChars: shownChars);
    } finally {
      _process = null;
    }
  }

  /// Kill the running process: SIGTERM first, SIGKILL after 400 ms
  /// (reference-app destroy → destroyForcibly parity). No-op for
  /// sandboxed one-shot runs (no live process handle).
  void kill() {
    final proc = _process;
    if (proc == null) return;
    try {
      proc.kill();
    } catch (_) {
      return;
    }
    Future.delayed(const Duration(milliseconds: 400), () {
      try {
        if (_process == proc) proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });
  }

  /// Clear the active session's output.
  void clear() {
    lines.clear();
    previewUrl.value = null;
    _stashActive();
  }

  /// Clear every session transcript (reference-app "Clear terminal
  /// history" parity): output lines go, command history stays — exactly
  /// like the reference app, which keeps its 50-command history.
  /// Never throws.
  void clearAll() {
    try {
      for (final entry in _sessions.entries) {
        entry.value.lines.clear();
      }
      lines.clear();
      previewUrl.value = null;
      _stashActive();
    } catch (_) {}
  }

  void _append(TerminalLine line) {
    // Strip ANSI escapes + control chars first (reference-app parity):
    // colored output must never render as raw glyph soup. The sniff
    // below then sees clean text.
    final clean = line.isCommand
        ? line
        : TerminalLine(sanitizeAnsi(line.text),
            isError: line.isError, isCommand: false);
    lines.add(clean);
    if (lines.length > maxLines) {
      lines.removeRange(0, lines.length - maxLines);
    }
    var total = 0;
    for (final l in lines) {
      total += l.text.length;
    }
    while (total > maxLiveChars && lines.length > 1) {
      total -= lines.first.text.length;
      lines.removeAt(0);
    }
    // Sniff loopback dev-server URLs for the preview chip. Cheap gate
    // first; full regex only on matching lines.
    if (!clean.isCommand &&
        previewUrl.value == null &&
        (clean.text.contains('localhost') ||
            clean.text.contains('127.0.0.1'))) {
      previewUrl.value = findPreviewUrl(clean.text);
    }
  }

  void _pushHistory(String cmd) {
    history.remove(cmd);
    history.insert(0, cmd);
    if (history.length > maxHistory) {
      history.removeRange(maxHistory, history.length);
    }
  }
}
