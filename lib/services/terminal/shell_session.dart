/// CubicLM Terminal — persistent interactive shell session (Termux core).
///
/// One long-lived shell process per session instead of a process per
/// command: `cd`, env vars, shell history, TAB completion and job control
/// persist exactly like Termux.
///
/// Output is fed into a real VT100/xterm [TerminalEmulator]; the view
/// renders that grid. A genuine PTY is obtained with `script -qefc`
/// inside the PRoot guest (or the host on Linux/macOS), which gives
/// readline, colors, full-screen apps (`vim`, `htop`, `nano`) and job
/// control. When `script`/PTY support is unavailable the session falls
/// back to a pipe-backed interactive shell, and the view shows the
/// classic input line instead.
///
/// Backends, in priority order:
/// 1. PRoot Ubuntu guest (Android, runtime installed): same argv/env as
///    the native one-shot channel (`MainActivity.runProotExec`).
/// 2. Host shell (desktop): cmd.exe on Windows, bash on Linux/macOS.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:get/get.dart';

import 'terminal_emulator.dart';

/// Where the session's shell runs.
enum ShellSessionBackend { none, prootUbuntu, host }

/// Marker kept for compatibility with older transcripts. The emulator
/// renders the real prompt now, so nothing parses it.
const shellPromptMarker = '@CLM|';

/// PS1 used by the guest shell: a Termux-flavored two-tone prompt.
const String guestPromptPs1 =
    r'\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ ';

/// A live shell process with streaming output and a terminal emulator.
class ShellSession {
  Process? _proc;
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;

  /// True while the process is alive and accepting stdin.
  final alive = false.obs;

  /// Which backend actually spawned (none = not started / failed).
  final backend = ShellSessionBackend.none.obs;

  /// True when stdin/stdout are a real PTY (readline, job control,
  /// full-screen apps work).
  final pty = false.obs;

  /// Window title reported by the shell (OSC 0/2).
  final title = ''.obs;

  /// The screen model the view paints.
  final emulator = TerminalEmulator();

  /// Fired when the process dies (view offers a restart).
  final onExit = <VoidCallback>[];

  String _sizeFile = '';

  bool get isAlive => alive.value;
  bool get isPty => pty.value;

  /// Spawn a persistent shell bound to [cwd] (host path). Returns true
  /// when the process is alive.
  Future<bool> start({
    required String cwd,
    required String? prootRoot,
    required String? prootTmpDir,
    String? nativeLibDir,
    int cols = 80,
    int rows = 24,
  }) async {
    await stop();
    emulator.resize(cols, rows);
    emulator.clear();

    try {
      Process? proc;
      var usePty = false;

      if (prootRoot != null) {
        final root = Directory(prootRoot);
        var proot = File('${root.path}/bin/proot');
        var loader = File('${root.path}/libexec/proot/loader');
        var loader32 = File('${root.path}/libexec/proot/loader32');
        final libs = Directory('${root.path}/lib');
        // Android 10+ denies execve() on app-private storage for
        // targetSdk 29+. PRoot and its loader are therefore shipped as
        // lib*.so in nativeLibraryDir; PRoot maps guest ELFs through
        // the loader instead of asking the kernel to execute them.
        final nativeLib = (nativeLibDir?.trim().isNotEmpty ?? false)
            ? nativeLibDir!.trim()
            : null;
        if (nativeLib != null) {
          final nativeProot = File('$nativeLib/libproot.so');
          final nativeLoader = File('$nativeLib/libproot_loader.so');
          if (await nativeProot.exists() && await nativeLoader.exists()) {
            proot = nativeProot;
            loader = nativeLoader;
            final nativeLoader32 = File('$nativeLib/libproot_loader32.so');
            if (await nativeLoader32.exists()) loader32 = nativeLoader32;
          }
        }
        if (!await proot.exists() || !await loader.exists()) {
          return false;
        }
        final hostDir = Directory(cwd);
        if (!await hostDir.exists()) {
          await hostDir.create(recursive: true);
        }
        final tmp =
            Directory('${prootTmpDir ?? Directory.systemTemp.path}/proot-tmp');
        if (!await tmp.exists()) await tmp.create(recursive: true);

        // Integration files live inside the guest's /root, never in the
        // user's project directory.
        final guestHome = Directory('${root.path}/ubuntu/root');
        if (!await guestHome.exists()) await guestHome.create(recursive: true);
        // /etc/bash.bashrc shows the Ubuntu sudo hint (and, under PRoot,
        // one "groups: cannot find name for group ID" warning per Android
        // GID) unless this marker exists. Keep startup output clean.
        try {
          final sudoMarker =
              File('${guestHome.path}/.sudo_as_admin_successful');
          if (!await sudoMarker.exists()) {
            await sudoMarker.writeAsString('', flush: true);
          }
        } catch (_) {}
        _sizeFile = '${guestHome.path}/.cubiclm.size';
        final rcHost = '${guestHome.path}/.cubiclmrc';
        const rcGuest = '/root/.cubiclmrc';
        const sizeGuest = '/root/.cubiclm.size';
        await _writeIntegration(rcHost, sizeGuest, cols, rows);

        final env = <String, String>{
          'HOME': '/root',
          'PATH':
              '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
          'LANG': 'C.UTF-8',
          'LC_ALL': 'C.UTF-8',
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'SHELL': '/bin/bash',
          'PS1': guestPromptPs1,
          'PROOT_NO_SECCOMP': '1',
          'PROOT_TMP_DIR': tmp.path,
          'PROOT_LOADER': loader.path,
          'PROOT_LOADER_32':
              loader32.existsSync() ? loader32.path : loader.path,
          'LD_LIBRARY_PATH':
              nativeLib == null ? libs.path : '$nativeLib:${libs.path}',
        };
        final base = <String>[
          proot.path,
          '--link2symlink',
          // No detached shell/foreground app may outlive its session
          // (proot otherwise waits on orphaned tracees after `exit`).
          '--kill-on-exit',
          '-0',
          '-r',
          '${root.path}/ubuntu',
          '-b',
          '/dev',
          '-b',
          '/proc',
          '-b',
          '/sys',
          '-b',
          '${hostDir.path}:/workspace',
          '-w',
          '/workspace',
        ];
        final hasScript =
            await File('${root.path}/ubuntu/usr/bin/script').exists() ||
                await File('${root.path}/ubuntu/bin/script').exists();

        if (hasScript) {
          proc = await _spawn(
            [
              ...base,
              '/usr/bin/script',
              '-qefc',
              'bash --rcfile $rcGuest -i',
              '/dev/null',
            ],
            null,
            env,
          );
          usePty = true;
        }
        if (proc == null || await _diedEarly(proc)) {
          await _discard(proc);
          proc = await _spawn(
            [...base, '/bin/bash', '--rcfile', rcGuest, '-i'],
            null,
            env,
          );
          usePty = false;
          emulator.clear();
        }
        backend.value = ShellSessionBackend.prootUbuntu;
      } else if (Platform.isWindows) {
        proc = await _spawn(
          ['cmd.exe', '/Q', '/K'],
          cwd.isEmpty ? null : cwd,
          {'PROMPT': r'$P$G'},
        );
        backend.value = ShellSessionBackend.host;
      } else {
        final hostDir = Directory(cwd);
        if (!await hostDir.exists()) await hostDir.create(recursive: true);
        final shell = File('/bin/bash').existsSync()
            ? '/bin/bash'
            : (Platform.environment['SHELL']?.isNotEmpty == true
                ? Platform.environment['SHELL']!
                : '/bin/sh');
        final tmp = Directory(
            '${prootTmpDir ?? Directory.systemTemp.path}/cubiclm-term');
        if (!await tmp.exists()) await tmp.create(recursive: true);
        _sizeFile = '${tmp.path}/.cubiclm.size';
        final rcHost = '${tmp.path}/.cubiclmrc';
        await _writeIntegration(rcHost, _sizeFile, cols, rows);
        final env = <String, String>{
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'SHELL': shell,
          'PS1': guestPromptPs1,
        };
        final scriptPath = _hostScriptPath();
        if (scriptPath != null) {
          proc = await _spawn(
            Platform.isMacOS
                ? [
                    scriptPath,
                    '-q',
                    '/dev/null',
                    shell,
                    '--rcfile',
                    rcHost,
                    '-i',
                  ]
                : [
                    scriptPath,
                    '-qefc',
                    '$shell --rcfile ${_quote(rcHost)} -i',
                    '/dev/null',
                  ],
            hostDir.path,
            env,
          );
          usePty = proc != null;
        }
        if (proc == null || await _diedEarly(proc)) {
          await _discard(proc);
          proc = await _spawn(
            [shell, '--rcfile', rcHost, '-i'],
            hostDir.path,
            env,
          );
          usePty = false;
          emulator.clear();
        }
        backend.value = ShellSessionBackend.host;
      }

      if (proc == null) {
        backend.value = ShellSessionBackend.none;
        return false;
      }

      _proc = proc;
      alive.value = true;
      pty.value = usePty;
      _wire(proc);
      return true;
    } catch (_) {
      alive.value = false;
      pty.value = false;
      backend.value = ShellSessionBackend.none;
      return false;
    }
  }

  Future<Process?> _spawn(
    List<String> args,
    String? workDir,
    Map<String, String> env,
  ) async {
    try {
      return await Process.start(
        args.first,
        args.sublist(1),
        workingDirectory: workDir,
        environment: env,
        runInShell: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Give a freshly spawned shell a moment to fail (e.g. `script`
  /// cannot allocate a PTY inside PRoot). Alive after ~350 ms wins.
  Future<bool> _diedEarly(Process proc) async {
    var exited = false;
    unawaited(proc.exitCode.then((_) => exited = true));
    // Drain nothing here: the real listeners attach once accepted. A
    // shell cannot fill a pipe with output in this window.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return exited;
  }

  Future<void> _discard(Process? proc) async {
    if (proc == null) return;
    try {
      proc.kill();
      await proc.exitCode
          .timeout(const Duration(milliseconds: 400), onTimeout: () => -1);
    } catch (_) {}
  }

  void _wire(Process proc) {
    emulator.onResponse = (data) => write(data);
    emulator.onTitle = (value) => title.value = value;
    emulator.onBell = () {};
    emulator.onClipboard = null;

    _outSub = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
            (chunk) => emulator.feed(isPty ? chunk : _normalizeNewlines(chunk)),
            onDone: _onProcExit,
            onError: (_) {});
    _errSub = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
      final clean = isPty ? chunk : _filterStderr(chunk);
      if (clean.isNotEmpty) {
        // A real PTY already emits CRLF; only pipes need translation.
        emulator.feed(isPty ? clean : _normalizeNewlines(clean));
      }
    }, onDone: () {}, onError: (_) {});
    unawaited(proc.exitCode.then((_) => _onProcExit()));
  }

  /// Pipe-backed shells emit bare `\n`; a real tty translates it to
  /// `\r\n` (ONLCR). Normalize so lines don't stair-step.
  static String _normalizeNewlines(String chunk) {
    if (!chunk.contains('\n')) return chunk;
    return chunk.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }

  static String _filterStderr(String chunk) {
    if (!chunk.contains('bash:')) return chunk;
    return chunk
        .replaceAll(
            RegExp(r'bash: cannot set terminal process group[^\n]*\n?'), '')
        .replaceAll(RegExp(r'bash: no job control in this shell[^\n]*\n?'), '');
  }

  /// Write the generated shell integration (colors, prompt, live resize).
  Future<void> _writeIntegration(
    String rcPath,
    String sizeFile,
    int cols,
    int rows,
  ) async {
    final rc = '''
# CubicLM Terminal integration — generated, safe to overwrite.
# Load the normal bash startup first so Termux-style dotfile tweaks
# keep working; the managed defaults below take precedence.
if [ -r "\$HOME/.bashrc" ]; then . "\$HOME/.bashrc"; fi
export TERM=xterm-256color
export COLORTERM=truecolor
export CLICOLOR=1
export CLICOLOR_FORCE=1
export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32'
export GREP_COLORS='ms=01;31:mc=01;31:sl=:cx=:fn=35:ln=32:bn=32:se=36'
export HISTCONTROL=ignoredups
export HISTSIZE=10000
export EDITOR=nano
export PAGER=less
export LESS='-R'
shopt -s checkwinsize 2>/dev/null
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
PS1='$guestPromptPs1'
CUBICLM_SIZE_FILE='$sizeFile'
__cubiclm_resize() {
  if [ -r "\$CUBICLM_SIZE_FILE" ]; then
    read -r __cubiclm_c __cubiclm_r < "\$CUBICLM_SIZE_FILE" 2>/dev/null
    if [ -n "\$__cubiclm_c" ] && [ -n "\$__cubiclm_r" ]; then
      stty cols "\$__cubiclm_c" rows "\$__cubiclm_r" 2>/dev/null
    fi
  fi
}
__cubiclm_title() {
  printf '\\033]0;%s@%s: %s\\007' "\${USER:-root}" "\${HOSTNAME:-localhost}" "\$PWD"
}
PROMPT_COMMAND="__cubiclm_resize; __cubiclm_title\${PROMPT_COMMAND:+; \$PROMPT_COMMAND}"
__cubiclm_resize
# Poll the size file so live resizes reach full-screen apps too. While
# vim/htop owns the foreground process group, PROMPT_COMMAND cannot run,
# but TIOCSWINSZ from here still delivers SIGWINCH to the app.
__cubiclm_watch_size() {
  trap '' TTOU 2>/dev/null
  __cubiclm_last=''
  while :; do
    if [ -r "\$CUBICLM_SIZE_FILE" ]; then
      __cubiclm_c=''
      __cubiclm_r=''
      read -r __cubiclm_c __cubiclm_r < "\$CUBICLM_SIZE_FILE" 2>/dev/null
      if [ -n "\$__cubiclm_c" ] && [ -n "\$__cubiclm_r" ] &&
        [ "\$__cubiclm_c \$__cubiclm_r" != "\$__cubiclm_last" ]; then
        stty cols "\$__cubiclm_c" rows "\$__cubiclm_r" </dev/tty 2>/dev/null
        __cubiclm_last="\$__cubiclm_c \$__cubiclm_r"
      fi
    fi
    sleep 0.5
  done
}
if [ -t 0 ] && [ -t 1 ]; then
  __cubiclm_watch_size </dev/tty >/dev/null 2>&1 &
  __cubiclm_watch_pid=\$!
  disown "\$__cubiclm_watch_pid" 2>/dev/null
  trap 'kill "\$__cubiclm_watch_pid" 2>/dev/null' EXIT
fi
''';
    try {
      final file = File(rcPath);
      if (!await file.exists() || await file.readAsString() != rc) {
        await file.writeAsString(rc, flush: true);
      }
    } catch (_) {}
    try {
      await File(sizeFile).writeAsString('$cols $rows', flush: true);
    } catch (_) {}
  }

  static String? _hostScriptPath() {
    for (final path in const ['/usr/bin/script', '/bin/script']) {
      try {
        if (File(path).existsSync()) return path;
      } catch (_) {}
    }
    return null;
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  /// Resize the screen grid and tell the shell (PTY) about it. The rc's
  /// size watcher applies the new dimensions asynchronously, including
  /// inside vim/htop where a prompt nudge would type into the buffer.
  void resize(int cols, int rows) {
    emulator.resize(cols, rows);
    if (_sizeFile.isEmpty) return;
    try {
      File(_sizeFile).writeAsStringSync('$cols $rows', flush: true);
    } catch (_) {}
  }

  void _onProcExit() {
    if (!alive.value) {
      return;
    }
    alive.value = false;
    pty.value = false;
    emulator.feed('\r\n\x1b[31m[session ended]\x1b[0m\r\n');
    for (final cb in List<VoidCallback>.from(onExit)) {
      try {
        cb();
      } catch (_) {}
    }
  }

  /// Write raw bytes to the shell's stdin (commands, control chars,
  /// escape sequences). No-op when dead.
  void write(String raw) {
    final proc = _proc;
    if (proc == null || !alive.value) return;
    try {
      proc.stdin.write(raw);
      unawaited(proc.stdin.flush().catchError((_) {}));
    } catch (_) {}
  }

  /// Submit one command line (adds the line terminator). A real tty
  /// turns `\r` into `\n` via ICRNL; a pipe has no such translation,
  /// so use `\n` there.
  void submitLine(String cmd) => write(isPty ? '$cmd\r' : '$cmd\n');

  /// CTRL + [letter]: 0x01–0x1A control codes (Termux CTRL key parity).
  /// [letter] is the lowercase char code ('c' → ^C).
  void sendCtrl(int letter) {
    final code = letter - 96;
    if (code >= 1 && code <= 26) {
      write(String.fromCharCode(code));
    }
  }

  /// Send an escape sequence (arrows, HOME/END, PGUP/PGDN, ESC …).
  void sendEscape(String seq) => write('\x1b$seq');

  /// Stop the shell process. Tries a clean `exit` first so the guest
  /// shell and its children tear down; escalates after 500 ms.
  Future<void> stop() async {
    final proc = _proc;
    final wasPty = pty.value;
    _proc = null;
    alive.value = false;
    pty.value = false;
    if (proc == null) return;
    try {
      // Interrupt a foreground command so `exit` reaches the shell and
      // the rc's EXIT trap can stop the size watcher. A stuck app is
      // still force-killed below. Pipe shells have no line discipline:
      // a literal ^C would corrupt the queued `exit` command.
      if (wasPty) {
        proc.stdin.write('\x03');
        await proc.stdin
            .flush()
            .timeout(const Duration(milliseconds: 80), onTimeout: () {});
      }
      proc.stdin.write('exit\n');
      await proc.stdin
          .flush()
          .timeout(const Duration(milliseconds: 120), onTimeout: () {});
    } catch (_) {}
    try {
      await proc.exitCode.timeout(const Duration(milliseconds: 500),
          onTimeout: () {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {}
        return -1;
      });
    } catch (_) {}
    try {
      proc.kill();
    } catch (_) {}
    await _outSub?.cancel();
    await _errSub?.cancel();
    _outSub = null;
    _errSub = null;
  }
}
