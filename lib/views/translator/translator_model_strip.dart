import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/model_switcher_sheet.dart';
import 'translator_model_notice.dart';

/// Loaded-model strip, or a compact no-model banner guiding to the Hub.
class TranslatorModelStrip extends StatelessWidget {
  final TranslatorController c;
  const TranslatorModelStrip({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Track reactivity.
      c.inputText.value;
      final ready = c.modelReady;
      if (ready) {
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              // Same switcher as the chat textbox: tap the model
              // name to open Switch Model.
              Expanded(
                child: InkWell(
                  onTap: () =>
                      showModelSwitcherSheet(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            c.loadedModelName.isEmpty
                                ? 'Local model ready'
                                : c.loadedModelName,
                            style: GoogleFonts.firaCode(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(LucideIcons.chevronDown,
                            size: 14,
                            color:
                                Theme.of(context).hintColor),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Which model works for translation?',
                onPressed: () =>
                    showTranslatorModelNotice(context, c),
                icon: Icon(LucideIcons.info,
                    size: 15,
                    color: Theme.of(context).hintColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.all(14),
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
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.download,
                  color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('No local model loaded',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                        tooltip:
                            'Which model works for translation?',
                        onPressed: () =>
                            showTranslatorModelNotice(context, c),
                        icon: Icon(LucideIcons.info,
                            size: 15,
                            color:
                                Theme.of(context).hintColor),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                  Text('Load Qwen2.5-1.5B (~1 GB) for accurate offline translation.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).hintColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: c.openModelHub,
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              child: const Text('Open Hub'),
            ),
          ],
        ),
      );
    });
  }
}
