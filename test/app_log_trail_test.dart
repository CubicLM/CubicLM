import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/app_log_service.dart';

void main() {
  group('AppLogService action trail', () {
    test('records newest-first and caps at maxTrailActions', () {
      final log = AppLogService();
      for (var i = 0; i < AppLogService.maxTrailActions + 10; i++) {
        log.trail('action $i');
      }
      expect(log.actionTrail.length, AppLogService.maxTrailActions);
      expect(log.actionTrail.first, contains('action 39'));
      expect(log.actionTrail.last, contains('action 10'));
    });

    test('ignores blank actions and never throws', () {
      final log = AppLogService();
      log.trail('   ');
      log.trail('');
      expect(log.actionTrail, isEmpty);
    });

    test('health summary lists recent actions', () {
      final log = AppLogService();
      log.trail('agent run finished');
      log.trail('project exported (ZIP)');
      final summary = log.healthSummary;
      expect(summary, contains('Recent actions:'));
      expect(summary, contains('agent run finished'));
      expect(summary, contains('project exported (ZIP)'));
    });
  });

  group('LogCategory lanes', () {
    test('new lanes round-trip through JSON by name', () {
      for (final cat in [
        LogCategory.agent,
        LogCategory.runtime,
        LogCategory.terminal,
        LogCategory.update,
      ]) {
        final back = AppLogEntry.fromJson(
          AppLogEntry(
            level: 'INFO',
            message: 'm',
            category: cat,
          ).toJson(),
        );
        expect(back.category, cat);
      }
    });

    test('unknown stored category falls back to system', () {
      final back = AppLogEntry.fromJson({
        't': DateTime.now().toIso8601String(),
        'l': 'INFO',
        'm': 'm',
        'c': 'no_such_lane',
      });
      expect(back.category, LogCategory.system);
    });
  });

  group('diagnosisFor', () {
    AppLogEntry overflowRow() => AppLogEntry(
          level: 'ERROR',
          message: 'A RenderFlex overflowed by 4.3 pixels on the right.\n'
              'debugCreator: Row ← Padding ← ⋯\n'
              '--- full widget path (nearest first) ---\n'
              'Row ← _CountStepper ← SlideDeckView\n'
              '--- environment ---\n'
              'window: 393x851 logical (portrait)',
          details: '#0 foo (a.dart:1)\n#1 bar (b.dart:2)',
          category: LogCategory.system,
          screen: 'Slide Maker',
        );

    test('packs path, env, screen, stack and actions', () {
      final log = AppLogService();
      log.trail('opened slide maker');
      final out = log.diagnosisFor(overflowRow());
      expect(out, contains('### CubicLM issue report'));
      expect(out, contains('Row ← _CountStepper ← SlideDeckView'));
      expect(out, contains('window: 393x851'));
      expect(out, contains('Slide Maker'));
      expect(out, contains('opened slide maker'));
      expect(out, contains('#0 foo (a.dart:1)'));
    });

    test('scrubs secrets before paste', () {
      final log = AppLogService();
      final out = log.diagnosisFor(AppLogEntry(
        level: 'ERROR',
        message: 'request failed sk-ant-secret12345xyz end',
        category: LogCategory.cloud,
      ));
      expect(out, isNot(contains('sk-ant-secret12345xyz')));
    });

    test('agent variant carries fixer instructions', () {
      final log = AppLogService();
      final out = log.diagnosisFor(overflowRow(), forAgent: true);
      expect(out, contains('CubicLM Flutter codebase'));
      expect(out, contains('Row ← _CountStepper'));
    });
  });

  group('LogRouteObserver', () {
    test('labels routes friendly', () {
      expect(LogRouteObserver.labelOf(null), 'null');
      expect(
        LogRouteObserver.labelOf(
          MaterialPageRoute(
            builder: (_) => const SizedBox(),
            settings: const RouteSettings(name: '/home'),
          ),
        ),
        'Page(/home)',
      );
      expect(
        LogRouteObserver.labelOf(
          MaterialPageRoute(builder: (_) => const SizedBox()),
        ),
        'Page',
      );
    });

    test('route trail caps and shows in health summary', () {
      final log = AppLogService();
      for (var i = 0; i < 20; i++) {
        log.trailRoute('→ Page(/p$i)');
      }
      expect(log.routeTrail.length, AppLogService.maxTrailRoutes);
      expect(log.routeTrail.first, contains('/p19'));
      expect(log.healthSummary, contains('Recent routes:'));
    });

    testWidgets('didPush records friendly sheet label', (tester) async {
      final log = AppLogService();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [
            _TestObserver(log),
          ],
          home: Builder(builder: (context) {
            Future.microtask(() => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(),
                ));
            return const SizedBox();
          }),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        log.routeTrail.any((r) => r.contains('BottomSheet')),
        isTrue,
      );
    });
  });
}

class _TestObserver extends NavigatorObserver {
  final AppLogService log;
  _TestObserver(this.log);

  @override
  void didPush(Route route, Route? previousRoute) {
    log.trailRoute('→ ${LogRouteObserver.labelOf(route)}');
    super.didPush(route, previousRoute);
  }
}
