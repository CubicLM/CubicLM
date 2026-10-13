import 'package:cubiclm/views/device_info_report.dart';
import 'package:cubiclm/views/device_info_search.dart';
import 'package:cubiclm/views/device_info_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('device info search', () {
    test('empty query returns no hits', () {
      expect(searchDeviceInfo('   '), isEmpty);
    });

    test('sim finds the Device SIM section', () {
      final hits = searchDeviceInfo('sim');
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.tab == 1), isTrue);
    });

    test('benchmark finds the Category tab', () {
      final hits = searchDeviceInfo('benchmark');
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.tab == 13), isTrue);
    });

    test('wifi finds the Network tab', () {
      final hits = searchDeviceInfo('wifi');
      expect(hits, isNotEmpty);
      expect(hits.any((h) => h.tab == 5), isTrue);
    });

    test('battery spans Dashboard and Battery tabs', () {
      final tabs =
          searchDeviceInfo('battery').map((h) => h.tab).toSet();
      expect(tabs, containsAll([0, 4]));
    });

    test('thermal finds only the Thermal tab', () {
      final hits = searchDeviceInfo('thermal');
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.tab == 11), isTrue);
    });

    test('tab names resolve', () {
      expect(deviceInfoTabName(0), 'Dashboard');
      expect(deviceInfoTabName(13), 'Category');
      expect(deviceInfoTabName(99), 'Device Info');
    });
  });

  group('device report', () {
    test('contains labels and values', () {
      final r = buildDeviceReport(
        deviceLabel: 'Pixel 8',
        processor: 'Tensor G3',
        androidRelease: '14',
        ramTotalGb: 8.0,
        ramAvailGb: 3.5,
        storageTotalGb: 128,
        storageFreeGb: 64,
        batteryLevel: 80,
        appCount: 120,
        sensorCount: 15,
        cameraCount: 3,
      );
      expect(r, contains('Pixel 8'));
      expect(r, contains('Tensor G3'));
      expect(r, contains('8.0 GB total, 3.5 GB free'));
      expect(r, contains('64 GB free of 128 GB'));
      expect(r, contains('80%'));
      expect(r, contains('Apps: 120'));
    });
  });

  group('DeferredBuild', () {
    testWidgets('shows placeholder first, content after a frame',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: DeferredBuild(
          builder: _content,
        ),
      ));
      expect(find.byType(CircularProgressIndicator),
          findsOneWidget);
      expect(find.text('content'), findsNothing);
      await t.pump();
      expect(find.text('content'), findsOneWidget);
    });
  });
}

Widget _content(BuildContext _) => const Text('content');
