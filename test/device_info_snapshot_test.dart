import 'package:cubiclm/services/device_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceInfoService load snapshot', () {
    test('before/after snapshot round-trips without platform', () {
      final d = DeviceInfoService();
      d.availableRamGB.value = 6.1;
      d.snapshotBeforeLoad('LFM2.5-350M-BF16.gguf');
      expect(d.lastLoadModelName.value, 'LFM2.5-350M-BF16.gguf');
      expect(d.ramBeforeLoadGb.value, 6.1);
      expect(d.ramAfterLoadGb.value, 0);
      // Simulate the post-load refresh result.
      d.availableRamGB.value = 5.4;
      d.ramAfterLoadGb.value = d.availableRamGB.value;
      expect(d.ramAfterLoadGb.value, 5.4);
      expect(
          d.ramBeforeLoadGb.value - d.ramAfterLoadGb.value,
          closeTo(0.7, 0.001));
    });

    test('clearLoadSnapshot resets all fields', () {
      final d = DeviceInfoService();
      d.availableRamGB.value = 6.1;
      d.snapshotBeforeLoad('m.gguf');
      d.ramAfterLoadGb.value = 5.4;
      d.clearLoadSnapshot();
      expect(d.lastLoadModelName.value, isEmpty);
      expect(d.ramBeforeLoadGb.value, 0);
      expect(d.ramAfterLoadGb.value, 0);
    });
  });
}
