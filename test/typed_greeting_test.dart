import 'package:cubiclm/views/chat/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TypedGreeting (shine sweep)', () {
    testWidgets('shows full uppercase line, then advances', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypedGreeting(
              lines: ['Hello friend', 'Second line'],
            ),
          ),
        ),
      );

      // Full first line, uppercased like the pen (text-transform).
      expect(find.text('HELLO FRIEND'), findsOneWidget);

      // Still first line just before the swap.
      await tester.pump(const Duration(milliseconds: 4100));
      expect(find.text('HELLO FRIEND'), findsOneWidget);

      // Fade 300ms + swap: second line takes over.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('SECOND LINE'), findsOneWidget);
    });

    testWidgets('empty lines render without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypedGreeting(lines: [])),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(''), findsOneWidget);
    });
  });
}
