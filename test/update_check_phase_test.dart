import 'package:cubiclm/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  group('UpdateService check-phase state', () {
    test('idle defaults (no check running)', () {
      Get.testMode = true;
      final svc = UpdateService();
      expect(svc.isChecking.value, isFalse);
      expect(svc.checkPhase.value, 0);
      expect(svc.checkStepText.value, isEmpty);
      expect(svc.lastCheckLabel.value, isEmpty);
      Get.reset();
    });
  });
}
