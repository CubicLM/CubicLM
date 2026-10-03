import 'package:flutter/material.dart';

/// Smartphone category chart (11 tiers) + device scoring.
///
/// Scoring is 0–100 from MEASURED signals only — SoC class, RAM,
/// storage, display, camera MP, battery. No single spec decides alone
/// (a big RAM number never outranks the SoC). Foldables are listed
/// for reference but never auto-matched (form factor, not performance).
class DeviceCategory {
  final String tier; // D, C-, C, B-, B, B+, A-, A, S, S+, SF
  final String name;
  final String soc;
  final String ram;
  final String rom;
  final String display;
  final String camera;
  final String battery;
  final String fiveG;
  final String use;
  final int minScore; // inclusive lower bound, -1 = never auto-matched
  final Color color;
  const DeviceCategory({
    required this.tier,
    required this.name,
    required this.soc,
    required this.ram,
    required this.rom,
    required this.display,
    required this.camera,
    required this.battery,
    required this.fiveG,
    required this.use,
    required this.minScore,
    required this.color,
  });
}

const deviceCategories = [
  DeviceCategory(
      tier: 'D',
      name: 'Ultra Budget',
      soc: 'Basic entry-level SoC',
      ram: '2–4 GB',
      rom: '32–128 GB',
      display: 'LCD, HD+, 60–90Hz',
      camera: '8–50MP',
      battery: '4000–5000mAh, 10–18W',
      fiveG: 'No / some models',
      use: 'Calls, WhatsApp, Facebook, YouTube',
      minScore: 0,
      color: Color(0xFF8D6E63)),
  DeviceCategory(
      tier: 'C-',
      name: 'Low Budget',
      soc: 'Snapdragon 4 / Helio G / Unisoc T entry',
      ram: '4–6 GB',
      rom: '64–128 GB',
      display: 'LCD, HD+/FHD+, 60–90Hz',
      camera: '13–50MP',
      battery: '4500–6000mAh, 15–25W',
      fiveG: 'Some models',
      use: 'Normal daily use',
      minScore: 19,
      color: Color(0xFF9C8A4A)),
  DeviceCategory(
      tier: 'C',
      name: 'Budget',
      soc: 'Snapdragon 4/6 entry, Helio G, Dimensity 6000',
      ram: '4–8 GB',
      rom: '128–256 GB',
      display: 'LCD/AMOLED, 90–120Hz',
      camera: '50MP class',
      battery: '5000–6000mAh, 18–45W',
      fiveG: 'Most models',
      use: 'Daily use + light gaming',
      minScore: 27,
      color: Color(0xFF6B9E5A)),
  DeviceCategory(
      tier: 'B-',
      name: 'Lower Mid-Range',
      soc: 'Snapdragon 6 / Dimensity 600–700 series',
      ram: '6–8 GB',
      rom: '128–256 GB',
      display: 'FHD+ LCD/AMOLED, 90–120Hz',
      camera: '50–108MP',
      battery: '5000–6000mAh, 25–67W',
      fiveG: 'Yes',
      use: 'Multitasking + casual gaming',
      minScore: 35,
      color: Color(0xFF4E9B8F)),
  DeviceCategory(
      tier: 'B',
      name: 'Mid-Range',
      soc: 'Snapdragon 6/7, Dimensity 700/800/7000',
      ram: '8–12 GB',
      rom: '128–256 GB',
      display: 'AMOLED, FHD+, 120Hz',
      camera: '50MP+, OIS on some',
      battery: '5000–6500mAh, 33–80W',
      fiveG: 'Yes',
      use: 'Heavy daily use + gaming',
      minScore: 43,
      color: Color(0xFF5B8DD9)),
  DeviceCategory(
      tier: 'B+',
      name: 'Upper Mid-Range',
      soc: 'Snapdragon 7 / 7+ series, Dimensity 8000',
      ram: '8–12 GB',
      rom: '256–512 GB',
      display: 'AMOLED, 120–144Hz',
      camera: '50MP OIS + ultrawide',
      battery: '5000–6500mAh, 45–100W+',
      fiveG: 'Yes',
      use: 'Heavy gaming + camera',
      minScore: 51,
      color: Color(0xFF7B7BD4)),
  DeviceCategory(
      tier: 'A-',
      name: 'Premium Mid-Range',
      soc: 'Snapdragon 7+ / 8s, Dimensity 8000/9000',
      ram: '8–16 GB',
      rom: '256–512 GB',
      display: 'AMOLED/LTPO, 120Hz',
      camera: '50MP OIS + UW/Telephoto',
      battery: '5000–6500mAh, 67–120W',
      fiveG: 'Yes',
      use: 'Power user + gaming',
      minScore: 59,
      color: Color(0xFF9B6BD3)),
  DeviceCategory(
      tier: 'A',
      name: 'Flagship Killer',
      soc: 'Snapdragon 8s/8 series, Dimensity 9000',
      ram: '12–16 GB',
      rom: '256–512 GB',
      display: 'High-end AMOLED/LTPO, 120Hz+',
      camera: '50MP OIS + UW + Telephoto',
      battery: '5000–6500mAh, 80–150W',
      fiveG: 'Yes',
      use: 'Flagship-level gaming/performance',
      minScore: 68,
      color: Color(0xFFB45BC4)),
  DeviceCategory(
      tier: 'S',
      name: 'Flagship',
      soc: 'Latest Snapdragon 8 / Dimensity flagship / Apple A-series',
      ram: '12–16 GB',
      rom: '256 GB–1 TB',
      display: 'LTPO AMOLED/OLED, 120Hz',
      camera: 'Advanced triple + OIS + Telephoto',
      battery: '4500–6000mAh, fast + wireless',
      fiveG: 'Yes',
      use: 'Maximum performance + camera',
      minScore: 77,
      color: Color(0xFFD9534F)),
  DeviceCategory(
      tier: 'S+',
      name: 'Ultra Flagship',
      soc: 'Top-tier flagship SoC',
      ram: '12–24 GB',
      rom: '512 GB–1 TB+',
      display: 'Best LTPO AMOLED/OLED, 120Hz+',
      camera: 'Large sensors + Periscope',
      battery: '5000–7000mAh, fast + wireless',
      fiveG: 'Yes',
      use: 'Extreme performance + photography',
      minScore: 86,
      color: Color(0xFFD4A017)),
  DeviceCategory(
      tier: 'S/F',
      name: 'Foldable Flagship',
      soc: 'Flagship SoC',
      ram: '12–16 GB',
      rom: '256 GB–1 TB',
      display: 'Foldable AMOLED/LTPO',
      camera: 'Flagship multi-camera',
      battery: '4000–6000mAh, fast + wireless',
      fiveG: 'Yes',
      use: 'Multitasking + premium (form factor)',
      minScore: -1,
      color: Color(0xFFC26BA0)),
];

/// SoC input classes mirror ChipClass ordering:
// ignore: constant_identifier_names
enum SocScoreClass {
  modernFlagship,
  oldFlagship,
  upperMid,
  mid,
  entry,
  unknown,
}

class CategoryScore {
  final int total; // 0..100
  final Map<String, int> earned; // signal -> points earned
  final DeviceCategory category;
  final DeviceCategory? next; // next tier up, if any
  final int toNext; // points missing for next tier (0 if top)
  final int socBase; // SoC points before era adjustment
  final int socPenalty; // era points removed (0 when young/unknown)
  final int chipAge; // years since chip launch (0 = unknown)
  const CategoryScore({
    required this.total,
    required this.earned,
    required this.category,
    required this.next,
    required this.toNext,
    required this.socBase,
    required this.socPenalty,
    required this.chipAge,
  });
}

const _maxParts = {
  'SoC': 42,
  'RAM': 20,
  'Storage': 10,
  'Display': 13,
  'Camera': 9,
  'Battery': 6,
};

Map<String, int> categoryMaxParts() =>
    Map<String, int>.from(_maxParts);

/// Score a device 0–100. Every input is measured; unknowns score 0.
///
/// Era adjustment: flagships decay toward their modern equivalent as
/// years pass — 4 pts per year after a 2-year grace period, SoC floor
/// 8. A 2019 flagship in 2026 lands near the 2024 upper-mid class,
/// which matches cross-generation analysis (SD 855 ≈ SD 7-series).
CategoryScore scoreDevice({
  required SocScoreClass chip,
  required double ramGb,
  required int storageTotalBytes,
  required int dispMinPx,
  required double refreshMaxHz,
  required int camMaxMp,
  required int battDesignMah,
  int chipYear = 0,
}) {
  final earned = <String, int>{};
  final socBase = switch (chip) {
    SocScoreClass.modernFlagship => 42,
    SocScoreClass.oldFlagship => 33,
    SocScoreClass.upperMid => 27,
    SocScoreClass.mid => 19,
    SocScoreClass.entry => 10,
    SocScoreClass.unknown => 16,
  };
  final nowYear = DateTime.now().year;
  final chipAge = chipYear > 0 ? (nowYear - chipYear).clamp(0, 30) : 0;
  final socPenalty =
      chipYear > 0 ? (4 * (chipAge - 2)).clamp(0, 34) : 0;
  earned['SoC'] = (socBase - socPenalty).clamp(8, 42);
  earned['RAM'] = ramGb >= 16
      ? 20
      : ramGb >= 12
          ? 18
          : ramGb >= 8
              ? 14
              : ramGb >= 6
                  ? 10
                  : ramGb >= 4
                      ? 5
                      : ramGb > 0
                          ? 2
                          : 0;
  final storGb = storageTotalBytes / 1000000000;
  earned['Storage'] = storGb >= 512
      ? 10
      : storGb >= 256
          ? 8
          : storGb >= 128
              ? 5
              : storGb > 0
                  ? 2
                  : 0;
  var disp = 0;
  if (dispMinPx >= 1440) {
    disp = 9;
  } else if (dispMinPx >= 1080) {
    disp = 6;
  } else if (dispMinPx >= 720) {
    disp = 3;
  } else if (dispMinPx > 0) {
    disp = 1;
  }
  if (refreshMaxHz >= 120) {
    disp += 4;
  } else if (refreshMaxHz >= 90) {
    disp += 2;
  }
  earned['Display'] = disp.clamp(0, 13);
  earned['Camera'] = camMaxMp >= 100
      ? 9
      : camMaxMp >= 48
          ? 8
          : camMaxMp >= 32
              ? 6
              : camMaxMp >= 12
                  ? 4
                  : camMaxMp > 0
                      ? 2
                      : 0;
  earned['Battery'] = battDesignMah >= 6000
      ? 6
      : battDesignMah >= 5000
          ? 4
          : battDesignMah >= 4000
              ? 3
              : battDesignMah > 0
                  ? 1
                  : 0;
  final total = earned.values.fold(0, (a, b) => a + b);
  DeviceCategory cat = deviceCategories.first;
  for (final c in deviceCategories) {
    if (c.minScore < 0) continue; // foldable: reference only
    if (total >= c.minScore) cat = c;
  }
  // First tier above the matched one.
  DeviceCategory? up;
  for (final c in deviceCategories) {
    if (c.minScore >= 0 && c.minScore > cat.minScore) {
      up = c;
      break;
    }
  }
  return CategoryScore(
    total: total.clamp(0, 100),
    earned: earned,
    category: cat,
    next: up,
    toNext: up == null ? 0 : (up.minScore - total).clamp(0, 100),
    socBase: socBase,
    socPenalty: socPenalty,
    chipAge: chipAge,
  );
}
