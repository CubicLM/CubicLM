/// Terminal color themes — Termux-accurate palettes.
///
/// The default [Termux] scheme is byte-for-byte the palette Termux ships
/// in `TerminalColorScheme.java` (16 ANSI colors, white on pure black),
/// so colored CLI output looks identical to Termux. Extra presets are
/// available for users who want a different code-color combination.
library;

import 'dart:ui' show Color;

/// A terminal color scheme: 16 ANSI slots + default fg/bg/cursor.
class TerminalTheme {
  final String id;
  final String name;
  final List<Color> colors;
  final Color foreground;
  final Color background;
  final Color cursor;
  final Color selection;

  const TerminalTheme({
    required this.id,
    required this.name,
    required this.colors,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.selection,
  });

  /// Resolve an SGR color spec.
  ///
  /// [spec] is `null`/`-1` for the default color, `0..255` for the indexed
  /// palette, or `0x1000000 | RGB` for 24-bit color.
  Color resolve(int? spec, {required bool foreground, bool bold = false}) {
    if (spec == null || spec < 0) {
      return foreground ? this.foreground : background;
    }
    if ((spec & 0x1000000) != 0) {
      return Color(0xFF000000 | (spec & 0xFFFFFF));
    }
    var index = spec & 0xFF;
    // Termux/xterm: bold brightens the first 8 ANSI colors.
    if (foreground && bold && index < 8) index += 8;
    return indexed(index);
  }

  /// The xterm 256-color palette (first 16 from this theme).
  ///
  /// The 6x6x6 cube uses Termux's exact levels (0x00, 0x5f, 0x87,
  /// 0xaf, 0xd7, 0xff) — a linear 51-step ramp is the common but wrong
  /// approximation and makes CLI output visibly off-color.
  Color indexed(int n) {
    if (n < 0) n = 0;
    if (n < 16) return colors[n];
    if (n < 232) {
      final i = n - 16;
      final r = cubeLevels[i ~/ 36];
      final g = cubeLevels[(i % 36) ~/ 6];
      final b = cubeLevels[i % 6];
      return Color.fromARGB(255, r, g, b);
    }
    final v = 8 + (n - 232) * 10;
    return Color.fromARGB(255, v, v, v);
  }

  /// Exact xterm cube levels from
  /// `TerminalColorScheme.DEFAULT_COLORSCHEME` in Termux.
  static const List<int> cubeLevels = [0, 95, 135, 175, 215, 255];

  static TerminalTheme byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return termux;
  }

  /// Termux's exact default palette.
  static const TerminalTheme termux = TerminalTheme(
    id: 'termux',
    name: 'Termux',
    colors: [
      Color(0xFF000000), // 0 black
      Color(0xFFCD0000), // 1 red
      Color(0xFF00CD00), // 2 green
      Color(0xFFCDCD00), // 3 yellow
      Color(0xFF6495ED), // 4 blue
      Color(0xFFCD00CD), // 5 magenta
      Color(0xFF00CDCD), // 6 cyan
      Color(0xFFE5E5E5), // 7 white
      Color(0xFF7F7F7F), // 8 bright black
      Color(0xFFFF0000), // 9 bright red
      Color(0xFF00FF00), // 10 bright green
      Color(0xFFFFFF00), // 11 bright yellow
      Color(0xFF5C5CFF), // 12 bright blue
      Color(0xFFFF00FF), // 13 bright magenta
      Color(0xFF00FFFF), // 14 bright cyan
      Color(0xFFFFFFFF), // 15 bright white
    ],
    foreground: Color(0xFFFFFFFF),
    background: Color(0xFF000000),
    cursor: Color(0xFFFFFFFF),
    selection: Color(0x664A90D9),
  );

  /// A vivid neon palette built on Termux's pure-black base.
  static const TerminalTheme cubicNeon = TerminalTheme(
    id: 'cubic_neon',
    name: 'Cubic Neon',
    colors: [
      Color(0xFF1B1B1B),
      Color(0xFFFF5F5F),
      Color(0xFF3DDC84),
      Color(0xFFFFD75F),
      Color(0xFF5FAFFF),
      Color(0xFFFF79C6),
      Color(0xFF56E1E9),
      Color(0xFFE6E6E6),
      Color(0xFF7A7A7A),
      Color(0xFFFF8A8A),
      Color(0xFF7CFFB2),
      Color(0xFFFFE98A),
      Color(0xFF8FC7FF),
      Color(0xFFFFA8D8),
      Color(0xFF8AF3F7),
      Color(0xFFFFFFFF),
    ],
    foreground: Color(0xFFF2F2F2),
    background: Color(0xFF000000),
    cursor: Color(0xFF3DDC84),
    selection: Color(0x553DDC84),
  );

  static const TerminalTheme oneDark = TerminalTheme(
    id: 'one_dark',
    name: 'One Dark',
    colors: [
      Color(0xFF282C34),
      Color(0xFFE06C75),
      Color(0xFF98C379),
      Color(0xFFE5C07B),
      Color(0xFF61AFEF),
      Color(0xFFC678DD),
      Color(0xFF56B6C2),
      Color(0xFFABB2BF),
      Color(0xFF5C6370),
      Color(0xFFFF7B86),
      Color(0xFFB5E890),
      Color(0xFFFFD68A),
      Color(0xFF7CC4FF),
      Color(0xFFDDA0F0),
      Color(0xFF6FD6E2),
      Color(0xFFFFFFFF),
    ],
    foreground: Color(0xFFABB2BF),
    background: Color(0xFF000000),
    cursor: Color(0xFF528BFF),
    selection: Color(0x55528BFF),
  );

  static const TerminalTheme dracula = TerminalTheme(
    id: 'dracula',
    name: 'Dracula',
    colors: [
      Color(0xFF21222C),
      Color(0xFFFF5555),
      Color(0xFF50FA7B),
      Color(0xFFF1FA8C),
      Color(0xFFBD93F9),
      Color(0xFFFF79C6),
      Color(0xFF8BE9FD),
      Color(0xFFF8F8F2),
      Color(0xFF6272A4),
      Color(0xFFFF6E6E),
      Color(0xFF69FF94),
      Color(0xFFFFFFA5),
      Color(0xFFD6ACFF),
      Color(0xFFFF92DF),
      Color(0xFFA4FFFF),
      Color(0xFFFFFFFF),
    ],
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF000000),
    cursor: Color(0xFFF8F8F2),
    selection: Color(0x5544475A),
  );

  static const TerminalTheme nord = TerminalTheme(
    id: 'nord',
    name: 'Nord',
    colors: [
      Color(0xFF3B4252),
      Color(0xFFBF616A),
      Color(0xFFA3BE8C),
      Color(0xFFEBCB8B),
      Color(0xFF81A1C1),
      Color(0xFFB48EAD),
      Color(0xFF88C0D0),
      Color(0xFFE5E9F0),
      Color(0xFF4C566A),
      Color(0xFFBF616A),
      Color(0xFFA3BE8C),
      Color(0xFFEBCB8B),
      Color(0xFF81A1C1),
      Color(0xFFB48EAD),
      Color(0xFF8FBCBB),
      Color(0xFFECEFF4),
    ],
    foreground: Color(0xFFD8DEE9),
    background: Color(0xFF000000),
    cursor: Color(0xFFD8DEE9),
    selection: Color(0x555E81AC),
  );

  static const TerminalTheme solarizedDark = TerminalTheme(
    id: 'solarized_dark',
    name: 'Solarized Dark',
    colors: [
      Color(0xFF073642),
      Color(0xFFDC322F),
      Color(0xFF859900),
      Color(0xFFB58900),
      Color(0xFF268BD2),
      Color(0xFFD33682),
      Color(0xFF2AA198),
      Color(0xFFEEE8D5),
      Color(0xFF002B36),
      Color(0xFFCB4B16),
      Color(0xFF586E75),
      Color(0xFF657B83),
      Color(0xFF839496),
      Color(0xFF6C71C4),
      Color(0xFF93A1A1),
      Color(0xFFFDF6E3),
    ],
    foreground: Color(0xFF839496),
    background: Color(0xFF000000),
    cursor: Color(0xFF839496),
    selection: Color(0x55073642),
  );

  static const TerminalTheme gruvbox = TerminalTheme(
    id: 'gruvbox',
    name: 'Gruvbox Dark',
    colors: [
      Color(0xFF282828),
      Color(0xFFCC241D),
      Color(0xFF98971A),
      Color(0xFFD79921),
      Color(0xFF458588),
      Color(0xFFB16286),
      Color(0xFF689D6A),
      Color(0xFFA89984),
      Color(0xFF928374),
      Color(0xFFFB4934),
      Color(0xFFB8BB26),
      Color(0xFFFABD2F),
      Color(0xFF83A598),
      Color(0xFFD3869B),
      Color(0xFF8EC07C),
      Color(0xFFEBDBB2),
    ],
    foreground: Color(0xFFEBDBB2),
    background: Color(0xFF000000),
    cursor: Color(0xFFEBDBB2),
    selection: Color(0x55504945),
  );

  static const TerminalTheme tokyoNight = TerminalTheme(
    id: 'tokyo_night',
    name: 'Tokyo Night',
    colors: [
      Color(0xFF15161E),
      Color(0xFFF7768E),
      Color(0xFF9ECE6A),
      Color(0xFFE0AF68),
      Color(0xFF7AA2F7),
      Color(0xFFBB9AF7),
      Color(0xFF7DCFFF),
      Color(0xFFA9B1D6),
      Color(0xFF414868),
      Color(0xFFFF899D),
      Color(0xFFB9F27C),
      Color(0xFFFF9E64),
      Color(0xFF7DA6FF),
      Color(0xFFC7A9FF),
      Color(0xFF86E1FC),
      Color(0xFFC0CAF5),
    ],
    foreground: Color(0xFFC0CAF5),
    background: Color(0xFF000000),
    cursor: Color(0xFFC0CAF5),
    selection: Color(0x5533467A),
  );

  static const List<TerminalTheme> all = [
    termux,
    cubicNeon,
    oneDark,
    dracula,
    nord,
    solarizedDark,
    gruvbox,
    tokyoNight,
  ];
}

/// Mutable per-session color table — the equivalent of Termux's
/// `TerminalColors`, which starts from the theme's 259 defaults (256
/// indexed + foreground/background/cursor) and can be changed at runtime
/// by OSC 4 / 10 / 11 / 12 (and reset by 104 / 110 / 111 / 112).
///
/// One instance is shared by the [TerminalEmulator] and the renderer, so
/// a shell that redefines its palette is displayed immediately.
class TerminalPalette {
  TerminalPalette(this.base) {
    resetAll();
  }

  TerminalTheme base;

  static const int foregroundIndex = 256;
  static const int backgroundIndex = 257;
  static const int cursorIndex = 258;
  static const int colorCount = 259;

  final List<int> _current = List<int>.filled(colorCount, 0);
  final List<bool> _custom = List<bool>.filled(colorCount, false);

  bool get hasOverrides => _custom.any((v) => v);

  /// Switch theme. Runtime OSC overrides are discarded, exactly like a
  /// fresh Termux session with a new `colors.properties`.
  void setBase(TerminalTheme theme) {
    base = theme;
    resetAll();
  }

  void resetAll() {
    for (var i = 0; i < colorCount; i++) {
      reset(i);
    }
  }

  void reset(int index) {
    if (index < 0 || index >= colorCount) return;
    _custom[index] = false;
    _current[index] = _default(index);
  }

  int _default(int index) {
    if (index < 256) return base.indexed(index).toARGB32();
    return switch (index) {
      foregroundIndex => base.foreground.toARGB32(),
      backgroundIndex => base.background.toARGB32(),
      _ => base.cursor.toARGB32(),
    };
  }

  void set(int index, int argb) {
    if (index < 0 || index >= colorCount) return;
    _current[index] = 0xFF000000 | (argb & 0xFFFFFF);
    _custom[index] = true;
  }

  int argbAt(int index) => _current[index.clamp(0, colorCount - 1)];
  Color colorAt(int index) => Color(argbAt(index));
  Color indexed(int n) => colorAt(n.clamp(0, 255));

  Color get foreground => colorAt(foregroundIndex);
  Color get background => colorAt(backgroundIndex);
  Color get cursor => colorAt(cursorIndex);
  Color get selection => base.selection;
  List<Color> get colors => [for (var i = 0; i < 16; i++) indexed(i)];
  String get id => base.id;
  String get name => base.name;

  /// Resolve an SGR color spec (`-1` = default, 0..255 = indexed,
  /// `0x1000000 | RGB` = 24-bit).
  Color resolve(int? spec, {required bool foreground, bool bold = false}) {
    if (spec == null || spec < 0) {
      return foreground ? this.foreground : background;
    }
    if ((spec & 0x1000000) != 0) {
      return Color(0xFF000000 | (spec & 0xFFFFFF));
    }
    var index = spec & 0xFF;
    // xterm/Termux: bold brightens the first eight ANSI colors.
    if (foreground && bold && index < 8) index += 8;
    return indexed(index);
  }

  /// Answer for an OSC 10/11/12 `?` query, in xterm's 16-bit form.
  String reportColor(int index) {
    final c = argbAt(index);
    String hex(int v) => ((65535 * v) ~/ 255).toRadixString(16).padLeft(4, '0');
    return 'rgb:${hex((c >> 16) & 0xFF)}/'
        '${hex((c >> 8) & 0xFF)}/'
        '${hex(c & 0xFF)}';
  }

  /// Exact port of Termux `TerminalColors.parse`:
  /// `#RGB`, `#RRGGBB`, `#RRRGGGBBB`, `#RRRRGGGGBBBB` and
  /// `rgb:r/g/b` (1–4 hex digits per component, scaled to 0..255).
  static int? parseColor(String c) {
    if (c.isEmpty) return null;
    final int skipInitial;
    final int skipBetween;
    if (c.startsWith('#')) {
      skipInitial = 1;
      skipBetween = 0;
    } else if (c.startsWith('rgb:')) {
      skipInitial = 4;
      skipBetween = 1;
    } else {
      return null;
    }
    final chars = c.length - skipInitial - 2 * skipBetween;
    if (chars <= 0 || chars % 3 != 0) return null;
    final comp = chars ~/ 3;
    if (comp < 1 || comp > 4) return null;
    final mult = 255 / ((1 << (comp * 4)) - 1);
    var pos = skipInitial;
    int? next() {
      if (pos + comp > c.length) return null;
      final value = int.tryParse(c.substring(pos, pos + comp), radix: 16);
      pos += comp + skipBetween;
      return value;
    }

    final r = next();
    final g = next();
    final b = next();
    if (r == null || g == null || b == null) return null;
    return 0xFF000000 |
        ((r * mult).toInt() << 16) |
        ((g * mult).toInt() << 8) |
        (b * mult).toInt();
  }
}
