import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import 'translator_script_font.dart';

/// Source text input + counter + paste/clear.
class TranslatorInputCard extends StatelessWidget {
  final TranslatorController c;
  const TranslatorInputCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Obx(() {
      final len = c.inputText.value.length;
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
          children: [
            TextField(
              controller: c.inputCtrl,
              minLines: 3,
              maxLines: 6,
              maxLength: TranslatorController.maxInputChars,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  const SizedBox.shrink(),
              // Same script-aware font so Bengali (etc.) input
              // renders instead of tofu while typing.
              style: translatorTextStyle(
                context,
                langId: c.sourceId.value,
                text: c.inputText.value,
                fontSize: 14,
                height: 1.5,
              ),
              // All borders pinned to none: the app theme's accent
              // focusedBorder would otherwise draw a ring on tap
              // (InputDecoration.collapsed leaves focusedBorder null,
              // which falls back to the theme).
              decoration: InputDecoration(
                hintText: 'Enter text to translate…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: hint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('$len / ${TranslatorController.maxInputChars}',
                    style: GoogleFonts.firaCode(
                        fontSize: 10.5, color: hint)),
                const Spacer(),
                IconButton(
                  tooltip: 'Paste',
                  onPressed: c.paste,
                  icon: Icon(LucideIcons.clipboardPaste,
                      size: 17, color: hint),
                ),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: len == 0 ? null : c.clearAll,
                  icon: Icon(LucideIcons.x,
                      size: 17, color: hint),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
