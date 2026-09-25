import 'package:cubiclm/services/chip_advice.dart';
import 'package:cubiclm/services/soc_family.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyChip', () {
    test('Snapdragon 845 (user phone) is old flagship', () {
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 845'),
          ChipClass.oldFlagship);
    });

    test('modern Snapdragon 8 series', () {
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 8 Gen 2'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 8 Elite'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 8s Gen 3'),
          ChipClass.modernFlagship);
    });

    test('older Snapdragon 8 series stays old flagship', () {
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 865'),
          ChipClass.oldFlagship);
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 8 Gen 1'),
          ChipClass.oldFlagship);
      expect(classifyChip(
          SocFamily.snapdragon, 'Snapdragon 8 series (sdm845)'),
          ChipClass.oldFlagship);
    });

    test('Snapdragon 7 / 6 series tiers', () {
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 778G'),
          ChipClass.upperMid);
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 7 Gen 1'),
          ChipClass.upperMid);
      expect(
          classifyChip(SocFamily.snapdragon, 'Snapdragon 695'), ChipClass.mid);
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 480'),
          ChipClass.entry);
    });

    test('865 does not get misread as 6-series', () {
      expect(classifyChip(SocFamily.snapdragon, 'Snapdragon 865'),
          isNot(ChipClass.mid));
    });

    test('desktop vendors classify as modern flagship', () {
      expect(classifyChip(SocFamily.amd, 'AMD PC · 16 cores'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.intel, 'Intel PC · 12 cores'),
          ChipClass.modernFlagship);
    });

    test('MediaTek / Exynos / Tensor / Apple', () {
      expect(classifyChip(SocFamily.mediatek, 'Dimensity 9200'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.mediatek, 'Dimensity 8200'),
          ChipClass.upperMid);
      expect(classifyChip(SocFamily.mediatek, 'Helio G99'), ChipClass.mid);
      expect(classifyChip(SocFamily.exynos, 'Exynos 2400'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.exynos, 'Exynos 990'),
          ChipClass.oldFlagship);
      expect(classifyChip(SocFamily.googleTensor, 'Google Tensor G3'),
          ChipClass.modernFlagship);
      expect(classifyChip(SocFamily.apple, 'Apple A17 Pro'),
          ChipClass.modernFlagship);
      expect(
          classifyChip(SocFamily.unknown, 'whatever'), ChipClass.unknown);
    });
  });

  group('adviseChip', () {
    test('K20 Pro profile: 845 + 6GB RAM', () {
      final a = adviseChip(
        family: SocFamily.snapdragon,
        processorName: 'Snapdragon 845',
        socHardware: 'qcom',
        totalRamGb: 5.4,
      );
      expect(a.chipLabel, 'Snapdragon 845');
      expect(a.quantLine, contains('Q4_K_M'));
      expect(a.quantLine, contains('BF16'));
      expect(a.sizeLine, contains('≤1B'));
      expect(a.explainWhy, contains('bandwidth'));
      expect(a.explainWhy, contains('2 bytes'));
      expect(a.warning, isNull);
    });

    test('RAM caps the size below the chip cap', () {
      final a = adviseChip(
        family: SocFamily.snapdragon,
        processorName: 'Snapdragon 8 Gen 2',
        socHardware: '',
        totalRamGb: 4.0,
      );
      expect(a.sizeLine, contains('≤500M'));
    });

    test('Tensor carries the Q4_K_M warning', () {
      final a = adviseChip(
        family: SocFamily.googleTensor,
        processorName: 'Google Tensor G2',
        socHardware: '',
        totalRamGb: 8.0,
      );
      expect(a.quantLine, contains('Q4_0'));
      expect(a.explainWhy, contains('bug'));
      expect(a.warning, isNotNull);
    });

    test('falls back to hardware string, then family name', () {
      final a = adviseChip(
        family: SocFamily.snapdragon,
        processorName: '',
        socHardware: 'sdm845',
        totalRamGb: 6.0,
      );
      expect(a.chipLabel, 'sdm845');
      final b = adviseChip(
        family: SocFamily.mediatek,
        processorName: '',
        socHardware: '',
        totalRamGb: 6.0,
      );
      expect(b.chipLabel, 'MediaTek Dimensity');
    });
  });
}
