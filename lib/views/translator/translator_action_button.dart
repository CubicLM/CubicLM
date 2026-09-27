import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Translate / Stop button + error line.
class TranslatorActionButton extends StatelessWidget {
  final TranslatorController c;
  const TranslatorActionButton({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final busy = c.translating.value;
      final ready = c.inputText.value.trim().isNotEmpty;
      if (busy) {
        return OutlinedButton.icon(
          onPressed: c.stop,
          icon: const Icon(LucideIcons.square, size: 16),
          label: Text('Stop',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(
                color: AppColors.error.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: ready ? c.translate : null,
            icon: const Icon(LucideIcons.languages, size: 18),
            label: Text('Translate',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (c.error.value.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(c.error.value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.error)),
          ],
        ],
      );
    });
  }
}
