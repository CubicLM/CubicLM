import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import '../../theme/design_tokens.dart';
import 'translator_script_font.dart';

/// Streaming translation output + copy.
class TranslatorOutputCard extends StatelessWidget {
  final TranslatorController c;
  const TranslatorOutputCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Obx(() {
      final out = c.output.value;
      final busy = c.translating.value;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  TranslatorController.labelOf(c.targetId.value),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Dt.accent),
                ),
                const Spacer(),
                if (busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  tooltip: 'Copy translation',
                  onPressed: out.trim().isEmpty ? null : c.copyOutput,
                  icon: Icon(LucideIcons.copy,
                      size: 17, color: hint),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              out.isEmpty
                  ? (busy
                      ? 'Translating…'
                      : 'Translation will appear here.')
                  : out,
              // Script-aware font: PlusJakartaSans has no Bengali /
              // Arabic / CJK glyphs (tofu boxes) — Noto covers them.
              style: out.isEmpty
                  ? GoogleFonts.plusJakartaSans(
                      fontSize: 14, height: 1.55, color: hint)
                  : translatorTextStyle(
                      context,
                      langId: c.targetId.value,
                      text: out,
                      fontSize: 15,
                      height: 1.6,
                    ),
            ),
          ],
        ),
      );
    });
  }
}
