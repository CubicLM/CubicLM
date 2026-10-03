import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import 'device_info_category.dart';
import 'device_info_category_widgets.dart';
import 'device_info_widgets.dart';

/// Hero card: your tier, score, equivalent-class line, era note and
/// the "Why this score" bars. Fully static — inputs are plain values.
class CategoryHeroCard extends StatelessWidget {
  final DeviceCategory cat;
  final CategoryScore score;
  final String? equiv;
  const CategoryHeroCard(
      {super.key,
      required this.cat,
      required this.score,
      required this.equiv});

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CatTierBadge(cat, big: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('Your device',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 11.5,
                                  color: Theme.of(
                                          context)
                                      .hintColor)),
                      Text(cat.name,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 19,
                                  fontWeight:
                                      FontWeight
                                          .w800)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${score.total}',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 26,
                                fontWeight:
                                    FontWeight.w800,
                                color: cat.color)),
                    CatInfoBtn('Your tier & score',
                        'Your tier (${cat.tier} ${cat.name}) comes from your 0–100 score: ${score.total} points.\n\nScore bands: S+ 86+, S 77+, A 68+, A− 59+, B+ 51+, B 43+, B− 35+, C 27+, C− 19+, else D.\n\nThe "performs like" line compares your aged chip against a modern class (e.g. a 2019 flagship behaves like a 2024 upper-mid). Era penalty and equivalent class come from public launch data, everything else is measured on your phone right now.'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                score.next == null
                    ? 'Top of the chart — nothing above.'
                    : '${score.toNext} pts to ${score.next!.name} (${score.next!.tier}).',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color:
                        Theme.of(context).hintColor)),
            if (equiv != null) ...[
              const SizedBox(height: 4),
              Text(
                  'Performs like a $equiv today.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Dt.accent)),
            ],
            if (score.socPenalty > 0) ...[
              const SizedBox(height: 2),
              Text(
                  'Era-adjusted −${score.socPenalty} SoC pts (${score.chipAge} yrs old — flagships decay as years pass).',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .hintColor)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Why this score',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const CatInfoBtn('How scoring works',
                    'Score is 0–100 from measured signals only:\n\n• SoC /42 — chip class from your processor name. Flagships decay 4 pts per year after a 2-year grace period (floor 8), so old flagships settle near their modern equivalent class.\n• RAM /20 — physical total RAM.\n• Storage /10 — internal partition size.\n• Display /13 — resolution class (up to 9) + refresh rate (up to 4).\n• Camera /9 — rear sensor megapixels from the pixel array (true sensor size, not binned JPEG).\n• Battery /6 — design capacity.\n\nUnknown signals score 0, never guessed. Bands: S+ 86+, S 77+, A 68+, A− 59+, B+ 51+, B 43+, B− 35+, C 27+, C− 19+, else D. Foldables are reference-only.\n\nFor running AI models on-device, RAM is the binding constraint — the AI sweet spot card applies that rule separately from this market-tier score.'),
              ],
            ),
            const SizedBox(height: 8),
            for (final k in [
              'SoC',
              'RAM',
              'Storage',
              'Display',
              'Camera',
              'Battery'
            ])
              CatScoreBar(
                  k,
                  score.earned[k] ?? 0,
                  categoryMaxParts()[k] ?? 1),
          ],
        ));
  }
}
