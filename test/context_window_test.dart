import 'package:cubiclm/views/chat/chat_bars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContextWindowData.local', () {
    test('computes progress, labels and warn flag', () {
      const d = ContextWindowData(
        isLocal: true,
        used: 380,
        total: 512,
        progress: 0,
        label: '',
        value: '',
        warn: false,
      );
      expect(d.shortfall, '380 / 512');
      expect(d.percentLabel, '0%');
    });

    test('local() clamps and formats', () {
      final d = ContextWindowData.local(used: 410, total: 512);
      expect(d.progress, closeTo(0.8, 0.01));
      expect(d.warn, isTrue);
      expect(d.value, contains('tokens'));
      expect(d.label, 'Local Context Window');
      expect(d.percentLabel, '80%');
    });

    test('local() clamps overflow to 100%', () {
      final d = ContextWindowData.local(used: 900, total: 512);
      expect(d.progress, 1.0);
      expect(d.used, 512);
      expect(d.warn, isTrue);
    });

    test('local() guards zero total', () {
      final d = ContextWindowData.local(used: 0, total: 0);
      expect(d.progress, 0);
      expect(d.total, 1);
    });

    test('cloud() has no total and never warns', () {
      final d = ContextWindowData.cloud(
        providerLabel: 'OpenRouter',
        modelName: 'x/y',
        sessionTokens: 1234,
      );
      expect(d.isLocal, isFalse);
      expect(d.total, -1);
      expect(d.warn, isFalse);
      expect(d.label, contains('OpenRouter'));
      expect(d.value, contains('session tokens'));
    });
  });
}
