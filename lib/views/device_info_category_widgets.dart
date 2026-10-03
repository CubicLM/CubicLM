import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_category.dart';

/// Shared bits for the Category tab sections (moved verbatim out of
/// the tab file so each section lives in its own file).
void showCatInfo(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      title: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Text(body,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.55)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// Small ⓘ button opening a [showCatInfo] dialog.
class CatInfoBtn extends StatelessWidget {
  final String title;
  final String body;
  const CatInfoBtn(this.title, this.body, {super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showCatInfo(context, title, body),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(LucideIcons.info,
            size: 14,
            color: Theme.of(context)
                .hintColor
                .withValues(alpha: 0.8)),
      ),
    );
  }
}

/// Tier letter badge (big in the hero, small in chart rows).
class CatTierBadge extends StatelessWidget {
  final DeviceCategory c;
  final bool big;
  const CatTierBadge(this.c, {this.big = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: big ? 46 : 34,
      height: big ? 46 : 34,
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.14),
        borderRadius:
            BorderRadius.circular(big ? 14 : 10),
      ),
      child: Center(
        child: Text(c.tier,
            style: GoogleFonts.plusJakartaSans(
                fontSize: big ? 15 : 12,
                fontWeight: FontWeight.w800,
                color: c.color)),
      ),
    );
  }
}

/// One "got/max" score bar from the hero's "Why this score" list.
class CatScoreBar extends StatelessWidget {
  final String label;
  final int got;
  final int max;
  const CatScoreBar(this.label, this.got, this.max,
      {super.key});

  @override
  Widget build(BuildContext context) {
    final f =
        max > 0 ? (got / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: Theme.of(context).hintColor)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 6,
                backgroundColor: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.35),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(
                        Dt.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('$got/$max',
                textAlign: TextAlign.end,
                style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    color: Theme.of(context).hintColor)),
          ),
        ],
      ),
    );
  }
}

/// Band color for a ladder tier letter (S/A+/A/B+/B/C/D).
Color catBandColor(String tier) {
  for (final c in deviceCategories) {
    if (c.tier == tier) return c.color;
  }
  if (tier == 'A+') {
    for (final c in deviceCategories) {
      if (c.tier == 'A') return c.color;
    }
  }
  return const Color(0xFF8D8D8D);
}

/// Does band letter [letter] represent the matched [tier]?
/// S+ lights the S rung (nearest rung above entry ladder top);
/// S/F never auto-matches by design.
bool catLadderHit(String tier, String letter) {
  if (tier == letter) return true;
  if (tier == 'S+' && letter == 'S') return true;
  return false;
}
