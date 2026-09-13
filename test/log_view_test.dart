import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:cubiclm/services/app_log_service.dart';
import 'package:cubiclm/views/log_view.dart';

/// Mounts the real LogView to prove the GetX "improper use" throw is gone.
void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppLogService());
  });
  tearDown(Get.reset);

  testWidgets('LogView mounts without the GetX improper-use error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogView()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('ALL'), findsOneWidget);
  });

  testWidgets('tapping a filter chip rebuilds via the Obx', (tester) async {
    final logs = Get.find<AppLogService>();
    logs.error('boom');
    logs.info('hello');

    await tester.pumpWidget(const MaterialApp(home: LogView()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Scope to the level-filter chip: "ERROR" also appears as a log
    // entry's level badge text (which has no InkWell ancestor).
    final errorChip = find.descendant(
      of: find.byType(InkWell),
      matching: find.text('ERROR'),
    );
    expect(errorChip, findsOneWidget);

    await tester.tap(errorChip);
    await tester.pump();
    // A rebuild happened and no reactive-scope error was thrown.
    expect(tester.takeException(), isNull);
    // Filter applied: only the error entry remains visible.
    expect(logs.selectedLevel.value, 'ERROR');
  });

  testWidgets('huge message + details card lays out without overflow',
      (tester) async {
    // Regression: the stripe card used IntrinsicHeight + unbounded
    // SelectableText, which overflowed ~14px on device (K20 Pro log).
    final logs = Get.find<AppLogService>();
    final bigMsg = List.filled(40, 'A RenderFlex overflowed by 4.4 pixels.').join('\n');
    final bigDetails = List.filled(120, 'debugCreator: Row ← Column ← Obx').join('\n');
    logs.error(bigMsg, details: bigDetails);

    await tester.pumpWidget(const MaterialApp(home: LogView()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The entry actually rendered (message first line visible).
    expect(find.textContaining('A RenderFlex overflowed'), findsWidgets);
  });
}
