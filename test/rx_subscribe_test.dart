import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Proves which Rx read shapes actually subscribe an Obx (no
/// improper-use throw) — the browser menu sheet lint hunt.
void main() {
  testWidgets('RxList.any subscribes', (tester) async {
    final list = <String>[].obs;
    var builds = 0;
    FlutterError.onError = (_) {};
    await tester.pumpWidget(
      MaterialApp(home: Obx(() {
        builds++;
        return Text(list.any((e) => e == 'x') ? 'y' : 'n');
      })),
    );
    await tester.pump();
    list.add('x');
    await tester.pump();
    expect(builds, 2, reason: '.any() must subscribe');
  });

  testWidgets('RxList.isEmpty subscribes', (tester) async {
    final list = <String>[].obs;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(home: Obx(() {
        builds++;
        return Text(list.isEmpty ? 'e' : 'f');
      })),
    );
    await tester.pump();
    list.add('x');
    await tester.pump();
    expect(builds, 2, reason: '.isEmpty must subscribe');
  });

  testWidgets('plain getter does NOT subscribe (lint shape)', (tester) async {
    var errors = 0;
    final prev = FlutterError.onError;
    FlutterError.onError = (_) => errors++;
    try {
      String plain() => 'static';
      await tester.pumpWidget(
        MaterialApp(home: Obx(() => Text(plain()))),
      );
      await tester.pump();
    } finally {
      FlutterError.onError = prev;
    }
    expect(errors, greaterThan(0),
        reason: 'empty Obx must report improper use');
  });

  testWidgets('subscribe-first helper never lints, even for empty input',
      (tester) async {    // Mirrors SettingsController.isBookmarked after the fix: snapshot the
    // observable BEFORE the plain early-return so blank-tab menu sheets
    // still subscribe.
    final items = <Map<String, String>>[].obs;
    bool helper(String url) {
      final snapshot = items.toList();
      final u = url.trim();
      if (u.isEmpty) return false;
      return snapshot.any((b) => b['url'] == u);
    }

    var errors = 0;
    final prev = FlutterError.onError;
    FlutterError.onError = (_) => errors++;
    try {
      await tester.pumpWidget(
        MaterialApp(home: Obx(() => Text(helper('') ? 'y' : 'n'))),
      );
      await tester.pump();
      items.add({'url': 'https://x.com'});
      await tester.pump();
    } finally {
      FlutterError.onError = prev;
    }
    expect(errors, 0);
  });

  testWidgets('map-miss early return inside Obx still subscribes',
      (tester) async {
    // Mirrors _ramFitDot after the fix: the size lookup lives INSIDE the
    // builder so a missing key still subscribes (no lint) and the dot
    // pops in live when the size lands.
    final sizes = <String, int>{}.obs;
    Widget dot(String name) {
      return Obx(() {
        int bytes = 0;
        try {
          bytes = sizes[name] ?? 0;
        } catch (_) {}
        if (bytes <= 0) return const SizedBox.shrink();
        return Text('$bytes');
      });
    }

    var errors = 0;
    final prev = FlutterError.onError;
    FlutterError.onError = (_) => errors++;
    try {
      await tester.pumpWidget(
        MaterialApp(
            home: Column(children: [
          Row(children: [dot('m.gguf')])
        ])),
      );
      await tester.pump();
      expect(errors, 0);
      expect(find.text('100'), findsNothing);
      sizes['m.gguf'] = 100;
      await tester.pump();
      expect(find.text('100'), findsOneWidget);
      expect(errors, 0);
    } finally {
      FlutterError.onError = prev;
    }
  });
}
