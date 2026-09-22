/// Writing assistant, AI theme generator, listening mode.
///
/// Split from `browser_sheets.dart` (part of `browser_view.dart`) - behavior is unchanged.
/// Contains: _showWritingAssistant(), _triggerAssistantAction(), _showAiThemeGenerator(), _generateAiTheme()
///   _toggleListeningMode()
part of 'browser_view.dart';

extension _BrowserSheetsAi on _BrowserViewState {
  void _showWritingAssistant() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('Writing Assistant', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter text to improve...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Improve');
                  },
                  child: const Text('Improve'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Simplify');
                  },
                  child: const Text('Simplify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerAssistantAction(String text, String action) async {
    if (text.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Assistant', 'Processing text...');
    Get.find<HomeController>().changeTab(0);
    await chat.askInNewChat('$action this text for me:\n\n$text');
  }

  void _showAiThemeGenerator() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('AI Theme Generator', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Describe a theme (e.g. Neon Cyberpunk)...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Get.back();
                _generateAiTheme(ctrl.text);
              },
              child: const Text('Generate Theme'),
            ),
            if (_settings.browserCustomTheme.isNotEmpty)
              TextButton(
                onPressed: () {
                  Get.back();
                  _settings.applyAiTheme({});
                },
                child: const Text('Reset Theme', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAiTheme(String prompt) async {
    if (prompt.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Theme', 'Generating color palette...');

    final result = await chat.askOnce(
      'Generate a color palette for a browser theme based on this prompt: "$prompt". Return ONLY a JSON object with these keys: "accent", "bg", "secondary". Use hex codes (e.g. #FF0000).',
    );

    if (result == null) return;
    try {
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(result);
      if (match != null) {
        final data = jsonDecode(match.group(0)!);
        if (data is Map) {
          final theme = data.map((k, v) => MapEntry(k.toString(), v.toString()));
          await _settings.applyAiTheme(theme);
          _toast('AI Theme', 'New theme applied!');
        }
      }
    } catch (_) {
      _toast('AI Theme', 'Failed to parse colors.');
    }
  }

  Future<void> _toggleListeningMode(WebTab tab) async {
    final tts = Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
    if (tts == null) return;

    if (_isReading.value) {
      await tts.stop();
      _isReading.value = false;
      return;
    }

    final page = await _extractPage(tab);
    if (page == null || (page['text'] ?? '').isEmpty) {
      _toast('Empty page', 'Nothing to read.');
      return;
    }

    _isReading.value = true;
    _toast('Listening Mode', 'Reading page...');
    await tts.speak(page['text']!);
    _isReading.value = false;
  }
}
