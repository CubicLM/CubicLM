import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/terminal/terminal_emulator.dart';
import 'package:cubiclm/services/terminal/terminal_theme.dart';

void main() {
  group('TerminalEmulator — text & cursor', () {
    test('writes plain text and tracks the cursor', () {
      final e = TerminalEmulator(cols: 20, rows: 5);
      e.feed('hello');
      expect(e.screenText(), 'hello');
      expect(e.cursorRow, 0);
      expect(e.cursorCol, 5);
      expect(e.rowAt(0)[0].text, 'h');
    });

    test('CR/LF overwrite and new lines', () {
      final e = TerminalEmulator(cols: 20, rows: 5);
      e.feed('abc\rXY\r\nnext');
      expect(e.screenText(), 'XYc\nnext');
    });

    test('lone LF keeps the column (VT100 semantics)', () {
      final e = TerminalEmulator(cols: 20, rows: 5);
      e.feed('ab\ncd');
      expect(e.screenText(), 'ab\n  cd');
    });

    test('backspace and tab', () {
      final e = TerminalEmulator(cols: 20, rows: 5);
      e.feed('abc\b\tZ');
      expect(e.screenText(), 'abc     Z');
    });

    test('autowrap at the right margin', () {
      final e = TerminalEmulator(cols: 5, rows: 4);
      e.feed('abcdefg');
      expect(e.screenText(), 'abcde\nfg');
      expect(e.cursorRow, 1);
      expect(e.cursorCol, 2);
    });

    test('wide characters occupy two cells', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('你a');
      expect(e.rowAt(0)[0].width, 2);
      expect(e.rowAt(0)[1].width, 0);
      expect(e.rowAt(0)[2].text, 'a');
      expect(e.cursorCol, 3);
    });

    test('combining marks attach to the previous cell', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('e\u0301');
      expect(e.rowAt(0)[0].text, 'e\u0301');
      expect(e.cursorCol, 1);
    });
  });

  group('TerminalEmulator — SGR', () {
    test('16-color foreground/background', () {
      final e = TerminalEmulator(cols: 20, rows: 3);
      e.feed('\x1b[31;44mX\x1b[0mY');
      expect(e.rowAt(0)[0].style.fg, 1);
      expect(e.rowAt(0)[0].style.bg, 4);
      expect(e.rowAt(0)[1].style.fg, -1);
      expect(e.rowAt(0)[1].style.bg, -1);
    });

    test('bold, faint, italic, underline, reverse, strike', () {
      final e = TerminalEmulator(cols: 20, rows: 3);
      e.feed('\x1b[1;2;3;4;7;9mA\x1b[0m');
      final s = e.rowAt(0)[0].style;
      expect(s.bold, isTrue);
      expect(s.faint, isTrue);
      expect(s.italic, isTrue);
      expect(s.underline, isTrue);
      expect(s.reverse, isTrue);
      expect(s.strikethrough, isTrue);
    });

    test('256-color and 24-bit color', () {
      final e = TerminalEmulator(cols: 20, rows: 3);
      e.feed('\x1b[38;5;196mA\x1b[38;2;10;20;30mB');
      expect(e.rowAt(0)[0].style.fg, 196);
      expect(e.rowAt(0)[1].style.fg, 0x1000000 | (10 << 16) | (20 << 8) | 30);
    });

    test('bright colors and resets', () {
      final e = TerminalEmulator(cols: 20, rows: 3);
      e.feed('\x1b[91mA\x1b[39mB\x1b[101mC\x1b[49mD');
      expect(e.rowAt(0)[0].style.fg, 9);
      expect(e.rowAt(0)[1].style.fg, -1);
      expect(e.rowAt(0)[2].style.bg, 9);
      expect(e.rowAt(0)[3].style.bg, -1);
    });
  });

  group('TerminalEmulator — screen operations', () {
    test('erase in line and display', () {
      final e = TerminalEmulator(cols: 10, rows: 4);
      e.feed('abcdef\x1b[3D\x1b[K');
      expect(e.screenText(), 'abc');
      e.feed('\x1b[2J');
      expect(e.screenText(), '');
    });

    test('cursor positioning', () {
      final e = TerminalEmulator(cols: 10, rows: 4);
      e.feed('\x1b[2;3HX');
      expect(e.rowAt(1)[2].text, 'X');
      e.feed('\x1b[HY');
      expect(e.rowAt(0)[0].text, 'Y');
    });

    test('insert and delete lines', () {
      final e = TerminalEmulator(cols: 10, rows: 4);
      e.feed('one\r\ntwo\r\nthree');
      e.feed('\x1b[2;1H\x1b[L');
      expect(e.rowAt(1).first.text.trim(), '');
      expect(e.rowAt(2).first.text, 't');
    });

    test('scroll region only moves the region', () {
      final e = TerminalEmulator(cols: 10, rows: 5);
      e.feed('a\r\nb\r\nc\r\nd\r\ne');
      e.feed('\x1b[2;4r\x1b[4;1H\r\n');
      expect(e.rowAt(0).first.text, 'a');
      expect(e.rowAt(1).first.text, 'c');
      expect(e.rowAt(4).first.text, 'e');
    });

    test('scrollback keeps rows pushed off the top', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('1\r\n2\r\n3\r\n4\r\n5');
      expect(e.scrollback.length, greaterThanOrEqualTo(2));
      expect(e.scrollback.first.first.text, '1');
      expect(e.plainText().contains('5'), isTrue);
    });

    test('alternate screen restores the primary buffer', () {
      final e = TerminalEmulator(cols: 10, rows: 4);
      e.feed('primary');
      e.feed('\x1b[?1049h');
      expect(e.inAltScreen, isTrue);
      e.feed('\x1b[2J\x1b[Halt');
      expect(e.screenText(), 'alt');
      e.feed('\x1b[?1049l');
      expect(e.inAltScreen, isFalse);
      expect(e.screenText(), 'primary');
    });

    test('resize preserves the newest rows', () {
      final e = TerminalEmulator(cols: 10, rows: 5);
      e.feed('a\r\nb\r\nc\r\nd\r\ne');
      e.resize(10, 3);
      expect(e.rows, 3);
      expect(e.screenText(), 'c\nd\ne');
      expect(e.scrollback.length, 2);
    });

    test('origin mode constrains cursor addressing', () {
      final e = TerminalEmulator(cols: 10, rows: 6);
      e.feed('\x1b[2;5r\x1b[?6h\x1b[1;1HX');
      expect(e.rowAt(1)[0].text, 'X');
    });
  });

  group('TerminalEmulator — parser', () {
    test('OSC title is reported and stripped', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      String? title;
      e.onTitle = (t) => title = t;
      e.feed('\x1b]0;my shell\x07ok');
      expect(title, 'my shell');
      expect(e.screenText(), 'ok');
    });

    test('device status report answers with the cursor position', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      String? reply;
      e.onResponse = (r) => reply = r;
      e.feed('\x1b[2;4H\x1b[6n');
      expect(reply, '\x1b[2;4R');
    });

    test('DEC special graphics render line drawing', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('\x1b(0q\x1b(B');
      expect(e.rowAt(0)[0].text, '─');
    });

    test('bracketed paste mode is tracked', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      expect(e.bracketedPaste, isFalse);
      e.feed('\x1b[?2004h');
      expect(e.bracketedPaste, isTrue);
      e.feed('\x1b[?2004l');
      expect(e.bracketedPaste, isFalse);
    });

    test('cursor style (DECSCUSR)', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('\x1b[4 q');
      expect(e.cursorStyle, TerminalCursorStyle.underline);
      expect(e.cursorBlink, isFalse);
      e.feed('\x1b[6 q');
      expect(e.cursorStyle, TerminalCursorStyle.bar);
    });

    test('clear resets the screen and scrollback', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('1\r\n2\r\n3\r\n4');
      e.clear();
      expect(e.screenText(), '');
      expect(e.scrollback, isEmpty);
      expect(e.cursorRow, 0);
      expect(e.cursorCol, 0);
    });
  });

  group('TerminalTheme', () {
    test('Termux default colors are exact', () {
      const t = TerminalTheme.termux;
      expect(t.background.toARGB32(), 0xFF000000);
      expect(t.foreground.toARGB32(), 0xFFFFFFFF);
      expect(t.colors[1].toARGB32(), 0xFFCD0000);
      expect(t.colors[2].toARGB32(), 0xFF00CD00);
      expect(t.colors[4].toARGB32(), 0xFF6495ED);
      expect(t.colors[15].toARGB32(), 0xFFFFFFFF);
    });

    test('bold brightens the first eight foreground colors', () {
      const t = TerminalTheme.termux;
      expect(t.resolve(1, foreground: true).toARGB32(), t.colors[1].toARGB32());
      expect(t.resolve(1, foreground: true, bold: true).toARGB32(),
          t.colors[9].toARGB32());
    });

    test('256-color cube and grayscale', () {
      const t = TerminalTheme.termux;
      expect(t.indexed(196).toARGB32(), 0xFFFF0000);
      expect(t.indexed(232).toARGB32(), 0xFF080808);
      expect(t.indexed(255).toARGB32(), 0xFFEEEEEE);
    });

    test('24-bit colors resolve exactly', () {
      const t = TerminalTheme.termux;
      const spec = 0x1000000 | (0x12 << 16) | (0x34 << 8) | 0x56;
      expect(t.resolve(spec, foreground: true).toARGB32(), 0xFF123456);
    });

    test('256 cube matches Termux byte-for-byte', () {
      const t = TerminalTheme.termux;
      // Termux uses 0/95/135/175/215/255, not a linear 51-step ramp.
      expect(t.indexed(17).toARGB32(), 0xFF00005F);
      expect(t.indexed(18).toARGB32(), 0xFF000087);
      expect(t.indexed(80).toARGB32(), 0xFF5FD7D7);
    });

    test('OSC colors parse all Termux formats', () {
      expect(TerminalPalette.parseColor('#f00'), 0xFFFF0000);
      expect(TerminalPalette.parseColor('#ff0000'), 0xFFFF0000);
      expect(TerminalPalette.parseColor('rgb:f/f/0'), 0xFFFFFF00);
      expect(TerminalPalette.parseColor('rgb:ffff/0000/0000'), 0xFFFF0000);
      expect(TerminalPalette.parseColor('red'), isNull);
    });
  });

  group('Termux protocol fidelity', () {
    test('OSC 4 recolors palette and answers queries', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      final palette = TerminalPalette(TerminalTheme.termux);
      e.bindPalette(palette);
      String? reply;
      e.onResponse = (r) => reply = r;
      e.feed('\x1b]4;1;#123456\x07');
      expect(palette.indexed(1).toARGB32(), 0xFF123456);
      e.feed('\x1b]4;1;?\x07');
      expect(reply, '\x1b]4;1;rgb:1212/3434/5656\x07');
      e.feed('\x1b]104;1\x07');
      expect(palette.indexed(1).toARGB32(),
          TerminalTheme.termux.colors[1].toARGB32());
    });

    test('OSC 10/11/12 query and reset', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      final palette = TerminalPalette(TerminalTheme.termux);
      e.bindPalette(palette);
      String? reply;
      e.onResponse = (r) => reply = r;
      e.feed('\x1b]11;#0000ff\x07');
      expect(palette.background.toARGB32(), 0xFF0000FF);
      e.feed('\x1b]11;?\x07');
      expect(reply, '\x1b]11;rgb:0000/0000/ffff\x07');
      e.feed('\x1b]111\x07');
      expect(palette.background.toARGB32(), 0xFF000000);
    });

    test('device attribute replies match Termux', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      String? reply;
      e.onResponse = (r) => reply = r;
      e.feed('\x1b[c');
      expect(reply, '\x1b[?64;1;2;4;6;9;15;18;21;22c');
      e.feed('\x1b[>c');
      expect(reply, '\x1b[>41;320;0c');
      e.feed('\x1b[2;4H\x1b[?6n');
      expect(reply, '\x1b[?2;4;1R');
    });

    test('focus reporting follows DEC mode 1004', () {
      final emu = TerminalEmulator();
      final out = <String>[];
      emu.onResponse = out.add;
      emu.sendFocusEvent(true);
      expect(out, isEmpty);

      emu.feed('\x1b[?1004h');
      // Enabling the mode reports the current focused state, like xterm.
      expect(out, ['\x1b[I']);

      out.clear();
      emu.sendFocusEvent(true);
      emu.sendFocusEvent(false);
      expect(out, ['\x1b[I', '\x1b[O']);

      out.clear();
      emu.feed('\x1b[?1004l');
      emu.sendFocusEvent(true);
      expect(out, isEmpty);
    });

    test('DEC mouse modes and SGR reporting', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('\x1b[?1000;1006h');
      expect(e.mouseTrackingEnabled, isTrue);
      expect(e.mouseSgrProtocol, isTrue);
      String? reply;
      e.onResponse = (r) => reply = r;
      e.sendMouseEvent(0, 3, 2);
      expect(reply, '\x1b[<0;3;2M');
      e.sendMouseEvent(0, 3, 2, pressed: false);
      expect(reply, '\x1b[<0;3;2m');
      e.feed('\x1b[?1000l');
      expect(e.mouseTrackingEnabled, isFalse);
    });

    test('DEC private modes 5, 66 and 2004', () {
      final e = TerminalEmulator(cols: 10, rows: 3);
      e.feed('\x1b[?5h\x1b[?66h\x1b[?2004h');
      expect(e.reverseVideo, isTrue);
      expect(e.applicationKeypad, isTrue);
      expect(e.bracketedPaste, isTrue);
      e.feed('\x1b[?5l');
      expect(e.reverseVideo, isFalse);
    });

    test('OSC 8 hyperlinks are stored per cell', () {
      final e = TerminalEmulator(cols: 20, rows: 3);
      e.feed('\x1b]8;;https://example.com\x07link\x1b]8;;\x07');
      expect(e.rowAt(0)[0].style.link, 'https://example.com');
      expect(e.rowAt(0)[3].style.link, 'https://example.com');
      expect(e.rowAt(0)[4].style.link, isNull);
    });
  });

  group('TermuxKeys', () {
    test('modifier mapping is exact', () {
      expect(TermuxKeys.modifier(), 1);
      expect(TermuxKeys.modifier(shift: true), 2);
      expect(TermuxKeys.modifier(alt: true), 3);
      expect(TermuxKeys.modifier(shift: true, alt: true), 4);
      expect(TermuxKeys.modifier(ctrl: true), 5);
      expect(TermuxKeys.modifier(shift: true, ctrl: true), 6);
      expect(TermuxKeys.modifier(alt: true, ctrl: true), 7);
      expect(TermuxKeys.modifier(shift: true, alt: true, ctrl: true), 8);
    });

    test('arrows, functions and control chars', () {
      expect(TermuxKeys.arrow('A', cursorApp: false), '\x1b[A');
      expect(TermuxKeys.arrow('A', cursorApp: true), '\x1bOA');
      expect(TermuxKeys.arrow('A', cursorApp: false, ctrl: true), '\x1b[1;5A');
      expect(
          TermuxKeys.arrow('A',
              cursorApp: false, shift: true, alt: true, ctrl: true),
          '\x1b[1;8A');
      expect(TermuxKeys.functionKey(1), '\x1bOP');
      expect(TermuxKeys.functionKey(5, ctrl: true), '\x1b[15;5~');
      expect(TermuxKeys.backspace(ctrl: true), '\x08');
      expect(TermuxKeys.backspace(alt: true), '\x1b\x7f');
      expect(TermuxKeys.tab(shift: true), '\x1b[Z');
      expect(TermuxKeys.ctrl('c'), '\x03');
      expect(TermuxKeys.keypadApplication['7'], '\x1bOw');
    });
  });
}
