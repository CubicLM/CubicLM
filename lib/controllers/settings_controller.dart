import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart' as la;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants.dart';
import '../services/hive_service.dart';
import '../services/secure_key_store.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../services/inference_service.dart';
import '../services/download_service.dart';
import '../services/local_image_service.dart';
import '../utils/export_file.dart';
import '../ffi/sd_ffi_bindings.dart';
import 'package:sd_flutter_android/sd_flutter_android.dart';
import '../services/skills/skill_injector.dart';
import '../services/browser/adblock_service.dart';
import '../utils/browser_utils.dart';
import '../core/languages.dart';

part 'settings_loading.dart';
part 'settings_cloud.dart';
part 'settings_browser.dart';
part 'settings_media.dart';
part 'settings_appearance.dart';

class SettingsController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final SecureKeyStore _keys = Get.find<SecureKeyStore>();

  /// All Hive option-keys that hold API keys and must live in secure storage.
  static const List<String> _secureOptionKeys = [
    AppConstants.keyOpenaiKey,
    AppConstants.keyAnthropicKey,
    AppConstants.keyGoogleKey,
    AppConstants.keyKimiKey,
    AppConstants.keyStabilityKey,
    AppConstants.keyNvidiaKey,
    AppConstants.keyOpenRouterKey,
    AppConstants.keyDeepSeekKey,
    AppConstants.keyZaiKey,
    AppConstants.keyGroqKey,
    AppConstants.keyMistralKey,
    AppConstants.keyTogetherKey,
    AppConstants.keyXaiKey,
    AppConstants.keyPerplexityKey,
    AppConstants.keyCerebrasKey,
    AppConstants.keyFireworksKey,
    AppConstants.keyCohereKey,
    AppConstants.keyHuggingFaceKey,
    AppConstants.keyXkiroKey,
    AppConstants.keyTokenRouterKey,
    AppConstants.keyAgentRouterKey,
    AppConstants.keyOrcaRouterKey,
    AppConstants.keyApinexKey,
    AppConstants.keyCustomCloudKey,
    AppConstants.keyServerApiKey,
  ];

  // Observable settings
  final themeMode = ThemeMode.system.obs;
  final inferenceMode = 'local'.obs; // 'local' or 'cloud'
  final exportSubfolder = AppConstants.defaultExportSubfolder.obs;
  final exportCustomDir = ''.obs;
  final exportTreeUri = ''.obs;
  final exportTreeName = ''.obs;
  final strictRamGuard = true.obs;
  final cloudProvider = 'openrouter'.obs;
  final openaiKey = ''.obs;
  final anthropicKey = ''.obs;
  final googleKey = ''.obs;
  final kimiKey = ''.obs;
  final stabilityKey = ''.obs;
  final nvidiaKey = ''.obs;
  final openRouterKey = ''.obs;
  final deepSeekKey = ''.obs;
  final zaiKey = ''.obs;
  final groqKey = ''.obs;
  final mistralKey = ''.obs;
  final togetherKey = ''.obs;
  final xaiKey = ''.obs;
  final perplexityKey = ''.obs;
  final cerebrasKey = ''.obs;
  final fireworksKey = ''.obs;
  final cohereKey = ''.obs;
  final huggingfaceKey = ''.obs;
  final xkiroKey = ''.obs;
  final tokenrouterKey = ''.obs;
  final agentrouterKey = ''.obs;
  final orcarouterKey = ''.obs;
  final apinexKey = ''.obs;
  final customCloudName = 'Custom API'.obs;
  final customCloudBaseUrl = ''.obs;
  final customCloudKey = ''.obs;
  final customCloudProfiles = <Map<String, String>>[].obs;
  final customCloudProfileIndex = (-1).obs;
  final openaiModel = 'gpt-5.2'.obs;
  final anthropicModel = 'claude-sonnet-4-6'.obs;
  final googleModel = 'gemini-2.5-flash'.obs;
  final kimiModel = 'kimi-k2.6'.obs;
  final stabilityModel = 'sd3.5-flash'.obs;
  final nvidiaModel = 'meta/llama-3.1-8b-instruct'.obs;
  final openRouterModel = 'openai/gpt-4o-mini'.obs;
  final deepSeekModel = 'deepseek-v4-flash'.obs;
  final zaiModel = 'glm-4.7-flash'.obs;
  final groqModel = 'llama-3.3-70b-versatile'.obs;
  final mistralModel = 'mistral-large-latest'.obs;
  final togetherModel = 'meta-llama/Llama-3.3-70B-Instruct-Turbo'.obs;
  final xaiModel = 'grok-4-fast'.obs;
  final perplexityModel = 'sonar-pro'.obs;
  final cerebrasModel = 'llama-3.3-70b'.obs;
  final fireworksModel =
      'accounts/fireworks/models/llama-v3p3-70b-instruct'.obs;
  final cohereModel = 'command-a-03-2025'.obs;
  final huggingfaceModel = 'meta-llama/Llama-3.3-70B-Instruct'.obs;
  final xkiroModel = 'openai/gpt-5.2'.obs;
  final tokenrouterModel = 'openai/gpt-5.2'.obs;
  final agentrouterModel = 'claude-opus-4-8'.obs;
  final orcarouterModel = 'orcarouter/auto'.obs;
  final apinexModel = 'gpt-4o'.obs;
  final customCloudModel = ''.obs;
  final globalSystemPrompt = AppConstants.systemPrompt.obs;
  final nvidiaModels = <String>[].obs;
  final isLoadingNvidiaModels = false.obs;
  final temperature = 0.1.obs;
  // Local sampling (GGUF + LiteRT; cloud keeps provider defaults).
  final topP = 0.9.obs;
  final topK = 40.obs;
  final repeatPenalty = 1.1.obs;
  final maxTokens = 512.obs;
  final contextSize = 2048.obs;

  /// Auto Tune (recommended): derive context & output limits from the
  /// device RAM tier, and let cloud models use their full native output.
  final autoTuneParams = true.obs;

  /// Web access: when on, URLs found in the user's message are fetched
  /// and their readable text is added to the model's context.
  final webFetchEnabled = true.obs;

  /// Privacy ad-block for the CubicWeb Browser (static host list,
  /// in-memory only). Persisted as a plain bool pref — no history DB.
  final adblockEnabled = true.obs;

  /// Browser search engine id (see [BrowserSearchEngines]). Plain pref.
  final browserSearchEngine = 'duckduckgo'.obs;

  /// Browser forced-dark overlay. Plain bool pref (survives view dispose).
  final browserForcedDark = false.obs;

  /// Per-site ad-block allowlist (hosts). Plain JSON-string pref.
  final browserAllowlist = <String>[].obs;

  /// Browser bookmarks (explicit user saves only — never auto-recorded).
  /// Each entry: {title, url, addedAt}. Plain JSON-string pref.
  final browserBookmarks = <Map<String, String>>[].obs;

  /// Block HTTP sites entirely (HTTPS-only mode). Plain bool pref.
  final browserHttpsOnly = false.obs;

  /// Send Do-Not-Track / Global Privacy Control headers. Plain bool pref.
  final browserDntEnabled = true.obs;

  /// Block third-party cookies. Plain bool pref.
  final browserBlockThirdPartyCookies = false.obs;
  final browserDataSaver = false.obs;
  final browserSpeedDial = <Map<String, String>>[].obs;
  final browserSidebarEnabled = true.obs;
  final browserNightModeIntensity = 0.5.obs;
  final browserResourceMonitor = true.obs;
  final browserWallpaperPath = ''.obs;
  final browserNightIntensity = 0.0.obs;
  final browserHapticsEnabled = true.obs;
  final browserSidebarShortcuts = <Map<String, String>>[].obs;
  final browserExtremeTextMode = false.obs;
  final browserSearchEnhancer = true.obs;
  final browserGesturesEnabled = true.obs;
  final browserPerformanceProfile =
      'balanced'.obs; // 'eco', 'balanced', 'beast'
  final browserAmbientMusicEnabled = false.obs;
  final browserTotalDataSaved = 0.obs; // bytes
  final browserCustomEngines = <Map<String, String>>[].obs;
  final browserToolbarTools = <String>[].obs;
  final browserNewsCategories = <String>[].obs;
  final browserPipEnabled = true.obs;
  final browserIdentity = <String, String>{}.obs;
  final browserCustomTheme = <String, String>{}.obs;
  final browserVoiceEnabled = true.obs;
  final browserAiNotes = <Map<String, String>>[].obs;
  final browserBlockedSelectors = <String, List<String>>{}.obs;
  final browserSplitEnabled = false.obs;
  final browserHibernationEnabled = true.obs;
  final browserSiteAiRules = <String, String>{}.obs;
  final browserAutoRenameDownloads = true.obs;

  /// Long-paste auto-convert: huge pastes become a .md file attachment
  /// (GPT-style) instead of flooding the composer. Plain bool pref.
  final longPasteToFile = true.obs;

  /// Custom homepage URL (empty = blank new-tab page). Plain string pref.
  final browserHomepage = ''.obs;

  /// Page text zoom percent (50–200, Android textZoom). Plain int pref.
  final browserTextZoom = 100.obs;
  final browserRamLimit = 1024.obs; // MB
  final browserCpuLimit = 0.5.obs; // 0.0 to 1.0
  final browserLimiterEnabled = false.obs;

  /// Dismissible upsell pill shown inside the composer card.
  final composerUpsellDismissed = false.obs;

  /// Composer toolbar buttons (chat input row). Hidden ones stay
  /// reachable from the + menu. Plain bool prefs, default visible.
  final showDeepSearch = true.obs;
  final showWebAccess = true.obs;
  final showLiveVision = true.obs;
  final showPolishPrompt = true.obs;

  /// Context-window indicator placement: 'header' | 'composer' | 'ring'.
  final contextWindowStyle = 'header'.obs;

  /// Settings-page search UI state (session only, never persisted).
  final settingsSearching = false.obs;
  final settingsSearchQuery = ''.obs;
  final liteRtPerformanceMode = AppConstants.defaultLiteRtPerformanceMode.obs;
  /// GGUF (llama.cpp) acceleration override: 'auto' (device-tier heuristic),
  /// 'cpu' (force CPU — stability / diagnose GPU crashes), 'gpu' (force full
  /// GPU offload when Vulkan is available, else CPU fallback).
  final ggufAccelMode = AppConstants.defaultGgufAccelMode.obs;
  /// Experimental large-model mode (13B+ attempts on phones): forces CPU
  /// offload, caps threads at 2, always evicts other residents before
  /// load. RAM gate still applies — unsafe loads stay blocked.
  final largeModelMode = AppConstants.defaultLargeModelMode.obs;
  /// Memory recall strictness: 'strict' | 'balanced' | 'loose'.
  /// Maps to the semantic rescue threshold (Memory page selector).
  final memoryRecallStrictness =
      AppConstants.defaultMemoryRecallStrictness.obs;
  final imageSteps = 1.obs;
  final imageGenForceCpu = AppConstants.defaultImageGenForceCpu.obs;
  final imageGenBackend = Backend.cpu.obs;
  final imageGpuVendor = 'detecting'.obs;
  final imageGenGpuGuardMb = AppConstants.defaultImageGenGpuGuardMb.obs;
  final imageGenSize = AppConstants.defaultImageGenSize.obs;
  final imageGenNegative = AppConstants.defaultImageGenNegative.obs;
  final imageGenSeed = AppConstants.defaultImageGenSeed.obs;
  final imageGenCfg = AppConstants.defaultImageGenCfg.obs;
  final fontScale = AppConstants.defaultFontScale.obs;
  final locale = AppLanguage.fromCode('en').obs;
  final appVersion = ''.obs;

  // Personalization
  final selectedThemeName = 'CubicLM'.obs;
  final isBoldTheme = false.obs;
  final customAccentColor = Rxn<Color>();
  final dynamicColorEnabled = true.obs;
  final glassIntensity = 0.7.obs;
  final selectedFontFamily = 'Plus Jakarta Sans'.obs;

  // Smart RAM & Performance
  final autoAdjustThreads = true.obs;

  int get recommendedThreads {
    if (!autoAdjustThreads.value) return 4; // Default fallback

    if (Get.isRegistered<DeviceInfoService>()) {
      final deviceInfo = Get.find<DeviceInfoService>();
      final cores = deviceInfo.cpuCores.value;
      if (cores > 0) {
        // Reserve ~2 cores for the OS/UI; clamp to llama.cpp's
        // sweet spot (more than 6 threads rarely helps on phones).
        return (cores - 2).clamp(2, 6);
      }
      final ram = deviceInfo.totalRamGB.value;
      return ram > 8 ? 6 : 4; // Legacy fallback when cores unknown
    }
    return 4;
  }

  String get recommendedQuantization {
    final ram = Get.find<DeviceInfoService>().totalRamGB.value;
    if (ram <= 4) return 'Q2_K or Q3_K_S';
    if (ram <= 8) return 'Q4_K_M or Q5_K_M';
    if (ram <= 16) return 'Q6_K or Q8_0';
    return 'Q8_0 or F16';
  }

  // Thinking Orb animation selections ('random' or an OrbState name).
  final orbChatAnim = 'random'.obs;
  final orbImageAnim = 'composing'.obs;
  final orbAnalysisAnim = 'random'.obs;

  // Startup — auto-load last model without asking dialog.
  final autoLoadLastModel = false.obs;

  // TTS — read aloud assistant messages.
  final readAloudEnabled = true.obs;

  // Code editor preference: 'split' (Split Canvas + Live Preview) or 'plain' (Lightweight Plain)
  final codeEditorType = 'split'.obs;

  // App Lock — require device biometrics/PIN to open the app.
  final appLockEnabled = false.obs;

  /// Minutes in background before re-lock (0 = immediately, default).
  final lockTimeoutMinutes = 0.obs;

  /// Biometric-only (no device-PIN fallback in the system prompt).
  final lockBiometricOnly = false.obs;
  final biometricsAvailable = false.obs;

  /// True when at least one biometric (or device credential usable by
  /// local_auth) is enrolled. Lets the UI tell "no hardware" apart from
  /// "hardware present, nothing enrolled" (e.g. Windows Hello supported
  /// but never set up — authenticating then would just fail).
  final hasEnrolledBiometrics = false.obs;

  /// Completes once [_detectBiometrics] has run. The lock gate awaits this
  /// before its first auth decision — otherwise a slow first detection
  /// fail-opens the lock on launch (race).
  final Completer<void> _biometricsDetected = Completer<void>();
  Future<void> get biometricsReady => _biometricsDetected.future;

  /// True while the app is locked and waiting for authentication.
  final isLocked = false.obs;

  // Persistent text controllers for settings fields
  final openaiKeyController = TextEditingController();
  final anthropicKeyController = TextEditingController();
  final googleKeyController = TextEditingController();
  final kimiKeyController = TextEditingController();
  final stabilityKeyController = TextEditingController();
  final nvidiaKeyController = TextEditingController();
  final openRouterKeyController = TextEditingController();
  final deepSeekKeyController = TextEditingController();
  final zaiKeyController = TextEditingController();
  final groqKeyController = TextEditingController();
  final mistralKeyController = TextEditingController();
  final togetherKeyController = TextEditingController();
  final xaiKeyController = TextEditingController();
  final perplexityKeyController = TextEditingController();
  final cerebrasKeyController = TextEditingController();
  final fireworksKeyController = TextEditingController();
  final cohereKeyController = TextEditingController();
  final huggingfaceKeyController = TextEditingController();
  final xkiroKeyController = TextEditingController();
  final tokenrouterKeyController = TextEditingController();
  final agentrouterKeyController = TextEditingController();
  final orcarouterKeyController = TextEditingController();
  final apinexKeyController = TextEditingController();
  final customCloudNameController = TextEditingController();
  final customCloudBaseUrlController = TextEditingController();
  final customCloudKeyController = TextEditingController();
  final globalSystemPromptController = TextEditingController();
  final imageGenNegativeController = TextEditingController();

  final openaiModelController = TextEditingController();
  final anthropicModelController = TextEditingController();
  final googleModelController = TextEditingController();
  final kimiModelController = TextEditingController();
  final stabilityModelController = TextEditingController();
  final nvidiaModelController = TextEditingController();
  final openRouterModelController = TextEditingController();
  final deepSeekModelController = TextEditingController();
  final zaiModelController = TextEditingController();
  final groqModelController = TextEditingController();
  final mistralModelController = TextEditingController();
  final togetherModelController = TextEditingController();
  final xaiModelController = TextEditingController();
  final perplexityModelController = TextEditingController();
  final cerebrasModelController = TextEditingController();
  final fireworksModelController = TextEditingController();
  final cohereModelController = TextEditingController();
  final huggingfaceModelController = TextEditingController();
  final xkiroModelController = TextEditingController();
  final tokenrouterModelController = TextEditingController();
  final agentrouterModelController = TextEditingController();
  final orcarouterModelController = TextEditingController();
  final apinexModelController = TextEditingController();
  final customCloudModelController = TextEditingController();

  Timer? _apiKeyDebounceTimer;
  Timer? _modelDebounceTimer;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion.value = packageInfo.version;
    } catch (_) {
      appVersion.value = '';
    }
  }

  @override
  void onClose() {
    openaiKeyController.dispose();
    anthropicKeyController.dispose();
    googleKeyController.dispose();
    kimiKeyController.dispose();
    stabilityKeyController.dispose();
    nvidiaKeyController.dispose();
    openRouterKeyController.dispose();
    deepSeekKeyController.dispose();
    zaiKeyController.dispose();
    customCloudNameController.dispose();
    customCloudBaseUrlController.dispose();
    customCloudKeyController.dispose();
    globalSystemPromptController.dispose();
    imageGenNegativeController.dispose();
    openaiModelController.dispose();
    anthropicModelController.dispose();
    googleModelController.dispose();
    kimiModelController.dispose();
    stabilityModelController.dispose();
    nvidiaModelController.dispose();
    openRouterModelController.dispose();
    deepSeekModelController.dispose();
    zaiModelController.dispose();
    customCloudModelController.dispose();
    _apiKeyDebounceTimer?.cancel();
    _modelDebounceTimer?.cancel();
    _contextReloadTimer?.cancel();
    super.onClose();
  }


  static const contextWindowStyles = ['header', 'composer', 'ring'];
  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static List<Map<String, String>> _decodeBookmarks(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) {
              return {
                'title': '${m['title'] ?? ''}',
                'url': '${m['url'] ?? ''}',
                'addedAt': '${m['addedAt'] ?? ''}',
              };
            })
            .where((b) => b['url']!.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }
  static const List<int> lockTimeoutOptions = [0, 1, 5, 15];


  Timer? _contextReloadTimer;
  bool _isReloadingForContext = false;
  final _localAuth = la.LocalAuthentication();
  static ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
