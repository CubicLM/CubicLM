import 'package:cubiclm/views/device_info_soc_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the contract users see: every chip the app can auto-detect
/// must exist in the tier tables (otherwise the verified tick silently
/// never appears), and every table row must carry a launch year.
void main() {
  group('SoC table coverage', () {
    test('auto-detect hardware ids tick the right table row', () {
      const probes = {
        // hardware id → expected Brand|chip pair
        'sm6375': 'Snapdragon|695',
        'sm4450': 'Snapdragon|4 Gen 2',
        'sm7325': 'Snapdragon|778G',
        'sm8750': 'Snapdragon|8 Elite',
        'sm8850': 'Snapdragon|8s Gen 4',
        'sm8635': 'Snapdragon|8s Gen 3',
        'sm8950': 'Snapdragon|8 Elite Gen 6',
        'sm8845': 'Snapdragon|8 Gen 5',
        'sm7450': 'Snapdragon|7 Gen 1',
        'sm7635': 'Snapdragon|7s Gen 4',
        'sm4635': 'Snapdragon|4s Gen 2',
        'sm6375-ac': 'Snapdragon|6s Gen 3',
        'mt6769': 'MediaTek Helio|G92',
        'mt6785': 'MediaTek Helio|G90T',
        'mt6835': 'MediaTek Dimensity|6300',
        'mt6855': 'MediaTek Dimensity|7025',
        'mt6858': 'MediaTek Dimensity|7100',
        'mt6886': 'MediaTek Dimensity|7200',
        'mt6899': 'MediaTek Dimensity|8400',
        's5e8865': 'Samsung Exynos|1680',
        's5e8855': 'Samsung Exynos|1580',
        's5e8835': 'Samsung Exynos|1380',
        'gs501': 'Google Tensor|G5',
        'Snapdragon 7s Gen 4': 'Snapdragon|7s Gen 4',
        'Snapdragon 4s Gen 2': 'Snapdragon|4s Gen 2',
        'Snapdragon 6s Gen 3': 'Snapdragon|6s Gen 3',
        'Snapdragon 8 Gen 5': 'Snapdragon|8 Gen 5',
        'Snapdragon 8 Elite Gen 6': 'Snapdragon|8 Elite Gen 6',
        'Dimensity 9400+': 'MediaTek Dimensity|9400+',
        'Dimensity 8450': 'MediaTek Dimensity|8450',
        'Dimensity 7200': 'MediaTek Dimensity|7200',
        'Dimensity 7100': 'MediaTek Dimensity|7100',
        'Helio G90T': 'MediaTek Helio|G90T',
        'Tensor G6': 'Google Tensor|G6',
        'Kirin 810': 'HiSilicon Kirin|810',
        'sdm845': 'Snapdragon|845',
        'msm8953': 'Snapdragon|625',
        'mt6833': 'MediaTek Dimensity|700',
        'mt6877': 'MediaTek Dimensity|900',
        'mt6893': 'MediaTek Dimensity|1200',
        'mt6983': 'MediaTek Dimensity|9000',
        'mt6896': 'MediaTek Dimensity|8200',
        'mt6991': 'MediaTek Dimensity|9400',
        'gs201': 'Google Tensor|G2',
        'zuma': 'Google Tensor|G3',
        'zumapro': 'Google Tensor|G4',
        'Exynos 1680': 'Samsung Exynos|1680',
        'exynos2100': 'Samsung Exynos|2100',
        's5e9925': 'Samsung Exynos|2200',
        's5e9945': 'Samsung Exynos|2400',
        'hi3680': 'HiSilicon Kirin|9000',
        // marketing names (direct match, case-insensitive)
        'Snapdragon 8 Gen 2': 'Snapdragon|8 Gen 2',
        'Snapdragon 695': 'Snapdragon|695',
        'Dimensity 9300': 'MediaTek Dimensity|9300',
        'Kirin 980': 'HiSilicon Kirin|980',
        'Exynos 980': 'Samsung Exynos|980',
        'Unisoc T606': 'Unisoc|T606',
      };
      for (final e in probes.entries) {
        expect(deviceChipsFor(e.key), contains(e.value),
            reason: 'hw "${e.key}" should tick ${e.value}');
      }
    });

    test('shared numbers never tick the wrong vendor', () {
      expect(deviceChipsFor('Exynos 980'),
          isNot(contains('HiSilicon Kirin|980')));
      expect(deviceChipsFor('Kirin 980'),
          isNot(contains('Samsung Exynos|980')));
      expect(deviceChipsFor('Dimensity 9000'),
          isNot(contains('HiSilicon Kirin|9000')));
      expect(deviceChipsFor('Kirin 9000'),
          isNot(contains('MediaTek Dimensity|9000')));
      expect(deviceChipsFor('zumapro'),
          isNot(contains('Google Tensor|G3')));
    });

    test('no chip appears in two tiers', () {
      final seen = <String, String>{};
      for (final e in socTierTable) {
        for (final g in e.brands) {
          for (final c in g.chips) {
            final k = '${g.brand}|$c';
            expect(seen, isNot(contains(k)),
                reason: '$k already placed in ${seen[k]}');
            seen[k] = e.tier;
          }
        }
      }
    });

    test('every ticked pair exists in the tier tables', () {
      const hwIds = [
        'sm6375',
        'sm8750',
        'sm8850',
        'sm8635',
        'sm7450',
        'mt6896',
        'mt6991',
        'hi3680',
        'Snapdragon 695',
        'Dimensity 9000',
        'Kirin 9000',
        'Exynos 1080',
        'Dimensity 1080',
      ];
      for (final hw in hwIds) {
        for (final m in deviceChipsFor(hw)) {
          final i = m.indexOf('|');
          expect(i, greaterThan(0), reason: 'pair format: $m');
          expect(
              socTierEntryForChip(
                  m.substring(0, i), m.substring(i + 1)),
              isNotNull,
              reason: '$m ticked but missing from tables');
        }
      }
    });

    test('device chip label resolves for known hardware', () {
      expect(deviceChipTierLabel('sm6375'),
          'Snapdragon 695 · B- Lower Mid-Range');
      expect(deviceChipTierLabel(''), isNull);
      expect(deviceChipTierLabel('definitely-not-a-chip'), isNull);
    });

    test('every table row has a launch year', () {
      final missing = <String>[];
      for (final e in socTierTable) {
        for (final g in e.brands) {
          for (final c in g.chips) {
            if (chipYearOf(c, g.brand) == null) {
              missing.add('${g.brand} :: $c');
            }
          }
        }
      }
      expect(missing, isEmpty, reason: 'rows without year: $missing');
    });
  });
}
