part of 'terminal_emulator.dart';

// Abstract screen primitives are implemented by TerminalEmulator in the
// main library file; the analyzer sees the declarations here as unused.
// ignore_for_file: unused_element

/// VT100/xterm escape-sequence parser. Mixed into [TerminalEmulator].
///
/// The mixin is declared `on ChangeNotifier` (not on the emulator itself,
/// which would be a circular superinterface) and requires the screen
/// primitives below. They are private, but both files are `part` of the
/// same library, so the implementations in `terminal_emulator.dart`
/// satisfy them directly.
mixin TerminalParser on ChangeNotifier {
  // Screen state supplied by the emulator.
  int get _cols;
  int get _rows;
  int get _cursorRow;
  set _cursorRow(int value);
  int get _cursorCol;
  set _cursorCol(int value);
  bool get _wrapPending;
  set _wrapPending(bool value);
  TerminalStyle get _style;
  set _style(TerminalStyle value);
  int get _scrollTop;
  set _scrollTop(int value);
  int get _scrollBottom;
  set _scrollBottom(int value);
  bool get _originMode;
  set _originMode(bool value);
  bool get _autowrap;
  set _autowrap(bool value);
  bool get _insertMode;
  set _insertMode(bool value);
  bool get _newlineMode;
  set _newlineMode(bool value);
  bool get _cursorVisible;
  set _cursorVisible(bool value);
  bool get _cursorBlink;
  set _cursorBlink(bool value);
  TerminalCursorStyle get _cursorStyle;
  set _cursorStyle(TerminalCursorStyle value);
  bool get _applicationCursorKeys;
  set _applicationCursorKeys(bool value);
  bool get _bracketedPaste;
  set _bracketedPaste(bool value);
  bool get _inAltScreen;
  int get _lastRune;
  set _lastRune(int value);
  String get _title;

  // Hooks wired by the owner.
  void Function(String data)? get onResponse;
  void Function(String title)? get onTitle;
  void Function()? get onBell;
  void Function(String text)? get onClipboard;
  TerminalPalette? get palette;

  // DECSET modes and OSC 8 are owned by the emulator.
  void _setDecsetMode(int mode, bool on);
  void _setLink(String? uri);

  // Screen primitives implemented by the emulator.
  void _writeRune(int rune);
  void _lineFeed();
  void _reverseIndex();
  void _carriageReturn();
  void _backspace();
  void _tabForward(int n);
  void _tabBackward(int n);
  void _scrollUp(int n);
  void _scrollDown(int n);
  void _eraseInLine(int mode);
  void _eraseInDisplay(int mode);
  void _eraseChars(int n);
  void _insertCells(int n);
  void _deleteCells(int n);
  void _insertLines(int n);
  void _deleteLines(int n);
  void _setCursor(int row, int col);
  void _moveCursor(int dRow, int dCol);
  void _saveCursor();
  void _restoreCursor();
  void _enterAltScreen({required bool clear});
  void _exitAltScreen();
  void _setScrollRegion(int top, int bottom);
  void _setTitle(String value);
  void clear();

  _ParserState _state = _ParserState.ground;
  final StringBuffer _csiParams = StringBuffer();
  final StringBuffer _csiIntermediates = StringBuffer();
  final StringBuffer _osc = StringBuffer();
  String _carry = '';
  bool _oscSawEsc = false;
  bool _dcsSawEsc = false;
  bool _charsetG1 = false;
  bool _decGraphics = false;

  /// Feed raw shell output (UTF-8 decoded) into the screen.
  void feed(String data) {
    if (data.isEmpty) return;
    var input = _carry + data;
    _carry = '';
    if (input.isNotEmpty) {
      final last = input.codeUnitAt(input.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        _carry = input.substring(input.length - 1);
        input = input.substring(0, input.length - 1);
      }
    }
    for (final rune in input.runes) {
      _consume(rune);
    }
    notifyListeners();
  }

  void _consume(int rune) {
    switch (_state) {
      case _ParserState.ground:
        _ground(rune);
      case _ParserState.escape:
        _escape(rune);
      case _ParserState.csi:
        _csi(rune);
      case _ParserState.osc:
        _oscChar(rune);
      case _ParserState.dcs:
        _dcsChar(rune);
      case _ParserState.charsetG0:
        _decGraphics = rune == 0x30; // '0' = DEC special graphics
        _state = _ParserState.ground;
      case _ParserState.charsetG1:
        _charsetG1 = rune == 0x30;
        _state = _ParserState.ground;
      case _ParserState.escapeHash:
        _state = _ParserState.ground;
    }
  }

  void _ground(int rune) {
    if (rune == 0x1B) {
      _state = _ParserState.escape;
      return;
    }
    if (rune == 0x9B) {
      _startCsi();
      return;
    }
    if (rune == 0x9D) {
      _osc.clear();
      _oscSawEsc = false;
      _state = _ParserState.osc;
      return;
    }
    switch (rune) {
      case 0x0A:
        _lineFeed();
        return;
      case 0x0D:
        _carriageReturn();
        return;
      case 0x08:
        _backspace();
        return;
      case 0x09:
        _tabForward(1);
        return;
      case 0x07:
        onBell?.call();
        return;
      case 0x0E:
        // SO — shift out (G1). We only track the DEC graphics flag.
        _decGraphics = _charsetG1;
        return;
      case 0x0F:
        // SI — shift in (G0).
        _decGraphics = false;
        return;
    }
    if (rune < 0x20 || rune == 0x7F) return;
    final glyph = _decGraphics ? _decGraphic(rune) : String.fromCharCode(rune);
    for (final r in glyph.runes) {
      _writeRune(r);
    }
  }

  void _escape(int rune) {
    _state = _ParserState.ground;
    switch (rune) {
      case 0x5B: // [
        _startCsi();
      case 0x5D: // ]
        _osc.clear();
        _oscSawEsc = false;
        _state = _ParserState.osc;
      case 0x50: // P — DCS, ignored
        _dcsSawEsc = false;
        _state = _ParserState.dcs;
      case 0x28: // (
        _state = _ParserState.charsetG0;
      case 0x29: // )
        _state = _ParserState.charsetG1;
      case 0x23: // #
        _state = _ParserState.escapeHash;
      case 0x37: // 7
        _saveCursor();
      case 0x38: // 8
        _restoreCursor();
      case 0x44: // D — index
        _lineFeed();
      case 0x45: // E — next line
        _carriageReturn();
        _lineFeed();
      case 0x4D: // M — reverse index
        _reverseIndex();
      case 0x63: // c — RIS
        clear();
      case 0x48: // H — set tab stop (fixed stops; ignore)
      case 0x3D: // =
      case 0x3E: // >
      case 0x5C: // ST
        break;
    }
  }

  void _startCsi() {
    _csiParams.clear();
    _csiIntermediates.clear();
    _state = _ParserState.csi;
  }

  void _csi(int rune) {
    if (rune == 0x1B) {
      _state = _ParserState.escape;
      return;
    }
    if (rune >= 0x30 && rune <= 0x3F) {
      if (_csiParams.length < 512) _csiParams.writeCharCode(rune);
      return;
    }
    if (rune >= 0x20 && rune <= 0x2F) {
      if (_csiIntermediates.length < 32) {
        _csiIntermediates.writeCharCode(rune);
      }
      return;
    }
    if (rune >= 0x40 && rune <= 0x7E) {
      _dispatchCsi(
        _csiParams.toString(),
        _csiIntermediates.toString(),
        String.fromCharCode(rune),
      );
      _state = _ParserState.ground;
    }
  }

  void _oscChar(int rune) {
    if (rune == 0x07) {
      _dispatchOsc(_osc.toString());
      _state = _ParserState.ground;
      return;
    }
    if (rune == 0x1B) {
      _oscSawEsc = true;
      return;
    }
    if (_oscSawEsc) {
      _oscSawEsc = false;
      if (rune == 0x5C) {
        _dispatchOsc(_osc.toString());
        _state = _ParserState.ground;
        return;
      }
      _state = _ParserState.ground;
      return;
    }
    if (_osc.length < 8192) _osc.writeCharCode(rune);
  }

  void _dcsChar(int rune) {
    if (rune == 0x07) {
      _state = _ParserState.ground;
      return;
    }
    if (rune == 0x1B) {
      _dcsSawEsc = true;
      return;
    }
    if (_dcsSawEsc) {
      _dcsSawEsc = false;
      if (rune == 0x5C) _state = _ParserState.ground;
    }
  }

  void _dispatchOsc(String data) {
    if (data.isEmpty) return;
    final semi = data.indexOf(';');
    final cmd = semi < 0 ? data : data.substring(0, semi);
    final rest = semi < 0 ? '' : data.substring(semi + 1);
    switch (cmd) {
      case '0':
      case '2':
        _setTitle(rest);
      case '4':
        _oscPalette(rest);
      case '8':
        // OSC 8 hyperlinks: `8;params;URI`, empty URI closes the link.
        final parts = rest.split(';');
        final uri = parts.isEmpty ? '' : parts.last;
        _setLink(uri.isEmpty ? null : uri);
      case '10':
      case '11':
      case '12':
        _oscSpecial(int.parse(cmd), rest);
      case '52':
        // OSC 52 clipboard writes are opt-in only.
        if (onClipboard != null) {
          final parts = rest.split(';');
          if (parts.length >= 2 && parts[1].isNotEmpty) {
            try {
              onClipboard?.call(utf8.decode(base64.decode(parts[1])));
            } catch (_) {}
          }
        }
      case '104':
        _oscReset(rest);
      case '110':
      case '111':
      case '112':
        palette?.reset(TerminalPalette.foregroundIndex + int.parse(cmd) - 110);
      case '119':
        break; // reset highlight color (not used)
    }
  }

  /// OSC 4: `4;<index>;<color>;…`. A `?` color asks for the current
  /// value, answered in xterm's `rgb:` form.
  void _oscPalette(String rest) {
    final parts = rest.split(';');
    for (var i = 0; i + 1 < parts.length; i += 2) {
      final index = int.tryParse(parts[i]);
      if (index == null || index < 0 || index > 255) continue;
      final spec = parts[i + 1];
      if (spec == '?') {
        onResponse?.call('\x1b]4;$index;'
            '${palette?.reportColor(index) ?? 'rgb:0000/0000/0000'}\x07');
      } else {
        final color = TerminalPalette.parseColor(spec);
        if (color != null) palette?.set(index, color);
      }
    }
  }

  /// OSC 10/11/12: set or query foreground / background / cursor.
  /// Multiple `;`-separated specs walk fg → bg → cursor.
  void _oscSpecial(int value, String rest) {
    final specs = rest.isEmpty ? const [''] : rest.split(';');
    for (var i = 0; i < specs.length; i++) {
      final index = TerminalPalette.foregroundIndex + (value - 10) + i;
      if (index > TerminalPalette.cursorIndex) break;
      final spec = specs[i];
      if (spec == '?') {
        onResponse?.call('\x1b]${value + i};'
            '${palette?.reportColor(index) ?? 'rgb:0000/0000/0000'}\x07');
      } else {
        final color = TerminalPalette.parseColor(spec);
        if (color != null) palette?.set(index, color);
      }
    }
  }

  /// OSC 104: reset indexed colors (all of them when no parameter).
  void _oscReset(String rest) {
    if (rest.trim().isEmpty) {
      palette?.resetAll();
      return;
    }
    for (final part in rest.split(';')) {
      final index = int.tryParse(part);
      if (index != null) palette?.reset(index);
    }
  }

  void _dispatchCsi(String params, String intermediates, String finalByte) {
    if (finalByte == 'm') {
      _applySgr(params);
      return;
    }
    if (finalByte == 'q' && intermediates == ' ') {
      _applyCursorStyle(params);
      return;
    }

    final private = params.startsWith('?');
    final body = (private ||
            params.startsWith('>') ||
            params.startsWith('<') ||
            params.startsWith('='))
        ? params.substring(1)
        : params;

    final nums = <int>[];
    if (body.isNotEmpty) {
      for (final part in body.split(';')) {
        nums.add(int.tryParse(part.split(':').first) ?? 0);
      }
    }
    int p(int i, [int def = 0]) =>
        i < nums.length && nums[i] != 0 ? nums[i] : def;
    int p1(int i) => i < nums.length && nums[i] > 0 ? nums[i] : 1;

    switch (finalByte) {
      case 'A':
        _moveCursor(-p1(0), 0);
      case 'B':
        _moveCursor(p1(0), 0);
      case 'C':
        _moveCursor(0, p1(0));
      case 'D':
        _moveCursor(0, -p1(0));
      case 'E':
        _moveCursor(p1(0), 0);
        _carriageReturn();
      case 'F':
        _moveCursor(-p1(0), 0);
        _carriageReturn();
      case 'G':
      case '`':
        _cursorCol = (p1(0) - 1).clamp(0, _cols - 1);
        _wrapPending = false;
      case 'H':
      case 'f':
        _setCursor(p1(0) - 1, p1(1) - 1);
      case 'd':
        _setCursor(p1(0) - 1, _cursorCol);
      case 'e':
        _moveCursor(p1(0), 0);
      case 'a':
        _moveCursor(0, p1(0));
      case 'I':
        _tabForward(p1(0));
      case 'Z':
        _tabBackward(p1(0));
      case 'J':
        _eraseInDisplay(p(0, 0));
      case 'K':
        _eraseInLine(p(0, 0));
      case 'L':
        _insertLines(p1(0));
      case 'M':
        _deleteLines(p1(0));
      case 'P':
        _deleteCells(p1(0));
      case '@':
        _insertCells(p1(0));
      case 'X':
        _eraseChars(p1(0));
      case 'S':
        _scrollUp(p1(0));
      case 'T':
        _scrollDown(p1(0));
      case 'b':
        if (_lastRune != 0) {
          for (var i = 0; i < p1(0); i++) {
            _writeRune(_lastRune);
          }
        }
      case 'g':
        break; // tab stops are fixed every 8 columns
      case 'h':
        private ? _setPrivateModes(nums, true) : _setModes(nums, true);
      case 'l':
        private ? _setPrivateModes(nums, false) : _setModes(nums, false);
      case 'n':
        final which = p(0, 0);
        if (which == 6) {
          // `CSI ? 6 n` is DECXCPR (page number included).
          if (private) {
            onResponse?.call('\x1b[?${_cursorRow + 1};${_cursorCol + 1};1R');
          } else {
            onResponse?.call('\x1b[${_cursorRow + 1};${_cursorCol + 1}R');
          }
        } else if (which == 5) {
          onResponse?.call('\x1b[0n');
        }
      case 'c':
        if (params.startsWith('>')) {
          // Secondary DA — exact Termux answer.
          onResponse?.call('\x1b[>41;320;0c');
        } else if (p(0, 0) == 0) {
          // Primary DA — exact Termux answer (vt420 + xterm attributes).
          onResponse?.call('\x1b[?64;1;2;4;6;9;15;18;21;22c');
        }
      case 'r':
        _setScrollRegion(p1(0) - 1, p(1, _rows) - 1);
      case 's':
        _saveCursor();
      case 'u':
        _restoreCursor();
      case 't':
        final op = p(0, 0);
        if (op == 18) {
          onResponse?.call('\x1b[8;$_rows;${_cols}t');
        } else if (op == 19) {
          onResponse?.call('\x1b[9;$_rows;${_cols}t');
        }
      case 'q':
        if (intermediates == ' ') _applyCursorStyle(params);
    }
  }

  void _setPrivateModes(List<int> modes, bool on) {
    for (final mode in modes) {
      _setDecsetMode(mode, on);
    }
  }

  void _setModes(List<int> modes, bool on) {
    for (final mode in modes) {
      switch (mode) {
        case 4:
          _insertMode = on;
        case 20:
          _newlineMode = on;
      }
    }
  }

  void _applyCursorStyle(String params) {
    final n = int.tryParse(params.trim()) ?? 0;
    switch (n) {
      case 1:
        _cursorStyle = TerminalCursorStyle.block;
        _cursorBlink = true;
      case 2:
        _cursorStyle = TerminalCursorStyle.block;
        _cursorBlink = false;
      case 3:
        _cursorStyle = TerminalCursorStyle.underline;
        _cursorBlink = true;
      case 4:
        _cursorStyle = TerminalCursorStyle.underline;
        _cursorBlink = false;
      case 5:
        _cursorStyle = TerminalCursorStyle.bar;
        _cursorBlink = true;
      case 6:
        _cursorStyle = TerminalCursorStyle.bar;
        _cursorBlink = false;
      default:
        _cursorStyle = TerminalCursorStyle.block;
        _cursorBlink = true;
    }
  }

  void _applySgr(String params) {
    final parts = params.isEmpty ? const ['0'] : params.split(';');
    var i = 0;
    while (i < parts.length) {
      final raw = parts[i];
      final sub = raw.split(':');
      final code = int.tryParse(sub[0]) ?? 0;
      switch (code) {
        case 0:
          _style = TerminalStyle.empty;
        case 1:
          _style = _style.copyWith(bold: true);
        case 2:
          _style = _style.copyWith(faint: true);
        case 3:
          _style = _style.copyWith(italic: true);
        case 4:
          _style = _style.copyWith(
            underline: sub.length < 2 || sub[1] != '0',
          );
        case 5:
          _style = _style.copyWith(blink: true);
        case 7:
          _style = _style.copyWith(reverse: true);
        case 8:
          _style = _style.copyWith(hidden: true);
        case 9:
          _style = _style.copyWith(strikethrough: true);
        case 21:
          _style = _style.copyWith(underline: true);
        case 22:
          _style = _style.copyWith(bold: false, faint: false);
        case 23:
          _style = _style.copyWith(italic: false);
        case 24:
          _style = _style.copyWith(underline: false);
        case 25:
          _style = _style.copyWith(blink: false);
        case 27:
          _style = _style.copyWith(reverse: false);
        case 28:
          _style = _style.copyWith(hidden: false);
        case 29:
          _style = _style.copyWith(strikethrough: false);
        case 39:
          _style = _style.copyWith(fg: -1);
        case 49:
          _style = _style.copyWith(bg: -1);
        case 53:
          _style = _style.copyWith(overline: true);
        case 55:
          _style = _style.copyWith(overline: false);
        case 38:
        case 48:
          final color = _readExtendedColor(parts, sub, i);
          if (color != null) {
            if (code == 38) {
              _style = _style.copyWith(fg: color.color);
            } else {
              _style = _style.copyWith(bg: color.color);
            }
            i += color.consumed;
          }
        default:
          if (code >= 30 && code <= 37) {
            _style = _style.copyWith(fg: code - 30);
          } else if (code >= 90 && code <= 97) {
            _style = _style.copyWith(fg: code - 90 + 8);
          } else if (code >= 40 && code <= 47) {
            _style = _style.copyWith(bg: code - 40);
          } else if (code >= 100 && code <= 107) {
            _style = _style.copyWith(bg: code - 100 + 8);
          }
      }
      i++;
    }
  }

  _ExtendedColor? _readExtendedColor(
    List<String> parts,
    List<String> sub,
    int index,
  ) {
    if (sub.length >= 3) {
      final mode = int.tryParse(sub[1]) ?? 0;
      if (mode == 5) {
        final n = int.tryParse(sub[2]);
        if (n == null) return null;
        return _ExtendedColor(n.clamp(0, 255), 0);
      }
      if (mode == 2) {
        int r;
        int g;
        int b;
        if (sub.length >= 6) {
          r = int.tryParse(sub[3]) ?? 0;
          g = int.tryParse(sub[4]) ?? 0;
          b = int.tryParse(sub[5]) ?? 0;
        } else {
          r = int.tryParse(sub[2]) ?? 0;
          g = int.tryParse(sub[3]) ?? 0;
          b = int.tryParse(sub[4]) ?? 0;
        }
        return _ExtendedColor(_rgb(r, g, b), 0);
      }
      return null;
    }

    if (index + 1 >= parts.length) return null;
    final mode = int.tryParse(parts[index + 1]) ?? 0;
    if (mode == 5 && index + 2 < parts.length) {
      final n = int.tryParse(parts[index + 2]);
      if (n == null) return null;
      return _ExtendedColor(n.clamp(0, 255), 2);
    }
    if (mode == 2 && index + 4 < parts.length) {
      return _ExtendedColor(
        _rgb(
          int.tryParse(parts[index + 2]) ?? 0,
          int.tryParse(parts[index + 3]) ?? 0,
          int.tryParse(parts[index + 4]) ?? 0,
        ),
        4,
      );
    }
    return null;
  }

  static int _rgb(int r, int g, int b) =>
      0x1000000 | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

  /// DEC special graphics (line drawing) used by ncurses/dialog.
  static String _decGraphic(int rune) {
    switch (rune) {
      case 0x60:
        return '◆';
      case 0x61:
        return '▒';
      case 0x62:
        return '␉';
      case 0x63:
        return '␌';
      case 0x64:
        return '␍';
      case 0x65:
        return '␊';
      case 0x66:
        return '°';
      case 0x67:
        return '±';
      case 0x68:
        return '␤';
      case 0x69:
        return '␋';
      case 0x6A:
        return '┘';
      case 0x6B:
        return '┐';
      case 0x6C:
        return '┌';
      case 0x6D:
        return '└';
      case 0x6E:
        return '┼';
      case 0x6F:
        return '⎺';
      case 0x70:
        return '⎻';
      case 0x71:
        return '─';
      case 0x72:
        return '⎼';
      case 0x73:
        return '⎽';
      case 0x74:
        return '├';
      case 0x75:
        return '┤';
      case 0x76:
        return '┴';
      case 0x77:
        return '┬';
      case 0x78:
        return '│';
      case 0x79:
        return '≤';
      case 0x7A:
        return '≥';
      case 0x7B:
        return 'π';
      case 0x7C:
        return '≠';
      case 0x7D:
        return '£';
      case 0x7E:
        return '·';
      default:
        return String.fromCharCode(rune);
    }
  }
}

enum _ParserState {
  ground,
  escape,
  csi,
  osc,
  dcs,
  charsetG0,
  charsetG1,
  escapeHash
}

class _ExtendedColor {
  final int color;
  final int consumed;
  const _ExtendedColor(this.color, this.consumed);
}
