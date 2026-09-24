import 'soc_family.dart';

/// Chip capability class — drives per-device model recommendations.
/// Pure logic (no platform calls) so it stays unit-testable.
enum ChipClass {
  modernFlagship,
  oldFlagship,
  upperMid,
  mid,
  entry,
  unknown,
}

/// Ordered size caps; advice takes the smaller of chip cap and RAM cap.
const _sizeCaps = <String>['≤500M', '≤1B', '≤3B', 'up to 7B'];

int _ramCapIndex(double totalRamGb) {
  if (totalRamGb <= 0) return 3; // unknown RAM: don't constrain
  if (totalRamGb <= 4) return 0;
  if (totalRamGb <= 6) return 1;
  if (totalRamGb <= 8) return 2;
  return 3;
}

int _chipCapIndex(ChipClass c) {
  switch (c) {
    case ChipClass.modernFlagship:
      return 3;
    case ChipClass.oldFlagship:
      return 1;
    case ChipClass.upperMid:
      return 2;
    case ChipClass.mid:
      return 1;
    case ChipClass.entry:
      return 0;
    case ChipClass.unknown:
      return 1;
  }
}

/// Classify a chip from its marketing name (e.g. "Snapdragon 845",
/// "Snapdragon 8 Gen 2", "Dimensity 8200", "Google Tensor G3").
/// Matching is ordered: newer/premium patterns first, because numbers
/// overlap ("865" contains "65").
ChipClass classifyChip(SocFamily family, String chipLabel) {
  final n = chipLabel.toLowerCase();
  switch (family) {
    case SocFamily.apple:
      return ChipClass.modernFlagship;
    case SocFamily.googleTensor:
      return ChipClass.modernFlagship;
    case SocFamily.snapdragon:
      if (n.contains('8 elite') ||
          n.contains('8s gen') ||
          RegExp(r'8 gen [2-9]').hasMatch(n)) {
        return ChipClass.modernFlagship;
      }
      if (n.contains('7 gen') ||
          n.contains('7s gen') ||
          n.contains('7+ gen') ||
          RegExp(r'\b(778g?|780g?|782g?|783g?|770|768g?|765g?|750|747|746)\b')
              .hasMatch(n)) {
        return ChipClass.upperMid;
      }
      if (n.contains('8 gen 1') ||
          n.contains('8+ gen 1') ||
          n.contains('8 series') ||
          RegExp(
                  r'\b(888|870|865|855|845|835|821|820|810|808|805|800|8450|8350|8250|8150)\b')
              .hasMatch(n) ||
          RegExp(r'\b(sdm8\d{2}|sm8\d{3})\b').hasMatch(n)) {
        return ChipClass.oldFlagship;
      }
      if (n.contains('6 gen') ||
          RegExp(
                  r'\b(695|690|685|680|678|675|673|672|670|668|665|662|660|659|653|652|650|648|636|632|630|626|625|622|615|612|610)\b')
              .hasMatch(n) ||
          RegExp(r'\b(sm6\d{3}|sdm6\d{2}|sdm7\d{2}|sm7\d{3})\b')
              .hasMatch(n)) {
        return ChipClass.mid;
      }
      if (n.contains('4 gen') ||
          RegExp(r'\b(4\d{2}|sm4\d{3}|sdm4\d{2}|msm8(917|920|937|939))\b')
              .hasMatch(n)) {
        return ChipClass.entry;
      }
      return ChipClass.mid;
    case SocFamily.mediatek:
      if (RegExp(r'\b(94\d\d|93\d\d|92\d\d|90\d\d)\b').hasMatch(n)) {
        return ChipClass.modernFlagship;
      }
      if (RegExp(r'\b(84\d\d|83\d\d|82\d\d|81\d\d|80\d\d|13\d\d|12\d\d|11\d\d|10\d\d)\b')
          .hasMatch(n)) {
        return ChipClass.upperMid;
      }
      if (n.contains('dimensity') ||
          n.contains('helio g') ||
          RegExp(r'\b(g\d{2,3}|mt[678]\d{3})\b').hasMatch(n)) {
        return ChipClass.mid;
      }
      return ChipClass.entry;
    case SocFamily.exynos:
      if (RegExp(r'\b(2500|2400|2300|2200|1580|1480)\b').hasMatch(n)) {
        return ChipClass.modernFlagship;
      }
      if (RegExp(r'\b(2100|2000|1080|9925|990|9825|9820|9810|980)\b')
          .hasMatch(n)) {
        return ChipClass.oldFlagship;
      }
      return ChipClass.mid;
    case SocFamily.hisilicon:
      if (RegExp(r'\b(9020|9000|990|980)\b').hasMatch(n)) {
        return ChipClass.oldFlagship;
      }
      return ChipClass.mid;
    case SocFamily.unisoc:
      if (RegExp(r'\bt[678]\d{2}\b').hasMatch(n)) return ChipClass.mid;
      return ChipClass.entry;
    case SocFamily.rockchip:
      return ChipClass.entry;
    case SocFamily.unknown:
      return ChipClass.unknown;
  }
}

/// One card-ready recommendation for a device.
class ChipAdvice {
  const ChipAdvice({
    required this.chipLabel,
    required this.quantLine,
    required this.sizeLine,
    this.warning,
  });

  /// e.g. "Snapdragon 845".
  final String chipLabel;

  /// e.g. "Best: Q4_K_M · BF16 works but ~2–3x slower".
  final String quantLine;

  /// e.g. "Stick to ≤1B on 5.4GB RAM".
  final String sizeLine;

  /// Optional hard warning (Tensor Q4_K_M bug, …).
  final String? warning;
}

String _resolveChipLabel({
  required String processorName,
  required String socHardware,
  required SocFamily family,
}) {
  final p = processorName.trim();
  if (p.isNotEmpty) return p;
  final h = socHardware.trim();
  if (h.isNotEmpty) return h;
  return family.displayName;
}

/// Build the Explore-card recommendation for this device.
ChipAdvice adviseChip({
  required SocFamily family,
  required String processorName,
  required String socHardware,
  required double totalRamGb,
}) {
  final label = _resolveChipLabel(
    processorName: processorName,
    socHardware: socHardware,
    family: family,
  );
  final cls = classifyChip(family, label);

  final String quantLine;
  switch (cls) {
    case ChipClass.modernFlagship:
      quantLine = family == SocFamily.googleTensor
          ? 'Best: Q4_0 / Q5_K_M · avoid Q4_K_M'
          : 'Best: Q4_K_M · BF16 fine ≤1B';
      break;
    case ChipClass.oldFlagship:
      quantLine = 'Best: Q4_K_M · BF16 works but ~2–3x slower';
      break;
    case ChipClass.upperMid:
      quantLine = 'Best: Q4_K_M / Q5_K_M · skip BF16';
      break;
    case ChipClass.mid:
      quantLine = 'Use Q4 quants only (Q4_K_M, Q4_0)';
      break;
    case ChipClass.entry:
      quantLine = 'Tiny Q4 only (Q2_K / Q3_K_S if tight)';
      break;
    case ChipClass.unknown:
      quantLine = family.recommendedQuant;
      break;
  }

  var capIdx = _chipCapIndex(cls);
  final ramIdx = _ramCapIndex(totalRamGb);
  if (ramIdx < capIdx) capIdx = ramIdx;
  final ramTxt = totalRamGb > 0
      ? ' on ${totalRamGb.toStringAsFixed(1)}GB RAM'
      : '';
  final sizeLine = 'Stick to ${_sizeCaps[capIdx]}$ramTxt';

  return ChipAdvice(
    chipLabel: label,
    quantLine: quantLine,
    sizeLine: sizeLine,
    warning: family.quantWarning,
  );
}
