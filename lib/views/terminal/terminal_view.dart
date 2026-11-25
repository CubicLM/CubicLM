/// CubicLM Terminal — a Termux-grade terminal screen.
///
/// Persistent PTY shell (PRoot Ubuntu on Android, host bash on desktop)
/// rendered by a real VT100/xterm emulator, with the exact Termux color
/// palette, extra keys, sticky CTRL/ALT, sessions, search, selection and
/// a pure-black UI. Falls back to one-shot commands when a persistent
/// shell is unavailable.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/agent_workspace.dart';
import '../../services/hive_service.dart';
import '../../services/security/sandbox_service.dart';
import '../../services/terminal/terminal_emulator.dart';
import '../../services/terminal/terminal_service.dart';
import '../../services/terminal/terminal_theme.dart';
import 'terminal_console.dart';

class TerminalView extends StatefulWidget {
  const TerminalView({super.key});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView>
    with WidgetsBindingObserver {
  late final TerminalService term;
  final _consoleKey = GlobalKey<TerminalConsoleState>();
  final _legacyScroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _raw = TextEditingController();
  final _rawFocus = FocusNode();

  late final Worker _scrollWorker;

  bool _startingShell = false;
  bool _autoStartTried = false;
  String _shellError = '';

  String _themeId = 'termux';
  double _fontSize = 12.5;
  TerminalCursorStyle _cursorStyle = TerminalCursorStyle.block;
  int _scrollback = 5000;

  bool _ctrlArmed = false;
  bool _altArmed = false;
  bool _shiftArmed = false;
  String _rawSent = '';
  int _histIndex = -1;

  /// The live color table (OSC-mutable) shared by emulator and renderer.
  late final TerminalPalette _palette;

  TerminalPalette get _theme => _palette;
  Color get _accent => _theme.colors[2];

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  @override
  void initState() {
    super.initState();
    term = Get.isRegistered<TerminalService>()
        ? Get.find<TerminalService>()
        : Get.put(TerminalService());
    _loadSettings();
    _palette = TerminalPalette(TerminalTheme.byId(_themeId));
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _scrollWorker = ever<List<TerminalLine>>(term.lines, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_legacyScroll.hasClients) return;
        try {
          _legacyScroll.jumpTo(_legacyScroll.position.maxScrollExtent);
        } catch (_) {}
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureShell());
  }

  void _loadSettings() {
    final hive = _hive;
    if (hive == null) return;
    try {
      _themeId =
          hive.getSetting<String>('terminal_theme', defaultValue: 'termux') ??
              'termux';
      _fontSize =
          hive.getSetting<double>('terminal_font_size', defaultValue: 12.5) ??
              12.5;
      _scrollback =
          hive.getSetting<int>('terminal_scrollback', defaultValue: 5000) ??
              5000;
      final cursor =
          hive.getSetting<String>('terminal_cursor', defaultValue: 'block') ??
              'block';
      _cursorStyle = switch (cursor) {
        'underline' => TerminalCursorStyle.underline,
        'bar' => TerminalCursorStyle.bar,
        _ => TerminalCursorStyle.block,
      };
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // xterm focus reporting (DEC 1004): vim/tmux/neovim use these to
    // pause redraws or commit swap files while the app is in the
    // background, exactly like Termux.
    final emu = term.emulator;
    if (emu == null) return;
    if (state == AppLifecycleState.resumed) {
      emu.sendFocusEvent(true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      emu.sendFocusEvent(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _scrollWorker.dispose();
    _legacyScroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _raw.dispose();
    _rawFocus.dispose();
    super.dispose();
  }

  // ── Shell lifecycle ──────────────────────────────────────────────

  ({int cols, int rows}) _estimateGrid() {
    final size = MediaQuery.sizeOf(context);
    final cellW = (_fontSize * 0.61).clamp(5.0, 20.0);
    final rowH = (_fontSize * 1.35).clamp(10.0, 40.0);
    final width = size.width - 16;
    final height = size.height - 240;
    return (
      cols: (width / cellW).floor().clamp(20, 300),
      rows: (height / rowH).floor().clamp(8, 200),
    );
  }

  Future<void> _ensureShell({bool force = false}) async {
    if (_startingShell) return;
    if (!force && term.emulator != null) return;
    if (!force && _autoStartTried) return;
    _autoStartTried = true;
    final grid = _estimateGrid();
    setState(() {
      _startingShell = true;
      _shellError = '';
    });
    final ok = await term.enablePersistentShell(
      cols: grid.cols,
      rows: grid.rows,
    );
    if (!mounted) return;
    setState(() {
      _startingShell = false;
      if (!ok) {
        _shellError = Platform.isAndroid
            ? 'Persistent shell unavailable. Install the PRoot Ubuntu runtime '
                'from Toolkit → Runtime, then retry. One-shot commands still work.'
            : 'Persistent shell unavailable. One-shot commands still work.';
      }
    });
    if (ok) {
      term.emulator?.maxScrollback = _scrollback;
      term.emulator?.bindPalette(_palette);
      term.emulator?.setCursorStyle(_cursorStyle);
      term.resizeTerminal(grid.cols, grid.rows);
    }
  }

  Future<void> _restartShell() async {
    await term.disablePersistentShell();
    if (!mounted) return;
    setState(() => _shellError = '');
    await _ensureShell(force: true);
  }

  Future<void> _switchSession(String id) async {
    Navigator.of(context).maybePop();
    if (id == term.activeSessionId.value) return;
    await term.switchSession(id);
    if (!mounted) return;
    setState(() {
      _autoStartTried = false;
      _shellError = '';
    });
    await _ensureShell(force: true);
  }

  void _resizeTerminal(int cols, int rows) {
    term.resizeTerminal(cols, rows);
  }

  // ── Input ────────────────────────────────────────────────────────

  void _focusKeyboard() {
    if (!term.isPty) return;
    _rawFocus.requestFocus();
  }

  void _writeText(String text) {
    if (text.isEmpty) return;
    // A pipe-backed shell has no tty: type into the visible input line
    // instead of writing straight to stdin.
    if (!term.isPty) {
      _insertIntoInput(text);
      return;
    }
    if (_ctrlArmed) {
      _ctrlArmed = false;
      for (final ch in text.split('')) {
        term.writeRaw(TermuxKeys.ctrl(ch));
      }
    } else if (_altArmed) {
      _altArmed = false;
      term.writeRaw('\x1b$text');
    } else if (_shiftArmed) {
      _shiftArmed = false;
      term.writeRaw(text.toUpperCase());
    } else {
      term.writeRaw(text);
    }
    if (mounted) setState(() {});
  }

  void _insertIntoInput(String text) {
    final value = _input.value;
    final sel = value.selection;
    final start =
        sel.isValid ? sel.start.clamp(0, value.text.length) : value.text.length;
    final end =
        sel.isValid ? sel.end.clamp(0, value.text.length) : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _inputFocus.requestFocus();
  }

  void _sendChar(String ch) {
    _writeText(ch);
    _focusKeyboard();
  }

  /// Sticky modifiers apply to exactly one key, then disarm themselves.
  ({bool shift, bool alt, bool ctrl}) _takeModifiers() {
    final mods = (shift: _shiftArmed, alt: _altArmed, ctrl: _ctrlArmed);
    _shiftArmed = false;
    _altArmed = false;
    _ctrlArmed = false;
    return mods;
  }

  void _sendSpecial(String id) {
    final m = _takeModifiers();
    final cursorApp = term.emulator?.applicationCursorKeys ?? false;
    String? seq;
    switch (id) {
      case 'esc':
        seq = '\x1b';
      case 'tab':
        seq = TermuxKeys.tab(shift: m.shift);
      case 'backspace':
        seq = TermuxKeys.backspace(alt: m.alt, ctrl: m.ctrl);
      case 'enter':
        seq = TermuxKeys.enter(alt: m.alt);
      case 'up':
        seq = TermuxKeys.arrow('A',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'down':
        seq = TermuxKeys.arrow('B',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'right':
        seq = TermuxKeys.arrow('C',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'left':
        seq = TermuxKeys.arrow('D',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'home':
        seq = TermuxKeys.homeEnd('H',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'end':
        seq = TermuxKeys.homeEnd('F',
            cursorApp: cursorApp, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'pgup':
        seq = TermuxKeys.tilde(5, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'pgdn':
        seq = TermuxKeys.tilde(6, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'insert':
        seq = TermuxKeys.tilde(2, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'delete':
        seq = TermuxKeys.tilde(3, shift: m.shift, alt: m.alt, ctrl: m.ctrl);
      case 'ctrl-c':
        seq = '\x03';
      default:
        if (id.startsWith('f')) {
          final n = int.tryParse(id.substring(1));
          if (n == null || n < 1 || n > 12) return;
          seq = TermuxKeys.functionKey(n,
              shift: m.shift, alt: m.alt, ctrl: m.ctrl);
        } else {
          return;
        }
    }
    if (seq.isEmpty) return;
    _resetRawMirror();
    term.writeRaw(seq);
    if (mounted) setState(() {});
    _focusKeyboard();
  }

  /// Readline/history/editing keys change the shell's input line without
  /// going through the hidden text field, so drop the mirrored text.
  /// Otherwise the next soft-keyboard edit would replay stale characters.
  void _resetRawMirror() {
    if (_rawSent.isEmpty && _raw.text.isEmpty) return;
    _rawSent = '';
    _raw.value = const TextEditingValue();
  }

  void _onRawChanged(String value) {
    if (!term.isPty) return;
    final composing = _raw.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    if (value.length > _rawSent.length && value.startsWith(_rawSent)) {
      _writeText(value.substring(_rawSent.length));
    } else if (value.length < _rawSent.length && _rawSent.startsWith(value)) {
      final removed = _rawSent.length - value.length;
      for (var i = 0; i < removed; i++) {
        term.writeRaw('\x7f');
      }
    } else if (value != _rawSent) {
      for (var i = 0; i < _rawSent.length; i++) {
        term.writeRaw('\x7f');
      }
      _writeText(value);
    }
    _rawSent = value;
    if (value.length > 200) {
      _rawSent = '';
      _raw.value = const TextEditingValue();
    }
  }

  void _onRawSubmitted(String _) {
    term.writeRaw('\r');
    _resetRawMirror();
    _focusKeyboard();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (!term.isPty) {
        _insertIntoInput(clean.replaceAll('\n', ' '));
        return;
      }
      if (term.emulator?.bracketedPaste == true) {
        term.writeRaw('\x1b[200~$clean\x1b[201~');
      } else {
        term.writeRaw(clean);
      }
    } catch (_) {}
    _focusKeyboard();
  }

  Future<void> _copyScreen() async {
    final text = term.emulator?.screenText() ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('Screen copied');
  }

  /// OSC 8 hyperlink tap. Bare hostnames become https:// URLs; only
  /// web links are opened (terminal output is untrusted).
  Future<void> _openLink(String raw) async {
    final target = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(target);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _toast('Blocked unsafe link: $raw');
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _toast('Cannot open $raw');
      }
    } catch (_) {
      _toast('Invalid link: $raw');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_inputFocus.hasFocus) return false;
    if (_consoleKey.currentState?.isSearching == true) return false;
    // Special keys must reach the shell even while the hidden IME field
    // owns focus (the normal state): otherwise physical arrows/PageUp/
    // Tab/Esc/Ctrl+C would only move a 1×1 invisible cursor instead of
    // driving readline or vim. Plain text still flows through the field
    // so the on-screen keyboard keeps its mirror in sync.
    if (!term.isPty) return false;

    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed;
    final alt = kb.isAltPressed;
    final shift = kb.isShiftPressed;
    final key = event.logicalKey;

    if (ctrl && shift && key == LogicalKeyboardKey.keyC) {
      unawaited(_copyScreen());
      return true;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return true;
    }

    final emu = term.emulator;
    final cursorApp = emu?.applicationCursorKeys ?? false;
    final keypadApp = emu?.applicationKeypad ?? false;
    final meta = kb.isMetaPressed;

    String arrow(String l) => TermuxKeys.arrow(l,
        cursorApp: cursorApp, shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    String tilde(int n) =>
        TermuxKeys.tilde(n, shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    String fkey(int n) => TermuxKeys.functionKey(n,
        shift: shift, alt: alt, ctrl: ctrl, meta: meta);

    String? seq;
    if (key == LogicalKeyboardKey.arrowUp) seq = arrow('A');
    if (key == LogicalKeyboardKey.arrowDown) seq = arrow('B');
    if (key == LogicalKeyboardKey.arrowRight) seq = arrow('C');
    if (key == LogicalKeyboardKey.arrowLeft) seq = arrow('D');
    if (key == LogicalKeyboardKey.home) {
      seq = TermuxKeys.homeEnd('H',
          cursorApp: cursorApp, shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    }
    if (key == LogicalKeyboardKey.end) {
      seq = TermuxKeys.homeEnd('F',
          cursorApp: cursorApp, shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    }
    if (key == LogicalKeyboardKey.pageUp) seq = tilde(5);
    if (key == LogicalKeyboardKey.pageDown) seq = tilde(6);
    if (key == LogicalKeyboardKey.insert) seq = tilde(2);
    if (key == LogicalKeyboardKey.delete) seq = tilde(3);
    if (key == LogicalKeyboardKey.escape) seq = '\x1b';
    if (key == LogicalKeyboardKey.tab) seq = TermuxKeys.tab(shift: shift);
    if (key == LogicalKeyboardKey.printScreen) seq = '\x1b[32~';
    if (key == LogicalKeyboardKey.pause) seq = '\x1b[34~';
    for (var n = 1; n <= 12; n++) {
      if (key == _fKeys[n - 1]) seq = fkey(n);
    }

    // Application keypad (DECNKM / ?66): SS3 sequences for the numpad.
    if (keypadApp) {
      for (var d = 0; d <= 9; d++) {
        if (key == _numKeys[d]) seq = TermuxKeys.keypadApplication['$d'];
      }
      if (key == LogicalKeyboardKey.numpadAdd) {
        seq = TermuxKeys.keypadApplication['+'];
      }
      if (key == LogicalKeyboardKey.numpadSubtract) {
        seq = TermuxKeys.keypadApplication['-'];
      }
      if (key == LogicalKeyboardKey.numpadMultiply) {
        seq = TermuxKeys.keypadApplication['*'];
      }
      if (key == LogicalKeyboardKey.numpadDivide) {
        seq = TermuxKeys.keypadApplication['/'];
      }
      if (key == LogicalKeyboardKey.numpadDecimal) {
        seq = TermuxKeys.keypadApplication['.'];
      }
      if (key == LogicalKeyboardKey.numpadEqual) {
        seq = TermuxKeys.keypadApplication['='];
      }
    }
    if (key == LogicalKeyboardKey.numpadEnter) {
      if (_rawFocus.hasFocus) return false;
      _resetRawMirror();
      term.writeRaw(keypadApp ? '\x1bOM' : '\n');
      return true;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (_rawFocus.hasFocus) return false;
      _resetRawMirror();
      term.writeRaw(TermuxKeys.enter(alt: alt));
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_rawFocus.hasFocus && _rawSent.isNotEmpty) return false;
      _resetRawMirror();
      term.writeRaw(TermuxKeys.backspace(alt: alt, ctrl: ctrl));
      return true;
    }
    if (seq != null && seq.isNotEmpty) {
      _resetRawMirror();
      term.writeRaw(seq);
      return true;
    }

    if (ctrl && !alt) {
      final ch = _letterFor(key, event);
      if (ch != null) {
        _resetRawMirror();
        term.writeRaw(TermuxKeys.ctrl(ch));
        return true;
      }
      if (key == LogicalKeyboardKey.space) {
        _resetRawMirror();
        term.writeRaw('\x00');
        return true;
      }
    }
    if (alt && !ctrl) {
      final ch = _letterFor(key, event);
      if (ch != null) {
        _resetRawMirror();
        term.writeRaw('\x1b$ch');
        return true;
      }
    }

    if (!ctrl && !alt && !_rawFocus.hasFocus) {
      final ch = event.character;
      if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
        term.writeRaw(ch);
        return true;
      }
    }
    return false;
  }

  static const _fKeys = [
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  ];

  static const _numKeys = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  String? _letterFor(LogicalKeyboardKey key, KeyEvent event) {
    final label = key.keyLabel;
    if (label.length == 1) {
      final code = label.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) return label;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1) {
      final code = ch.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) return ch;
    }
    return null;
  }

  // ── Legacy (one-shot) mode ───────────────────────────────────────

  void _runLegacy() {
    final cmd = _input.text.trim();
    if (cmd.isEmpty) return;
    if (term.isRunning.value) {
      term.sendInput(cmd);
      _input.clear();
      return;
    }
    if (term.persistentMode.value) {
      if (term.isPty) {
        term.writeRaw('$cmd\r');
        _input.clear();
        _histIndex = -1;
        _focusKeyboard();
        return;
      }
      _submitToShell(cmd);
      return;
    }
    final verdict = SandboxService.classifyCommand(cmd);
    if (verdict.risk == CommandRisk.high) {
      _confirmRun(cmd);
      return;
    }
    _launchLegacy(cmd);
  }

  /// Send a line to the persistent shell and handle the sandbox verdict.
  SubmitVerdict _submitToShell(String cmd, {bool confirmed = false}) {
    final verdict = term.submitCommand(cmd, confirmed: confirmed);
    switch (verdict) {
      case SubmitVerdict.sent:
        _input.clear();
        _histIndex = -1;
      case SubmitVerdict.blocked:
        _toast('Blocked by sandbox safety.');
      case SubmitVerdict.needsConfirm:
        _confirmRun(cmd);
      case SubmitVerdict.empty:
      case SubmitVerdict.fallback:
        break;
    }
    return verdict;
  }

  void _launchLegacy(String cmd) {
    _input.clear();
    _histIndex = -1;
    term.runCommand(cmd);
  }

  void _confirmRun(String cmd) {
    final preview = cmd.length > 300 ? '${cmd.substring(0, 300)}…' : cmd;
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Run this command?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                preview,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'High-risk commands always ask first. Catastrophic ones stay blocked.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5, color: const Color(0xFF9AA0A6)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFCF6679)),
            onPressed: () {
              Get.back();
              if (term.persistentMode.value) {
                final verdict = _submitToShell(cmd, confirmed: true);
                if (verdict == SubmitVerdict.fallback) _launchLegacy(cmd);
              } else {
                _launchLegacy(cmd);
              }
            },
            child: const Text('Run'),
          ),
        ],
      ),
      name: 'terminal-confirm-run',
    );
  }

  void _walkHistory(bool older) {
    final h = term.history;
    if (h.isEmpty) return;
    if (older) {
      if (_histIndex < h.length - 1) _histIndex++;
    } else {
      if (_histIndex > 0) {
        _histIndex--;
      } else {
        _histIndex = -1;
        _input.clear();
        return;
      }
    }
    if (_histIndex >= 0) {
      _input.text = h[_histIndex];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  void _runQuick(String cmd) {
    Navigator.of(context).maybePop();
    if (term.isPty) {
      term.writeRaw('$cmd\r');
      _focusKeyboard();
    } else if (term.persistentMode.value) {
      final verdict = _submitToShell(cmd);
      if (verdict == SubmitVerdict.fallback) _launchLegacy(cmd);
    } else {
      _input.text = cmd;
      _runLegacy();
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.background,
      drawer: _sessionsDrawer(theme),
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleSpacing: 0,
        title: Obx(() {
          final title = term.shellTitle.value;
          return Row(
            children: [
              Icon(Icons.terminal_rounded, size: 18, color: theme.colors[2]),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title.isEmpty ? 'Terminal' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (term.persistentMode.value)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: theme.colors[2],
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          );
        }),
        actions: [
          IconButton(
            tooltip: 'Find',
            icon: const Icon(Icons.search_rounded, size: 20),
            onPressed: () => _consoleKey.currentState?.openSearch(),
          ),
          IconButton(
            tooltip: 'Appearance',
            icon: const Icon(Icons.palette_outlined, size: 20),
            onPressed: () => _openSettings(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _export();
                case 'clear':
                  term.clear();
                case 'copy':
                  unawaited(_copyScreen());
                case 'restart':
                  unawaited(_restartShell());
                case 'stop':
                  unawaited(term.disablePersistentShell(keepScreen: true));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'export', child: Text('Export transcript')),
              const PopupMenuItem(value: 'copy', child: Text('Copy screen')),
              const PopupMenuItem(
                  value: 'clear', child: Text('Clear terminal')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'restart', child: Text('Restart shell')),
              const PopupMenuItem(value: 'stop', child: Text('Stop shell')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Obx(() {
          final emu = term.emulator;
          final running = term.persistentMode.value;
          return Column(
            children: [
              _statusBar(theme),
              if (term.previewUrl.value != null &&
                  term.previewUrl.value!.isNotEmpty)
                _previewChip(theme, term.previewUrl.value!),
              Expanded(
                child: _startingShell && emu == null
                    ? _startingView(theme)
                    : emu != null
                        ? TerminalConsole(
                            key: _consoleKey,
                            emulator: emu,
                            palette: theme,
                            fontSize: _fontSize,
                            cursorStyle: emu.cursorStyle,
                            showCursor: running,
                            onResize: _resizeTerminal,
                            onCopied: (text) =>
                                _toast('Copied ${text.length} characters'),
                            onTap: _focusKeyboard,
                            onLinkTap: (url) => unawaited(_openLink(url)),
                          )
                        : _legacyConsole(theme),
              ),
              if (emu != null && !running) _endedBar(theme),
              if (emu != null && !term.isPty && running) _pipeInputBar(theme),
              if (emu == null) _legacyInputBar(theme),
              if (emu != null && term.isPty) _extraKeys(theme),
              _hiddenInput(),
            ],
          );
        }),
      ),
    );
  }

  Widget _statusBar(TerminalPalette theme) {
    return Obx(() {
      final label = term.sessionBackendLabel.value;
      final emu = term.emulator;
      final alive = term.persistentMode.value;
      final backend = label.isEmpty
          ? (_startingShell ? 'starting shell…' : 'one-shot mode')
          : label;
      final size = emu == null ? '' : '${emu.cols}×${emu.rows}';
      final cwd = term.workingDir.value;
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF050505),
          border: Border(bottom: BorderSide(color: Color(0xFF171717))),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: alive ? theme.colors[2] : const Color(0xFF6E7681),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                backend,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(
                    fontSize: 10, color: const Color(0xFF9AA0A6)),
              ),
            ),
            if (cwd.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Text('·',
                  style: TextStyle(color: Color(0xFF444444), fontSize: 10)),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  compactPromptPath(cwd),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaCode(
                      fontSize: 10, color: const Color(0xFF6E7681)),
                ),
              ),
            ],
            const Spacer(),
            if (size.isNotEmpty)
              Text(
                size,
                style: GoogleFonts.firaCode(
                    fontSize: 10, color: const Color(0xFF6E7681)),
              ),
          ],
        ),
      );
    });
  }

  Widget _startingView(TerminalPalette theme) {
    return ColoredBox(
      color: theme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: theme.colors[2],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Starting shell…',
              style:
                  GoogleFonts.firaCode(fontSize: 12, color: theme.foreground),
            ),
            const SizedBox(height: 4),
            Text(
              'PRoot Ubuntu · PTY',
              style: GoogleFonts.firaCode(
                  fontSize: 10.5, color: const Color(0xFF6E7681)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _endedBar(TerminalPalette theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1A0E0E),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: theme.colors[1]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _shellError.isEmpty ? 'Shell ended.' : _shellError,
              style: GoogleFonts.firaCode(
                  fontSize: 10.5, color: const Color(0xFFE6B0B0)),
            ),
          ),
          TextButton(
            onPressed: _restartShell,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Restart',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: theme.colors[2],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewChip(TerminalPalette theme, String url) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colors[2].withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.colors[2].withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.language_rounded, size: 14, color: theme.colors[2]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.firaCode(fontSize: 11, color: theme.colors[2]),
            ),
          ),
          GestureDetector(
            onTap: () async {
              try {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            child: Text(
              'Open',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: theme.colors[2],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close_rounded, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => term.previewUrl.value = null,
          ),
        ],
      ),
    );
  }

  // ── Extra keys ───────────────────────────────────────────────────

  Widget _extraKeys(TerminalPalette theme) {
    final keys = <Widget>[
      _key(theme, 'ESC', () => _sendSpecial('esc')),
      _key(theme, 'TAB', () => _sendSpecial('tab')),
      _key(theme, 'CTRL', () {
        setState(() {
          _ctrlArmed = !_ctrlArmed;
          if (_ctrlArmed) {
            _altArmed = false;
            _shiftArmed = false;
          }
        });
      }, active: _ctrlArmed),
      _key(theme, 'ALT', () {
        setState(() {
          _altArmed = !_altArmed;
          if (_altArmed) {
            _ctrlArmed = false;
            _shiftArmed = false;
          }
        });
      }, active: _altArmed),
      _key(theme, 'SHIFT', () {
        setState(() {
          _shiftArmed = !_shiftArmed;
          if (_shiftArmed) {
            _ctrlArmed = false;
            _altArmed = false;
          }
        });
      }, active: _shiftArmed),
      _key(theme, '^C', () => _sendSpecial('ctrl-c')),
      _key(theme, '↑', () => _sendSpecial('up')),
      _key(theme, '↓', () => _sendSpecial('down')),
      _key(theme, '←', () => _sendSpecial('left')),
      _key(theme, '→', () => _sendSpecial('right')),
      _key(theme, 'HOME', () => _sendSpecial('home')),
      _key(theme, 'END', () => _sendSpecial('end')),
      _key(theme, 'PGUP', () => _sendSpecial('pgup')),
      _key(theme, 'PGDN', () => _sendSpecial('pgdn')),
      _key(theme, 'INS', () => _sendSpecial('insert')),
      _key(theme, 'DEL', () => _sendSpecial('delete')),
      for (var n = 1; n <= 4; n++)
        _key(theme, 'F$n', () => _sendSpecial('f$n')),
      _key(theme, '⌫', () => _sendSpecial('backspace')),
      _key(theme, '⏎', () => _sendSpecial('enter')),
      for (final ch in const [
        '|',
        '~',
        '/',
        '-',
        '_',
        ':',
        ';',
        '&',
        '*',
        r'$',
        '#',
        '"',
        "'",
        '(',
        ')',
        '<',
        '>',
        '=',
        '+',
        '!',
        '?',
        r'\',
        '@',
        '%',
        '^',
        ',',
        '.',
      ])
        _key(theme, ch, () => _sendChar(ch)),
      _key(theme, 'PASTE', () => unawaited(_paste())),
      _key(theme, '⌨', () {
        if (_rawFocus.hasFocus) {
          _rawFocus.unfocus();
        } else {
          _rawFocus.requestFocus();
        }
        setState(() {});
      }, active: _rawFocus.hasFocus),
    ];
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF080808),
        border: Border(top: BorderSide(color: Color(0xFF1B1B1B))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(children: keys),
      ),
    );
  }

  Widget _key(
    TerminalPalette theme,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 34),
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? theme.colors[2].withValues(alpha: 0.18)
              : const Color(0xFF151515),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? theme.colors[2] : const Color(0xFF2A2A2A),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.firaCode(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? theme.colors[2] : const Color(0xFFD6D6D6),
          ),
        ),
      ),
    );
  }

  Widget _hiddenInput() {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: TextField(
          controller: _raw,
          focusNode: _rawFocus,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          maxLines: 1,
          showCursor: false,
          style: const TextStyle(color: Colors.transparent, fontSize: 1),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _onRawChanged,
          onSubmitted: _onRawSubmitted,
        ),
      ),
    );
  }

  // ── Pipe / legacy input ──────────────────────────────────────────

  Widget _pipeInputBar(TerminalPalette theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF080808),
        border: Border(top: BorderSide(color: Color(0xFF1B1B1B))),
      ),
      child: Row(
        children: [
          Text(
            '\$ ',
            style: GoogleFonts.firaCode(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colors[2],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              style:
                  GoogleFonts.firaCode(fontSize: 13, color: theme.foreground),
              cursorColor: theme.cursor,
              decoration: const InputDecoration(
                hintText: 'command…',
                hintStyle: TextStyle(color: Color(0xFF5A5A5A)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (_) => _runLegacy(),
            ),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded, size: 18),
            onPressed: () => _walkHistory(true),
          ),
          IconButton(
            tooltip: 'Run',
            icon: Icon(Icons.play_arrow_rounded, color: theme.colors[2]),
            onPressed: _runLegacy,
          ),
        ],
      ),
    );
  }

  Widget _legacyInputBar(TerminalPalette theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF080808),
        border: Border(top: BorderSide(color: Color(0xFF1B1B1B))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shellError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13, color: theme.colors[3]),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _shellError,
                      style: GoogleFonts.firaCode(
                          fontSize: 10, color: const Color(0xFFB0A070)),
                    ),
                  ),
                  TextButton(
                    onPressed: _restartShell,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Retry',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: theme.colors[2],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Obx(() {
                final cwd = term.workingDir.value;
                final short = cwd.isEmpty ? '~' : compactPromptPath(cwd);
                return Flexible(
                  child: Text(
                    '\$ $short ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.firaCode(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: theme.colors[2],
                    ),
                  ),
                );
              }),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  style: GoogleFonts.firaCode(
                      fontSize: 13, color: theme.foreground),
                  cursorColor: theme.cursor,
                  decoration: const InputDecoration(
                    hintText: 'command…',
                    hintStyle: TextStyle(color: Color(0xFF5A5A5A)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _runLegacy(),
                ),
              ),
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history_rounded, size: 18),
                onPressed: () => _walkHistory(true),
              ),
              Obx(() => term.isRunning.value
                  ? IconButton(
                      tooltip: 'Kill',
                      icon: Icon(Icons.stop_rounded, color: theme.colors[1]),
                      onPressed: term.kill,
                    )
                  : IconButton(
                      tooltip: 'Run',
                      icon: Icon(Icons.play_arrow_rounded,
                          color: theme.colors[2]),
                      onPressed: _runLegacy,
                    )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legacyConsole(TerminalPalette theme) {
    return Container(
      color: theme.background,
      child: Obx(() {
        if (term.lines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'CubicLM Terminal ready.\nType a shell command below.',
              style: GoogleFonts.firaCode(
                fontSize: 12,
                height: 1.5,
                color: const Color(0xFF6E7681),
              ),
            ),
          );
        }
        return ListView.builder(
          controller: _legacyScroll,
          padding: const EdgeInsets.all(12),
          itemCount: term.lines.length,
          itemBuilder: (context, i) {
            final line = term.lines[i];
            return SelectableText(
              line.text.isEmpty ? ' ' : line.text,
              style: GoogleFonts.firaCode(
                fontSize: _fontSize,
                height: 1.45,
                fontWeight:
                    line.isCommand ? FontWeight.bold : FontWeight.normal,
                color: line.isCommand
                    ? theme.colors[2]
                    : line.isError
                        ? theme.colors[1]
                        : theme.foreground,
              ),
            );
          },
        );
      }),
    );
  }

  // ── Drawer ───────────────────────────────────────────────────────

  Widget _sessionsDrawer(TerminalPalette theme) {
    final hasWs = Get.isRegistered<AgentWorkspaceService>();
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Obx(() {
          final projects = hasWs
              ? Get.find<AgentWorkspaceService>().projects.toList()
              : const [];
          final active = term.activeSessionId.value;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded,
                        color: theme.colors[2], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Terminal',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  term.sessionBackendLabel.value.isEmpty
                      ? 'One-shot mode'
                      : term.sessionBackendLabel.value,
                  style: GoogleFonts.firaCode(
                      fontSize: 10.5, color: const Color(0xFF6E7681)),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFF1C1C1C)),
              _sectionLabel('Sessions'),
              _sessionTile(
                theme,
                id: TerminalService.defaultSessionId,
                name: 'Default shell',
                subtitle: 'App workspace',
                active: active == TerminalService.defaultSessionId,
              ),
              for (final p in projects)
                _sessionTile(
                  theme,
                  id: p.id,
                  name: p.name,
                  subtitle: p.framework,
                  active: active == p.id,
                ),
              const Divider(height: 1, color: Color(0xFF1C1C1C)),
              _sectionLabel('Quick commands'),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cmd in _quickCommands)
                      GestureDetector(
                        onTap: () => _runQuick(cmd),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: const Color(0xFF262626)),
                          ),
                          child: Text(
                            cmd,
                            style: GoogleFonts.firaCode(
                              fontSize: 10.5,
                              color: const Color(0xFFC8C8C8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1C1C1C)),
              ListTile(
                dense: true,
                leading: Icon(Icons.palette_outlined,
                    size: 19, color: theme.colors[2]),
                title: Text('Appearance',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                subtitle: Text(
                  '${theme.name} · ${_fontSize.toStringAsFixed(1)}pt',
                  style: GoogleFonts.firaCode(
                      fontSize: 10, color: const Color(0xFF6E7681)),
                ),
                onTap: () {
                  Navigator.of(context).maybePop();
                  _openSettings();
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.restart_alt_rounded,
                    size: 19, color: Color(0xFF9AA0A6)),
                title: Text('Restart shell',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                onTap: () {
                  Navigator.of(context).maybePop();
                  unawaited(_restartShell());
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.save_alt_rounded,
                    size: 19, color: Color(0xFF9AA0A6)),
                title: Text('Export transcript',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                onTap: () {
                  Navigator.of(context).maybePop();
                  _export();
                },
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Long-press the console to select and copy. '
                  'CTRL/ALT stay armed for one key.',
                  style: GoogleFonts.firaCode(
                      fontSize: 9.5, color: const Color(0xFF4A4A4A)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        }),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: const Color(0xFF6E7681),
        ),
      ),
    );
  }

  Widget _sessionTile(
    TerminalPalette theme, {
    required String id,
    required String name,
    required String subtitle,
    required bool active,
  }) {
    return ListTile(
      dense: true,
      selected: active,
      selectedTileColor: theme.colors[2].withValues(alpha: 0.08),
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 17,
        color: active ? theme.colors[2] : const Color(0xFF5A5A5A),
      ),
      title: Text(
        name,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? Colors.white : const Color(0xFFC8C8C8),
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.firaCode(
                  fontSize: 9.5, color: const Color(0xFF5A5A5A)),
            ),
      onTap: () => _switchSession(id),
    );
  }

  // ── Appearance sheet ─────────────────────────────────────────────

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C0C0C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final theme = _theme;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Terminal appearance',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Termux is the exact default palette. All themes keep a pure-black console.',
                    style: GoogleFonts.firaCode(
                        fontSize: 10, color: const Color(0xFF6E7681)),
                  ),
                  const SizedBox(height: 16),
                  Text('Palette',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC8C8C8))),
                  const SizedBox(height: 8),
                  for (final t in TerminalTheme.all)
                    _themeRow(t, theme, setSheet),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Font size',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFC8C8C8))),
                      const Spacer(),
                      Text('${_fontSize.toStringAsFixed(1)} pt',
                          style: GoogleFonts.firaCode(
                              fontSize: 11, color: _accent)),
                    ],
                  ),
                  Slider(
                    value: _fontSize,
                    min: 9,
                    max: 22,
                    divisions: 26,
                    activeColor: _accent,
                    onChanged: (v) {
                      setState(() => _fontSize = v);
                      _hive?.setSetting('terminal_font_size', v);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  Text('Cursor',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC8C8C8))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in const {
                        TerminalCursorStyle.block: 'Block',
                        TerminalCursorStyle.underline: 'Underline',
                        TerminalCursorStyle.bar: 'Bar',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _cursorStyle == entry.key,
                          selectedColor: _accent.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: _cursorStyle == entry.key
                                ? _accent
                                : const Color(0xFF2A2A2A),
                          ),
                          backgroundColor: const Color(0xFF141414),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: _cursorStyle == entry.key
                                ? _accent
                                : const Color(0xFFC8C8C8),
                          ),
                          onSelected: (_) {
                            setState(() => _cursorStyle = entry.key);
                            term.emulator?.setCursorStyle(entry.key);
                            _hive?.setSetting(
                                'terminal_cursor', entry.key.name);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Scrollback',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFC8C8C8))),
                      const Spacer(),
                      Text('$_scrollback lines',
                          style: GoogleFonts.firaCode(
                              fontSize: 11, color: _accent)),
                    ],
                  ),
                  Slider(
                    value: _scrollback.toDouble(),
                    min: 1000,
                    max: 20000,
                    divisions: 19,
                    activeColor: _accent,
                    onChanged: (v) {
                      final n = (v / 1000).round() * 1000;
                      setState(() => _scrollback = n);
                      term.emulator?.maxScrollback = n;
                      _hive?.setSetting('terminal_scrollback', n);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _themeId = 'termux';
                        _fontSize = 12.5;
                        _cursorStyle = TerminalCursorStyle.block;
                        _scrollback = 5000;
                      });
                      term.emulator?.maxScrollback = 5000;
                      term.emulator?.setCursorStyle(TerminalCursorStyle.block);
                      _palette.setBase(TerminalTheme.termux);
                      _hive?.setSetting('terminal_theme', 'termux');
                      _hive?.setSetting('terminal_font_size', 12.5);
                      _hive?.setSetting('terminal_cursor', 'block');
                      _hive?.setSetting('terminal_scrollback', 5000);
                      setSheet(() {});
                    },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Reset to Termux defaults'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _themeRow(
      TerminalTheme t, TerminalPalette active, StateSetter setSheet) {
    final selected = t.id == active.id;
    return GestureDetector(
      onTap: () {
        setState(() => _themeId = t.id);
        _palette.setBase(t);
        _hive?.setSetting('terminal_theme', t.id);
        setSheet(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? t.colors[2].withValues(alpha: 0.1)
              : const Color(0xFF131313),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? t.colors[2] : const Color(0xFF242424),
          ),
        ),
        child: Row(
          children: [
            // 16-color strip.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Row(
                children: [
                  for (final c in t.colors)
                    Container(width: 9, height: 16, color: c),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFFC8C8C8),
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 16, color: t.colors[2]),
          ],
        ),
      ),
    );
  }

  void _export() {
    final text = term.exportTranscript();
    Clipboard.setData(ClipboardData(text: text));
    _toast('Transcript copied to clipboard');
  }

  static const _quickCommands = [
    'uname -a',
    'ls -la',
    'pwd',
    'whoami',
    'node -v',
    'python3 --version',
    'df -h',
    'free -m',
  ];
}
