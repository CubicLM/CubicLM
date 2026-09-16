import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/error_diagnostics.dart';

void main() {
  group('trimStack', () {
    test('keeps short stacks whole', () {
      const s = '#0 foo (a.dart:1)\n#1 bar (b.dart:2)';
      expect(trimStack(StackTrace.fromString(s)), s);
    });

    test('collapses long stacks with a marker', () {
      final frames = List.generate(518, (i) => '#$i frame$i (f.dart:$i)');
      final out = trimStack(StackTrace.fromString(frames.join('\n')));
      expect(out, contains('#0 frame0'));
      expect(out, contains('#59 frame59'));
      expect(out, isNot(contains('#60 frame60')));
      expect(out, contains('[... 458 more frames]'));
    });

    test('null stack reports cleanly', () {
      expect(trimStack(null), 'No stack');
    });
  });

  group('fullCreatorChain', () {
    testWidgets('walks live ancestors nearest-first', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Row(
                children: [Text('probe')],
              ),
            ],
          ),
        ),
      );
      final el = tester.element(find.text('probe'));
      final details = FlutterErrorDetails(
        exception: Exception('boom'),
        context: DiagnosticsProperty<Element>('ctx', el),
      );
      final chain = fullCreatorChain(details);
      expect(chain, startsWith('Text'));
      expect(chain, contains('Row'));
      expect(chain, contains('Column'));
      expect(chain, isNot(contains('⋯')));
    });

    testWidgets('resolves via collector node when context is bare text',
        (tester) async {
      // The GetX-lint shape: context is an ErrorDescription, the creator
      // element hides in an informationCollector node.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Row(
                children: [Text('probe')],
              ),
            ],
          ),
        ),
      );
      final el = tester.element(find.text('probe'));
      final details = FlutterErrorDetails(
        exception: Exception('lint'),
        context: ErrorDescription('no element here'),
        informationCollector: () => [
          DiagnosticsDebugCreator(DebugCreator(el)),
        ],
      );
      final chain = fullCreatorChain(details);
      expect(chain, startsWith('Text'));
      expect(chain, contains('Row ←'));
      expect(chain, isNot(contains('unresolved')));
    });

    test('reports why resolution failed instead of empty', () {
      const details = FlutterErrorDetails(exception: 'x');
      expect(fullCreatorChain(details), contains('unresolved'));
    });
  });

  group('diagnosticEnv', () {
    testWidgets('reports window facts', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final env = diagnosticEnv();
      expect(env, contains('window:'));
      expect(env, contains('platform:'));
    });
  });
}
