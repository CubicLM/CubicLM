/// Voice for [ChatController]: TTS playback, voice mode, speech
/// recognition, locale mapping and read-aloud.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: _tts(), setVoiceMode(), _attachVoiceWorkers(), _onTextChanged(), _detachVoiceWorkers()
///   _onVoiceReplyReady(), toggleListening(), _sttLocaleId()
part of 'chat_controller.dart';

extension ChatControllerVoice on ChatController {
  TtsService? _tts() {
    try {
      return Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
    } catch (_) {
      return null;
    }
  }

  void setVoiceMode(bool on) {
    voiceMode.value = on;
    if (on) {
      _voiceStopQuiet = false;
      _voiceSpeaking = false;
      _voiceSendArmed = true;
      _attachVoiceWorkers();
      Get.snackbar(
        'Hands-free on',
        'Speak, and CubicLM replies aloud. Tap the headset icon to stop.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      unawaited(toggleListening());
    } else {
      _detachVoiceWorkers();
      _voiceSpeaking = false;
      try {
        _speech.stop();
      } catch (_) {}
      try {
        _tts()?.stop();
      } catch (_) {}
      isListening.value = false;
    }
  }

  void _attachVoiceWorkers() {
    _detachVoiceWorkers();
    final tts = _tts();
    if (tts != null) {
      _voiceWorkers.add(ever<bool>(tts.isSpeaking, (speaking) {
        if (!voiceMode.value) return;
        if (_voiceSpeaking && !speaking) {
          _voiceSpeaking = false;
          _voiceSendArmed = true;
          unawaited(toggleListening());
        }
      }));
    }
    _voiceWorkers.add(ever<bool>(isLoading, (loading) {
      if (_wasLoading && !loading) unawaited(_onVoiceReplyReady());
      _wasLoading = loading;
    }));

    _voiceWorkers.add(ever<bool>(isListening, (listening) {
      if (voiceMode.value && listening && tts != null && tts.isSpeaking.value) {
        unawaited(tts.stop());
      }
    }));
  }

  void _onTextChanged() {
    inputText.value = textController.text;
    
    // LaTeX Preview logic
    _latexDebounce?.cancel();
    _latexDebounce = Timer(const Duration(milliseconds: 300), () {
      final text = textController.text;
      if (text.contains(r'$') || text.contains(r'$$')) {
        latexPreviewText.value = text;
      } else {
        latexPreviewText.value = '';
      }
    });
  }

  void _detachVoiceWorkers() {
    for (final w in _voiceWorkers) {
      try {
        w.dispose();
      } catch (_) {}
    }
    _voiceWorkers.clear();
  }

  Future<void> _onVoiceReplyReady() async {
    if (!voiceMode.value) return;
    if (_voiceStopQuiet) {
      _voiceStopQuiet = false;
      return;
    }
    if (currentSessionId.value.isEmpty) return;
    ChatMessage? last;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.chatId == currentSessionId.value &&
          m.role == 'assistant' &&
          m.content.trim().isNotEmpty) {
        last = m;
        break;
      }
    }
    if (last == null) return;
    final tts = _tts();
    if (tts == null) {
      _voiceSendArmed = true;
      unawaited(toggleListening());
      return;
    }
    _voiceSpeaking = true;
    _voiceSendArmed = true;
    await tts.speak(last.content);
  }

  Future<void> toggleListening() async {
    try {
      if (isListening.value) {
        await _speech.stop();
        isListening.value = false;
        return;
      }
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        var mic = await Permission.microphone.status;
        if (!mic.isGranted) {
          mic = await Permission.microphone.request();
        }
        if (mic.isPermanentlyDenied) {
          Get.snackbar(
            'Microphone blocked',
            'Allow microphone access in system settings to use voice input.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
            mainButton: const TextButton(
              onPressed: openAppSettings,
              child: Text('Open settings'),
            ),
          );
          return;
        }
        if (!mic.isGranted) return;
      }
      if (!sttAvailable.value) {
        try {
          final ok = await _speech.initialize();
          sttAvailable.value = ok;
        } catch (_) {
          sttAvailable.value = false;
        }
        if (!sttAvailable.value) {
          Get.snackbar('Voice Input Unavailable',
              'Speech recognition is not available on this device.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }
      }
      await _speech.listen(
        onResult: (result) {
          textController.text = sanitizeUtf16(result.recognizedWords);
          inputText.value = textController.text;
          if (voiceMode.value && result.finalResult) {
            final said = result.recognizedWords.trim();
            if (said.isNotEmpty && _voiceSendArmed && !isLoading.value) {
              _voiceSendArmed = false;
              sendMessage();
            }
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          localeId: _sttLocaleId(),
        ),
      );
      isListening.value = true;
      _voiceSendArmed = true;
    } catch (_) {
      isListening.value = false;
    }
  }

  String _sttLocaleId() {
    var code = 'en';
    try {
      if (Get.isRegistered<SettingsController>()) {
        code = Get.find<SettingsController>().locale.value.code;
      } else if (Get.locale != null) {
        code = Get.locale!.languageCode;
      }
    } catch (_) {}
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
}
