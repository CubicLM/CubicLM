import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_category_widgets.dart';
import 'device_info_widgets.dart';

/// SoC tier ladder card (S → D) with your band ticked.
/// Fully static — [tier] is a plain value.
class CategoryLadderCard extends StatelessWidget {
  final String tier;
  final String? detected;
  const CategoryLadderCard(
      {super.key, required this.tier, this.detected});

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('SoC tier ladder',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const CatInfoBtn('SoC tier ladder',
                    'S = current flagship, A+ = high flagship, A = old flagship, B+ = upper mid, B = mid, C = entry, D = basic.\n\nThe check mark is YOUR band from the score above. SoC sets the speed class — a big RAM number never outranks the chip, which is why SoC alone is worth 42 of 100 points. For on-device AI, RAM is the gatekeeper instead — see the AI sweet spot card.'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'SoC sets the speed class — for on-device AI, RAM sets the headroom.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color:
                        Theme.of(context).hintColor)),
            if (detected != null) ...[
              const SizedBox(height: 4),
              Text('Your chip: $detected.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Dt.accent)),
            ],
            const SizedBox(height: 8),
            for (final t in [
              ['S', 'Flagship', catBandColor('S')],
              ['A+', 'High flagship', catBandColor('A')],
              ['A', 'Old flagship', catBandColor('A')],
              ['A-', 'Premium mid', catBandColor('A-')],
              ['B+', 'Upper mid', catBandColor('B+')],
              ['B', 'Mid', catBandColor('B')],
              ['B-', 'Lower mid', catBandColor('B-')],
              ['C', 'Entry', catBandColor('C')],
              ['C-', 'Low budget', catBandColor('C-')],
              ['D', 'Basic', catBandColor('D')],
            ])
              Padding(
                padding:
                    const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: (t[2] as Color)
                            .withValues(alpha: 0.14),
                        borderRadius:
                            BorderRadius.circular(
                                9),
                      ),
                      child: Center(
                        child: Text(t[0] as String,
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                    color: t[2]
                                        as Color)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t[1] as String,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  color: Theme.of(
                                          context)
                                      .hintColor)),
                    ),
                    if (catLadderHit(
                        tier, t[0] as String))
                      const Icon(
                          LucideIcons.checkCircle2,
                          size: 15,
                          color: Dt.accent),
                  ],
                ),
              ),
          ],
        ));
  }
}
