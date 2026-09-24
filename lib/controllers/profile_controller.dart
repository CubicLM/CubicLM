import 'package:get/get.dart';

import '../core/constants.dart';
import '../services/hive_service.dart';

/// User profile: name (mandatory at first setup), profession, avatar.
/// Own tiny controller so Chat/Hub/sidebar share one reactive source.
/// Degrades to in-memory defaults when Hive is unavailable (tests).
class ProfileController extends GetxController {
  final name = ''.obs;
  final profession = ''.obs;
  final avatar = '😎'.obs;
  final avatarColor = 0.obs;
  final setupAt = 0.obs; // epoch ms of first setup (0 = unknown)

  /// Fixed profession options shown as chips on the Profile tab.
  static const professions = <String>[
    'Student',
    'Developer',
    'Designer',
    'Engineer',
    'Doctor',
    'Teacher',
    'Researcher',
    'Writer',
    'Business',
    'Marketing',
    'Gamer',
    'Other',
  ];

  /// Avatar emoji choices for the picker.
  static const avatars = <String>[
    '😎',
    '🦊',
    '🐼',
    '🦁',
    '🐸',
    '🤖',
    '🧑‍💻',
    '🧑‍🎨',
    '🚀',
    '⭐',
    '🎮',
    '🐱',
  ];

  /// Avatar ring colors (ARGB) matching the picker swatches.
  static const avatarColors = <int>[
    0xFF6C5CE7,
    0xFF00B894,
    0xFFE17055,
    0xFF0984E3,
    0xFFE84393,
    0xFFFDCB6E,
    0xFF00CEC9,
    0xFFD63031,
  ];

  HiveService? get _hive {
    try {
      return Get.find<HiveService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  /// Re-read everything from disk (used after onboarding saves).
  void reload() {
    try {
      final h = _hive;
      if (h == null) return;
      name.value = h.getSetting<String>(AppConstants.keyUserName) ?? '';
      profession.value =
          h.getSetting<String>(AppConstants.keyUserProfession) ?? '';
      avatar.value =
          h.getSetting<String>(AppConstants.keyUserAvatar) ?? '😎';
      avatarColor.value =
          h.getSetting<int>(AppConstants.keyUserAvatarColor) ?? 0;
      setupAt.value =
          h.getSetting<int>(AppConstants.keyProfileSetupAt) ?? 0;
    } catch (_) {}
  }

  bool get hasName => name.value.trim().isNotEmpty;

  /// "AB" for "Abir Hasan" — avatar fallback + sidebar identity.
  static String initialsFor(String raw) {
    final parts =
        raw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) {
      final p = parts.first;
      return p.length == 1 ? p.toUpperCase() : p.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get initials => initialsFor(name.value);

  int get safeAvatarColor {
    final i = avatarColor.value;
    if (i < 0 || i >= avatarColors.length) return 0;
    return i;
  }

  /// Time-based greeting used on the Dashboard tab. Pure for tests.
  static String greetingFor(String rawName, DateTime now) {
    final first = rawName.trim().split(RegExp(r'\s+')).firstWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );
    final suffix = first.isEmpty ? '' : ', $first';
    final h = now.hour;
    if (h < 12) return 'Good morning$suffix';
    if (h < 17) return 'Good afternoon$suffix';
    return 'Good evening$suffix';
  }

  String greetingNow() => greetingFor(name.value, DateTime.now());

  Future<void> saveName(String raw) async {
    final v = raw.trim();
    if (v.isEmpty) return;
    name.value = v;
    try {
      final h = _hive;
      if (h == null) return;
      await h.setSetting(AppConstants.keyUserName, v);
      if ((setupAt.value) == 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        setupAt.value = now;
        await h.setSetting(AppConstants.keyProfileSetupAt, now);
      }
    } catch (_) {}
  }

  Future<void> setProfession(String v) async {
    profession.value = v;
    try {
      await _hive?.setSetting(AppConstants.keyUserProfession, v);
    } catch (_) {}
  }

  Future<void> setAvatar(String emoji, int colorIndex) async {
    avatar.value = emoji;
    avatarColor.value = colorIndex;
    try {
      final h = _hive;
      if (h == null) return;
      await h.setSetting(AppConstants.keyUserAvatar, emoji);
      await h.setSetting(AppConstants.keyUserAvatarColor, colorIndex);
    } catch (_) {}
  }
}
