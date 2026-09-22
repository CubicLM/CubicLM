import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart'
    show compute, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import '../controllers/settings_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/home_controller.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/project_model.dart';
import '../models/folder_model.dart';
import '../ffi/sd_ffi_bindings.dart';
import '../services/hive_service.dart';
import '../services/chat_backup.dart';
import '../services/web_fetch_service.dart';
import '../services/web_search_service.dart';
import '../services/inference_service.dart';
import '../services/cloud_service.dart';
import '../services/local_image_service.dart';
import '../services/tts_service.dart';
import '../services/app_log_service.dart';
import '../services/image_generation_notification_service.dart';
import '../services/document_extractor_service.dart';
import '../services/skills/skill_injector.dart';
import '../models/web_source.dart';
import '../utils/thought_parser.dart';
import '../utils/text_sanitize.dart';
import '../utils/paste_convert.dart';
import '../utils/app_snackbar.dart';
import '../utils/history_budget.dart';
import '../utils/memory_extract.dart';
import '../services/stats_service.dart';
import '../services/device_info_service.dart';
import '../services/tool_service.dart';
import '../services/memory_service.dart';
import '../services/vector_service.dart';
import '../utils/artifact_parser.dart';

part 'chat_controller_sessions.dart';
part 'chat_controller_templates.dart';
part 'chat_controller_messages.dart';
part 'chat_controller_attachments.dart';
part 'chat_controller_generation.dart';
part 'chat_controller_find.dart';
part 'chat_controller_voice.dart';

const int _visionImageMaxSide = 768;
const int _visionImageJpegQuality = 72;

class ChatController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  // State
  final sessions = <ChatSession>[].obs;
  final messages = <ChatMessage>[].obs;
  final projects = <ChatProject>[].obs;
  final folders = <ChatFolder>[].obs;

  // Session-list UI state (logic lives in chat_controller_sessions).
  final showArchived = false.obs;
  final showHidden = false.obs;
  final labelFilter = ''.obs;
  static const int _chatPageSize = 100;
  final hasOlderMessages = false.obs;
  final isLoadingOlder = false.obs;
  ChatSession? _trashSession;
  List<Map<String, dynamic>> _trashMessages = [];
  final currentSessionId = ''.obs;
  final currentProjectId = Rxn<String>();
  final isLoading = false.obs;
  final inputText = ''.obs;
  final selectedImagePath = Rxn<String>();
  final selectedImageBase64 = Rxn<String>();
  final selectedFileName = Rxn<String>();
  final selectedFileContent = Rxn<String>();
  final selectedFilePath = Rxn<String>();
  final selectedFileType = Rxn<String>();
  final selectedFileSize = 0.obs;
  final selectedFileChunks = <String>[].obs;

  // Real-time LaTeX Preview
  final latexPreviewText = ''.obs;
  Timer? _latexDebounce;

  // IDE Mode / Active Project File
  final activeProjectFile = Rxn<String>(); // Path

  // Real-time streaming state — the AI response as it's being generated
  final streamingResponse = ''.obs;
  final streamingThought = ''.obs;
  final streamingAnswer = ''.obs;
  final streamingIsThinking = false.obs;
  final isStreaming = false.obs;
  final streamingAttachmentType = Rxn<String>();
  final generationStartTime = Rxn<DateTime>();
  final generationLiveDurationSecs = 0.obs;
  Timer? _generationTimer;

  // Image generation progress (lightweight, replaces text-heavy updates)
  final imageGenStep = 0.obs;
  final imageGenTotal = 0.obs;
  final imageGenEstimatedSecs = 0.obs;
  final imageGenStartTime = Rxn<DateTime>();
  final imageGenDecoding = false.obs;

  // UI state
  final showScrollToBottom = false.obs;

  // Artifacts (Claude-style side panel)
  final activeArtifactId = Rxn<String>();
  final artifacts = <String, List<Map<String, String>>>{}
      .obs; // id -> [{title, type, content, timestamp}]
  final showArtifactPanel = false.obs;

  // Tool call steps (MCP / Agent visual pipeline)
  final currentToolSteps = <Map<String, dynamic>>[].obs;

  void addToolStep({
    required String name,
    Map<String, dynamic> args = const {},
    String output = '',
    bool success = true,
    int durationMs = 0,
    List<String> modifiedFiles = const [],
    bool running = false,
  }) {
    currentToolSteps.add({
      'name': name,
      'args': args,
      'output': output,
      'success': success,
      'durationMs': durationMs,
      'modifiedFiles': modifiedFiles,
      'running': running,
    });
  }

  // Search Mode (Perplexity-style)
  final isSearchMode = false.obs;

  // Prompt templates
  static const _kTemplatesKey = 'prompt_templates_v1';
  final promptTemplates = <Map<String, String>>[].obs;
  bool _templatesLoaded = false;
  final templateSearchQuery = ''.obs;

  List<Map<String, String>> get filteredTemplates {
    final query = templateSearchQuery.value.toLowerCase();
    if (query.isEmpty) return promptTemplates;
    return promptTemplates.where((t) {
      final name = (t['name'] ?? '').toLowerCase();
      final body = (t['body'] ?? '').toLowerCase();
      return name.contains(query) || body.contains(query);
    }).toList();
  }

  // Multi-select
  final selectionMode = false.obs;
  final selectedIds = <String>{}.obs;

  // Project Chunks Cache
  final _projectChunkCache = <String, List<String>>{};

  Future<String> _getProjectRelevantContext(String query, ChatProject project) async {
    if (project.filePaths.isEmpty) return '';
    
    final vs = Get.find<VectorService>();
    
    // Check cache
    List<String> chunks = _projectChunkCache[project.id] ?? [];
    
    if (chunks.isEmpty) {
      for (final path in project.filePaths) {
        try {
          final ext = path.split('.').last.toLowerCase();
          final text = await DocumentExtractorService.extractText(path, ext);
          if (text.isNotEmpty) {
            chunks.addAll(vs.chunkText(text));
          }
        } catch (_) {}
      }
      _projectChunkCache[project.id] = chunks;
    }
    
    if (chunks.isEmpty) return '';
    final hits = vs.retrieve(query, chunks, topK: 5);
    return hits.map((h) => "> $h").join('\n\n');
  }
  
  void invalidateProjectCache(String projectId) {
    _projectChunkCache.remove(projectId);
  }

  Future<String?> pickProjectRoot(ChatProject project) async {
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected != null) {
        final updated = project.copyWith(rootPath: selected);
        final idx = projects.indexOf(project);
        if (idx >= 0) projects[idx] = updated;
        await _hive.saveProject(project.id, updated.toMap());
        return selected;
      }
    } catch (_) {}
    return null;
  }

  // Side-by-side compare
  Map<String, String>? _compareRef;
  final compareLabel = ''.obs;

  // Streaming draft
  String? _draftMsgId;

  void openArtifact(String id, String content, {String? title, String? type}) {
    final version = {
      'title': title ?? 'Artifact',
      'type': type ?? 'code',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (artifacts.containsKey(id)) {
      if (artifacts[id]!.last['content'] != content) {
        artifacts[id]!.add(version);
      }
    } else {
      artifacts[id] = [version];
    }

    activeArtifactId.value = id;
    showArtifactPanel.value = true;
  }

  void updateArtifact(String id, String content) {
    if (!artifacts.containsKey(id)) return;
    final last = artifacts[id]!.last;
    final version = {
      'title': last['title'] ?? 'Artifact',
      'type': last['type'] ?? 'code',
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };
    artifacts[id]!.add(version);
    artifacts.refresh();

    // Persist changes to Hive
    try {
      final msg = messages.firstWhereOrNull(
        (m) => m.artifacts?.any((a) => a['id'] == id) ?? false,
      );
      if (msg != null) {
        final updatedArtifacts = msg.artifacts!.map((a) {
          if (a['id'] == id) {
            return {...a, 'content': content};
          }
          return a;
        }).toList();
        final idx = messages.indexOf(msg);
        if (idx != -1) {
          final updatedMsg = msg.copyWithArtifacts(updatedArtifacts);
          messages[idx] = updatedMsg;
          persistMessage(updatedMsg);
        }
      }
    } catch (_) {}
  }

  Future<void> persistMessage(ChatMessage msg) async {
    try {
      await _hive.saveMessage(msg.id, msg.toMap());
    } catch (_) {}
  }

  void closeArtifact() {
    showArtifactPanel.value = false;
  }

  // Response Mode: 0 = Single, 1 = Dual, 2 = Triple
  final responseMode = 0.obs;

  bool get dualResponseMode => responseMode.value >= 1;
  bool get tripleResponseMode => responseMode.value >= 2;

  void toggleResponseMode() {
    responseMode.value = (responseMode.value + 1) % 3;
    final labels = ['Single', 'Dual', 'Triple'];
    Get.snackbar(
      '${labels[responseMode.value]} Mode',
      'AI will generate ${responseMode.value + 1} version(s) for comparison.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> setPreference(String messageId, int index) async {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = messages[idx];
    final updated = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: msg.content,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      tokensPerSec: msg.tokensPerSec,
      thoughtDurationSeconds: msg.thoughtDurationSeconds,
      generationDurationMs: msg.generationDurationMs,
      timestamp: msg.timestamp,
      webSources: msg.webSources,
      usedSkills: msg.usedSkills,
      artifacts: msg.artifacts,
      citations: msg.citations,
      alternatives: msg.alternatives,
      preferredIndex: index,
      feedback: msg.feedback,
      suggestions: msg.suggestions,
    );
    messages[idx] = updated;
    await _hive.saveMessage(updated.id, updated.toMap());
  }

  Future<void> setFeedback(String messageId, String feedback) async {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = messages[idx];
    final updated = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: msg.content,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      tokensPerSec: msg.tokensPerSec,
      thoughtDurationSeconds: msg.thoughtDurationSeconds,
      generationDurationMs: msg.generationDurationMs,
      timestamp: msg.timestamp,
      webSources: msg.webSources,
      usedSkills: msg.usedSkills,
      artifacts: msg.artifacts,
      citations: msg.citations,
      alternatives: msg.alternatives,
      preferredIndex: msg.preferredIndex,
      feedback: feedback,
      suggestions: msg.suggestions,
    );
    messages[idx] = updated;
    await _hive.saveMessage(updated.id, updated.toMap());
  }

  // Speech-to-text
  final isListening = false.obs;
  final sttAvailable = false.obs;
  final _speech = stt.SpeechToText();

  final voiceMode = false.obs;
  bool _voiceSpeaking = false;
  bool _voiceSendArmed = true;
  bool _wasLoading = false;
  bool _voiceStopQuiet = false;
  final _voiceWorkers = <Worker>[];

  /// Prompts sent while a generation is busy wait here FIFO instead of
  /// being dropped (see sendMessage isBusy branch + queue drain).
  final pendingQueue = <Map<String, dynamic>>[];

  // Outbox state (logic lives in chat_controller_generation).
  bool _flushingOutbox = false;
  DateTime? _outboxBackoffUntil;



  final textController = TextEditingController();
  final scrollController = ScrollController();
  final composerFocusNode = FocusNode();
  final composerKeyboardFocusNode = FocusNode();

  /// A single text change adding this many chars counts as a bulk insert
  /// (paste), eligible for auto-convert to a file attachment.
  static const int longPasteThreshold = 2000;

  /// Set while our own code rewrites the composer, so the paste watcher
  /// doesn't mistake bulk programmatic inserts for user pastes.
  bool suppressPasteWatch = false;
  String _lastComposerText = '';

  /// Runs [fn] with the paste watcher suppressed, resyncing the
  /// baseline afterwards. Use around programmatic bulk writes.
  T withoutPasteWatch<T>(T Function() fn) {
    suppressPasteWatch = true;
    try {
      return fn();
    } finally {
      suppressPasteWatch = false;
      _lastComposerText = textController.text;
    }
  }

  /// Watches for huge pastes (IME commits bypass menus/shortcuts) and
  /// converts them to a file attachment, keeping surrounding text.
  void _watchComposerPaste() {
    final cur = textController.text;
    final prev = _lastComposerText;
    _lastComposerText = cur;
    if (suppressPasteWatch) return;
    if (!looksLikeBulkInsert(prev, cur, longPasteThreshold)) return;
    final inserted = extractInserted(prev, cur);
    if (inserted.length < longPasteThreshold) return;
    withoutPasteWatch(() {
      textController.text = removeInserted(prev, cur);
      inputText.value = textController.text;
    });
    unawaited(handlePastedText(inserted));
  }

  /// Converts huge pasted text into a .md file attachment (GPT-style).
  /// Returns true when converted (caller should NOT insert the text).
  /// Honors the [SettingsController.longPasteToFile] toggle.
  Future<bool> handlePastedText(String pasted) async {
    if (pasted.length < longPasteThreshold) return false;
    try {
      if (Get.isRegistered<SettingsController>()) {
        if (!Get.find<SettingsController>().longPasteToFile.value) {
          return false;
        }
      }
    } catch (_) {
      return false;
    }
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = 'pasted-$stamp.md';
      final file = File('${dir.path}/$name');
      await file.writeAsString(pasted, flush: true);
      selectedFileName.value = name;
      selectedFileType.value = 'md';
      selectedFileSize.value = pasted.length;
      selectedFilePath.value = file.path;
      selectedFileContent.value = pasted;
      try {
        if (Get.isRegistered<VectorService>()) {
          selectedFileChunks.assignAll(
              Get.find<VectorService>().chunkText(pasted));
        }
      } catch (_) {}
      AppSnackbar.showTop(
          'Pasted as file', '$name attached — send to include it.',
          icon: LucideIcons.fileText, type: 'general', logHistory: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  final findActive = false.obs;
  final findQuery = ''.obs;
  final findMatches = <String>[].obs;
  final findIndex = 0.obs;
  final findController = TextEditingController();
  final _findKeys = <String, GlobalKey>{};
  int _findGen = 0;
  final historySearchFocus = FocusNode();

  /// Active ChatView Scaffold key (per mounted instance — see
  /// _ChatViewElement). Null when no ChatView is mounted.
  GlobalKey<ScaffoldState>? chatScaffoldKey;


  Timer? _scrollTimer;
  bool _followStreaming = true;
  bool _scrollListenerAttached = false;
  int _generationSerial = 0;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_handleUserScroll);
    textController.addListener(_onTextChanged);
    textController.addListener(_watchComposerPaste);
    _lastComposerText = textController.text;
    _scrollListenerAttached = true;
    loadSessions();
    loadProjects();
    loadFolders();
    _initSpeech();
    _loadAutoBackupPrefs();
    unawaited(checkSharedText());
    if (!_autoBackupChecked) {
      _autoBackupChecked = true;
      unawaited(Future.delayed(
          const Duration(seconds: 10), () => maybeAutoBackup(_hive)));
    }
  }

  static bool _autoBackupChecked = false;

  Future<void> checkSharedText() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      final text = await const MethodChannel('com.cubiclm.app/model_import')
          .invokeMethod<String>('getSharedText');
      if (text == null || text.trim().isEmpty) return;
      if (currentSessionId.value.isEmpty) createNewChat();
      final cur = textController.text;
      withoutPasteWatch(() {
        textController.text =
            cur.isEmpty ? sanitizeUtf16(text) : '$cur\n${sanitizeUtf16(text)}';
      });
      try {
        textController.selection =
            TextSelection.collapsed(offset: textController.text.length);
      } catch (_) {}
      inputText.value = textController.text;
      try {
        if (Get.isRegistered<HomeController>()) {
          Get.find<HomeController>().changeTab(0);
        }
      } catch (_) {}
      Get.snackbar('Shared text added', 'Review and tap send when ready.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Insert browser-extracted page text into the composer for review.
  /// Same pattern as [checkSharedText]: never auto-sends, jumps to Chat.
  void insertBrowserExtract(String title, String url, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (currentSessionId.value.isEmpty) createNewChat();
    final header = title.trim().isEmpty ? url : '${title.trim()} ($url)';
    final block = sanitizeUtf16('[Web page: $header]\n$clean');
    final cur = textController.text;
    withoutPasteWatch(() {
      textController.text = cur.isEmpty ? block : '$cur\n\n$block';
    });
    try {
      textController.selection =
          TextSelection.collapsed(offset: textController.text.length);
    } catch (_) {}
    inputText.value = textController.text;
    try {
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().changeTab(0);
      }
    } catch (_) {}
  }

  final autoBackupEnabled = false.obs;
  final autoBackupDays = 7.obs;
  static const List<int> autoBackupDayOptions = [1, 3, 7, 14, 30];

  void _loadAutoBackupPrefs() {
    try {
      autoBackupEnabled.value = _hive.getSetting<bool>(
              AppConstants.keyAutoBackupEnabled,
              defaultValue: false) ??
          false;
      autoBackupDays.value = _hive.getSetting<int>(
              AppConstants.keyAutoBackupDays,
              defaultValue: 7) ??
          7;
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    try {
      sttAvailable.value = await _speech.initialize(
        onError: (_) => isListening.value = false,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            isListening.value = false;
          }
        },
      );
    } catch (_) {
      sttAvailable.value = false;
    }
  }


  @override
  void onClose() {
    _detachVoiceWorkers();
    _scrollTimer?.cancel();
    if (_scrollListenerAttached) {
      scrollController.removeListener(_handleUserScroll);
    }
    textController.dispose();
    findController.dispose();
    composerFocusNode.dispose();
    composerKeyboardFocusNode.dispose();
    historySearchFocus.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void stopGenerating() {
    if (!isLoading.value && !isStreaming.value) return;
    _voiceStopQuiet = true;
    _voiceSpeaking = false;
    try {
      if (Get.isRegistered<TtsService>()) Get.find<TtsService>().stop();
    } catch (_) {}
    final partialResponse = streamingResponse.value.trim();

    final genDurationMs = generationStartTime.value != null
        ? DateTime.now().difference(generationStartTime.value!).inMilliseconds
        : null;

    if (partialResponse.isNotEmpty) {
      final tps = Get.find<InferenceService>().tokensPerSecond.value;
      _dropStreamingDraft();
      _saveAssistantMessage(
        content: partialResponse,
        tokensPerSec: tps > 0 ? tps : null,
        generationDurationMs: genDurationMs,
      );
    }
    _generationSerial++;
    _generationTimer?.cancel();
    _generationTimer = null;
    isLoading.value = false;
    isStreaming.value = false;
    streamingAttachmentType.value = null;
    streamingResponse.value = '';
    generationStartTime.value = null;
    generationLiveDurationSecs.value = 0;
    Get.find<ImageGenerationNotificationService>().cancel();
    imageGenStep.value = 0;
    imageGenTotal.value = 0;
    imageGenEstimatedSecs.value = 0;
    imageGenStartTime.value = null;
    imageGenDecoding.value = false;
    unawaited(Get.find<InferenceService>().stopGeneration());
    Get.find<LocalImageService>().cancelGeneration();
  }


  bool _isImageGenerationPrompt(String prompt) {
    final lower = prompt.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (lower.startsWith('/image') ||
        lower.startsWith('/img') ||
        lower.startsWith('/draw') ||
        lower.startsWith('/generate image')) {
      return true;
    }
    const triggers = [
      'generate image', 'create image', 'make image', 'generate a image',
      'create a picture', 'generate a picture', 'make a picture',
      'generate photo', 'create photo', 'draw a', 'draw an',
      'painting of', 'illustration of', 'render image', 'generate picture',
    ];
    if (triggers.any((t) => lower.contains(t))) return true;
    final hasImageWord = lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('illustration') ||
        lower.contains('artwork');
    final hasAction = lower.contains('generate') ||
        lower.contains('create') ||
        lower.contains('make') ||
        lower.contains('draw') ||
        lower.contains('render') ||
        lower.contains('paint') ||
        lower.contains('design');
    if (hasImageWord && hasAction) return true;
    if (lower.contains('draw ')) return true;
    return false;
  }
}
