import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/update_service.dart';

void main() {
  group('UpdateService.parseChecksums', () {
    test('parses sha256sum lines with binary markers and paths', () {
      const text = 'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb  cubiclm.apk\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  *./dir/other.apk\n'
          'not-a-hash line\n';
      final sums = UpdateService.parseChecksums(text);
      expect(sums['cubiclm.apk'],
          'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb');
      expect(sums['other.apk'],
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sums.length, 2);
    });

    test('empty input yields empty map', () {
      expect(UpdateService.parseChecksums(''), isEmpty);
    });
  });
}
