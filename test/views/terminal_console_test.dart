// TerminalConsole smoke coverage: the grid, ANSI attributes, wide glyphs
// and OSC 8 links must paint without layout or paint exceptions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/terminal/terminal_emulator.dart';
import 'package:cubiclm/services/terminal/terminal_theme.dart';
import 'package:cubiclm/views/terminal/terminal_console.dart';

void main() {
  testWidgets('paints ANSI, 256/RGB colors, wide glyphs and links',
      (tester) async {
    final emu = TerminalEmulator(cols: 80, rows: 24);
    final palette = TerminalPalette(TerminalTheme.termux);
    emu.bindPalette(palette);
    emu.feed('\x1b[1;31mred\x1b[0m '
        '\x1b[38;5;196m256\x1b[0m '
        '\x1b[38;2;1;2;3mtruecolor\x1b[0m\r\n');
    emu.feed('CJK 世界 emoji 😀 combining e\u0301\r\n');
    emu.feed('\x1b]8;;https://example.com\x07link\x1b]8;;\x07\r\n');
    emu.feed('\x1b[?1049h\x1b[2J\x1b[Halt screen\x1b[?1049l');

    int? resizedCols;
    int? resizedRows;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: TerminalConsole(
            emulator: emu,
            palette: palette,
            onResize: (cols, rows) {
              resizedCols = cols;
              resizedRows = rows;
            },
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 32));

    expect(tester.takeException(), isNull);
    expect(resizedCols, isNotNull);
    expect(resizedRows, isNotNull);
    expect(resizedCols!, greaterThan(20));
    expect(resizedRows!, greaterThan(5));
    expect(emu.rowAt(0)[0].text, 'r');
    expect(emu.rowAt(0)[0].style.bold, isTrue);

    // DECSCNM must invert the page background, not just cell colors.
    emu.feed('\x1b[?5h');
    await tester.pump();
    final page = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(TerminalConsole),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(page.color, palette.foreground);
    emu.feed('\x1b[?5l');
    await tester.pump();
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(TerminalConsole),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      palette.background,
    );

    // Dispose the periodic cursor timer with the widget.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
