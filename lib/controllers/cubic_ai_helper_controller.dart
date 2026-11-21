/// CubicAi Helper — a dedicated, page-aware chat for CubicWeb Browser.
///
/// Unlike the main Chat tab this controller owns a small, independent
/// conversation and always injects the content of the *current browser tab*
/// into the prompt. It uses the same engine switch as the rest of the app:
/// `SettingsController.inferenceMode` ('local' on-device or 'cloud' API).
library;

import 'package:get/get.dart';

import 'settings_controller.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';

/// Supplies a fresh snapshot of the active browser tab. Installed by the
/// browser view when CubicAi Helper is opened / the split pane is built.
typedef CubicPageProvider = Future<Map<String, String>?> Function();

class CubicAiMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  String content;
  final DateTime at;
  final String? pageTitle;
  final String? pageUrl;
  String? modelLabel;
  bool streaming;
  bool isError;

  CubicAiMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? at,
    this.pageTitle,
    this.pageUrl,
    this.modelLabel,
    this.streaming = false,
    this.isError = false,
  }) : at = at ?? DateTime.now();
}

class CubicAiHelperController extends GetxController {
  static CubicPageProvider? _pageProvider;

  /// Returns the single shared helper controller, creating it if the app's
  /// startup registration was skipped (e.g. a hot restart straight into a route).
  static CubicAiHelperController ensure() {
    if (Get.isRegistered<CubicAiHelperController>()) {
      return Get.find<CubicAiHelperController>();
    }
    return Get.put(CubicAiHelperController());
  }

  /// Called by the browser view with a closure that reads its current tab.
  static void bind(
    CubicPageProvider provider, {
    String? initialPrompt,
    String? extraContext,
  }) {
    _pageProvider = provider;
    if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
      ensure()._queue(initialPrompt.trim(), extraContext: extraContext);
    }
  }

  final messages = <CubicAiMessage>[].obs;
  final pageTitle = ''.obs;
  final pageUrl = ''.obs;
  final pageText = ''.obs;
  final hasPage = false.obs;
  final isBusy = false.obs;
  final contextLoading = false.obs;

  /// Set before navigating so the view can auto-send the first prompt.
  final pendingPrompt = ''.obs;
  String? pendingExtraContext;
  bool _pendingConsumed = false;

  int _serial = 0;
  int _counter = 0;

  SettingsController get _settings => Get.find<SettingsController>();

  bool get isCloud => _settings.inferenceMode.value == 'cloud';

  String get engineLabel => isCloud ? 'API' : 'Local';

  String get modelLabel {
    try {
      if (isCloud) {
        final provider = _settings.cloudProvider.value;
        final model = _settings.selectedCloudModelName;
        final shortProvider = provider.isEmpty ? 'api' : provider;
        if (model.isEmpty) return shortProvider;
        // Avoid an unreadably long header on small screens.
        final shortModel = model.length > 26 ? '${model.substring(0, 26)}…' : model;
        return '$shortProvider · $shortModel';
      }
      final inference = Get.find<InferenceService>();
      final name = inference.loadedModelName.value;
      if (name.isNotEmpty) return name.replaceAll('.gguf', '');
      return 'No local model loaded';
    } catch (_) {
      return isCloud ? 'API model' : 'No local model loaded';
    }
  }

  void _queue(String prompt, {String? extraContext}) {
    pendingPrompt.value = prompt;
    pendingExtraContext = extraContext;
    _pendingConsumed = false;
  }

  /// One-shot handoff used by the helper view / split pane.
  Map<String, dynamic>? consumePending() {
    if (_pendingConsumed || pendingPrompt.value.isEmpty) return null;
    _pendingConsumed = true;
    final map = <String, dynamic>{
      'prompt': pendingPrompt.value,
      'extraContext': pendingExtraContext,
    };
    pendingPrompt.value = '';
    pendingExtraContext = null;
    return map;
  }

  Future<void> setEngine(String mode) async {
    if (mode != 'local' && mode != 'cloud') return;
    await _settings.setInferenceMode(mode);
  }

  Future<void> refreshContext() async {
    final provider = _pageProvider;
    if (provider == null) return;
    contextLoading.value = true;
    try {
      final page = await provider();
      if (page == null) {
        pageTitle.value = '';
        pageUrl.value = '';
        pageText.value = '';
        hasPage.value = false;
        return;
      }
      pageTitle.value = (page['title'] ?? '').trim();
      pageUrl.value = (page['url'] ?? '').trim();
      pageText.value = (page['text'] ?? '').trim();
      hasPage.value = pageText.value.isNotEmpty;
    } catch (_) {
      // Keep the last good snapshot — it is still useful context.
    } finally {
      contextLoading.value = false;
    }
  }

  static const _kSystem = 'You are CubicAi Helper, the built-in AI assistant of '
      'CubicWeb Browser. The user is browsing a web page and you are given its '
      'title, URL and visible text as context. Prefer that page when answering '
      'questions about it; quote or paraphrase it accurately. If the answer is '
      'not in the page, say so briefly and then help using your own knowledge. '
      'Be clear, concise and friendly. Never invent page content.';

  String _buildSystem() {
    final buf = StringBuffer(_kSystem);
    if (pageText.value.isNotEmpty) {
      buf.writeln('\n\n[CURRENT BROWSER TAB]');
      if (pageTitle.value.isNotEmpty) buf.writeln('Title: ${pageTitle.value}');
      if (pageUrl.value.isNotEmpty) buf.writeln('URL: ${pageUrl.value}');
      buf.writeln('Page content:');
      // Keep local inference responsive on small context windows while
      // letting API models use as much of the page as we captured.
      final limit = isCloud ? 24000 : 9000;
      final text = pageText.value.length > limit
          ? '${pageText.value.substring(0, limit)}\n…[page truncated]'
          : pageText.value;
      buf.writeln(text);
    }
    return buf.toString();
  }

  List<Map<String, String>> _history() {
    final out = <Map<String, String>>[];
    for (final m in messages) {
      if (m.isError || m.content.trim().isEmpty) continue;
      if (m.role != 'user' && m.role != 'assistant') continue;
      out.add({'role': m.role, 'content': m.content.trim()});
    }
    if (out.length > 12) return out.sublist(out.length - 12);
    return out;
  }

  /// Streams a reply for [prompt] using the selected engine.
  Future<void> send(String prompt, {String? extraContext}) async {
    final clean = prompt.trim();
    if (clean.isEmpty || isBusy.value) return;

    await refreshContext();
    final system = _buildSystem();
    final history = _history();
    final enriched = StringBuffer(clean);
    if (extraContext != null && extraContext.trim().isNotEmpty) {
      enriched.writeln('\n\nSelected text from the page:\n${extraContext.trim()}');
    }

    final userMsg = CubicAiMessage(
      id: 'u${++_counter}',
      role: 'user',
      content: clean,
      pageTitle: hasPage.value ? pageTitle.value : null,
      pageUrl: hasPage.value ? pageUrl.value : null,
    );
    final answer = CubicAiMessage(
      id: 'a${++_counter}',
      role: 'assistant',
      content: '',
      pageTitle: hasPage.value ? pageTitle.value : null,
      pageUrl: hasPage.value ? pageUrl.value : null,
      modelLabel: modelLabel,
      streaming: true,
    );
    messages.add(userMsg);
    messages.add(answer);
    isBusy.value = true;

    final mySerial = ++_serial;
    void append(String token) {
      if (mySerial != _serial) return; // stopped / superseded
      answer.content += token;
      messages.refresh();
    }

    try {
      final String raw;
      if (isCloud) {
        final cloud = Get.find<CloudService>();
        if (!cloud.isConfigured) {
          throw const CubicAiEngineException(
            'No API provider is configured. Add an API key in Explore → Cloud '
            'models, or switch to Local mode.',
          );
        }
        final chat = <Map<String, String>>[
          {'role': 'system', 'content': system},
          ...history,
          {'role': 'user', 'content': enriched.toString()},
        ];
        raw = await cloud.sendMessage(
          messages: chat,
          maxTokens: 1024,
          onToken: append,
        );
      } else {
        final inference = Get.find<InferenceService>();
        if (!inference.isModelLoaded.value) {
          throw const CubicAiEngineException(
            'No on-device model is loaded. Open the model switcher to load one, '
            'or switch to API mode.',
          );
        }
        raw = await inference.generate(
          prompt: enriched.toString(),
          systemPrompt: system,
          conversationHistory: history,
          source: 'cubic_ai_helper',
          onToken: append,
        );
      }

      final trimmed = raw.trim();
      if (trimmed.startsWith('ERROR:')) {
        throw CubicAiEngineException(trimmed.replaceFirst('ERROR:', '').trim());
      }
      answer.content = trimmed.isEmpty ? 'No response from the model.' : trimmed;
      answer.modelLabel = modelLabel;
    } catch (e) {
      final text = e is CubicAiEngineException
          ? e.message
          : 'Could not reach the ${isCloud ? 'API provider' : 'local model'}: $e';
      answer.content = text;
      answer.isError = true;
    } finally {
      if (mySerial == _serial) {
        answer.streaming = false;
        isBusy.value = false;
        messages.refresh();
      }
    }
  }

  /// Cancels an in-flight answer (local generation is stopped at the engine).
  void stop() {
    if (!isBusy.value) return;
    _serial++;
    try {
      Get.find<InferenceService>().stopGeneration();
    } catch (_) {}
    for (final m in messages) {
      if (m.streaming) m.streaming = false;
    }
    isBusy.value = false;
    messages.refresh();
  }

  void clear() {
    _serial++;
    messages.clear();
    isBusy.value = false;
  }

  static const suggestions = <String, String>{
    'summarize': 'Summarize this page in 5 short bullet points.',
    'explain': 'Explain this page in simple terms.',
    'keyPoints': 'What are the most important takeaways from this page?',
    'askPage': 'What is this page about?',
  };
}

class CubicAiEngineException implements Exception {
  final String message;
  const CubicAiEngineException(this.message);

  @override
  String toString() => message;
}
