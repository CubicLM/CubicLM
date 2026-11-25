/// Termux-grade terminal console.
///
/// Paints the [TerminalEmulator] grid cell-by-cell: 16/256/truecolor
/// backgrounds and text, bold/faint/italic/underline/strikethrough,
/// wide characters, block/underline/bar cursors, scrollback, long-press
/// selection with copy, and in-console search. Pure black by default
/// (the Termux palette), with selectable themes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/terminal/terminal_emulator.dart';
import '../../services/terminal/terminal_theme.dart';

/// A search hit: absolute line + cell range (end exclusive).
class TerminalMatch {
  final int line;
  final int start;
  final int end;
  const TerminalMatch(this.line, this.start, this.end);
}

/// The interactive grid.
class TerminalConsole extends StatefulWidget {
  const TerminalConsole({
    super.key,
    required this.emulator,
    required this.palette,
    this.fontSize = 12,
    this.cursorStyle = TerminalCursorStyle.block,
    this.onResize,
    this.onCopied,
    this.onTap,
    this.onLinkTap,
    this.showCursor = true,
  });

  final TerminalEmulator emulator;
  final TerminalPalette palette;
  final double fontSize;
  final TerminalCursorStyle cursorStyle;
  final void Function(int cols, int rows)? onResize;
  final void Function(String text)? onCopied;
  final VoidCallback? onTap;
  final void Function(String url)? onLinkTap;
  final bool showCursor;

  @override
  State<TerminalConsole> createState() => TerminalConsoleState();
}

class TerminalConsoleState extends State<TerminalConsole> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _blink;
  Timer? _searchDebounce;
  bool _cursorOn = true;
  bool _autoScroll = true;
  bool _atBottom = true;

  // Grid metrics (cached per font size).
  double _metricSize = -1;
  double _cellW = 8;
  double _rowH = 16;

  // Selection (absolute line indexes, cell columns).
  int? _selAnchorLine;
  int? _selAnchorCol;
  int? _selLine;
  int? _selCol;

  // Search.
  bool _searchOpen = false;
  String _query = '';
  List<TerminalMatch> _matches = const [];
  Map<int, List<TerminalMatch>> _byLine = const {};
  int _active = -1;

  // Pending resize (avoids notifying during layout).
  int _pendingCols = -1;
  int _pendingRows = -1;

  // Last pointer button, so a drag/release reports the same button.
  int _mouseButton = 0;

  static const _padX = 8.0;
  static const _padY = 6.0;

  @override
  void initState() {
    super.initState();
    widget.emulator.addListener(_onEmulator);
    _scroll.addListener(_onScroll);
    // GoogleFonts resolves asynchronously; remeasure the cell grid when
    // the real face arrives so columns never drift.
    unawaited(GoogleFonts.pendingFonts([GoogleFonts.firaCode()]).then((_) {
      if (!mounted) return;
      _metricSize = -1;
      setState(() {});
    }).catchError((_) {}));
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted) return;
      if (!widget.emulator.cursorBlink ||
          !widget.emulator.cursorVisible ||
          !widget.showCursor) {
        if (!_cursorOn) setState(() => _cursorOn = true);
        return;
      }
      setState(() => _cursorOn = !_cursorOn);
    });
  }

  @override
  void didUpdateWidget(covariant TerminalConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emulator != widget.emulator) {
      oldWidget.emulator.removeListener(_onEmulator);
      widget.emulator.addListener(_onEmulator);
      _autoScroll = true;
      _atBottom = true;
      _clearSelection();
      _runSearch(_query);
    }
  }

  @override
  void dispose() {
    widget.emulator.removeListener(_onEmulator);
    _blink?.cancel();
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onEmulator() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - _rowH * 1.5;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    _autoScroll = atBottom;
  }

  void _jumpToBottom() {
    if (!mounted || !_scroll.hasClients) return;
    try {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    } catch (_) {}
  }

  void _ensureMetrics() {
    if (_metricSize == widget.fontSize) return;
    final style = _baseStyle(widget.fontSize);
    final tp = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _cellW = math.max(4, tp.width);
    _rowH = math.max(widget.fontSize * 1.3, tp.height + 4);
    _metricSize = widget.fontSize;
  }

  TextStyle _baseStyle(double size) => GoogleFonts.firaCode(
        fontSize: size,
        height: 1.0,
        color: widget.palette.foreground,
        // A terminal is a strict cell grid: programming ligatures and
        // contextual alternates would change glyph advance and break
        // column alignment.
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.disable('liga'),
          FontFeature.disable('clig'),
          FontFeature.disable('calt'),
          FontFeature.disable('dlig'),
        ],
      ).copyWith(
        // If Google Fonts has not loaded yet (offline first run), fall
        // back to a monospace face so columns still line up.
        fontFamilyFallback: const [
          'monospace',
          'Roboto Mono',
          'Droid Sans Mono',
          'Courier New',
        ],
      );

  // ── Selection ────────────────────────────────────────────────────

  void _clearSelection() {
    _selAnchorLine = null;
    _selAnchorCol = null;
    _selLine = null;
    _selCol = null;
  }

  ({int line, int col}) _hitTest(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return (line: 0, col: 0);
    final local = box.globalToLocal(global);
    final total = widget.emulator.totalLines;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final line = ((local.dy - _padY + offset) / _rowH).floor();
    final col = ((local.dx - _padX) / _cellW).floor();
    return (
      line: line.clamp(0, math.max(0, total - 1)),
      col: col.clamp(0, widget.emulator.cols - 1),
    );
  }

  // ── Mouse tracking / OSC 8 ────────────────────────────────────────

  ({int line, int col, int screenRow})? _cellFromLocal(Offset local) {
    final emu = widget.emulator;
    final total = emu.totalLines;
    if (total == 0) return null;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final line = ((local.dy - _padY + offset) / _rowH).floor();
    final col = ((local.dx - _padX) / _cellW).floor();
    if (line < 0 || line >= total) return null;
    final screenRow = line - emu.scrollback.length;
    if (screenRow < 0 || screenRow >= emu.rows) return null;
    return (
      line: line,
      col: col.clamp(0, emu.cols - 1),
      screenRow: screenRow,
    );
  }

  int _modifiers(PointerEvent _) {
    final kb = HardwareKeyboard.instance;
    var mod = 0;
    if (kb.isShiftPressed) mod += 4;
    if (kb.isMetaPressed) mod += 8;
    if (kb.isControlPressed) mod += 16;
    return mod;
  }

  static int _button(PointerEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) return 2;
    if ((event.buttons & kMiddleMouseButton) != 0) return 1;
    return 0;
  }

  void _mouseDown(PointerDownEvent event) {
    if (!widget.emulator.mouseTrackingEnabled) return;
    final hit = _cellFromLocal(event.localPosition);
    if (hit == null) return;
    _mouseButton = _button(event) + _modifiers(event);
    widget.emulator.sendMouseEvent(
      _mouseButton,
      hit.col + 1,
      hit.screenRow + 1,
    );
  }

  void _mouseMove(PointerMoveEvent event) {
    final emu = widget.emulator;
    if (!emu.mouseTracksMotion || event.buttons == 0) return;
    final hit = _cellFromLocal(event.localPosition);
    if (hit == null) return;
    // xterm encodes a drag as button + 32.
    widget.emulator.sendMouseEvent(
      (_mouseButton & 0x03) + 32 + _modifiers(event),
      hit.col + 1,
      hit.screenRow + 1,
    );
  }

  void _mouseUp(PointerUpEvent event) {
    if (!widget.emulator.mouseTrackingEnabled) return;
    final hit = _cellFromLocal(event.localPosition);
    if (hit == null) return;
    widget.emulator.sendMouseEvent(
      (_mouseButton & 0x03) + _modifiers(event),
      hit.col + 1,
      hit.screenRow + 1,
      pressed: false,
    );
    _mouseButton = 0;
  }

  void _wheel(PointerScrollEvent event) {
    if (!widget.emulator.mouseTrackingEnabled) return;
    final hit = _cellFromLocal(event.localPosition);
    if (hit == null) return;
    final button = event.scrollDelta.dy > 0 ? 65 : 64;
    // Wheel events are press-only in xterm (SGR/urxvt and legacy X10).
    widget.emulator.sendMouseEvent(
        button + _modifiers(event), hit.col + 1, hit.screenRow + 1);
  }

  String? _linkAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final hit = _hitTest(global);
    final row = widget.emulator.rowAt(hit.line);
    if (hit.col >= row.length) return null;
    return row[hit.col].style.link;
  }

  void _startSelection(Offset global) {
    final hit = _hitTest(global);
    setState(() {
      _selAnchorLine = hit.line;
      _selAnchorCol = hit.col;
      _selLine = hit.line;
      _selCol = hit.col;
      _autoScroll = false;
    });
  }

  void _moveSelection(Offset global) {
    if (_selAnchorLine == null) return;
    final hit = _hitTest(global);
    setState(() {
      _selLine = hit.line;
      _selCol = hit.col;
    });
  }

  Future<void> _endSelection() async {
    final text = _selectedText();
    if (text.trim().isEmpty) {
      setState(_clearSelection);
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      widget.onCopied?.call(text);
    } catch (_) {}
    if (mounted) setState(_clearSelection);
  }

  String _selectedText() {
    final al = _selAnchorLine;
    final ac = _selAnchorCol;
    final el = _selLine;
    final ec = _selCol;
    if (al == null || ac == null || el == null || ec == null) return '';
    final startLine = math.min(al, el);
    final endLine = math.max(al, el);
    final forward = el > al || (el == al && ec >= ac);
    final startCol =
        forward ? (al == startLine ? ac : 0) : (el == startLine ? ec : 0);
    final endCol = forward
        ? (el == endLine ? ec : widget.emulator.cols - 1)
        : (al == endLine ? ac : widget.emulator.cols - 1);
    final buf = StringBuffer();
    for (var line = startLine; line <= endLine; line++) {
      final row = widget.emulator.rowAt(line);
      final from = line == startLine ? startCol : 0;
      final to = line == endLine ? endCol : math.max(0, row.length - 1);
      final cells = _cellColumns(row);
      var out = StringBuffer();
      for (var c = from; c <= to && c < cells.length; c++) {
        out.write(cells[c]);
      }
      buf.write(out.toString().trimRight());
      if (line != endLine) buf.write('\n');
    }
    return buf.toString();
  }

  /// Cell-index → text for a row (continuations folded into the wide
  /// character's first cell; blanks become spaces).
  List<String> _cellColumns(List<TerminalCell> row) {
    final cols = widget.emulator.cols;
    final out = List<String>.filled(cols, ' ');
    for (var i = 0; i < row.length && i < cols; i++) {
      final cell = row[i];
      if (cell.width == 0) continue;
      out[i] = cell.text.isEmpty ? ' ' : cell.text;
    }
    return out;
  }

  String _lineText(int line) {
    final cells = _cellColumns(widget.emulator.rowAt(line));
    final buf = StringBuffer();
    for (final c in cells) {
      buf.write(c);
    }
    return buf.toString().trimRight();
  }

  // ── Search ───────────────────────────────────────────────────────

  /// Open the in-console search bar.
  void openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  /// True while the find bar is open (hardware key passthrough is off).
  bool get isSearching => _searchOpen;

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchOpen = false;
      _query = '';
      _matches = const [];
      _byLine = const {};
      _active = -1;
    });
    _searchCtrl.clear();
    _searchFocus.unfocus();
  }

  void _runSearch(String query) {
    final q = query.trim();
    final matches = <TerminalMatch>[];
    if (q.isNotEmpty) {
      final needle = q.toLowerCase();
      final total = widget.emulator.totalLines;
      for (var line = 0; line < total; line++) {
        final text = _lineText(line).toLowerCase();
        if (text.isEmpty) continue;
        var from = 0;
        while (from <= text.length - needle.length) {
          final idx = text.indexOf(needle, from);
          if (idx < 0) break;
          matches.add(TerminalMatch(line, idx, idx + needle.length));
          from = idx + math.max(1, needle.length);
        }
      }
    }
    final byLine = <int, List<TerminalMatch>>{};
    for (final m in matches) {
      byLine.putIfAbsent(m.line, () => []).add(m);
    }
    setState(() {
      _query = q;
      _matches = matches;
      _byLine = byLine;
      _active = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _scrollToMatch(0);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _runSearch(query);
    });
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    final next = (_active + delta) % _matches.length;
    final wrapped = next < 0 ? _matches.length + next : next;
    setState(() => _active = wrapped);
    _scrollToMatch(wrapped);
  }

  void _scrollToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    final line = _matches[index].line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final viewport = _scroll.position.viewportDimension;
      final target = (line * _rowH + _padY - viewport * 0.35)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _autoScroll = false;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _ensureMetrics();
    final emu = widget.emulator;
    final theme = widget.palette;

    return LayoutBuilder(builder: (context, constraints) {
      final cols =
          ((constraints.maxWidth - _padX * 2) / _cellW).floor().clamp(2, 500);
      final rows =
          ((constraints.maxHeight - _padY * 2) / _rowH).floor().clamp(2, 300);
      if ((cols != emu.cols || rows != emu.rows) &&
          (cols != _pendingCols || rows != _pendingRows)) {
        _pendingCols = cols;
        _pendingRows = rows;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pendingCols = -1;
          _pendingRows = -1;
          widget.onResize?.call(cols, rows);
        });
      }

      final total = emu.totalLines;
      final cursorLine = emu.scrollback.length + emu.cursorRow;

      return ColoredBox(
        // DECSCNM (?5) inverts the whole screen: the page background
        // becomes the foreground color so default cells stay readable.
        color: emu.reverseVideo ? theme.foreground : theme.background,
        child: Stack(
          children: [
            Listener(
              onPointerDown: _mouseDown,
              onPointerMove: _mouseMove,
              onPointerUp: _mouseUp,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) _wheel(event);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final link = _linkAt(details.globalPosition);
                  if (link != null) {
                    widget.onLinkTap?.call(link);
                    return;
                  }
                  if (_selAnchorLine != null) {
                    setState(_clearSelection);
                  }
                  widget.onTap?.call();
                },
                onLongPressStart: (d) => _startSelection(d.globalPosition),
                onLongPressMoveUpdate: (d) => _moveSelection(d.globalPosition),
                onLongPressEnd: (_) => _endSelection(),
                child: Scrollbar(
                  controller: _scroll,
                  thickness: 3,
                  radius: const Radius.circular(2),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: _padX, vertical: _padY),
                    itemExtent: _rowH,
                    itemCount: total,
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final row = emu.rowAt(index);
                      final sel = _selectionFor(index);
                      final search = _byLine[index];
                      final active = _active >= 0 &&
                              _active < _matches.length &&
                              _matches[_active].line == index
                          ? _matches[_active]
                          : null;
                      return RepaintBoundary(
                        child: _TerminalRow(
                          row: row,
                          cols: emu.cols,
                          theme: theme,
                          base: _baseStyle(widget.fontSize),
                          cellW: _cellW,
                          rowH: _rowH,
                          cursorCol: widget.showCursor &&
                                  _cursorOn &&
                                  index == cursorLine &&
                                  emu.cursorVisible
                              ? emu.cursorCol
                              : -1,
                          cursorStyle: widget.cursorStyle,
                          reverseVideo: emu.reverseVideo,
                          selStart: sel?.start ?? -1,
                          selEnd: sel?.end ?? -1,
                          search: search,
                          activeSearch: active,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (!_atBottom)
              Positioned(
                right: 14,
                bottom: 12,
                child: _RoundButton(
                  icon: Icons.arrow_downward_rounded,
                  tooltip: 'Jump to bottom',
                  onTap: () {
                    _autoScroll = true;
                    _jumpToBottom();
                  },
                ),
              ),
            if (_searchOpen) _searchBar(theme),
          ],
        ),
      );
    });
  }

  ({int start, int end})? _selectionFor(int line) {
    final al = _selAnchorLine;
    final ac = _selAnchorCol;
    final el = _selLine;
    final ec = _selCol;
    if (al == null || ac == null || el == null || ec == null) return null;
    final startLine = math.min(al, el);
    final endLine = math.max(al, el);
    if (line < startLine || line > endLine) return null;
    final forward = el > al || (el == al && ec >= ac);
    final startCol =
        forward ? (al == startLine ? ac : 0) : (el == startLine ? ec : 0);
    final endCol = forward
        ? (el == endLine ? ec : widget.emulator.cols - 1)
        : (al == endLine ? ac : widget.emulator.cols - 1);
    if (line == startLine && line == endLine) {
      return (
        start: math.min(startCol, endCol),
        end: math.max(startCol, endCol) + 1
      );
    }
    if (line == startLine) return (start: startCol, end: widget.emulator.cols);
    if (line == endLine) return (start: 0, end: endCol + 1);
    return (start: 0, end: widget.emulator.cols);
  }

  Widget _searchBar(TerminalPalette theme) {
    final count = _matches.isEmpty
        ? (_query.isEmpty ? '' : '0/0')
        : '${_active + 1}/${_matches.length}';
    return Positioned(
      left: 8,
      right: 8,
      top: 6,
      child: Material(
        color: const Color(0xFF161616),
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.search_rounded,
                  size: 16, color: Color(0xFF9AA0A6)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style:
                      GoogleFonts.firaCode(fontSize: 12, color: Colors.white),
                  cursorColor: theme.cursor,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Find in terminal…',
                    hintStyle: TextStyle(color: Color(0xFF6E7681)),
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _stepMatch(1),
                  textInputAction: TextInputAction.search,
                ),
              ),
              if (count.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    count,
                    style: GoogleFonts.firaCode(
                        fontSize: 10.5, color: const Color(0xFF9AA0A6)),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Close search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: _closeSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One grid row, painted in a repaint boundary.
class _TerminalRow extends StatelessWidget {
  const _TerminalRow({
    required this.row,
    required this.cols,
    required this.theme,
    required this.base,
    required this.cellW,
    required this.rowH,
    required this.cursorCol,
    required this.cursorStyle,
    required this.reverseVideo,
    required this.selStart,
    required this.selEnd,
    required this.search,
    required this.activeSearch,
  });

  final List<TerminalCell> row;
  final int cols;
  final TerminalPalette theme;
  final TextStyle base;
  final double cellW;
  final double rowH;
  final int cursorCol;
  final TerminalCursorStyle cursorStyle;
  final bool reverseVideo;
  final int selStart;
  final int selEnd;
  final List<TerminalMatch>? search;
  final TerminalMatch? activeSearch;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(cols * cellW, rowH),
      painter: _RowPainter(
        row: row,
        cols: cols,
        theme: theme,
        base: base,
        cellW: cellW,
        rowH: rowH,
        cursorCol: cursorCol,
        cursorStyle: cursorStyle,
        reverseVideo: reverseVideo,
        selStart: selStart,
        selEnd: selEnd,
        search: search,
        activeSearch: activeSearch,
      ),
    );
  }
}

class _RowPainter extends CustomPainter {
  _RowPainter({
    required this.row,
    required this.cols,
    required this.theme,
    required this.base,
    required this.cellW,
    required this.rowH,
    required this.cursorCol,
    required this.cursorStyle,
    required this.reverseVideo,
    required this.selStart,
    required this.selEnd,
    required this.search,
    required this.activeSearch,
  });

  final List<TerminalCell> row;
  final int cols;
  final TerminalPalette theme;
  final TextStyle base;
  final double cellW;
  final double rowH;
  final int cursorCol;
  final TerminalCursorStyle cursorStyle;
  final bool reverseVideo;
  final int selStart;
  final int selEnd;
  final List<TerminalMatch>? search;
  final TerminalMatch? activeSearch;

  @override
  void paint(Canvas canvas, Size size) {
    final n = cols;
    // DECSCNM (?5) inverts the whole screen; a cell's own SGR 7 still
    // flips its individual colors on top of that.
    final baseFg = reverseVideo ? theme.background : theme.foreground;
    final baseBg = reverseVideo ? theme.foreground : theme.background;
    final fgs = List<Color>.filled(n, baseFg);
    final bgs = List<Color>.filled(n, baseBg);
    final hidden = List<bool>.filled(n, false);
    final bold = List<bool>.filled(n, false);
    final italic = List<bool>.filled(n, false);
    final underline = List<bool>.filled(n, false);
    final strike = List<bool>.filled(n, false);
    final overline = List<bool>.filled(n, false);

    for (var c = 0; c < n; c++) {
      final cell = c < row.length ? row[c] : TerminalCell.blank;
      if (cell.width == 0) {
        if (c > 0) {
          fgs[c] = fgs[c - 1];
          bgs[c] = bgs[c - 1];
          hidden[c] = hidden[c - 1];
          bold[c] = bold[c - 1];
          italic[c] = italic[c - 1];
          underline[c] = underline[c - 1];
          strike[c] = strike[c - 1];
          overline[c] = overline[c - 1];
        }
        continue;
      }
      var fg =
          theme.resolve(cell.style.fg, foreground: true, bold: cell.style.bold);
      var bg = theme.resolve(cell.style.bg, foreground: false);
      if (cell.style.reverse) {
        final t = fg;
        fg = bg;
        bg = t;
      }
      if (cell.style.faint) fg = Color.lerp(fg, bg, 0.55) ?? fg;
      fgs[c] = fg;
      bgs[c] = bg;
      hidden[c] = cell.style.hidden;
      bold[c] = cell.style.bold;
      italic[c] = cell.style.italic;
      // OSC 8 hyperlinks are underlined and tappable (beyond Termux).
      underline[c] = cell.style.underline || cell.style.link != null;
      strike[c] = cell.style.strikethrough;
      overline[c] = cell.style.overline;
    }

    // Backgrounds (grouped runs).
    final bgPaint = Paint()..style = PaintingStyle.fill;
    var c = 0;
    while (c < n) {
      final color = bgs[c];
      var end = c + 1;
      while (end < n && bgs[end] == color) {
        end++;
      }
      if (color != baseBg) {
        bgPaint.color = color;
        canvas.drawRect(
            Rect.fromLTWH(c * cellW, 0, (end - c) * cellW, rowH), bgPaint);
      }
      c = end;
    }

    // Selection.
    if (selStart >= 0) {
      final from = selStart.clamp(0, n);
      final to = selEnd.clamp(0, n);
      if (to > from) {
        bgPaint.color = theme.selection;
        canvas.drawRect(
            Rect.fromLTWH(from * cellW, 0, (to - from) * cellW, rowH), bgPaint);
      }
    }

    // Search hits.
    if (search != null && search!.isNotEmpty) {
      for (final m in search!) {
        final active = activeSearch != null &&
            m.line == activeSearch!.line &&
            m.start == activeSearch!.start;
        bgPaint.color =
            active ? const Color(0x99FFB300) : const Color(0x55FFB300);
        final from = m.start.clamp(0, n);
        final to = m.end.clamp(0, n);
        if (to > from) {
          canvas.drawRect(
              Rect.fromLTWH(from * cellW, 0, (to - from) * cellW, rowH),
              bgPaint);
        }
      }
    }

    // Block cursor background (text is drawn on top in the bg color).
    var cursorCell = cursorCol;
    if (cursorCell > 0 &&
        cursorCell < row.length &&
        row[cursorCell].width == 0) {
      cursorCell -= 1;
    }
    final cursorFg = List<Color>.filled(n, baseBg);
    if (cursorCell >= 0 && cursorCell < n) {
      final wide = cursorCell < row.length && row[cursorCell].width == 2;
      final width = (wide ? 2 : 1) * cellW;
      if (cursorStyle == TerminalCursorStyle.block) {
        bgPaint.color = theme.cursor;
        canvas.drawRect(
            Rect.fromLTWH(cursorCell * cellW, 0, width, rowH), bgPaint);
      }
    }

    // Text runs.
    var i = 0;
    while (i < n) {
      final cell = i < row.length ? row[i] : TerminalCell.blank;
      if (cell.width == 0) {
        i++;
        continue;
      }
      if (hidden[i]) {
        i += cell.width == 2 ? 2 : 1;
        continue;
      }
      if (cell.width == 2) {
        _drawWide(canvas, i, cell, cursorCell, cursorFg, fgs);
        i += 2;
        continue;
      }
      // A run of single-width cells with identical styling. A block
      // cursor paints the glyph in the background color; bar and
      // underline cursors keep the text readable.
      final invert = cursorStyle == TerminalCursorStyle.block;
      final runFg = i == cursorCell && invert ? cursorFg[i] : fgs[i];
      final runBold = bold[i];
      final runItalic = italic[i];
      final runUnderline = underline[i];
      final runStrike = strike[i];
      final runOverline = overline[i];
      var end = i + 1;
      final buf = StringBuffer(_charOf(cell));
      while (end < n) {
        final next = end < row.length ? row[end] : TerminalCell.blank;
        if (next.width != 1) break;
        if (hidden[end]) break;
        final nextFg = end == cursorCell && invert ? cursorFg[end] : fgs[end];
        if (nextFg != runFg ||
            bold[end] != runBold ||
            italic[end] != runItalic ||
            underline[end] != runUnderline ||
            strike[end] != runStrike ||
            overline[end] != runOverline) {
          break;
        }
        buf.write(_charOf(next));
        end++;
      }
      final style = base.copyWith(
        color: runFg,
        fontWeight: runBold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: runItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _decoration(runUnderline, runStrike),
      );
      final tp = TextPainter(
        text: TextSpan(text: buf.toString(), style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final y = (rowH - tp.height) / 2;
      tp.paint(canvas, Offset(i * cellW, y));
      if (runOverline) {
        final linePaint = Paint()
          ..color = runFg
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(i * cellW, 1),
          Offset(end * cellW, 1),
          linePaint,
        );
      }
      i = end;
    }

    // Underline/bar cursor on top of the text.
    if (cursorCell >= 0 && cursorCell < n) {
      final wide = cursorCell < row.length && row[cursorCell].width == 2;
      final width = (wide ? 2 : 1) * cellW;
      final paint = Paint()..color = theme.cursor;
      if (cursorStyle == TerminalCursorStyle.underline) {
        canvas.drawRect(
            Rect.fromLTWH(cursorCell * cellW, rowH - 2, width, 2), paint);
      } else if (cursorStyle == TerminalCursorStyle.bar) {
        canvas.drawRect(Rect.fromLTWH(cursorCell * cellW, 0, 2, rowH), paint);
      }
    }
  }

  void _drawWide(
    Canvas canvas,
    int col,
    TerminalCell cell,
    int cursorCell,
    List<Color> cursorFg,
    List<Color> fgs,
  ) {
    final invert = cursorStyle == TerminalCursorStyle.block;
    final style = base.copyWith(
      color: col == cursorCell && invert ? cursorFg[col] : fgs[col],
      fontWeight: cell.style.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: cell.style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: _decoration(cell.style.underline, cell.style.strikethrough),
    );
    final tp = TextPainter(
      text: TextSpan(text: cell.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final y = (rowH - tp.height) / 2;
    final x = col * cellW + (2 * cellW - tp.width) / 2;
    tp.paint(canvas, Offset(x, y));
  }

  static String _charOf(TerminalCell cell) =>
      cell.text.isEmpty ? ' ' : cell.text;

  static TextDecoration _decoration(bool underline, bool strike) {
    if (underline && strike) {
      return TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.lineThrough]);
    }
    if (underline) return TextDecoration.underline;
    if (strike) return TextDecoration.lineThrough;
    return TextDecoration.none;
  }

  @override
  bool shouldRepaint(covariant _RowPainter old) => true;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xE6262626),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
