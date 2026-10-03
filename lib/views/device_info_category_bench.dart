import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'benchmark_view.dart';
import 'device_info_category_widgets.dart';
import 'device_info_widgets.dart';

/// Benchmark promo card. Fully static.
class CategoryBenchCard extends StatelessWidget {
  const CategoryBenchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Dt.accent
                    .withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: const Icon(
                  LucideIcons.gauge,
                  size: 20,
                  color: Dt.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text('Benchmark this device',
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight:
                                  FontWeight.w800)),
                  const CatInfoBtn('Benchmark this device',
                      'Runs a live benchmark on your loaded local model: 1 discarded warm-up + 3 measured generations on the real inference engine.\n\nMeasured: generation tok/s, time-to-first-token, prompt-processing estimate, RAM before/peak, battery and thermal status, stability. Nothing is simulated — estimates are labeled est, unknowns show —.\n\nResult is a documented CubicLM AI Score (0–100) with history and JSON export.'),
                  Text(
                      'Live tok/s, TTFT, RAM, thermal + AI score.',
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(
                                      context)
                                  .hintColor)),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => Get.to(
                  () => const BenchmarkView()),
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize:
                    MaterialTapTargetSize
                        .shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                            12)),
                textStyle: GoogleFonts
                        .plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight:
                                FontWeight.w700),
              ),
              child: const Text('Benchmark'),
            ),
          ],
        ));
  }
}
