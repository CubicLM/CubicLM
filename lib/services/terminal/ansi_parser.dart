/// ANSI escape parser for the terminal (pure, unit-testable).
///
/// Converts text containing ANSI escape sequences into styled spans so
/// the terminal can render colored output like a real terminal emulator
/// (Termux parity). Handles:
/// - SGR (Select Graphic Rendition) `ESC[...m`: 16 foreground/background
///   colors, 256-color (`38;5;n` / `48;5;n`), 24-bit RGB, bold, faint,
///   italic, underline, and their resets.
/// - Non-SGR CSI sequences (cursor moves, erase) and OSC sequences are
///   stripped — they carry no colors.
/// - Carriage returns mid-line (`\r`) are handled by the caller (the
///   shell session buffer), the parser only sees final line text.
library;

import 'dart:ui' show Color;

/// One styled run of text within a terminal line.
class AnsiSpan {
  final String text;
  final AnsiStyle style;

  const AnsiSpan(this.text, this.style);
}

/// Cumulative text style carried across an SGR stream.
class AnsiStyle {
  final Color? fg;
  final Color? bg;
  final bool bold;
  final bool faint;
  final bool italic;
  final bool underline;

  const AnsiStyle({
    this.fg,
    this.bg,
    this.bold = false,
    this.faint = false,
    this.italic = false,
    this.underline = false,
  });

  AnsiStyle copyWith({
    Color? fg,
    Color? bg,
    bool? bold,
    bool? faint,
    bool? italic,
    bool? underline,
    bool resetFg = false,
    bool resetBg = false,
  }) =>
      AnsiStyle(
        fg: resetFg ? null : (fg ?? this.fg),
        bg: resetBg ? null : (bg ?? this.bg),
        bold: bold ?? this.bold,
        faint: faint ?? this.faint,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
      );

  @override
  bool operator ==(Object other) =>
      other is AnsiStyle &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold &&
      other.faint == faint &&
      other.italic == italic &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(fg, bg, bold, faint, italic, underline);
}

/// The 16 ANSI base colors (Termux-ish palette — slightly softened for
/// the pure-black background).
const List<Color> ansiBaseColors = [
  Color(0xFF3DDC84), // 0 black → android green (never rendered as black text)
  Color(0xFFE57373), // 1 red
  Color(0xFF8BC34A), // 2 green
  Color(0xFFFFD54F), // 3 yellow
  Color(0xFF64B5F6), // 4 blue
  Color(0xFFCE93D8), // 5 magenta
  Color(0xFF4DD0E1), // 6 cyan
  Color(0xFFE0E0E0), // 7 white
  Color(0xFF2E7D32), // 8 bright black
  Color(0xFFFF8A80), // 9 bright red
  Color(0xFFAED581), // 10 bright green
  Color(0xFFFFE082), // 11 bright yellow
  Color(0xFF82B1FF), // 12 bright blue
  Color(0xFFB388FF), // 13 bright magenta
  Color(0xFF84FFFF), // 14 bright cyan
  Color(0xFFFFFFFF), // 15 bright white
];

/// True when [text] contains any ANSI escape sequence. Pure.
bool containsAnsi(String text) => text.contains('\x1b');

/// Parse [input] into styled spans. [base] seeds the style (the parser
/// returns spans even for plain text — one span, base style). Control
/// sequences that are not SGR are removed from the output.
List<AnsiSpan> parseAnsiSpans(String input, {AnsiStyle? base}) {
  var style = base ?? const AnsiStyle();
  final spans = <AnsiSpan>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isEmpty) return;
    spans.add(AnsiSpan(buf.toString(), style));
    buf.clear();
  }

  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (ch != '\x1b') {
      buf.write(ch);
      i++;
      continue;
    }
    // Escape sequence start.
    if (i + 1 >= input.length) break;
    final next = input[i + 1];
    if (next == '[') {
      // CSI: scan to the final byte (0x40–0x7E).
      var j = i + 2;
      var params = '';
      var finalByte = '';
      while (j < input.length) {
        final c = input[j];
        final code = c.codeUnitAt(0);
        if (code >= 0x40 && code <= 0x7E) {
          finalByte = c;
          j++;
          break;
        }
        params += c;
        j++;
      }
      i = j;
      if (finalByte == 'm') {
        flush();
        style = _applySgr(params, style);
      }
      // Non-SGR CSI: dropped silently.
      continue;
    }
    if (next == ']') {
      // OSC: scan to BEL or ST (ESC \).
      var j = i + 2;
      while (j < input.length) {
        if (input[j] == '\x07') {
          j++;
          break;
        }
        if (input[j] == '\x1b' &&
            j + 1 < input.length &&
            input[j + 1] == '\\') {
          j += 2;
          break;
        }
        j++;
      }
      i = j;
      continue;
    }
    // Other escapes (ESC 7, ESC (B, …): drop the pair.
    i += 2;
  }
  flush();
  return spans;
}

/// Apply one SGR parameter set to [style]. Pure.
AnsiStyle _applySgr(String params, AnsiStyle style) {
  if (params.isEmpty) params = '0';
  final codes = params
      .split(';')
      .map((s) => int.tryParse(s) ?? 0)
      .toList(growable: false);
  var out = style;
  var i = 0;
  while (i < codes.length) {
    final c = codes[i];
    switch (c) {
      case 0:
        out = const AnsiStyle();
        break;
      case 1:
        out = out.copyWith(bold: true, faint: false);
        break;
      case 2:
        out = out.copyWith(faint: true, bold: false);
        break;
      case 3:
        out = out.copyWith(italic: true);
        break;
      case 4:
        out = out.copyWith(underline: true);
        break;
      case 22:
        out = out.copyWith(bold: false, faint: false);
        break;
      case 23:
        out = out.copyWith(italic: false);
        break;
      case 24:
        out = out.copyWith(underline: false);
        break;
      case 39:
        out = out.copyWith(resetFg: true);
        break;
      case 49:
        out = out.copyWith(resetBg: true);
        break;
      case 38:
      case 48:
        // Extended color: 38;5;n (256) or 38;2;r;g;b (24-bit).
        final color = _readExtendedColor(codes, i);
        if (color == null) {
          i = codes.length; // malformed — bail out of this SGR
          break;
        }
        out = out.copyWith(
          fg: c == 38 ? color.color : null,
          bg: c == 48 ? color.color : null,
          resetFg: false,
          resetBg: false,
        );
        i += color.consumed;
        break;
      default:
        if (c >= 30 && c <= 37) {
          out = out.copyWith(fg: ansiBaseColors[c - 30], resetFg: false);
        } else if (c >= 90 && c <= 97) {
          out = out.copyWith(fg: ansiBaseColors[c - 90 + 8], resetFg: false);
        } else if (c >= 40 && c <= 47) {
          out = out.copyWith(bg: ansiBaseColors[c - 40], resetBg: false);
        } else if (c >= 100 && c <= 107) {
          out = out.copyWith(bg: ansiBaseColors[c - 100 + 8], resetBg: false);
        }
        break;
    }
    i++;
  }
  return out;
}

class _ExtendedColor {
  final Color color;
  final int consumed;
  const _ExtendedColor(this.color, this.consumed);
}

/// Parse `5;n` / `2;r;g;b` after the 38/48 code at [index]. Returns null
/// when the sequence is truncated/malformed.
_ExtendedColor? _readExtendedColor(List<int> codes, int index) {
  if (index + 1 >= codes.length) return null;
  final mode = codes[index + 1];
  if (mode == 5) {
    if (index + 2 >= codes.length) return null;
    final n = codes[index + 2].clamp(0, 255);
    return _ExtendedColor(_color256(n), 2);
  }
  if (mode == 2) {
    if (index + 4 >= codes.length) return null;
    return _ExtendedColor(
      Color.fromARGB(
        255,
        codes[index + 2].clamp(0, 255),
        codes[index + 3].clamp(0, 255),
        codes[index + 4].clamp(0, 255),
      ),
      4,
    );
  }
  return null;
}

/// The classic xterm 256-color palette entry. Pure.
Color _color256(int n) {
  if (n < 16) return ansiBaseColors[n];
  if (n < 232) {
    final i = n - 16;
    final r = (i ~/ 36) * 51;
    final g = ((i % 36) ~/ 6) * 51;
    final b = (i % 6) * 51;
    return Color.fromARGB(255, r, g, b);
  }
  final v = 8 + (n - 232) * 10;
  return Color.fromARGB(255, v, v, v);
}

/// Strip all ANSI escape sequences (kept for one-shot compatibility).
/// Pure.
String stripAnsi(String input) {
  final spans = parseAnsiSpans(input);
  return spans.map((s) => s.text).join();
}
