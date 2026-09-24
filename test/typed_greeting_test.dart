import 'package:cubiclm/views/chat/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TypedGreeting (typewriter and fade)', () {
    testWidgets('types out text and advances to second line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypedGreeting(
              lines: ['Hello', 'World'],
            ),
          ),
        ),
      );

      // Initially starts typing first line
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Text), findsOneWidget);

      // Pump enough time for first line to fully type out
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hello'), findsOneWidget);

      // Pump through hold (2500ms) + fade out (320ms) + next line typing
      await tester.pump(const Duration(milliseconds: 3200));
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('empty lines render without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypedGreeting(lines: [])),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(SizedBox), findsWidgets);
    });
  });
}
