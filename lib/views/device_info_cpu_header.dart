import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// CPU tab: SoC header card (app card language).
/// All values are static snapshots passed in as plain params.
class CpuSocHeader extends StatelessWidget {
  final String displayName;
  final List<String> clusterLines;
  final String? process;
  final String? brandAsset;
  final bool hasSpec;
  const CpuSocHeader({
    super.key,
    required this.displayName,
    required this.clusterLines,
    required this.process,
    required this.brandAsset,
    required this.hasSpec,
  });

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Dt.accent.withValues(alpha: 0.10),
              ),
              clipBehavior: Clip.antiAlias,
              child: brandAsset == null
                  ? const Icon(LucideIcons.cpu,
                      size: 30, color: Dt.accent)
                  : Image.asset(brandAsset!,
                      fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  if (hasSpec) ...[
                    const SizedBox(height: 4),
                    for (final cl in clusterLines)
                      Text(cl,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .hintColor)),
                    const SizedBox(height: 2),
                    Text(process ?? '—',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.w600,
                                color: Theme.of(context)
                                    .hintColor)),
                  ],
                ],
              ),
            ),
            if (hasSpec)
              const Icon(LucideIcons.badgeCheck,
                  size: 20, color: Dt.accent),
          ],
        ));
  }
}
