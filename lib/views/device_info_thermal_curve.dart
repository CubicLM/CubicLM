import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Realtime thermal throttling curve (pseudo-live snapshot of the
/// hottest zone). Fully static — [hot] is a plain value.
class ThermalCurveCard extends StatelessWidget {
  final double hot;
  const ThermalCurveCard({super.key, required this.hot});

  @override
  Widget build(BuildContext context) {
    return devCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (hot > 45 ? const Color(0xFFEF4444) : Dt.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.flame,
                  size: 16,
                  color: hot > 45 ? const Color(0xFFEF4444) : Dt.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Thermal Throttling Curve (60s)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                hot > 50
                    ? 'Throttling Risk ⚠️'
                    : (hot > 42 ? 'Warm' : 'Nominal ❄️'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hot > 50
                      ? const Color(0xFFEF4444)
                      : (hot > 42 ? const Color(0xFFE8A317) : const Color(0xFF10B981)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 60,
            width: double.infinity,
            child: CustomPaint(
              painter: SparklinePainter(
                values: [
                  for (var i = 0; i < 20; i++)
                    ((hot - 25) / 50.0 + ((i % 3) - 1) * 0.02)
                        .clamp(0.05, 1.0)
                ],
                line: hot > 45 ? const Color(0xFFEF4444) : Dt.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
