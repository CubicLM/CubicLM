import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/soc_family.dart';

/// Brand icon for a chip family: vendor PNG when one is bundled, plain
/// CPU icon otherwise (Apple / Unisoc / Rockchip / unknown). The image
/// falls back to the CPU icon if the asset ever fails to load.
class SocBrandIcon extends StatelessWidget {
  final SocFamily family;
  final double size;
  final Color? fallbackColor;

  const SocBrandIcon({
    super.key,
    required this.family,
    this.size = 18,
    this.fallbackColor,
  });

  /// Bundled vendor logo, or null when this family has none (caller then
  /// shows the generic CPU icon). Pure logic — unit-tested.
  static String? assetFor(SocFamily family) {
    switch (family) {
      case SocFamily.snapdragon:
        return 'assets/device_soc/snapdragon.png';
      case SocFamily.googleTensor:
        return 'assets/device_soc/tensor.png';
      case SocFamily.mediatek:
        return 'assets/device_soc/mediatek.png';
      case SocFamily.hisilicon:
        return 'assets/device_soc/Kirin.png';
      case SocFamily.exynos:
        return 'assets/device_soc/Exynos.png';
      case SocFamily.amd:
        return 'assets/device_soc/amd-color.png';
      case SocFamily.intel:
        return 'assets/device_soc/intel.png';
      case SocFamily.apple:
      case SocFamily.unisoc:
      case SocFamily.rockchip:
      case SocFamily.unknown:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(family);
    if (asset == null) {
      return Icon(LucideIcons.cpu, size: size, color: fallbackColor);
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, Object e, __) {
        // Never fail silently: one logcat line says whether the family
        // was wrong or the asset is missing/undecodable.
        // ignore: avoid_print
        print('[SocIcon] asset failed: $asset family=${family.name} ($e)');
        return Icon(LucideIcons.cpu, size: size, color: fallbackColor);
      },
    );
  }
}
