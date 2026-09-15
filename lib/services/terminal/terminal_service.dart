/// CubicLM Terminal — sandboxed shell sessions.
///
/// One session per scope (`default` + one per agent project), each with its
/// own transcript, history, and working directory, persisted across
/// restarts. Commands route through [SandboxManager] (PRoot Ubuntu when
/// the native runtime is installed, host shell otherwise) after
/// [SandboxService] screening. Full PRoot/Ubuntu isolation is deferred
/// native work (roadmap Phase 6).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../hive_service.dart';
import '../sandbox/sandbox_manager.dart';
import '../security/sandbox_service.dart';

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
  static const defaultSessionId = 'default';

  /// Active session observables (the view binds to these).
  final lines = <TerminalLine>[].obs;
  final history = <String>[].obs;
  final isRunning = false.obs;
  final workingDir = ''.obs;
  final lastExitCode = RxnInt();
  final activeSessionId = defaultSessionId.obs;

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
  Future<int> runCommand(String command, {Duration? timeout}) async {
    final cmd = command.trim();
    if (cmd.isEmpty) return -1;
    if (isRunning.value) return -1;

    final blocked = SandboxService.isCommandBlocked(cmd);
    if (blocked != null) {
      _append(TerminalLine('Blocked: $blocked', isError: true));
      lastExitCode.value = -1;
      return -1;
    }

    _append(TerminalLine('\$ $cmd', isCommand: true));
    _pushHistory(cmd);
    isRunning.value = true;
    try {
      int exitCode;
      if (Get.isRegistered<SandboxManager>()) {
        // Sandboxed run (PRoot when installed): output lands at once.
        final result = await Get.find<SandboxManager>().run(
          cmd,
          workDir: workingDir.value.isEmpty ? null : workingDir.value,
          timeout: timeout ?? const Duration(seconds: 60),
        );
        for (final line in const LineSplitter().convert(result.stdout)) {
          _append(TerminalLine(SandboxService.redactSecrets(line)));
        }
        for (final line in const LineSplitter().convert(result.stderr)) {
          _append(TerminalLine(SandboxService.redactSecrets(line),
              isError: true));
        }
        if (result.timedOut) {
          _append(const TerminalLine('(timed out)', isError: true));
        }
        exitCode = result.exitCode;
      } else {
        // Direct host run with live streaming (tests + fallback).
        exitCode = await _runDirect(cmd, timeout: timeout);
      }
      lastExitCode.value = exitCode;
      _append(TerminalLine('[exit $exitCode]', isError: exitCode != 0));
      return exitCode;
    } finally {
      isRunning.value = false;
      _stashActive();
    }
  }

  Future<int> _runDirect(String cmd, {Duration? timeout}) async {
    final parts = buildShellParts(cmd);
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
          .listen((line) => _append(TerminalLine(
              SandboxService.redactSecrets(line))));
      final stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _append(TerminalLine(
              SandboxService.redactSecrets(line),
              isError: true)));
      try {
        if (timeout == null) return await proc.exitCode;
        return await proc.exitCode.timeout(timeout, onTimeout: () {
          kill();
          return -1;
        });
      } finally {
        await stdoutSub.cancel();
        await stderrSub.cancel();
      }
    } on ProcessException catch (e) {
      _append(TerminalLine('Failed to start: ${e.message}', isError: true));
      return -1;
    } catch (e) {
      _append(TerminalLine('Error: $e', isError: true));
      return -1;
    } finally {
      _process = null;
    }
  }

  /// Kill the running process (if any).
  void kill() {
    try {
      _process?.kill();
    } catch (_) {}
  }

  /// Clear the active session's output.
  void clear() {
    lines.clear();
    _stashActive();
  }

  void _append(TerminalLine line) {
    lines.add(line);
    if (lines.length > maxLines) {
      lines.removeRange(0, lines.length - maxLines);
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
