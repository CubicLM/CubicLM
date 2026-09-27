/// Translator user actions: translate/stop/swap/clipboard/navigation.
///
/// Split from `translator_controller.dart` - behavior is unchanged.
/// Contains: swap(), clearAll(), paste(), copyOutput(), openModelHub(),
///   stop(), translate()
part of 'translator_controller.dart';

extension TranslatorControllerActions on TranslatorController {
  void swap() {
    // Auto-detect can't be a target: fall back to English.
    if (sourceId.value == 'auto') return;
    final s = sourceId.value;
    sourceId.value = targetId.value;
    targetId.value = s;
    output.value = '';
    error.value = '';
  }

  void clearAll() {
    inputCtrl.clear();
    output.value = '';
    error.value = '';
  }

  Future<void> paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = (data?.text ?? '').trim();
      if (text.isEmpty) return;
      final cur = inputCtrl.text;
      final combined = (cur.isEmpty ? text : '$cur $text').trim();
      inputCtrl.text = combined.length > TranslatorController.maxInputChars
          ? combined.substring(0, TranslatorController.maxInputChars)
          : combined;
      inputCtrl.selection =
          TextSelection.collapsed(offset: inputCtrl.text.length);
    } catch (_) {}
  }

  void copyOutput() {
    final text = output.value.trim();
    if (text.isEmpty) return;
    try {
      Clipboard.setData(ClipboardData(text: text));
      Get.snackbar('Copied', 'Translation copied to clipboard.',
          snackPosition: SnackPosition.BOTTOM);
    } catch (_) {}
  }

  void openModelHub() {
    try {
      Get.find<ModelController>().modelScope.value = 'local';
    } catch (_) {}
    try {
      // Translator opens as a pushed route on top of home — pop back
      // to home first, otherwise the tab switch happens invisibly
      // underneath and the user never reaches the marketplace.
      Get.until((route) => route.isFirst);
    } catch (_) {}
    try {
      Get.find<HomeController>().changeTab(1);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _inference.stopGeneration();
    } catch (_) {}
  }

  /// Translate [inputText] with the loaded local model (streaming).
  Future<void> translate() async {
    final text = inputText.value.trim();
    if (text.isEmpty || translating.value) return;
    error.value = '';
    output.value = '';

    if (!modelReady) {
      error.value =
          'No local model loaded. Load one below (Qwen2.5-1.5B recommended).';
      return;
    }

    final src = sourceId.value == 'auto'
        ? 'the detected source language (detect it yourself)'
        : TranslatorController.labelOf(sourceId.value);
    final tgt = TranslatorController.labelOf(targetId.value);

    translating.value = true;
    final buf = StringBuffer();
    try {
      final raw = await _inference.generate(
        prompt: buildTranslationPrompt(
            sourceLabel: src, targetLabel: tgt, text: text),
        systemPrompt: 'You are a professional translator. '
            'Reply with the translation only.',
        source: 'translator',
        onToken: (t) {
          buf.write(t);
          output.value = buf.toString();
        },
      );
      if (raw.startsWith('ERROR')) {
        error.value = raw;
        output.value = '';
      } else {
        output.value =
            cleanTranslationOutput(raw.isEmpty ? buf.toString() : raw, text);
      }
    } catch (e) {
      error.value = 'Translation failed: $e';
    } finally {
      translating.value = false;
    }
  }
}
