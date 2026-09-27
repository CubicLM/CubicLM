import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/translator_controller.dart';
import 'translator/translator_action_button.dart';
import 'translator/translator_input_card.dart';
import 'translator/translator_lang_bar.dart';
import 'translator/translator_model_strip.dart';
import 'translator/translator_output_card.dart';

/// CubicTranslator — Google-Translate-style on-device translator.
/// Runs on the loaded local GGUF model (e.g. Qwen2.5-0.5B-Instruct):
/// no cloud, no scripts, everything stays on the phone.
///
/// Thin shell — one widget per file under views/translator/:
///   translator_model_strip.dart  → model status + no-model banner
///   translator_model_notice.dart → all-language-model notice dialog
///   translator_lang_bar.dart     → From | swap | To pickers
///   translator_input_card.dart   → source text input
///   translator_action_button.dart → Translate / Stop + error
///   translator_output_card.dart  → streaming output + copy
class TranslatorView extends StatefulWidget {
  const TranslatorView({super.key});

  @override
  State<TranslatorView> createState() => _TranslatorViewState();
}

class _TranslatorViewState extends State<TranslatorView> {
  late final TranslatorController c;

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<TranslatorController>()
        ? Get.find<TranslatorController>()
        : Get.put(TranslatorController());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.languages, size: 22),
            const SizedBox(width: 10),
            Text('CubicTranslator',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.5)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TranslatorModelStrip(c: c),
          const SizedBox(height: 12),
          TranslatorLangBar(c: c),
          const SizedBox(height: 12),
          TranslatorInputCard(c: c),
          const SizedBox(height: 12),
          TranslatorActionButton(c: c),
          const SizedBox(height: 12),
          TranslatorOutputCard(c: c),
        ],
      ),
    );
  }
}
