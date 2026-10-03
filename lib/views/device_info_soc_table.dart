import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_category.dart';
import 'device_info_widgets.dart';

/// All mainstream mobile processors per category tier, grouped by
/// brand. Covers 2014–2026 lineups (Snapdragon, Dimensity, Helio,
/// Exynos, Tensor, Kirin, Unisoc + Apple A-series as reference).
/// Regional one-offs may be absent — the table is representative,
/// not silicon census.
class SocBrandGroup {
  final String brand;
  final List<String> chips;
  const SocBrandGroup(this.brand, this.chips);
}

class SocTierEntry {
  final String tier;
  final String tierName;
  final List<SocBrandGroup> brands;
  const SocTierEntry(this.tier, this.tierName, this.brands);

  int get total =>
      brands.fold(0, (a, b) => a + b.chips.length);
}

// Every brand list is ordered strongest-first (row 1 = fastest).
const socTierTable = [
  SocTierEntry('D', 'Ultra Budget', [
    SocBrandGroup('Snapdragon',
        ['636', '652', '650', '630', '626', '625', '460', '450', '439', '435', '430', '429', '427', '425', '215', '212', '210']),
    SocBrandGroup('MediaTek Helio',
        ['P25', 'P20', 'A25', 'A22', 'A20', 'MT6750', 'MT6739', 'MT6737', 'MT6735', 'X30', 'X27', 'X25', 'X20', 'X10']),
    SocBrandGroup('Unisoc',
        ['T310', 'T107', 'SC9863A', 'SC9832E', 'SC7731']),
  ]),
  SocTierEntry('C-', 'Low Budget', [
    SocBrandGroup('Snapdragon',
        ['4 Gen 1', '480+', '480', '675', '670', '665', '660']),
    SocBrandGroup('MediaTek Helio',
        ['G70', 'G37', 'G36', 'G35', 'G25', 'G92', 'P35', 'P23', 'P22']),
    SocBrandGroup('Unisoc',
        ['T7250', 'T620', 'T618', 'T616', 'T615', 'T612', 'T610', 'T606']),
    SocBrandGroup('Samsung Exynos',
        ['880', '850', '7885', '7884']),
    SocBrandGroup('HiSilicon Kirin',
        ['710F', '710A', '710', '659', '655', '650']),
    SocBrandGroup('Apple A-series (ref)',
        ['A10', 'A9']),
  ]),
  SocTierEntry('C', 'Budget', [
    SocBrandGroup('Snapdragon',
        ['4 Gen 2', '6s 4G Gen 2', '6s 4G Gen 1', '732G', '730G', '730', '720G', '712', '710', '690', '685', '680', '662']),
    SocBrandGroup('MediaTek Helio',
        ['G200', 'G100', 'G99', 'G96', 'G95', 'G91', 'G88', 'G85', 'G81', 'G80', 'P95', 'P90', 'P70', 'P65', 'P60']),
    SocBrandGroup('MediaTek Dimensity',
        ['7025', '7020', '6400', '6300', '6100+', '6080', '6050', '6020', '810 Ultra', '810', '800U', '800', '720', '700', '600']),
    SocBrandGroup('Unisoc',
        ['T8100', 'T765', 'T760', 'T750', 'T712', 'T710', 'T700', 'T619']),
    SocBrandGroup('Samsung Exynos',
        ['1330', '1280', '9611', '9610']),
    SocBrandGroup('Apple A-series (ref)', ['A10X', 'A11']),
  ]),
  SocTierEntry('B-', 'Lower Mid-Range', [
    SocBrandGroup('Snapdragon',
        ['6 Gen 3', '6 Gen 1', '768G', '765G', '765', '750G']),
    SocBrandGroup('MediaTek Dimensity',
        ['7050', '1080', '920', '900']),
    SocBrandGroup('Samsung Exynos', ['1380', '980']),
    SocBrandGroup('HiSilicon Kirin', ['985', '820E', '820']),
    SocBrandGroup('Unisoc', ['T8300', 'T820', 'T770', 'T7280']),
    SocBrandGroup('Apple A-series (ref)', ['A11']),
  ]),
  SocTierEntry('B', 'Mid-Range', [
    SocBrandGroup('Snapdragon',
        ['7s Gen 3', '7s Gen 2', '7 Gen 1', '6 Gen 4', '780G']),
    SocBrandGroup('MediaTek Dimensity',
        ['7400', '7350', '7300X', '7300', '8200', '8100', '8000']),
    SocBrandGroup('Samsung Exynos', ['1580', '1480']),
    SocBrandGroup('HiSilicon Kirin', ['980', '970']),
    SocBrandGroup('Apple A-series (ref)', ['A12']),
  ]),
  SocTierEntry('B+', 'Upper Mid-Range', [
    SocBrandGroup('Snapdragon', ['7 Gen 3', '782G', '778G']),
    SocBrandGroup('MediaTek Dimensity', ['8350', '8300']),
    SocBrandGroup('HiSilicon Kirin', ['8000']),
  ]),
  SocTierEntry('A-', 'Premium Mid-Range', [
    SocBrandGroup('Snapdragon', ['7 Gen 4', '7+ Gen 3', '7+ Gen 2']),
    SocBrandGroup('MediaTek Dimensity', ['8400', '8050', '8020']),
  ]),
  SocTierEntry('A', 'Flagship Killer', [
    SocBrandGroup('Snapdragon',
        ['8s Gen 4', '8s Gen 3', '8+ Gen 1', '8 Gen 1', '888+', '888', '870', '865+', '865', '860', '855+', '855', '845', '835', '821', '820']),
    SocBrandGroup('MediaTek Dimensity',
        ['9400e', '9400', '9300+', '9300', '9200+', '9200', '9000+', '9000', '1200', '1100', '1000+', '1000']),
    SocBrandGroup('Samsung Exynos',
        ['2200', '2100', '1080', '990', '9825', '9820', '9810']),
    SocBrandGroup('Google Tensor', ['G4', 'G3', 'G2', 'G1']),
    SocBrandGroup('HiSilicon Kirin',
        ['9020', '9010', '9000S', '9000', '9000E', '8010', '990 5G', '990E', '990', '980', '960', '955']),
    SocBrandGroup('Apple A-series (ref)',
        ['A15', 'A14', 'A13']),
  ]),
  SocTierEntry('S', 'Flagship', [
    SocBrandGroup('Snapdragon', ['8 Gen 3', '8 Gen 2']),
    SocBrandGroup('MediaTek Dimensity', ['9400']),
    SocBrandGroup('Samsung Exynos', ['2500', '2400', '2400e']),
    SocBrandGroup('Google Tensor', ['G5']),
    SocBrandGroup('Apple A-series (ref)',
        ['A17 Pro', 'A16']),
  ]),
  SocTierEntry('S+', 'Ultra Flagship', [
    SocBrandGroup('Snapdragon', ['8 Elite Gen 5', '8 Elite']),
    SocBrandGroup('MediaTek Dimensity', ['9500']),
    SocBrandGroup('Apple A-series (ref)',
        ['A19 Pro', 'A19', 'A18 Pro', 'A18']),
  ]),
];

SocTierEntry? socTierEntryFor(String tier) {
  for (final e in socTierTable) {
    if (e.tier == tier) return e;
  }
  return null;
}

/// Brand display name → bundled logo asset.
String? socBrandAsset(String brand) {
  switch (brand) {
    case 'Snapdragon':
      return 'assets/device_soc/snapdragon.png';
    case 'MediaTek Dimensity':
    case 'MediaTek Helio':
      return 'assets/device_soc/mediatek.png';
    case 'Samsung Exynos':
      return 'assets/device_soc/Exynos.png';
    case 'Google Tensor':
      return 'assets/device_soc/tensor.png';
    case 'HiSilicon Kirin':
      return 'assets/device_soc/Kirin.png';
    case 'Unisoc':
      return 'assets/device_soc/unisoc.png';
    default:
      if (brand.startsWith('Apple')) {
        return 'assets/device_soc/apple.png';
      }
      return null;
  }
}

/// Launch year per chip (public launch years). Only confident entries
/// are listed — missing chips render without a year, never a guess.
const _chipYears = {
  '210': 2014, '212': 2016, '215': 2019, '425': 2016, '427': 2017,
  '429': 2018, '430': 2016, '435': 2017, '439': 2018, '450': 2017,
  '460': 2020, '625': 2016, '626': 2016, '630': 2017, '636': 2017,
  '650': 2016, '652': 2016, '660': 2017, '665': 2019, '670': 2018,
  '675': 2018, '480': 2021, '480+': 2022, '4 Gen 1': 2022,
  '4 Gen 2': 2023, '662': 2020, '680': 2021, '685': 2023,
  '690': 2020, '710': 2018, '712': 2019, '720G': 2020, '730': 2019,
  '730G': 2019, '732G': 2020, '6s 4G Gen 1': 2024,
  '6s 4G Gen 2': 2025, '750G': 2020, '765': 2019, '765G': 2020,
  '768G': 2020, '6 Gen 1': 2022, '6 Gen 3': 2024, '6 Gen 4': 2025, '7 Gen 1': 2022,
  '7s Gen 2': 2023, '7s Gen 3': 2024, '780G': 2021, '778G': 2021,
  '782G': 2022, '7 Gen 3': 2023, '7 Gen 4': 2025, '7+ Gen 2': 2023,
  '7+ Gen 3': 2024, '820': 2016, '821': 2016, '835': 2017,
  '845': 2018, '855': 2019, '855+': 2019, '860': 2021, '865': 2020,
  '865+': 2020, '870': 2021, '888': 2021, '888+': 2021,
  '8 Gen 1': 2021, '8+ Gen 1': 2022, '8 Gen 2': 2022,
  '8 Gen 3': 2023, '8s Gen 3': 2024, '8s Gen 4': 2025,
  '8 Elite': 2024, '8 Elite Gen 5': 2025,
  'MT6735': 2016, 'MT6737': 2016, 'MT6739': 2017, 'MT6750': 2016,
  'A20': 2020, 'A22': 2018, 'A25': 2020, 'P20': 2016, 'P25': 2017,
  'P22': 2018, 'P23': 2017, 'P35': 2018, 'X10': 2015, 'X20': 2016,
  'X25': 2016, 'X27': 2016, 'X30': 2017, 'G25': 2020, 'G35': 2020,
  'G36': 2022, 'G37': 2022, 'G70': 2020, 'G80': 2020, 'G81': 2022,
  'G85': 2020,   'G88': 2021, 'G91': 2024, 'G92': 2024, 'G95': 2020, 'G96': 2021,
  'G99': 2022, 'G100': 2024, 'G200': 2025, 'P60': 2018, 'P65': 2019,
  'P70': 2018, 'P90': 2019, 'P95': 2020,
  '600': 2020, '700': 2020, '720': 2020, '800': 2020, '800U': 2020, '810': 2021,
  '810 Ultra': 2021, '900': 2020, '920': 2021, '1000': 2019,
  '1000+': 2020, '1100': 2021, '1200': 2021,
  '1300': 2022, '6020': 2023, '6050': 2023, '6080': 2023, '6100+': 2023,
  '6300': 2024, '6400': 2025, '7020': 2023, '7025': 2024,
  '7050': 2023, '7300': 2024, '7300X': 2024, '7350': 2024,
  '7400': 2025, '8000': 2024, '8020': 2023, '8050': 2023,
  '8100': 2022, '8200': 2022, '8300': 2023, '8350': 2024,
  '8400': 2024, '9300': 2023, '9300+': 2024, '9000': 2021, '9000+': 2022, '9200': 2022,
  '9200+': 2023, '9400e': 2025, '9400': 2024, '9500': 2025,
  'SC7731': 2019, 'SC9832E': 2018, 'SC9863A': 2019,
  'T107': 2023, 'T310': 2019, 'T606': 2021, 'T610': 2019,
  'T612': 2021, 'T615': 2023, 'T616': 2021, 'T618': 2019,
  'T619': 2021, 'T620': 2023, 'T700': 2021, 'T710': 2020,
  'T712': 2021, 'T7250': 2024, 'T7280': 2024, 'T750': 2022,
  'T760': 2023, 'T765': 2024, 'T770': 2023, 'T8100': 2024,
  'T820': 2022, 'T8300': 2025,
  '850': 2020, '880': 2020, '7884': 2018, '7885': 2018,
  '9610': 2018, '9611': 2019, '9810': 2018, '9820': 2018,
  '9825': 2019,
  '1280': 2022, '1330': 2023, '1380': 2023, '1480': 2024,
  '1580': 2024, '2100': 2020, '2200': 2022, '2400': 2024,
  '2400e': 2024, '2500': 2025,
  '659': 2017, '710A': 2020, '710F': 2019,
  '955': 2016, '960': 2016, '970': 2017, '985': 2020,
  '990E': 2020, '990 5G': 2019, '9000E': 2020,
  '8010': 2024, '820E': 2022,
  '9000S': 2023, '9010': 2024, '9020': 2024,
  // Same number, different vendors — brand-qualified so each row
  // shows its own launch year.
  'Snapdragon|710': 2018, 'HiSilicon Kirin|710': 2018,
  'HiSilicon Kirin|650': 2016, 'HiSilicon Kirin|655': 2016,
  'HiSilicon Kirin|820': 2020,
  'MediaTek Dimensity|8000': 2024, 'HiSilicon Kirin|8000': 2024,
  'MediaTek Dimensity|9000': 2021, 'HiSilicon Kirin|9000': 2020,
  'MediaTek Dimensity|1080': 2022, 'Samsung Exynos|1080': 2020,
  'HiSilicon Kirin|980': 2018, 'Samsung Exynos|980': 2019,
  'HiSilicon Kirin|990': 2019, 'Samsung Exynos|990': 2020,
  'G1': 2021, 'G2': 2022, 'G3': 2023, 'G4': 2024, 'G5': 2025,
  'A9': 2015, 'A10': 2016, 'A10X': 2017, 'A11': 2017,
  'A12': 2018, 'A13': 2019, 'A14': 2020, 'A15': 2021,
  'A16': 2022, 'A17 Pro': 2023, 'A18': 2024, 'A18 Pro': 2024,
  'A19': 2025, 'A19 Pro': 2025,
};

int? chipYearOf(String chip, [String brand = '']) {
  if (brand.isNotEmpty) {
    final v = _chipYears['$brand|$chip'];
    if (v != null) return v;
  }
  return _chipYears[chip];
}

// SoC auto-detect aliases live below (canonical _chipAliases).

// (duplicate _chipYears/chipYearOf removed — canonical versions above.)

/// Hardware-id fragment → `Brand|chip` pairs in our tables.
/// Brand-qualified so shared numbers (9000, 980, 990…) tick only the
/// vendor that actually made this device's chip. Keys mirror the SoC
/// match keys; values are exact table strings.
const _chipAliases = {
  'sm4450': ['Snapdragon|4 Gen 2'],
  'sm6225': ['Snapdragon|680'],
  'sm6375': ['Snapdragon|695'],
  'sm7325': ['Snapdragon|778G'],
  'sm7435': ['Snapdragon|7s Gen 2'],
  'sm7450-ab': ['Snapdragon|7 Gen 1'],
  'sm7550': ['Snapdragon|7 Gen 3'],
  'sm7675': ['Snapdragon|7+ Gen 3'],
  'sm7750': ['Snapdragon|7 Gen 4'],
  'sm6450': ['Snapdragon|6 Gen 1'],
  'sm6650': ['Snapdragon|6s 4G Gen 1'],
  'sm6150': ['Snapdragon|675'],
  'sm6125': ['Snapdragon|665'],
  'sm7150': ['Snapdragon|730'],
  'sm4375': ['Snapdragon|480'],
  'sdm820': ['Snapdragon|820'],
  'sdm821': ['Snapdragon|821'],
  'sdm835': ['Snapdragon|835'],
  'sdm845': ['Snapdragon|845'],
  'sdm660': ['Snapdragon|660'],
  'sdm636': ['Snapdragon|636'],
  'sdm710': ['Snapdragon|710'],
  'sdm712': ['Snapdragon|712'],
  'sdm670': ['Snapdragon|670'],
  'sdm678': ['Snapdragon|675'],
  'sdm765': ['Snapdragon|765G'],
  'sdm730': ['Snapdragon|730'],
  'msm8953': ['Snapdragon|625'],
  'msm8937': ['Snapdragon|430'],
  'qcm6490': ['Snapdragon|778G'],
  'sm8150': ['Snapdragon|855', 'Snapdragon|855+'],
  'sm8250': ['Snapdragon|865', 'Snapdragon|865+'],
  'sm8350': ['Snapdragon|888', 'Snapdragon|888+'],
  'sm8450': ['Snapdragon|8 Gen 1'],
  'sm8475': ['Snapdragon|8+ Gen 1'],
  'sm8550': ['Snapdragon|8 Gen 2'],
  'sm8650': ['Snapdragon|8 Gen 3'],
  'sm8750': ['Snapdragon|8 Elite'],
  'mt6833': ['MediaTek Dimensity|700'],
  'mt6877': ['MediaTek Dimensity|900'],
  'mt6893': ['MediaTek Dimensity|1200'],
  'mt6983': ['MediaTek Dimensity|9000'],
  'mt6896': ['MediaTek Dimensity|9300'],
  'mt6991': ['MediaTek Dimensity|9500'],
  'gs101': ['Google Tensor|G1'],
  'gs201': ['Google Tensor|G2'],
  'zuma': ['Google Tensor|G3'],
  'zumapro': ['Google Tensor|G4'],
  'exynos2100': ['Samsung Exynos|2100'],
  's5e9925': ['Samsung Exynos|2200'],
  's5e9945': ['Samsung Exynos|2400'],
  'hi3680': ['HiSilicon Kirin|9000'],
};

/// Brand display name → lowercase name fragments the device may
/// report (marketing names vary: "Kirin" vs "HiSilicon Kirin").
const _brandShorts = {
  'Snapdragon': ['snapdragon'],
  'MediaTek Dimensity': ['mediatek dimensity', 'dimensity'],
  'MediaTek Helio': ['mediatek helio', 'helio'],
  'Samsung Exynos': ['samsung exynos', 'exynos'],
  'Google Tensor': ['google tensor', 'tensor'],
  'HiSilicon Kirin': ['hisilicon kirin', 'kirin'],
  'Unisoc': ['unisoc'],
};

/// `Brand|chip` pairs of the current device (empty = unknown).
/// Hardware-id aliases first, then direct marketing-name match
/// ("snapdragon 8 gen 2", "dimensity 9300", "unisoc t606"…).
/// Apple rows are reference-only and never ticked.
Set<String> deviceChipsFor(String hardware) {
  final h = hardware.toLowerCase();
  if (h.isEmpty) return const {};
  final out = <String>{};
  for (final e in _chipAliases.entries) {
    if (h.contains(e.key)) out.addAll(e.value);
  }
  for (final e in socTierTable) {
    for (final g in e.brands) {
      if (g.brand.startsWith('Apple')) continue;
      final shorts = _brandShorts[g.brand] ?? [g.brand.toLowerCase()];
      for (final s in shorts) {
        for (final c in g.chips) {
          if (h.contains('$s ${c.toLowerCase()}')) {
            out.add('${g.brand}|$c');
          }
        }
      }
    }
  }
  return out;
}

/// Current device's `Brand|chip` pairs (empty when unavailable).
/// Same hardware string the Category tab scores from.
Set<String> _deviceChipSet() {
  try {
    final dev = Get.find<DeviceInfoService>();
    final hw = dev.processorName.value.isEmpty
        ? dev.socHardware.value
        : dev.processorName.value;
    return deviceChipsFor(hw);
  } catch (_) {
    return const {};
  }
}

/// Bundled brand logo (22px), or nothing when unmapped.
Widget _brandLogo(String brand) {
  final a = socBrandAsset(brand);
  if (a == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Image.asset(a,
        width: 22,
        height: 22,
        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
  );
}

/// One per-tier chip row: name + launch year + verified tick + serial.
TableRow _chipRow(BuildContext context, String brand, String chip,
    int i, Set<String> mine) {
  final year = chipYearOf(chip, brand);
  final isMine = mine.contains('$brand|$chip');
  return TableRow(
    decoration: i.isEven
        ? null
        : BoxDecoration(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: chip,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (year != null)
              TextSpan(
                  text: '  · $year',
                  style: GoogleFonts.firaCode(
                      fontSize: 10.5,
                      color: Theme.of(context).hintColor)),
            if (isMine)
              const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(LucideIcons.badgeCheck,
                          size: 14, color: Dt.accent))),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text('${i + 1}',
            textAlign: TextAlign.end,
            style: GoogleFonts.firaCode(
                fontSize: 10.5, color: Theme.of(context).hintColor)),
      ),
    ],
  );
}

/// One all-processors row: serial + name + year + tick, tier tag.
TableRow _allRow(
    BuildContext context, SocAllRow r, int i, Set<String> mine) {
  final year = chipYearOf(r.chip, r.brand);
  final isMine = mine.contains('${r.brand}|${r.chip}');
  return TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '#${i + 1}  ',
                style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    color: Theme.of(context).hintColor)),
            TextSpan(
                text: r.chip,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (year != null)
              TextSpan(
                  text: '  · $year',
                  style: GoogleFonts.firaCode(
                      fontSize: 10.5,
                      color: Theme.of(context).hintColor)),
            if (isMine)
              const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(LucideIcons.badgeCheck,
                          size: 14, color: Dt.accent))),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: r.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text('${r.tier} · ${r.tierName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: r.color)),
        ),
      ),
    ],
  );
}

/// One flat row: every processor with its category tag.
class SocAllRow {
  final String brand;
  final String chip;
  final String tier;
  final String tierName;
  final Color color;
  const SocAllRow(
      this.brand, this.chip, this.tier, this.tierName, this.color);
}

/// All tiers flattened, grouped by brand (same brand order as the
/// per-tier tables). Each row carries its category tag.
Map<String, List<SocAllRow>> socAllByBrand() {
  const order = [
    'Snapdragon',
    'MediaTek Dimensity',
    'MediaTek Helio',
    'Samsung Exynos',
    'Google Tensor',
    'HiSilicon Kirin',
    'Unisoc',
  ];
  final out = <String, List<SocAllRow>>{};
  for (final e in socTierTable) {
    final cat = _categoryFor(e.tier);
    for (final g in e.brands) {
      if (g.brand.startsWith('Apple')) continue; // own section below
      out.putIfAbsent(g.brand, () => []).addAll([
        for (final c in g.chips)
          SocAllRow(g.brand, c, e.tier,
              cat?.name ?? e.tier, cat?.color ?? const Color(0xFF8D8D8D)),
      ]);
    }
  }
  // Apple reference last.
  final apple = <SocAllRow>[];
  for (final e in socTierTable) {
    final cat = _categoryFor(e.tier);
    for (final g in e.brands) {
      if (!g.brand.startsWith('Apple')) continue;
      apple.addAll([
        for (final c in g.chips)
          SocAllRow(g.brand, c, e.tier,
              cat?.name ?? e.tier, cat?.color ?? const Color(0xFF8D8D8D)),
      ]);
    }
  }
  if (apple.isNotEmpty) {
    out['Apple A-series (ref)'] = apple;
  }
  // Keep canonical brand order first, extras after.
  final ordered = <String, List<SocAllRow>>{};
  for (final b in order) {
    if (out.containsKey(b)) ordered[b] = out[b]!;
  }
  for (final k in out.keys) {
    if (!ordered.containsKey(k)) ordered[k] = out[k]!;
  }
  return ordered;
}

DeviceCategory? _categoryFor(String tier) {
  for (final c in deviceCategories) {
    if (c.tier == tier) return c;
  }
  return null;
}

/// Full processor table for one category tier, grouped by brand
/// (Snapdragon table, MediaTek table, …). Opened from the More
/// button on a category's SoC row.
class SocTableView extends StatelessWidget {
  final String tier;
  final String tierName;
  const SocTableView(
      {super.key, required this.tier, required this.tierName});

  @override
  Widget build(BuildContext context) {
    final entry = socTierEntryFor(tier);
    final mine = _deviceChipSet();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('$tierName processors',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: entry == null
          ? Center(
              child: Text('No table for this tier.',
                  style: GoogleFonts.plusJakartaSans(
                      color:
                          Theme.of(context).hintColor)))
          : ListView(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(
                    '${entry.total} processors · strongest first · 2014–2026 lineups',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color:
                            Theme.of(context).hintColor)),
                const SizedBox(height: 10),
                for (final g in entry.brands) ...[
                  devCard(context,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _brandLogo(g.brand),
                              Expanded(
                                child: Text(g.brand,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight
                                                    .w800)),
                              ),
                              Text('${g.chips.length}',
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight
                                                  .w700,
                                          color: Theme.of(
                                                  context)
                                              .hintColor)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // One full-width row per chip (table style).
                          Table(
                            columnWidths: const {
                              0: FlexColumnWidth(),
                              1: IntrinsicColumnWidth(),
                            },
                            children: [
                              for (var i = 0;
                                  i < g.chips.length;
                                  i++)
                                _chipRow(context, g.brand,
                                    g.chips[i], i, mine),
                            ],
                          ),
                        ],
                      )),
                  const SizedBox(height: 12),
                ],
                Text(
                    'Representative mainstream lineups — rare regional variants may be absent. Apple rows are reference only.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color:
                            Theme.of(context).hintColor)),
              ],
            ),
    );
  }
}

/// All processors on one page: same brand tables, but every row
/// carries its category tag (tier letter + name, tier-colored).
/// Opened from the button under "Complete category chart".
class SocAllTableView extends StatefulWidget {
  const SocAllTableView({super.key});

  @override
  State<SocAllTableView> createState() =>
      _SocAllTableViewState();
}

class _SocAllTableViewState extends State<SocAllTableView> {
  var _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byBrand = socAllByBrand();
    var total = 0;
    final mine = _deviceChipSet();
    final shown = <String, List<SocAllRow>>{};
    for (final e in byBrand.entries) {
      final rows = _query.isEmpty
          ? e.value
          : e.value
              .where((r) => r.chip
                  .toLowerCase()
                  .contains(_query))
              .toList();
      if (rows.isNotEmpty) {
        shown[e.key] = rows;
        total += rows.length;
      }
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('All processors',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(
                () => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search processors…',
              prefixIcon:
                  const Icon(LucideIcons.search, size: 17),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                          LucideIcons.x,
                          size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('$total processors · strongest first within each tier table',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Text('No match for "$_query".',
                style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).hintColor))
          else
            for (final e in shown.entries) ...[
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _brandLogo(e.key),
                          Expanded(
                            child: Text(e.key,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight:
                                            FontWeight
                                                .w800)),
                          ),
                          Text('${e.value.length}',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w700,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(),
                          1: IntrinsicColumnWidth(),
                        },
                        children: [
                          for (var i = 0;
                              i < e.value.length;
                              i++)
                            _allRow(context, e.value[i],
                                i, mine),
                        ],
                      ),
                    ],
                  )),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
