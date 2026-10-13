import 'package:cubiclm/views/device_info_device_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SIM operator display', () {
    test('flagForIso maps ISO codes to flags', () {
      expect(flagForIso('bd'), ' 🇧🇩');
      expect(flagForIso('BD'), ' 🇧🇩');
      expect(flagForIso('us'), ' 🇺🇸');
      expect(flagForIso('in'), ' 🇮🇳');
    });

    test('flagForIso rejects bad input', () {
      expect(flagForIso(null), '');
      expect(flagForIso(''), '');
      expect(flagForIso('b'), '');
      expect(flagForIso('bda'), '');
      expect(flagForIso('12'), '');
    });
  });
}
