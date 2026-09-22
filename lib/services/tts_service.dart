import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../utils/app_snackbar.dart';
import '../controllers/settings_controller.dart';

/// Minimal TTS service wrapping `flutter_tts`.
///
/// - Web stub: no-op + snackbar (flutter_tts Web Speech is not used).
/// - Language from [Get.locale] / [SettingsController.locale].
/// - Fixed speech rate 0.5.
class TtsService extends GetxService {
  FlutterTts? _flutterTts;
  final isSpeaking = false.obs;
  final isInitialized = false.obs;
  String _currentText = '';

  String get currentText => _currentText;

  Future<TtsService> init() async {
    try {
      _flutterTts = FlutterTts();
      await _flutterTts!.awaitSpeakCompletion(true);
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);
      await _applyLocaleLanguage();

      _flutterTts!.setStartHandler(() {
        isSpeaking.value = true;
      });
      _flutterTts!.setCompletionHandler(() {
        isSpeaking.value = false;
        _currentText = '';
      });
      _flutterTts!.setCancelHandler(() {
        isSpeaking.value = false;
        _currentText = '';
      });
      _flutterTts!.setErrorHandler((_) {
        isSpeaking.value = false;
        _currentText = '';
      });

      isInitialized.value = true;
    } catch (_) {
      isInitialized.value = false;
    }
    return this;
  }

  /// Speak [rawText]. If already speaking the same text, toggles stop.
  /// Shows top snackbar on start/stop. Web uses the browser speech engine
  /// via the flutter_tts web backend.
  Future<void> speak(String rawText) async {

    // Respect user toggle.
    if (Get.isRegistered<SettingsController>()) {
      final sc = Get.find<SettingsController>();
      if (!sc.readAloudEnabled.value) {
        AppSnackbar.showTop(
          'Read aloud off',
          'Enable it in App Settings to use text-to-speech',
          icon: LucideIcons.volumeX,
          iconName: 'volumeX',
          logHistory: false,
        );
        return;
      }
    }

    final text = _cleanForSpeech(rawText);
    if (text.trim().isEmpty) {
      AppSnackbar.showTop(
        'Nothing to read',
        'Message is empty',
        icon: LucideIcons.volumeX,
        iconName: 'volumeX',
        logHistory: false,
      );
      return;
    }

    // Toggle if same utterance is already playing.
    if (isSpeaking.value && _currentText == text) {
      await stop();
      return;
    }

    // Stop any current speech before starting new one.
    if (isSpeaking.value) {
      try {
        await _flutterTts?.stop();
      } catch (_) {}
      isSpeaking.value = false;
    }

    if (_flutterTts == null) {
      await init();
      if (_flutterTts == null) {
        AppSnackbar.showTop(
          'TTS unavailable',
          'Speech engine not initialized',
          icon: LucideIcons.volumeX,
          iconName: 'volumeX',
          logHistory: false,
        );
        return;
      }
    }

    _currentText = text;
    await _applyLocaleLanguage();
    try {
      await _flutterTts!.setSpeechRate(0.5);
    } catch (_) {}

    isSpeaking.value = true;
    AppSnackbar.showTop(
      'Reading aloud',
      _truncate(text, 80),
      icon: LucideIcons.volume2,
      iconName: 'volume2',
      type: 'tts',
      logHistory: false,
    );

    try {
      final result = await _flutterTts!.speak(text);
      // Some platforms return 0/1, others null. 0 can mean failure.
      if (result == 0) {
        isSpeaking.value = false;
        _currentText = '';
        AppSnackbar.showTop(
          'TTS failed',
          'Could not start speech on this device',
          icon: LucideIcons.volumeX,
          iconName: 'volumeX',
          logHistory: false,
        );
      }
    } catch (e) {
      isSpeaking.value = false;
      _currentText = '';
      AppSnackbar.showTop(
        'TTS error',
        e.toString(),
        icon: LucideIcons.volumeX,
        iconName: 'volumeX',
        logHistory: false,
      );
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts?.stop();
    } catch (_) {}
    final wasSpeaking = isSpeaking.value;
    isSpeaking.value = false;
    _currentText = '';
    if (wasSpeaking) {
      AppSnackbar.showTop(
        'Stopped',
        'Read aloud stopped',
        icon: LucideIcons.volumeX,
        iconName: 'volumeX',
        logHistory: false,
      );
    }
  }

  Future<void> _applyLocaleLanguage() async {
    if (_flutterTts == null) return;
    String code = 'en';
    try {
      if (Get.isRegistered<SettingsController>()) {
        code = Get.find<SettingsController>().locale.value.code;
      } else if (Get.locale != null) {
        code = Get.locale!.languageCode;
      }
    } catch (_) {}
    final ttsLocale = _ttsLanguageForCode(code);
    try {
      await _flutterTts!.setLanguage(ttsLocale);
    } catch (_) {}
  }

  String _ttsLanguageForCode(String code) {
    switch (code) {
      case 'bn':
        return 'bn-BD';
      case 'hi':
        return 'hi-IN';
      case 'ar':
        return 'ar-SA';
      case 'zh':
        return 'zh-CN';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'pt':
        return 'pt-BR';
      case 'de':
        return 'de-DE';
      case 'tr':
        return 'tr-TR';
      case 'id':
        return 'id-ID';
      case 'ru':
        return 'ru-RU';
      case 'ur':
        return 'ur-PK';
      case 'en':
      default:
        return 'en-US';
    }
  }

  /// Strip thinking tags, markdown, and attachment footers for cleaner speech.
  String _cleanForSpeech(String raw) => cleanTextForSpeech(raw);

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max).trim()}…';
  }

  @override
  void onClose() {
    try {
      _flutterTts?.stop();
    } catch (_) {}
    super.onClose();
  }
}

/// Speech-ready text cleanup (top-level + pure so it is unit-testable).
/// Strips everything a speech engine would read as gibberish: think
/// blocks, code (summarized, not read), bare URLs, LaTeX math, HTML,
/// markdown markup and emoji (engines spell emoji names aloud).
String cleanTextForSpeech(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  // Remove <think>...</think> blocks (including unclosed thinking).
  s = s.replaceAll(
      RegExp(r'<think>.*?</think>', caseSensitive: false, dotAll: true), ' ');
  s = s.replaceAll(
      RegExp(r'<think>.*', caseSensitive: false, dotAll: true), ' ');

  // Remove attached file footer.
  final attachedIdx = s.indexOf('Attached file:');
  if (attachedIdx != -1) {
    s = s.substring(0, attachedIdx);
  }

  // Remove special tokens.
  s = s.replaceAll('<|endoftext|>', ' ');
  s = s.replaceAll('<|im_end|>', ' ');
  s = s.replaceAll('<|end|>', ' ');

  // LaTeX math ($..$, $$..$$, \(..\)) -> placeholder (else the engine
  // reads dollar/backslash/brace soup).
  s = s.replaceAll(RegExp(r'\$\$.+?\$\$', dotAll: true), ' math expression ');
  s = s.replaceAll(RegExp(r'\$[^$\n]+\$'), ' math expression ');
  s = s.replaceAll(RegExp(r'\\\(.+?\\\)'), ' math expression ');

  // Code fences -> a short marker (reading 50 lines of code aloud is
  // noise; the user sees the block on screen).
  s = s.replaceAllMapped(RegExp(r'```[\s\S]*?```'), (m) {
    final inner = m.group(0)!.replaceAll('```', '').trim();
    if (inner.isEmpty) return ' code block ';
    final firstLine = inner.split('\n').first.trim();
    // Tiny snippets (one-liners) are worth reading; big blocks aren't.
    if (!inner.contains('\n') && firstLine.length <= 80) {
      return ' $firstLine ';
    }
    return ' code snippet ';
  });

  // Inline code `...` -> keep short content, summarize long content.
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) {
    final inner = m.group(1)!.trim();
    return inner.length <= 40 ? ' $inner ' : ' code ';
  });

  // Bare URLs -> "link" (else the engine spells h-t-t-p-s aloud).
  s = s.replaceAllMapped(
      RegExp(r'https?://[^\s)>\]]+'), (m) => ' link ');

  // Images ![alt](url) -> alt
  s = s.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), (m) => ' ${m.group(1)} ');

  // Links [text](url) -> text
  s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (m) => ' ${m.group(1)} ');

  // Headings: remove leading #'s
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

  // Bold/italic markers (replaceAllMapped: plain replaceAll does NOT
  // substitute $1 — it would read "dollar-one" aloud).
  s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!);
  s = s.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1)!);
  // Simple * wrappers (avoid mangling normal underscores)
  s = s.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!);

  // Blockquote markers
  s = s.replaceAll(RegExp(r'^>\s?', multiLine: true), '');

  // List bullets at line start
  s = s.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

  // HTML tags
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');

  // Emoji + pictographs (engines spell their names aloud).
  s = s.replaceAll(
      RegExp(
          r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
          unicode: true),
      ' ');

  // Collapse markdown table pipes and dashes
  s = s.replaceAll('|', ' ');
  s = s.replaceAll(RegExp(r'-{2,}'), ' ');

  // Collapse whitespace
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  return s;
}
