/// Startup loading, migration, persistence, and tab/font/theme application.
///
/// Split from `settings_controller.dart` - behavior is unchanged.
/// Contains: _loadSettings(), apiKeyControllerFor(), modelControllerFor()
part of 'settings_controller.dart';

extension SettingsControllerLoading on SettingsController {
  void _loadSettings() {
    unawaited(_migrateKeysFromHive());
    final savedTheme = _hive.getSetting<String>('theme_mode');
    themeMode.value = SettingsController._themeModeFromString(savedTheme);
    inferenceMode.value = _hive.getSetting(AppConstants.keyInferenceMode,
            defaultValue: 'local') ??
        'local';
    exportSubfolder.value = _hive.getSetting(AppConstants.keyExportSubfolder,
            defaultValue: AppConstants.defaultExportSubfolder) ??
        AppConstants.defaultExportSubfolder;
    exportCustomDir.value =
        _hive.getSetting(AppConstants.keyExportCustomDir, defaultValue: '') ??
            '';
    exportTreeUri.value =
        _hive.getSetting(AppConstants.keyExportTreeUri, defaultValue: '') ?? '';
    exportTreeName.value =
        _hive.getSetting(AppConstants.keyExportTreeName, defaultValue: '') ??
            '';
    strictRamGuard.value =
        _hive.getSetting(AppConstants.keyStrictRamGuard, defaultValue: true) ??
            true;
    cloudProvider.value = _hive.getSetting(AppConstants.keyCloudProvider,
            defaultValue: 'openrouter') ??
        'openrouter';
    openaiKey.value = _keys.read(AppConstants.keyOpenaiKey);
    anthropicKey.value = _keys.read(AppConstants.keyAnthropicKey);
    googleKey.value = _keys.read(AppConstants.keyGoogleKey);
    kimiKey.value = _keys.read(AppConstants.keyKimiKey);
    stabilityKey.value = _keys.read(AppConstants.keyStabilityKey);
    nvidiaKey.value = _keys.read(AppConstants.keyNvidiaKey);
    openRouterKey.value = _keys.read(AppConstants.keyOpenRouterKey);
    deepSeekKey.value = _keys.read(AppConstants.keyDeepSeekKey);
    zaiKey.value = _keys.read(AppConstants.keyZaiKey);
    groqKey.value = _keys.read(AppConstants.keyGroqKey);
    mistralKey.value = _keys.read(AppConstants.keyMistralKey);
    togetherKey.value = _keys.read(AppConstants.keyTogetherKey);
    xaiKey.value = _keys.read(AppConstants.keyXaiKey);
    perplexityKey.value = _keys.read(AppConstants.keyPerplexityKey);
    cerebrasKey.value = _keys.read(AppConstants.keyCerebrasKey);
    fireworksKey.value = _keys.read(AppConstants.keyFireworksKey);
    cohereKey.value = _keys.read(AppConstants.keyCohereKey);
    huggingfaceKey.value = _keys.read(AppConstants.keyHuggingFaceKey);
    xkiroKey.value = _keys.read(AppConstants.keyXkiroKey);
    tokenrouterKey.value = _keys.read(AppConstants.keyTokenRouterKey);
    agentrouterKey.value = _keys.read(AppConstants.keyAgentRouterKey);
    orcarouterKey.value = _keys.read(AppConstants.keyOrcaRouterKey);
    apinexKey.value = _keys.read(AppConstants.keyApinexKey);
    customCloudName.value = _hive.getSetting(AppConstants.keyCustomCloudName,
            defaultValue: 'Custom API') ??
        'Custom API';
    customCloudBaseUrl.value =
        _hive.getSetting(AppConstants.keyCustomCloudBaseUrl) ?? '';
    customCloudKey.value = _keys.read(AppConstants.keyCustomCloudKey);
    openaiModel.value = _hive.getSetting(AppConstants.keyOpenaiModel,
            defaultValue: 'gpt-5.2') ??
        'gpt-5.2';
    anthropicModel.value = _hive.getSetting(AppConstants.keyAnthropicModel,
            defaultValue: 'claude-sonnet-4-6') ??
        'claude-sonnet-4-6';
    googleModel.value = _hive.getSetting(AppConstants.keyGoogleModel,
            defaultValue: 'gemini-2.5-flash') ??
        'gemini-2.5-flash';
    kimiModel.value = _hive.getSetting(AppConstants.keyKimiModel,
            defaultValue: 'kimi-k2.6') ??
        'kimi-k2.6';
    stabilityModel.value = _hive.getSetting(AppConstants.keyStabilityModel,
            defaultValue: 'sd3.5-flash') ??
        'sd3.5-flash';
    nvidiaModel.value = _hive.getSetting(AppConstants.keyNvidiaModel,
            defaultValue: 'meta/llama-3.1-8b-instruct') ??
        'meta/llama-3.1-8b-instruct';
    openRouterModel.value = _hive.getSetting(AppConstants.keyOpenRouterModel,
            defaultValue: 'openai/gpt-4o-mini') ??
        'openai/gpt-4o-mini';
    deepSeekModel.value = _hive.getSetting(AppConstants.keyDeepSeekModel,
            defaultValue: 'deepseek-v4-flash') ??
        'deepseek-v4-flash';
    zaiModel.value = _hive.getSetting(AppConstants.keyZaiModel,
            defaultValue: 'glm-4.7-flash') ??
        'glm-4.7-flash';
    groqModel.value = _hive.getSetting(AppConstants.keyGroqModel,
            defaultValue: 'llama-3.3-70b-versatile') ??
        'llama-3.3-70b-versatile';
    mistralModel.value = _hive.getSetting(AppConstants.keyMistralModel,
            defaultValue: 'mistral-large-latest') ??
        'mistral-large-latest';
    togetherModel.value = _hive.getSetting(AppConstants.keyTogetherModel,
            defaultValue: 'meta-llama/Llama-3.3-70B-Instruct-Turbo') ??
        'meta-llama/Llama-3.3-70B-Instruct-Turbo';
    xaiModel.value = _hive.getSetting(AppConstants.keyXaiModel,
            defaultValue: 'grok-4-fast') ??
        'grok-4-fast';
    perplexityModel.value = _hive.getSetting(AppConstants.keyPerplexityModel,
            defaultValue: 'sonar-pro') ??
        'sonar-pro';
    cerebrasModel.value = _hive.getSetting(AppConstants.keyCerebrasModel,
            defaultValue: 'llama-3.3-70b') ??
        'llama-3.3-70b';
    fireworksModel.value = _hive.getSetting(AppConstants.keyFireworksModel,
            defaultValue:
                'accounts/fireworks/models/llama-v3p3-70b-instruct') ??
        'accounts/fireworks/models/llama-v3p3-70b-instruct';
    cohereModel.value = _hive.getSetting(AppConstants.keyCohereModel,
            defaultValue: 'command-a-03-2025') ??
        'command-a-03-2025';
    customCloudModel.value =
        _hive.getSetting(AppConstants.keyCustomCloudModel) ?? '';
    _loadCustomCloudProfiles();
    globalSystemPrompt.value = _hive.getSetting(
            AppConstants.keyGlobalSystemPrompt,
            defaultValue: AppConstants.systemPrompt) ??
        AppConstants.systemPrompt;
    temperature.value = _hive.getSetting(AppConstants.keyTemperature,
            defaultValue: AppConstants.defaultTemperature) ??
        AppConstants.defaultTemperature;
    topP.value = _hive.getSetting(AppConstants.keyTopP,
            defaultValue: AppConstants.defaultTopP) ??
        AppConstants.defaultTopP;
    topK.value = _hive.getSetting(AppConstants.keyTopK,
            defaultValue: AppConstants.defaultTopK) ??
        AppConstants.defaultTopK;
    repeatPenalty.value = _hive.getSetting(AppConstants.keyRepeatPenalty,
            defaultValue: AppConstants.defaultRepeatPenalty) ??
        AppConstants.defaultRepeatPenalty;
    maxTokens.value = _hive.getSetting(AppConstants.keyMaxTokens,
            defaultValue: AppConstants.defaultMaxTokens) ??
        AppConstants.defaultMaxTokens;
    contextSize.value = _hive.getSetting(AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize) ??
        AppConstants.defaultContextSize;
    autoTuneParams.value = _hive.getSetting<bool>(
            AppConstants.keyAutoTuneParams,
            defaultValue: true) ??
        true;
    webFetchEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyWebFetchEnabled,
            defaultValue: true) ??
        true;
    adblockEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyAdblockEnabled,
            defaultValue: true) ??
        true;
    final engineRaw = _hive.getSetting<String>(
            AppConstants.keyBrowserSearchEngine,
            defaultValue: 'duckduckgo') ??
        'duckduckgo';
    browserSearchEngine.value =
        BrowserSearchEngines.isKnown(engineRaw) ? engineRaw : 'duckduckgo';
    browserForcedDark.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserForcedDark,
            defaultValue: false) ??
        false;
    browserAllowlist.assignAll(SettingsController._decodeStringList(
        _hive.getSetting<String>(AppConstants.keyBrowserAllowlist)));
    browserBookmarks.assignAll(SettingsController._decodeBookmarks(
        _hive.getSetting<String>(AppConstants.keyBrowserBookmarks)));
    browserHttpsOnly.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserHttpsOnly,
            defaultValue: false) ??
        false;
    browserDntEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserDntEnabled,
            defaultValue: true) ??
        true;
    browserBlockThirdPartyCookies.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserBlockThirdPartyCookies,
            defaultValue: false) ??
        false;
    browserDataSaver.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserDataSaver,
            defaultValue: false) ??
        false;
    browserSpeedDial.assignAll(SettingsController._decodeBookmarks(
        _hive.getSetting<String>(AppConstants.keyBrowserSpeedDial)));
    browserSidebarEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserSidebarEnabled,
            defaultValue: true) ??
        true;
    browserNightModeIntensity.value = _hive.getSetting<double>(
            AppConstants.keyBrowserNightModeIntensity,
            defaultValue: 0.5) ??
        0.5;
    browserResourceMonitor.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserResourceMonitor,
            defaultValue: true) ??
        true;
    _loadSpeedDial();
    browserWallpaperPath.value = _hive.getSetting<String>(
            AppConstants.keyBrowserWallpaperPath,
            defaultValue: '') ??
        '';
    browserNightIntensity.value = _hive.getSetting<double>(
            AppConstants.keyBrowserNightIntensity,
            defaultValue: 0.0) ??
        0.0;
    browserHapticsEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserHapticsEnabled,
            defaultValue: true) ??
        true;
    browserSidebarShortcuts.assignAll(SettingsController._decodeBookmarks(
        _hive.getSetting<String>(AppConstants.keyBrowserSidebarShortcuts)));
    browserExtremeTextMode.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserExtremeTextMode,
            defaultValue: false) ??
        false;
    browserSearchEnhancer.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserSearchEnhancer,
            defaultValue: true) ??
        true;
    browserGesturesEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserGesturesEnabled,
            defaultValue: true) ??
        true;
    browserPerformanceProfile.value = _hive.getSetting<String>(
            AppConstants.keyBrowserPerformanceProfile,
            defaultValue: 'balanced') ??
        'balanced';
    browserAmbientMusicEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserAmbientMusic,
            defaultValue: false) ??
        false;
    browserTotalDataSaved.value = _hive.getSetting<int>(
            AppConstants.keyBrowserTotalDataSaved,
            defaultValue: 0) ??
        0;
    browserCustomEngines.assignAll(SettingsController._decodeBookmarks(
        _hive.getSetting<String>(AppConstants.keyBrowserCustomEngines)));
    _loadToolbarConfig();
    browserNewsCategories.assignAll(SettingsController._decodeStringList(
        _hive.getSetting<String>(AppConstants.keyBrowserNewsCategories)));
    if (browserNewsCategories.isEmpty) {
      browserNewsCategories
          .assignAll(['artificial intelligence', 'technology', 'science']);
    }
    browserPipEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserPipEnabled,
            defaultValue: true) ??
        true;
    browserIdentity.assignAll(Map<String, String>.from(_hive.getSetting<Map>(
            AppConstants.keyBrowserIdentity,
            defaultValue: {}) ??
        {}));
    browserCustomTheme.assignAll(Map<String, String>.from(_hive.getSetting<Map>(
            AppConstants.keyBrowserAiThemeColors,
            defaultValue: {}) ??
        {}));
    browserVoiceEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserVoiceEnabled,
            defaultValue: true) ??
        true;
    browserAiNotes.assignAll((_hive.getSetting<List>(
                AppConstants.keyBrowserAiNotes,
                defaultValue: []) ??
            [])
        .map((e) => Map<String, String>.from(e as Map)));
    browserBlockedSelectors.assignAll((_hive.getSetting<Map>(
                AppConstants.keyBrowserBlockedSelectors,
                defaultValue: {}) ??
            {})
        .map((k, v) => MapEntry(k.toString(), List<String>.from(v as List))));
    browserSplitEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserSplitEnabled,
            defaultValue: false) ??
        false;
    browserHibernationEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserHibernationEnabled,
            defaultValue: true) ??
        true;
    browserSiteAiRules.assignAll(Map<String, String>.from(_hive.getSetting<Map>(
            AppConstants.keyBrowserSiteAiRules,
            defaultValue: {}) ??
        {}));
    browserAutoRenameDownloads.value = _hive.getSetting<bool>(
            AppConstants.keyBrowserAutoRenameDownloads,
            defaultValue: true) ??
        true;
    longPasteToFile.value = _hive.getSetting<bool>(
            AppConstants.keyLongPasteToFile,
            defaultValue: true) ??
        true;
    browserRamLimit.value = _hive.getSetting<int>(AppConstants.keyBrowserRamLimit, defaultValue: 1024) ?? 1024;
    browserCpuLimit.value = _hive.getSetting<double>(AppConstants.keyBrowserCpuLimit, defaultValue: 0.5) ?? 0.5;
    browserLimiterEnabled.value = _hive.getSetting<bool>(AppConstants.keyBrowserLimiterEnabled, defaultValue: false) ?? false;
    browserHomepage.value = _hive.getSetting<String>(
            AppConstants.keyBrowserHomepage,
            defaultValue: '') ??
        '';
    browserTextZoom.value = _hive.getSetting<int>(
            AppConstants.keyBrowserTextZoom,
            defaultValue: 100) ??
        100;
    composerUpsellDismissed.value = _hive.getSetting<bool>(
            AppConstants.keyComposerUpsellDismissed,
            defaultValue: false) ??
        false;
    showDeepSearch.value = _hive.getSetting<bool>(
            AppConstants.keyShowDeepSearch,
            defaultValue: true) ??
        true;
    showWebAccess.value = _hive.getSetting<bool>(
            AppConstants.keyShowWebAccess,
            defaultValue: true) ??
        true;
    showLiveVision.value = _hive.getSetting<bool>(
            AppConstants.keyShowLiveVision,
            defaultValue: true) ??
        true;
    showPolishPrompt.value = _hive.getSetting<bool>(
            AppConstants.keyShowPolishPrompt,
            defaultValue: true) ??
        true;
    contextWindowStyle.value = _hive.getSetting<String>(
            AppConstants.keyContextWindowStyle,
            defaultValue: 'header') ??
        'header';
    if (autoTuneParams.value) {
      // Persist tuned values so the native loaders (which read the Hive
      // keys directly) always pick up tier-matched context/output even if
      // the RAM tier changed since last launch.
      unawaited(_applyAutoTune(writeSettings: true));
    }
    liteRtPerformanceMode.value = _hive.getSetting(
          AppConstants.keyLiteRtPerformanceMode,
          defaultValue: AppConstants.defaultLiteRtPerformanceMode,
        ) ??
        AppConstants.defaultLiteRtPerformanceMode;
    ggufAccelMode.value = _hive.getSetting(
          AppConstants.keyGgufAccelMode,
          defaultValue: AppConstants.defaultGgufAccelMode,
        ) ??
        AppConstants.defaultGgufAccelMode;
    largeModelMode.value = _hive.getSetting(
          AppConstants.keyLargeModelMode,
          defaultValue: AppConstants.defaultLargeModelMode,
        ) ??
        AppConstants.defaultLargeModelMode;
    imageSteps.value = _hive.getSetting(AppConstants.keyImageSteps,
            defaultValue: AppConstants.defaultImageSteps) ??
        AppConstants.defaultImageSteps;
    imageGenForceCpu.value = _hive.getSetting(AppConstants.keyImageGenForceCpu,
            defaultValue: AppConstants.defaultImageGenForceCpu) ??
        AppConstants.defaultImageGenForceCpu;
    imageGenGpuGuardMb.value = _hive.getSetting(
            AppConstants.keyImageGenGpuGuardMb,
            defaultValue: AppConstants.defaultImageGenGpuGuardMb) ??
        AppConstants.defaultImageGenGpuGuardMb;
    imageGenSize.value = _hive.getSetting(AppConstants.keyImageGenSize,
            defaultValue: AppConstants.defaultImageGenSize) ??
        AppConstants.defaultImageGenSize;
    imageGenNegative.value = _hive.getSetting(AppConstants.keyImageGenNegative,
            defaultValue: AppConstants.defaultImageGenNegative) ??
        AppConstants.defaultImageGenNegative;
    imageGenSeed.value = _hive.getSetting(AppConstants.keyImageGenSeed,
            defaultValue: AppConstants.defaultImageGenSeed) ??
        AppConstants.defaultImageGenSeed;
    imageGenCfg.value = _hive.getSetting(AppConstants.keyImageGenCfg,
            defaultValue: AppConstants.defaultImageGenCfg) ??
        AppConstants.defaultImageGenCfg;
    final savedImageBackend = _hive.getSetting<int>(
        AppConstants.keyImageGenBackend,
        defaultValue: Backend.cpu.index);
    if (savedImageBackend != null &&
        savedImageBackend >= 0 &&
        savedImageBackend < Backend.values.length &&
        !imageGenForceCpu.value) {
      imageGenBackend.value = Backend.values[savedImageBackend];
    } else {
      imageGenBackend.value = Backend.cpu;
    }
    _detectImageGpu();
    fontScale.value = _hive.getSetting(AppConstants.keyFontScale,
            defaultValue: AppConstants.defaultFontScale) ??
        AppConstants.defaultFontScale;
    final savedLang = _hive.getSetting<String>(AppConstants.keyLanguage,
            defaultValue: 'en') ??
        'en';
    locale.value = AppLanguage.fromCode(savedLang);

    // Personalization
    selectedThemeName.value = _hive.getSetting<String>(AppConstants.keySelectedTheme,
            defaultValue: 'CubicLM') ??
        'CubicLM';
    final savedColor = _hive.getSetting<int>(AppConstants.keyCustomAccentColor);
    if (savedColor != null) {
      customAccentColor.value = Color(savedColor);
    }
    dynamicColorEnabled.value = _hive.getSetting<bool>(AppConstants.keyDynamicColorEnabled,
            defaultValue: true) ??
        true;
    glassIntensity.value = _hive.getSetting<double>(AppConstants.keyGlassIntensity,
            defaultValue: 0.7) ??
        0.7;
    selectedFontFamily.value = _hive.getSetting<String>(AppConstants.keySelectedFont,
            defaultValue: 'Plus Jakarta Sans') ??
        'Plus Jakarta Sans';
    // 'Source Sans Pro' was renamed upstream ('Source Sans 3' now) and
    // crashes GoogleFonts.getFont — migrate stale persisted values.
    if (selectedFontFamily.value == 'Source Sans Pro') {
      selectedFontFamily.value = 'Source Sans 3';
      unawaited(_hive.setSetting(
          AppConstants.keySelectedFont, selectedFontFamily.value));
    }

    orbChatAnim.value =
        _hive.getSetting(AppConstants.keyOrbChat, defaultValue: 'random') ??
            'random';
    orbImageAnim.value =
        _hive.getSetting(AppConstants.keyOrbImage, defaultValue: 'composing') ??
            'composing';
    orbAnalysisAnim.value =
        _hive.getSetting(AppConstants.keyOrbAnalysis, defaultValue: 'random') ??
            'random';
    autoLoadLastModel.value = _hive.getSetting<bool>(
            AppConstants.keyAutoLoadLastModel,
            defaultValue: false) ??
        false;
    readAloudEnabled.value =
        _hive.getSetting<bool>(AppConstants.keyReadAloud, defaultValue: true) ??
            true;
    codeEditorType.value =
        _hive.getSetting<String>('code_editor_type', defaultValue: 'split') ??
            'split';
    appLockEnabled.value = _hive.getSetting<bool>(
            AppConstants.keyAppLockEnabled,
            defaultValue: false) ??
        false;
    lockTimeoutMinutes.value = _hive.getSetting<int>(
            AppConstants.keyLockTimeoutMinutes,
            defaultValue: 0) ??
        0;
    lockBiometricOnly.value = _hive.getSetting<bool>(
            AppConstants.keyLockBiometricOnly,
            defaultValue: false) ??
        false;
    _detectBiometrics();
    if (appLockEnabled.value && !kIsWeb) {
      // Start locked so the gate shows before any chat content renders.
      isLocked.value = true;
      // Re-arm screenshot blackout (flag doesn't survive process death).
      unawaited(_setSecureFlag(true));
    }

    // Sync controllers with loaded values
    openaiKeyController.text = openaiKey.value;
    anthropicKeyController.text = anthropicKey.value;
    googleKeyController.text = googleKey.value;
    kimiKeyController.text = kimiKey.value;
    stabilityKeyController.text = stabilityKey.value;
    nvidiaKeyController.text = nvidiaKey.value;
    openRouterKeyController.text = openRouterKey.value;
    deepSeekKeyController.text = deepSeekKey.value;
    zaiKeyController.text = zaiKey.value;
    groqKeyController.text = groqKey.value;
    mistralKeyController.text = mistralKey.value;
    togetherKeyController.text = togetherKey.value;
    xaiKeyController.text = xaiKey.value;
    perplexityKeyController.text = perplexityKey.value;
    cerebrasKeyController.text = cerebrasKey.value;
    fireworksKeyController.text = fireworksKey.value;
    cohereKeyController.text = cohereKey.value;
    huggingfaceKeyController.text = huggingfaceKey.value;
    xkiroKeyController.text = xkiroKey.value;
    tokenrouterKeyController.text = tokenrouterKey.value;
    agentrouterKeyController.text = agentrouterKey.value;
    orcarouterKeyController.text = orcarouterKey.value;
    apinexKeyController.text = apinexKey.value;
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    globalSystemPromptController.text = globalSystemPrompt.value;
    imageGenNegativeController.text = imageGenNegative.value;

    openaiModelController.text = openaiModel.value;
    anthropicModelController.text = anthropicModel.value;
    googleModelController.text = googleModel.value;
    kimiModelController.text = kimiModel.value;
    stabilityModelController.text = stabilityModel.value;
    nvidiaModelController.text = nvidiaModel.value;
    openRouterModelController.text = openRouterModel.value;
    deepSeekModelController.text = deepSeekModel.value;
    zaiModelController.text = zaiModel.value;
    groqModelController.text = groqModel.value;
    mistralModelController.text = mistralModel.value;
    togetherModelController.text = togetherModel.value;
    xaiModelController.text = xaiModel.value;
    perplexityModelController.text = perplexityModel.value;
    cerebrasModelController.text = cerebrasModel.value;
    fireworksModelController.text = fireworksModel.value;
    cohereModelController.text = cohereModel.value;
    huggingfaceModelController.text = huggingfaceModel.value;
    xkiroModelController.text = xkiroModel.value;
    tokenrouterModelController.text = tokenrouterModel.value;
    agentrouterModelController.text = agentrouterModel.value;
    orcarouterModelController.text = orcarouterModel.value;
    apinexModelController.text = apinexModel.value;
    customCloudModelController.text = customCloudModel.value;
  }

  TextEditingController apiKeyControllerFor(String provider) {
    switch (provider) {
      case 'anthropic':
        return anthropicKeyController;
      case 'google':
        return googleKeyController;
      case 'kimi':
        return kimiKeyController;
      case 'stability':
        return stabilityKeyController;
      case 'nvidia':
        return nvidiaKeyController;
      case 'openrouter':
        return openRouterKeyController;
      case 'deepseek':
        return deepSeekKeyController;
      case 'zai':
        return zaiKeyController;
      case 'groq':
        return groqKeyController;
      case 'mistral':
        return mistralKeyController;
      case 'together':
        return togetherKeyController;
      case 'xai':
        return xaiKeyController;
      case 'perplexity':
        return perplexityKeyController;
      case 'cerebras':
        return cerebrasKeyController;
      case 'fireworks':
        return fireworksKeyController;
      case 'cohere':
        return cohereKeyController;
      case 'huggingface':
        return huggingfaceKeyController;
      case 'xkiro':
        return xkiroKeyController;
      case 'tokenrouter':
        return tokenrouterKeyController;
      case 'agentrouter':
        return agentrouterKeyController;
      case 'orcarouter':
        return orcarouterKeyController;
      case 'apinex':
        return apinexKeyController;
      case 'custom':
        return customCloudKeyController;
      default:
        return openaiKeyController;
    }
  }

  TextEditingController modelControllerFor(String provider) {
    switch (provider) {
      case 'anthropic':
        return anthropicModelController;
      case 'google':
        return googleModelController;
      case 'kimi':
        return kimiModelController;
      case 'stability':
        return stabilityModelController;
      case 'nvidia':
        return nvidiaModelController;
      case 'openrouter':
        return openRouterModelController;
      case 'deepseek':
        return deepSeekModelController;
      case 'zai':
        return zaiModelController;
      case 'groq':
        return groqModelController;
      case 'mistral':
        return mistralModelController;
      case 'together':
        return togetherModelController;
      case 'xai':
        return xaiModelController;
      case 'perplexity':
        return perplexityModelController;
      case 'cerebras':
        return cerebrasModelController;
      case 'fireworks':
        return fireworksModelController;
      case 'cohere':
        return cohereModelController;
      case 'huggingface':
        return huggingfaceModelController;
      case 'xkiro':
        return xkiroModelController;
      case 'tokenrouter':
        return tokenrouterModelController;
      case 'agentrouter':
        return agentrouterModelController;
      case 'orcarouter':
        return orcarouterModelController;
      case 'apinex':
        return apinexModelController;
      case 'custom':
        return customCloudModelController;
      default:
        return openaiModelController;
    }
  }
}
