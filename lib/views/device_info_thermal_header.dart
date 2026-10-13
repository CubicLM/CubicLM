import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_thermal_utils.dart';

/// Thermal header: hottest zone + status chips. Fully static —
/// inputs are plain values.
class ThermalHeaderCard extends StatelessWidget {
  final int sensorCount;
  final double hot;
  final String hotGroup;
  final int status;
  const ThermalHeaderCard(
      {super.key,
      required this.sensorCount,
      required this.hot,
      required this.hotGroup,
      required this.status});

  @override
  Widget build(BuildContext context) {
    Widget chip(String s) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(s,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Dt.accent)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text('Thermal Status',
                    style: GoogleFonts
                        .plusJakartaSans(
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w700,
                            color: Theme.of(
                                    context)
                                .hintColor)),
                const SizedBox(height: 2),
                Text(
                    sensorCount == 0
                        ? '—'
                        : '${hot.toStringAsFixed(1)} °C',
                    style: GoogleFonts
                        .plusJakartaSans(
                            fontSize: 30,
                            fontWeight:
                                FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    chip(thermalStatusLabel(status)),
                    chip(hotGroup),
                    chip('$sensorCount Sensors'),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
              LucideIcons.thermometerSun,
              size: 44,
              color: Dt.accent),
        ],
      ),
    );
  }
}
