import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/slide_deck.dart';
import 'package:cubiclm/utils/slide_palette.dart';
import 'package:cubiclm/views/slides/slide_canvas.dart';
import 'package:cubiclm/views/slides/slide_present_view.dart';

/// Shared renderer: every layout (both themes, both modes) must build
/// without throwing. Pure widget pumps — no controllers, no platform.
void main() {
  Slide base(String layout) => Slide(
        title: 'Title $layout',
        subtitle: 'Subtitle',
        points: const ['Alpha: 1', 'Beta: 2', 'Gamma: 3'],
        layout: layout,
        imagePrompt: 'a mountain',
        notes: 'note',
        quoteAuthor: 'Author',
        columns: const [
          ['a1', 'a2'],
          ['b1', 'b2']
        ],
        stats: const [
          {'value': '99%', 'label': 'done'}
        ],
        chartData: {
          'type': 'bar',
          'items': [
            {'label': 'A', 'value': '10'},
            {'label': 'B', 'value': '20'},
          ]
        },
        diagram: 'A --> B',
        speakerNotes: 'Say it slowly.',
      );

  Future<void> pumpCanvas(
    WidgetTester tester,
    Slide slide,
    SlidePalette pal, {
    bool interactive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideCanvas(
            slide: slide,
            index: 0,
            pal: pal,
            interactive: interactive,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final themeName in ['Modern Terracotta', 'Paper']) {
    group('SlideCanvas [$themeName]', () {
      late SlidePalette pal;
      setUpAll(() {
        pal = SlidePalette.fromTheme(
            SlideThemePresets.byName(themeName));
      });

      for (final layout in [
        'title',
        'bullets',
        'image',
        'quote',
        'comparison',
        'stats',
        'timeline',
        'summary',
        'chart',
        'diagram',
      ]) {
        testWidgets('layout $layout builds', (tester) async {
          await pumpCanvas(tester, base(layout), pal);
          // Quote layout leads with the first point, not the title.
          expect(
            find.textContaining(
                layout == 'quote' ? 'Alpha' : 'Title'),
            findsWidgets,
          );
        });
      }

      testWidgets('freeLayout builds in both modes', (tester) async {
        final s = base('bullets')..freeLayout = true;
        await pumpCanvas(tester, s, pal, interactive: true);
        await pumpCanvas(tester, s, pal, interactive: false);
      });

      testWidgets('donut + line charts build', (tester) async {
        for (final type in ['donut', 'line']) {
          final s = base('chart');
          s.chartData = {
            'type': type,
            'items': [
              {'label': 'A', 'value': '10'},
              {'label': 'B', 'value': '20'},
            ]
          };
          await pumpCanvas(tester, s, pal);
        }
      });

      // Phone-width regression (Redmi 360px → 66px bottom overflow):
      // tall fixed layouts must scale down, never overflow. Framework
      // overflow errors fail the test automatically; takeException
      // asserts nothing was thrown either.
      testWidgets('tall fixed layouts fit a 330px canvas', (tester) async {
        for (final layout in [
          'timeline',
          'comparison',
          'stats',
          'bullets',
          'summary',
          'table',
        ]) {
          final s = Slide(
            title: 'A fairly long slide title that wraps onto two lines',
            subtitle: '',
            points: List.generate(
                8,
                (i) =>
                    'Point number $i with enough words to wrap onto multiple lines of body text'),
            layout: layout,
            imagePrompt: '',
            notes: '',
            quoteAuthor: '',
            columns: [
              List.generate(
                  4, (i) => 'Left item $i with wrapping text here'),
              List.generate(
                  4, (i) => 'Right item $i with wrapping text here'),
            ],
            stats: List.generate(
                3, (i) => {'value': '99%', 'label': 'A longish label $i'}),
            tableData: List.generate(
                5, (r) => List.generate(3, (c) => 'Cell $r-$c text')),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 330,
                    child: SlideCanvas(
                      slide: s,
                      index: 0,
                      pal: pal,
                      interactive: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    });
  }

  group('SlidePresentView.stepIndex', () {
    test('clamps at both ends', () {
      expect(SlidePresentView.stepIndex(0, 5, -1), 0);
      expect(SlidePresentView.stepIndex(4, 5, 1), 4);
      expect(SlidePresentView.stepIndex(2, 5, 1), 3);
      expect(SlidePresentView.stepIndex(2, 5, -1), 1);
      expect(SlidePresentView.stepIndex(0, 0, 1), 0);
    });
  });
}
