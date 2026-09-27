import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/translator_controller.dart';
import '../../theme/design_tokens.dart';

/// Source | swap | target language pickers.
class TranslatorLangBar extends StatelessWidget {
  final TranslatorController c;
  const TranslatorLangBar({super.key, required this.c});

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final itemStyle =
        GoogleFonts.plusJakartaSans(fontSize: 13.5, color: onSurface);
    Text dropdownItem(String s) => Text(s,
        style: itemStyle, overflow: TextOverflow.ellipsis);
    return Obx(() {
      final src = c.sourceId.value;
      final tgt = c.targetId.value;
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
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('tr-src-$src'),
                initialValue: src,
                isExpanded: true,
                dropdownColor: Theme.of(context).cardColor,
                decoration: _deco('From'),
                style: itemStyle,
                items: [
                  DropdownMenuItem(
                      value: 'auto', child: dropdownItem('Auto')),
                  for (final l in TranslatorController.languages)
                    DropdownMenuItem(
                        value: l.id, child: dropdownItem(l.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  c.sourceId.value = v;
                  c.output.value = '';
                  c.error.value = '';
                },
              ),
            ),
            IconButton(
              tooltip: 'Swap languages',
              onPressed: src == 'auto' ? null : c.swap,
              icon: const Icon(LucideIcons.arrowLeftRight, size: 18),
              color: Dt.accent,
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('tr-tgt-$tgt'),
                initialValue: tgt,
                isExpanded: true,
                dropdownColor: Theme.of(context).cardColor,
                decoration: _deco('To'),
                style: itemStyle,
                items: [
                  for (final l in TranslatorController.languages)
                    DropdownMenuItem(
                        value: l.id, child: dropdownItem(l.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  c.targetId.value = v;
                  c.output.value = '';
                  c.error.value = '';
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}
