import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../services/inference_service.dart';
import 'home_controller.dart';
import 'model_controller.dart';

part 'translator_languages.dart';
part 'translator_prompt.dart';
part 'translator_actions.dart';

/// On-device translator state (CubicTranslator).
/// Uses the loaded local GGUF model (e.g. Qwen2.5-0.5B-Instruct) through
/// [InferenceService.generate] with a strict translation prompt — no
/// scripts, no cloud, everything stays on the phone.
///
/// Split for easy handling (one responsibility per file):
///   translator_languages.dart → language catalog
///   translator_prompt.dart    → prompt builder + output cleanup
///   translator_actions.dart   → translate/stop/swap/clipboard/navigation
class TranslatorController extends GetxController {
  static const maxInputChars = 2000;

  /// Kept for call-site compatibility (backed by translator_languages.dart).
  static List<TranslatorLanguage> get languages => translatorLanguages;
  static String labelOf(String id) => translatorLabelOf(id);

  final inputCtrl = TextEditingController();
  final inputText = ''.obs;
  final sourceId = 'auto'.obs;
  final targetId = 'en'.obs;
  final output = ''.obs;
  final translating = false.obs;
  final error = ''.obs;

  InferenceService get _inference {
    try {
      return Get.find<InferenceService>();
    } catch (_) {
      throw StateError('InferenceService not registered');
    }
  }

  @override
  void onInit() {
    super.onInit();
    // Default target = device language when supported, else English.
    try {
      final code = Get.locale?.languageCode ?? '';
      if (translatorLanguages.any((l) => l.id == code)) {
        targetId.value = code;
      }
    } catch (_) {}
    inputCtrl.addListener(() {
      var v = inputCtrl.text;
      if (v.length > maxInputChars) {
        v = v.substring(0, maxInputChars);
        inputCtrl.value = TextEditingValue(
          text: v,
          selection: TextSelection.collapsed(offset: v.length),
        );
      }
      inputText.value = v;
    });
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }

  bool get canTranslate =>
      inputText.value.trim().isNotEmpty && !translating.value;

  bool get modelReady {
    try {
      return _inference.isModelLoaded.value;
    } catch (_) {
      return false;
    }
  }

  String get loadedModelName {
    try {
      return _inference.loadedModelName.value;
    } catch (_) {
      return '';
    }
  }
}
