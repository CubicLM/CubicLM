import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Notice: offline translation needs an all-language model —
/// not every local model can translate every language. Guides the
/// user to import one or download from the Local marketplace.
void showTranslatorModelNotice(
    BuildContext context, TranslatorController c) {
  Widget bullet(String text, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Expanded(
            child: Text(text,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight:
                        strong ? FontWeight.w700 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }

  Widget modelRow(String name, String size) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(LucideIcons.checkCircle2,
              size: 14, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          Text(size,
              style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(LucideIcons.info, size: 18, color: Dt.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('You need an all-language model',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bullet(
                'CubicTranslator works 100% offline on your loaded local AI model — nothing leaves the phone.'),
            bullet(
                'But not every model can translate every language. Tiny or specialist models (code-only, English-only) will give wrong output.',
                strong: true),
            bullet(
                'Use an all-language model: import any GGUF from Explore → Downloaded models (import / Add URL), or download one from the Explore → Local marketplace:'),
            modelRow('Qwen2.5 0.5B Instruct (Q4_K_M)', '~400 MB'),
            modelRow('Qwen2.5 1.5B Instruct (Q4_K_M)', '~1 GB'),
            modelRow('Gemma 2 2B Instruct (Q4_K_M)', '~1.7 GB'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            c.openModelHub();
          },
          style: FilledButton.styleFrom(
              backgroundColor: Dt.accent,
              foregroundColor: Colors.white),
          child: const Text('Open Model Hub'),
        ),
      ],
    ),
  );
}
