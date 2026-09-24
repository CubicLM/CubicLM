import 'package:cubiclm/controllers/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  group('ProfileController pure helpers', () {
    test('initialsFor builds initials', () {
      expect(ProfileController.initialsFor('Abir Hasan'), 'AH');
      expect(ProfileController.initialsFor('  abir   hasan siam '), 'AS');
      expect(ProfileController.initialsFor('Siam'), 'S');
      expect(ProfileController.initialsFor(''), 'C');
      expect(ProfileController.initialsFor('   '), 'C');
    });

    test('greetingFor is time-based and uses first name', () {
      expect(
          ProfileController.greetingFor(
              'Abir Hasan', DateTime(2026, 1, 1, 9)),
          'Good morning, Abir');
      expect(
          ProfileController.greetingFor(
              'Abir Hasan', DateTime(2026, 1, 1, 14)),
          'Good afternoon, Abir');
      expect(
          ProfileController.greetingFor(
              'Abir Hasan', DateTime(2026, 1, 1, 20)),
          'Good evening, Abir');
      expect(ProfileController.greetingFor('', DateTime(2026, 1, 1, 9)),
          'Good morning');
    });

    test('profession and avatar option lists are non-empty', () {
      expect(ProfileController.professions, contains('Student'));
      expect(ProfileController.professions, contains('Developer'));
      expect(ProfileController.professions.length, greaterThan(5));
      expect(ProfileController.avatars.length, greaterThan(5));
      expect(ProfileController.avatarColors.length, greaterThan(3));
    });
  });

  group('ProfileController without Hive', () {
    test('degrades to defaults and stays in memory', () async {
      Get.testMode = true;
      final c = ProfileController();
      expect(c.hasName, isFalse);
      expect(c.initials, 'C');
      await c.saveName('  Tester ');
      expect(c.name.value, 'Tester');
      expect(c.hasName, isTrue);
      expect(c.initials, 'T');
      await c.setProfession('Student');
      expect(c.profession.value, 'Student');
      await c.setAvatar('🦊', 2);
      expect(c.avatar.value, '🦊');
      expect(c.avatarColor.value, 2);
      expect(c.safeAvatarColor, 2);
      Get.reset();
    });

    test('ignores blank names', () async {
      Get.testMode = true;
      final c = ProfileController();
      await c.saveName('   ');
      expect(c.hasName, isFalse);
      Get.reset();
    });
  });
}
