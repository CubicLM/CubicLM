/// A real VT100/xterm screen emulator in pure Dart.
///
/// This is the rendering model behind the Toolkit terminal: a grid of
/// styled cells, a cursor, scrollback, alternate screen, scroll regions,
/// insert/delete operations and the full SGR color system. Output from the
/// shell is fed through [feed]; the view renders [scrollback] + [screen]
/// exactly like Termux renders its native `TerminalBuffer`.
///
/// The escape-sequence parser lives in `terminal_parser.dart` (same
/// library) so this file stays focused on the screen model.
library;

// Screen primitives satisfy the abstract members of TerminalParser; the
// parser file declares them, so overrides here need no annotations.
// ignore_for_file: annotate_overrides

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'terminal_theme.dart';

part 'terminal_parser.dart';

/// One styled terminal cell. [width] is 0 for the second half of a wide
/// character, 1 for normal characters and 2 for CJK/emoji.
class TerminalCell {
  final String text;
  final int width;
  final TerminalStyle style;

  const TerminalCell(
    this.text, {
    this.width = 1,
    this.style = TerminalStyle.empty,
  });

  static const TerminalCell blank = TerminalCell(' ');

  bool get isContinuation => width == 0;
}

/// Cumulative SGR attributes for a cell.
class TerminalStyle {
  /// -1 = default, 0..255 = indexed, 0x1000000 | RGB = 24-bit.
  final int fg;
  final int bg;
  final bool bold;
  final bool faint;
  final bool italic;
  final bool underline;
  final bool blink;
  final bool reverse;
  final bool hidden;
  final bool strikethrough;
  final bool overline;

  /// OSC 8 hyperlink target. `null` outside a hyperlink. Termux does not
  /// support OSC 8; CubicLM renders these links and makes them tappable.
  final String? link;

  const TerminalStyle({
    this.fg = -1,
    this.bg = -1,
    this.bold = false,
    this.faint = false,
    this.italic = false,
    this.underline = false,
    this.blink = false,
    this.reverse = false,
    this.hidden = false,
    this.strikethrough = false,
    this.overline = false,
    this.link,
  });

  static const TerminalStyle empty = TerminalStyle();

  TerminalStyle copyWith({
    int? fg,
    int? bg,
    bool? bold,
    bool? faint,
    bool? italic,
    bool? underline,
    bool? blink,
    bool? reverse,
    bool? hidden,
    bool? strikethrough,
    bool? overline,
    String? link,
    bool clearLink = false,
  }) =>
      TerminalStyle(
        fg: fg ?? this.fg,
        bg: bg ?? this.bg,
        bold: bold ?? this.bold,
        faint: faint ?? this.faint,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        blink: blink ?? this.blink,
        reverse: reverse ?? this.reverse,
        hidden: hidden ?? this.hidden,
        strikethrough: strikethrough ?? this.strikethrough,
        overline: overline ?? this.overline,
        link: clearLink ? null : (link ?? this.link),
      );

  /// Set (or clear, with `null`) the OSC 8 hyperlink while keeping every
  /// other SGR attribute intact.
  TerminalStyle withLink(String? value) => TerminalStyle(
        fg: fg,
        bg: bg,
        bold: bold,
        faint: faint,
        italic: italic,
        underline: underline,
        blink: blink,
        reverse: reverse,
        hidden: hidden,
        strikethrough: strikethrough,
        overline: overline,
        link: value,
      );

  @override
  bool operator ==(Object other) =>
      other is TerminalStyle &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold &&
      other.faint == faint &&
      other.italic == italic &&
      other.underline == underline &&
      other.blink == blink &&
      other.reverse == reverse &&
      other.hidden == hidden &&
      other.strikethrough == strikethrough &&
      other.overline == overline &&
      other.link == link;

  @override
  int get hashCode => Object.hash(fg, bg, bold, faint, italic, underline, blink,
      reverse, hidden, strikethrough, overline, link);
}

/// DECSCUSR cursor shapes.
enum TerminalCursorStyle { block, underline, bar }

/// The screen model. Feed output with [feed]; listen with [ChangeNotifier].
class TerminalEmulator extends ChangeNotifier with TerminalParser {
  TerminalEmulator({int cols = 80, int rows = 24})
      : _cols = cols.clamp(2, 500),
        _rows = rows.clamp(2, 300) {
    _screen = List.generate(_rows, (_) => _blankRow(_cols));
    _scrollBottom = _rows - 1;
  }

  int _cols;
  int _rows;
  late List<List<TerminalCell>> _screen;
  final List<List<TerminalCell>> _scrollback = [];

  int _cursorRow = 0;
  int _cursorCol = 0;
  bool _wrapPending = false;
  TerminalStyle _style = TerminalStyle.empty;

  int _scrollTop = 0;
  int _scrollBottom = 0;
  bool _originMode = false;
  bool _autowrap = true;
  bool _insertMode = false;
  bool _newlineMode = false;
  bool _cursorVisible = true;
  bool _cursorBlink = true;
  TerminalCursorStyle _cursorStyle = TerminalCursorStyle.block;
  bool _applicationCursorKeys = false;
  bool _applicationKeypad = false;
  bool _bracketedPaste = false;
  bool _reverseVideo = false;

  // DECSET mouse / focus flags (same bit set as Termux's TerminalEmulator).
  bool _mousePressRelease = false; // 1000
  bool _mouseButtonMotion = false; // 1002
  bool _mouseAnyMotion = false; // 1003
  bool _mouseSgrProtocol = false; // 1006
  bool _mouseUrxvtProtocol = false; // 1015
  bool _sendFocusEvents = false; // 1004

  /// The live color table shared with the renderer. OSC color sequences
  /// mutate it; the view binds it on every (re)connect.
  TerminalPalette? palette;

  bool _inAltScreen = false;
  List<List<TerminalCell>>? _savedScreen;
  int _savedCursorRow = 0;
  int _savedCursorCol = 0;
  TerminalStyle _savedStyle = TerminalStyle.empty;
  bool _savedWrapPending = false;
  bool _savedOriginMode = false;
  int _savedScrollTop = 0;
  int _savedScrollBottom = 0;

  int _lastRune = 0;
  String _title = '';

  /// Maximum retained scrollback rows.
  int maxScrollback = 5000;

  /// Replies the emulator needs to send back to the shell (DSR/DA/window
  /// size queries). Wired to the live shell by `ShellSession`.
  void Function(String data)? onResponse;

  /// OSC 0/2 window title.
  void Function(String title)? onTitle;

  /// BEL.
  void Function()? onBell;

  /// OSC 52 clipboard write (never enabled by default — privacy).
  void Function(String text)? onClipboard;

  int get cols => _cols;
  int get rows => _rows;
  List<List<TerminalCell>> get scrollback => _scrollback;
  List<List<TerminalCell>> get screen => _screen;
  int get cursorRow => _cursorRow;
  int get cursorCol => _cursorCol;
  bool get cursorVisible => _cursorVisible;
  bool get cursorBlink => _cursorBlink;
  TerminalCursorStyle get cursorStyle => _cursorStyle;
  bool get applicationCursorKeys => _applicationCursorKeys;
  bool get applicationKeypad => _applicationKeypad;
  bool get bracketedPaste => _bracketedPaste;
  bool get reverseVideo => _reverseVideo;
  bool get inAltScreen => _inAltScreen;
  bool get autowrap => _autowrap;
  String get title => _title;
  int get totalLines => _scrollback.length + _rows;

  // ── Mouse tracking ─────────────────────────────────────────────────
  bool get mouseTrackingEnabled =>
      _mousePressRelease || _mouseButtonMotion || _mouseAnyMotion;
  bool get mouseTracksMotion => _mouseButtonMotion || _mouseAnyMotion;
  bool get mouseSgrProtocol => _mouseSgrProtocol;
  bool get mouseUrxvtProtocol => _mouseUrxvtProtocol;

  /// Bind the shared palette. Idempotent so the view can call it on every
  /// rebuild (sessions can replace the emulator at any time).
  void bindPalette(TerminalPalette value) {
    if (identical(palette, value)) return;
    palette = value;
    notifyListeners();
  }

  /// Encode and send an xterm mouse report. [button] uses xterm's numbers
  /// (0 left, 1 middle, 2 right, 64 wheel up, 65 wheel down, +32 = drag,
  /// +4 shift, +8 meta, +16 ctrl). Column/row are 1-based screen cells.
  /// SGR (1006) and urxvt (1015) protocols are preferred over the legacy
  /// 8-bit X10 encoding, which Termux also does.
  void sendMouseEvent(
    int button,
    int col,
    int row, {
    bool pressed = true,
  }) {
    if (!mouseTrackingEnabled) return;
    col = col.clamp(1, _cols);
    row = row.clamp(1, _rows);
    if (_mouseSgrProtocol) {
      onResponse?.call('\x1b[<$button;$col;$row${pressed ? 'M' : 'm'}');
    } else if (_mouseUrxvtProtocol) {
      onResponse?.call('\x1b[$button;$col;$row${pressed ? 'M' : 'm'}');
    } else {
      final b = pressed ? button : 3;
      if (b > 223 || col > 223 || row > 223) return;
      onResponse?.call('\x1b[M'
          '${String.fromCharCode(32 + b)}'
          '${String.fromCharCode(32 + col)}'
          '${String.fromCharCode(32 + row)}');
    }
  }

  void sendFocusEvent(bool focused) {
    if (_sendFocusEvents) onResponse?.call(focused ? '\x1b[I' : '\x1b[O');
  }

  /// Apply (or reset) a DECSET/DECRST private mode. Mirrors Termux's
  /// `mapDecSetBitToInternalBit` handling, plus 1003/1015 which real TUI
  /// apps commonly request.
  void _setDecsetMode(int mode, bool on) {
    switch (mode) {
      case 1:
        _applicationCursorKeys = on;
      case 5:
        _reverseVideo = on;
      case 6:
        _originMode = on;
        _setCursor(0, 0);
      case 7:
        _autowrap = on;
      case 12:
        _cursorBlink = on;
      case 25:
        _cursorVisible = on;
      case 47:
      case 1047:
      case 1049:
        if (on) {
          _enterAltScreen(clear: mode != 47);
        } else {
          _exitAltScreen();
        }
      case 66:
        _applicationKeypad = on;
      case 1000:
        _mousePressRelease = on;
        if (on) {
          _mouseButtonMotion = false;
          _mouseAnyMotion = false;
        }
      case 1002:
        _mouseButtonMotion = on;
        if (on) {
          _mousePressRelease = false;
          _mouseAnyMotion = false;
        }
      case 1003:
        _mouseAnyMotion = on;
        if (on) {
          _mousePressRelease = false;
          _mouseButtonMotion = false;
        }
      case 1004:
        _sendFocusEvents = on;
        // Report the current (focused) state as xterm does on enable.
        if (on) onResponse?.call('\x1b[I');
      case 1006:
        _mouseSgrProtocol = on;
      case 1015:
        _mouseUrxvtProtocol = on;
      case 2004:
        _bracketedPaste = on;
    }
  }

  List<TerminalCell> rowAt(int index) => index < _scrollback.length
      ? _scrollback[index]
      : _screen[index - _scrollback.length];

  /// Change the user's preferred cursor shape (DECSCUSR can override it).
  void setCursorStyle(TerminalCursorStyle style) {
    if (_cursorStyle == style) return;
    _cursorStyle = style;
    notifyListeners();
  }

  void setCursorBlink(bool blink) {
    if (_cursorBlink == blink) return;
    _cursorBlink = blink;
    notifyListeners();
  }

  /// Plain text of the visible screen (trailing blanks trimmed).
  String screenText() {
    final lines = _screen.map(_rowText).toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  /// Plain text of scrollback + screen. [maxLines] keeps the newest lines
  /// (used for bounded persistence).
  String plainText({bool includeScrollback = true, int? maxLines}) {
    final rows = <List<TerminalCell>>[];
    if (includeScrollback) rows.addAll(_scrollback);
    rows.addAll(_screen);
    final lines = rows.map(_rowText).toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final start = maxLines != null && lines.length > maxLines
        ? lines.length - maxLines
        : 0;
    return lines.sublist(start).join('\n');
  }

  /// Full reset, as if a new terminal was opened.
  void clear() {
    _screen = List.generate(_rows, (_) => _blankRow(_cols));
    _scrollback.clear();
    _cursorRow = 0;
    _cursorCol = 0;
    _wrapPending = false;
    _style = TerminalStyle.empty;
    _inAltScreen = false;
    _savedScreen = null;
    _scrollTop = 0;
    _scrollBottom = _rows - 1;
    _originMode = false;
    _autowrap = true;
    _insertMode = false;
    _newlineMode = false;
    _cursorVisible = true;
    _cursorBlink = true;
    _applicationCursorKeys = false;
    _applicationKeypad = false;
    _bracketedPaste = false;
    _reverseVideo = false;
    _mousePressRelease = false;
    _mouseButtonMotion = false;
    _mouseAnyMotion = false;
    _mouseSgrProtocol = false;
    _mouseUrxvtProtocol = false;
    _sendFocusEvents = false;
    _lastRune = 0;
    notifyListeners();
  }

  /// Resize the grid, preserving the newest rows. When the height shrinks
  /// the rows that fall off the top are pushed into scrollback, so no
  /// output is silently lost.
  void resize(int cols, int rows) {
    cols = cols.clamp(2, 500);
    rows = rows.clamp(2, 300);
    if (cols == _cols && rows == _rows) return;

    final oldScreen = _screen;
    final oldRows = oldScreen.length;
    final keepFrom = rows < oldRows ? oldRows - rows : 0;
    final newScreen = List.generate(rows, (_) => _blankRow(cols));

    for (var r = 0; r < rows; r++) {
      final src = keepFrom + r;
      if (src >= oldRows) break;
      final oldRow = oldScreen[src];
      final newRow = newScreen[r];
      final copyCols = math.min(cols, oldRow.length);
      for (var c = 0; c < copyCols; c++) {
        newRow[c] = oldRow[c];
      }
    }

    if (keepFrom > 0 && !_inAltScreen) {
      for (var i = 0; i < keepFrom; i++) {
        _scrollback.add(oldScreen[i]);
      }
      while (_scrollback.length > maxScrollback) {
        _scrollback.removeAt(0);
      }
    }

    _screen = newScreen;
    _cols = cols;
    _rows = rows;
    _scrollTop = 0;
    _scrollBottom = rows - 1;
    _cursorRow = (_cursorRow - keepFrom).clamp(0, rows - 1);
    _cursorCol = _cursorCol.clamp(0, cols - 1);
    _wrapPending = false;
    notifyListeners();
  }

  // ── Screen primitives (used by the parser) ─────────────────────────

  List<TerminalCell> _blankRow(int cols) =>
      List<TerminalCell>.filled(cols, TerminalCell.blank, growable: true);

  String _rowText(List<TerminalCell> row) {
    var last = row.length - 1;
    while (last >= 0) {
      final c = row[last];
      if (c.width != 0 && (c.text.trim().isNotEmpty || c.style.bg >= 0)) break;
      last--;
    }
    final buf = StringBuffer();
    for (var i = 0; i <= last; i++) {
      final c = row[i];
      if (c.width == 0) continue;
      buf.write(c.text.isEmpty ? ' ' : c.text);
    }
    return buf.toString().trimRight();
  }

  void _writeRune(int rune) {
    final width = terminalCharWidth(rune);
    if (width == 0) {
      _appendCombining(rune);
      return;
    }

    if (_wrapPending && _autowrap) {
      _cursorCol = 0;
      _lineFeed();
      _wrapPending = false;
    }
    if (_cursorCol >= _cols) {
      if (_autowrap) {
        _cursorCol = 0;
        _lineFeed();
      } else {
        _cursorCol = _cols - 1;
      }
    }
    if (width == 2 && _cursorCol == _cols - 1) {
      if (_autowrap) {
        _cursorCol = 0;
        _lineFeed();
      } else {
        _cursorCol = math.max(0, _cols - 2);
      }
    }

    if (_insertMode) _insertCells(width);
    final row = _screen[_cursorRow];
    row[_cursorCol] = TerminalCell(
      String.fromCharCode(rune),
      width: width,
      style: _style,
    );
    if (width == 2 && _cursorCol + 1 < _cols) {
      row[_cursorCol + 1] = const TerminalCell('', width: 0);
    }
    _lastRune = rune;
    _cursorCol += width;
    if (_cursorCol >= _cols) {
      _cursorCol = _cols - 1;
      _wrapPending = true;
    }
  }

  void _appendCombining(int rune) {
    var col = math.min(_cursorCol, _cols - 1);
    if (col > 0) col--;
    final row = _screen[_cursorRow];
    var cell = row[col];
    if (cell.isContinuation && col > 0) {
      col--;
      cell = row[col];
    }
    row[col] = TerminalCell(
      cell.text + String.fromCharCode(rune),
      width: cell.width,
      style: cell.style,
    );
  }

  void _lineFeed() {
    _wrapPending = false;
    if (_cursorRow == _scrollBottom) {
      _scrollUp(1);
    } else if (_cursorRow < _rows - 1) {
      _cursorRow++;
    }
    if (_newlineMode) _cursorCol = 0;
  }

  void _reverseIndex() {
    if (_cursorRow == _scrollTop) {
      _scrollDown(1);
    } else if (_cursorRow > 0) {
      _cursorRow--;
    }
  }

  void _carriageReturn() {
    _cursorCol = 0;
    _wrapPending = false;
  }

  void _backspace() {
    if (_cursorCol > 0) _cursorCol--;
    _wrapPending = false;
  }

  void _tabForward(int n) {
    for (var i = 0; i < n; i++) {
      final next = ((_cursorCol ~/ 8) + 1) * 8;
      _cursorCol = math.min(_cols - 1, next);
    }
    _wrapPending = false;
  }

  void _tabBackward(int n) {
    for (var i = 0; i < n; i++) {
      var next = ((_cursorCol - 1) ~/ 8) * 8;
      if (next < 0) next = 0;
      _cursorCol = next;
    }
    _wrapPending = false;
  }

  void _scrollUp(int n) {
    n = n.clamp(0, _rows);
    for (var i = 0; i < n; i++) {
      final fullScreen = _scrollTop == 0 && _scrollBottom == _rows - 1;
      if (fullScreen && !_inAltScreen) {
        final removed = _screen.removeAt(0);
        _scrollback.add(removed);
        while (_scrollback.length > maxScrollback) {
          _scrollback.removeAt(0);
        }
      } else {
        _screen.removeAt(_scrollTop);
      }
      _screen.insert(_scrollBottom, _blankRow(_cols));
    }
  }

  void _scrollDown(int n) {
    n = n.clamp(0, _rows);
    for (var i = 0; i < n; i++) {
      _screen.removeAt(_scrollBottom);
      _screen.insert(_scrollTop, _blankRow(_cols));
    }
  }

  void _eraseInLine(int mode) {
    final row = _screen[_cursorRow];
    switch (mode) {
      case 0:
        for (var c = _cursorCol; c < _cols; c++) {
          row[c] = TerminalCell.blank;
        }
      case 1:
        for (var c = 0; c <= _cursorCol && c < _cols; c++) {
          row[c] = TerminalCell.blank;
        }
      case 2:
        for (var c = 0; c < _cols; c++) {
          row[c] = TerminalCell.blank;
        }
    }
    _wrapPending = false;
  }

  void _eraseInDisplay(int mode) {
    switch (mode) {
      case 0:
        _eraseInLine(0);
        for (var r = _cursorRow + 1; r < _rows; r++) {
          _screen[r] = _blankRow(_cols);
        }
      case 1:
        _eraseInLine(1);
        for (var r = 0; r < _cursorRow; r++) {
          _screen[r] = _blankRow(_cols);
        }
      case 2:
        for (var r = 0; r < _rows; r++) {
          _screen[r] = _blankRow(_cols);
        }
      case 3:
        _scrollback.clear();
        for (var r = 0; r < _rows; r++) {
          _screen[r] = _blankRow(_cols);
        }
    }
    _wrapPending = false;
  }

  void _eraseChars(int n) {
    final row = _screen[_cursorRow];
    final end = math.min(_cols, _cursorCol + n);
    for (var c = _cursorCol; c < end; c++) {
      row[c] = TerminalCell.blank;
    }
  }

  void _insertCells(int n) {
    if (n <= 0) return;
    final row = _screen[_cursorRow];
    final keep = _cols - n;
    for (var i = keep - 1; i >= 0; i--) {
      row[i + n] = row[i];
    }
    for (var i = 0; i < n && i < _cols; i++) {
      row[i] = TerminalCell.blank;
    }
    _wrapPending = false;
  }

  void _deleteCells(int n) {
    if (n <= 0) return;
    final row = _screen[_cursorRow];
    for (var i = _cursorCol; i < _cols; i++) {
      final src = i + n;
      row[i] = src < _cols ? row[src] : TerminalCell.blank;
    }
    _wrapPending = false;
  }

  void _insertLines(int n) {
    if (_cursorRow < _scrollTop || _cursorRow > _scrollBottom) return;
    n = n.clamp(0, _scrollBottom - _cursorRow + 1);
    for (var i = 0; i < n; i++) {
      _screen.removeAt(_scrollBottom);
      _screen.insert(_cursorRow, _blankRow(_cols));
    }
    _wrapPending = false;
  }

  void _deleteLines(int n) {
    if (_cursorRow < _scrollTop || _cursorRow > _scrollBottom) return;
    n = n.clamp(0, _scrollBottom - _cursorRow + 1);
    for (var i = 0; i < n; i++) {
      _screen.removeAt(_cursorRow);
      _screen.insert(_scrollBottom, _blankRow(_cols));
    }
    _wrapPending = false;
  }

  void _setCursor(int row, int col) {
    final top = _originMode ? _scrollTop : 0;
    final bottom = _originMode ? _scrollBottom : _rows - 1;
    _cursorRow = (row + top).clamp(top, bottom);
    _cursorCol = col.clamp(0, _cols - 1);
    _wrapPending = false;
  }

  void _moveCursor(int dRow, int dCol) {
    final inside = _cursorRow >= _scrollTop && _cursorRow <= _scrollBottom;
    final top = inside ? _scrollTop : 0;
    final bottom = inside ? _scrollBottom : _rows - 1;
    _cursorRow = (_cursorRow + dRow).clamp(top, bottom);
    _cursorCol = (_cursorCol + dCol).clamp(0, _cols - 1);
    _wrapPending = false;
  }

  void _saveCursor() {
    _savedCursorRow = _cursorRow;
    _savedCursorCol = _cursorCol;
    _savedStyle = _style;
    _savedWrapPending = _wrapPending;
    _savedOriginMode = _originMode;
    _savedScrollTop = _scrollTop;
    _savedScrollBottom = _scrollBottom;
  }

  void _restoreCursor() {
    _cursorRow = _savedCursorRow.clamp(0, _rows - 1);
    _cursorCol = _savedCursorCol.clamp(0, _cols - 1);
    _style = _savedStyle;
    _wrapPending = _savedWrapPending;
    _originMode = _savedOriginMode;
    _scrollTop = _savedScrollTop.clamp(0, _rows - 1);
    _scrollBottom = _savedScrollBottom.clamp(_scrollTop, _rows - 1);
  }

  void _enterAltScreen({required bool clear}) {
    if (_inAltScreen) return;
    _savedScreen = _copyScreen(_screen);
    _savedCursorRow = _cursorRow;
    _savedCursorCol = _cursorCol;
    _savedStyle = _style;
    _savedWrapPending = _wrapPending;
    _savedOriginMode = _originMode;
    _savedScrollTop = _scrollTop;
    _savedScrollBottom = _scrollBottom;
    _inAltScreen = true;
    if (clear) {
      _screen = List.generate(_rows, (_) => _blankRow(_cols));
      _cursorRow = 0;
      _cursorCol = 0;
    } else {
      // Mode 47 keeps the visible contents but needs its own buffer so
      // edits in the alternate screen don't mutate the saved primary.
      _screen = _copyScreen(_screen);
    }
  }

  void _exitAltScreen() {
    if (!_inAltScreen) return;
    final saved = _savedScreen;
    if (saved != null) {
      _screen = saved;
      _cursorRow = _savedCursorRow.clamp(0, _rows - 1);
      _cursorCol = _savedCursorCol.clamp(0, _cols - 1);
      _style = _savedStyle;
      _wrapPending = _savedWrapPending;
      _originMode = _savedOriginMode;
      _scrollTop = _savedScrollTop.clamp(0, _rows - 1);
      _scrollBottom = _savedScrollBottom.clamp(_scrollTop, _rows - 1);
    }
    _savedScreen = null;
    _inAltScreen = false;
  }

  List<List<TerminalCell>> _copyScreen(List<List<TerminalCell>> source) =>
      [for (final row in source) List<TerminalCell>.of(row, growable: true)];

  void _setScrollRegion(int top, int bottom) {
    if (top < 0) top = 0;
    if (bottom < 0 || bottom >= _rows) bottom = _rows - 1;
    if (top >= bottom) return;
    _scrollTop = top;
    _scrollBottom = bottom;
    _setCursor(0, 0);
  }

  void _setTitle(String value) {
    final clean = value.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    if (clean.isEmpty || clean == _title) return;
    _title = clean.length > 120 ? clean.substring(0, 120) : clean;
    onTitle?.call(_title);
  }

  void _setLink(String? uri) {
    if (_style.link == uri) return;
    _style = _style.withLink(uri);
  }
}

/// Display width of a Unicode code point in a terminal cell.
///
/// Pure, no Flutter dependencies beyond `dart:core`. Wide characters
/// (CJK, most emoji) occupy two cells; combining marks occupy zero.
int terminalCharWidth(int rune) {
  if (rune == 0) return 0;
  if (rune < 32) return 0;
  if (rune >= 0x7F && rune < 0xA0) return 0;
  if (_isCombining(rune)) return 0;
  if (rune == 0x200D || (rune >= 0x200B && rune <= 0x200F)) return 0;
  if (rune >= 0xFE00 && rune <= 0xFE0F) return 0;
  if (rune >= 0xE0100 && rune <= 0xE01EF) return 0;
  if (_isWide(rune)) return 2;
  return 1;
}

bool _isCombining(int r) =>
    (r >= 0x0300 && r <= 0x036F) ||
    (r >= 0x0483 && r <= 0x0489) ||
    (r >= 0x0591 && r <= 0x05BD) ||
    (r >= 0x0610 && r <= 0x061A) ||
    (r >= 0x064B && r <= 0x065F) ||
    (r >= 0x0670 && r <= 0x0670) ||
    (r >= 0x06D6 && r <= 0x06DC) ||
    (r >= 0x0900 && r <= 0x0903) ||
    (r >= 0x093A && r <= 0x094F) ||
    (r >= 0x0951 && r <= 0x0957) ||
    (r >= 0x0E31 && r <= 0x0E31) ||
    (r >= 0x0E34 && r <= 0x0E3A) ||
    (r >= 0x0E47 && r <= 0x0E4E) ||
    (r >= 0x1AB0 && r <= 0x1AFF) ||
    (r >= 0x1DC0 && r <= 0x1DFF) ||
    (r >= 0x20D0 && r <= 0x20FF) ||
    (r >= 0xFE20 && r <= 0xFE2F) ||
    (r >= 0xFE00 && r <= 0xFE0F);

/// Keyboard protocol — a direct port of Termux's
/// `KeyHandler.getCode` / `transformForModifiers`.
///
/// Keeping this with the emulator (instead of inside the view) means the
/// same escape sequences can be unit-tested and reused by hardware keys,
/// the extra-keys bar and any future remote session.
class TermuxKeys {
  const TermuxKeys._();

  /// xterm's modifier parameter for `CSI 1;<mod>X`.
  /// Termux mapping: shift=2, alt=3, shift+alt=4, ctrl=5,
  /// shift+ctrl=6, alt+ctrl=7, all three=8.
  static int modifier({
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) {
    var mod = 1;
    if (shift) mod += 1;
    if (alt) mod += 2;
    if (ctrl) mod += 4;
    if (meta) mod += 8;
    // Exact Termux table for the seven combinations it defines.
    if (!meta) {
      if (shift && alt && ctrl) return 8;
      if (alt && ctrl) return 7;
      if (shift && ctrl) return 6;
      if (ctrl) return 5;
      if (shift && alt) return 4;
      if (alt) return 3;
      if (shift) return 2;
      return 1;
    }
    return mod;
  }

  static bool _any({
    required bool shift,
    required bool alt,
    required bool ctrl,
    required bool meta,
  }) =>
      shift || alt || ctrl || meta;

  static String transform(
    String start,
    String last, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) {
    final mod = modifier(shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    return mod == 1 ? '$start$last' : '$start;$mod$last';
  }

  static String arrow(
    String letter, {
    required bool cursorApp,
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) {
    if (!_any(shift: shift, alt: alt, ctrl: ctrl, meta: meta)) {
      return cursorApp ? '\x1bO$letter' : '\x1b[$letter';
    }
    return transform('\x1b[1', letter,
        shift: shift, alt: alt, ctrl: ctrl, meta: meta);
  }

  /// HOME/END: `H` / `F` in cursor-key sequences, `~` codes differ from
  /// their `CSI 1;mod` letters exactly as Termux sends them.
  static String homeEnd(
    String letter, {
    required bool cursorApp,
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) =>
      arrow(letter,
          cursorApp: cursorApp, shift: shift, alt: alt, ctrl: ctrl, meta: meta);

  static String tilde(
    int n, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) =>
      transform('\x1b[$n', '~', shift: shift, alt: alt, ctrl: ctrl, meta: meta);

  static String functionKey(
    int n, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) {
    final any = _any(shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    if (n >= 1 && n <= 4) {
      const letters = ['P', 'Q', 'R', 'S'];
      final l = letters[n - 1];
      if (!any) return '\x1bO$l';
      return transform('\x1b[1', l,
          shift: shift, alt: alt, ctrl: ctrl, meta: meta);
    }
    const codes = {
      5: 15,
      6: 17,
      7: 18,
      8: 19,
      9: 20,
      10: 21,
      11: 23,
      12: 24,
    };
    final code = codes[n];
    if (code == null) return '';
    return tilde(code, shift: shift, alt: alt, ctrl: ctrl, meta: meta);
  }

  /// `KEYCODE_DEL`: xterm sends DEL, CTRL+DEL sends BS, ALT prefixes ESC.
  static String backspace({bool alt = false, bool ctrl = false}) =>
      (alt ? '\x1b' : '') + (ctrl ? '\x08' : '\x7f');

  static String enter({
    bool alt = false,
    bool keypadApp = false,
    bool numpad = false,
  }) {
    if (numpad && keypadApp) return '\x1bOM';
    return '${alt ? '\x1b' : ''}\r';
  }

  static String tab({bool shift = false}) => shift ? '\x1b[Z' : '\t';

  /// CTRL + character → control code (Termux sticky-CTRL parity).
  static String ctrl(String ch) {
    if (ch.isEmpty) return '';
    if (ch == ' ') return '\x00';
    final code = ch.toUpperCase().codeUnitAt(0);
    if (code >= 64 && code <= 95) return String.fromCharCode(code - 64);
    return ch;
  }

  /// Application keypad (DECNKM / ?66) sequences, per KeyHandler.
  static const Map<String, String> keypadApplication = {
    '0': '\x1bOp',
    '1': '\x1bOq',
    '2': '\x1bOr',
    '3': '\x1bOs',
    '4': '\x1bOt',
    '5': '\x1bOu',
    '6': '\x1bOv',
    '7': '\x1bOw',
    '8': '\x1bOx',
    '9': '\x1bOy',
    '.': '\x1bOn',
    '+': '\x1bOk',
    '-': '\x1bOm',
    '*': '\x1bOj',
    '/': '\x1bOo',
    '=': '\x1bOX',
  };
}

bool _isWide(int r) =>
    (r >= 0x1100 && r <= 0x115F) ||
    (r >= 0x2E80 && r <= 0x303E) ||
    (r >= 0x3041 && r <= 0x33FF) ||
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0xA000 && r <= 0xA4CF) ||
    (r >= 0xA960 && r <= 0xA97F) ||
    (r >= 0xAC00 && r <= 0xD7A3) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0xFE10 && r <= 0xFE19) ||
    (r >= 0xFE30 && r <= 0xFE6F) ||
    (r >= 0xFF00 && r <= 0xFF60) ||
    (r >= 0xFFE0 && r <= 0xFFE6) ||
    (r >= 0x1F000 && r <= 0x1F02F) ||
    (r >= 0x1F0A0 && r <= 0x1F0FF) ||
    (r >= 0x1F100 && r <= 0x1F1AD) ||
    (r >= 0x1F300 && r <= 0x1F64F) ||
    (r >= 0x1F680 && r <= 0x1F6FF) ||
    (r >= 0x1F900 && r <= 0x1F9FF) ||
    (r >= 0x1FA70 && r <= 0x1FAFF) ||
    (r >= 0x20000 && r <= 0x3FFFD);
