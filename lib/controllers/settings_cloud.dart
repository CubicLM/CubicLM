/// Cloud providers, API keys, credit packs, sync, and shared generation.
///
/// Split from `settings_controller.dart` - behavior is unchanged.
/// Contains: selectedCloudModelName, setInferenceMode(), setStrictRamGuard(), setExportSubfolder()
///   setExportCustomDir(), setExportTree(), resetExportDir(), setCloudProvider()
///   _migrateKeysFromHive(), setApiKey(), debouncedSetApiKey(), cancelApiKeyDebounce()
///   removeApiKey(), setCloudModel(), setCustomCloudConfig(), clearCustomCloudConfig()
///   beginNewCustomCloudProfile(), selectCustomCloudProfile(), _loadCustomCloudProfiles()
///   _saveCustomCloudProfiles(), setGlobalSystemPrompt(), baseSystemPromptForModel()
///   effectiveSystemPromptForModel(), effectiveSystemPromptForPrompt(), refreshNvidiaModels()
///   debouncedSetCloudModel(), cancelModelDebounce()
part of 'settings_controller.dart';

extension SettingsControllerCloud on SettingsController {
  String get selectedCloudModelName {
    switch (cloudProvider.value) {
      case 'anthropic':
        return anthropicModel.value;
      case 'google':
        return googleModel.value;
      case 'kimi':
        return kimiModel.value;
      case 'stability':
        return stabilityModel.value;
      case 'nvidia':
        return nvidiaModel.value;
      case 'openrouter':
        return openRouterModel.value;
      case 'deepseek':
        return deepSeekModel.value;
      case 'zai':
        return zaiModel.value;
      case 'groq':
        return groqModel.value;
      case 'mistral':
        return mistralModel.value;
      case 'together':
        return togetherModel.value;
      case 'xai':
        return xaiModel.value;
      case 'perplexity':
        return perplexityModel.value;
      case 'cerebras':
        return cerebrasModel.value;
      case 'fireworks':
        return fireworksModel.value;
      case 'cohere':
        return cohereModel.value;
      case 'huggingface':
        return huggingfaceModel.value;
      case 'xkiro':
        return xkiroModel.value;
      case 'tokenrouter':
        return tokenrouterModel.value;
      case 'agentrouter':
        return agentrouterModel.value;
      case 'orcarouter':
        return orcarouterModel.value;
      case 'apinex':
        return apinexModel.value;
      case 'custom':
        return customCloudModel.value;
      default:
        return openaiModel.value;
    }
  }

  Future<void> setInferenceMode(String mode) async {
    inferenceMode.value = mode;
    await _hive.setSetting(AppConstants.keyInferenceMode, mode);
  }

  /// Strict RAM guard: blocks loads that would almost surely die
  /// natively. Power users may switch it off (with an explicit warning
  /// in the UI); blocked loads then become confirmed risky loads.
  Future<void> setStrictRamGuard(bool v) async {
    strictRamGuard.value = v;
    await _hive.setSetting(AppConstants.keyStrictRamGuard, v);
  }

  /// Export subfolder under Downloads (Android) or Documents (desktop).
  /// Sanitized; falls back to the default name when blank.
  Future<void> setExportSubfolder(String v) async {
    final clean = ExportFile.sanitizeExportSubfolder(v);
    exportSubfolder.value =
        clean.isEmpty ? AppConstants.defaultExportSubfolder : clean;
    await _hive.setSetting(
        AppConstants.keyExportSubfolder, exportSubfolder.value);
  }

  /// Fully custom export directory (desktop folder picker). Empty = default.
  Future<void> setExportCustomDir(String v) async {
    exportCustomDir.value = v.trim();
    await _hive.setSetting(
        AppConstants.keyExportCustomDir, exportCustomDir.value);
  }

  /// System-picked folder (Android SAF tree). Stored for every save.
  Future<void> setExportTree(String uri, String name) async {
    exportTreeUri.value = uri;
    exportTreeName.value = name;
    await _hive.setSetting(AppConstants.keyExportTreeUri, uri);
    await _hive.setSetting(AppConstants.keyExportTreeName, name);
  }

  /// Back to Downloads/Documents + default subfolder name.
  Future<void> resetExportDir() async {
    exportSubfolder.value = AppConstants.defaultExportSubfolder;
    exportCustomDir.value = '';
    exportTreeUri.value = '';
    exportTreeName.value = '';
    await _hive.setSetting(
        AppConstants.keyExportSubfolder, exportSubfolder.value);
    await _hive.setSetting(AppConstants.keyExportCustomDir, '');
    await _hive.setSetting(AppConstants.keyExportTreeUri, '');
    await _hive.setSetting(AppConstants.keyExportTreeName, '');
  }

  Future<void> setCloudProvider(String provider) async {
    cloudProvider.value = provider;
    await _hive.setSetting(AppConstants.keyCloudProvider, provider);
  }

  /// One-time migration: move API keys from the plaintext Hive settings box
  /// into platform secure storage, then wipe them from Hive.
  Future<void> _migrateKeysFromHive() async {
    const migrationDoneKey = 'api_keys_migrated_to_secure';
    try {
      if (_hive.getSetting<bool>(migrationDoneKey) ?? false) return;
      var moved = 0;
      for (final k in SettingsController._secureOptionKeys) {
        final legacy = _hive.getSetting<String>(k);
        if (legacy != null && legacy.isNotEmpty && _keys.read(k).isEmpty) {
          await _keys.write(k, legacy);
          moved++;
        }
        // Always wipe the plaintext copy from Hive.
        await _hive.deleteSetting(k);
      }
      await _hive.setSetting(migrationDoneKey, true);
      if (moved > 0 && Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().info(
            '[SecureKeyStore] Migrated $moved API keys Hive → secure storage',
            category: LogCategory.system);
      }
    } catch (e) {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().error('API key migration failed',
            details: e.toString(), category: LogCategory.system);
      }
    }
  }

  Future<void> setApiKey(String provider, String key) async {
    final trimmed = key.trim();
    switch (provider) {
      case 'openai':
        openaiKey.value = trimmed;
        openaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyOpenaiKey, trimmed);
        break;
      case 'anthropic':
        anthropicKey.value = trimmed;
        anthropicKeyController.text = trimmed;
        await _keys.write(AppConstants.keyAnthropicKey, trimmed);
        break;
      case 'google':
        googleKey.value = trimmed;
        googleKeyController.text = trimmed;
        await _keys.write(AppConstants.keyGoogleKey, trimmed);
        break;
      case 'kimi':
        kimiKey.value = trimmed;
        kimiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyKimiKey, trimmed);
        break;
      case 'stability':
        stabilityKey.value = trimmed;
        stabilityKeyController.text = trimmed;
        await _keys.write(AppConstants.keyStabilityKey, trimmed);
        break;
      case 'nvidia':
        nvidiaKey.value = trimmed;
        nvidiaKeyController.text = trimmed;
        await _keys.write(AppConstants.keyNvidiaKey, trimmed);
        await refreshNvidiaModels();
        break;
      case 'openrouter':
        openRouterKey.value = trimmed;
        openRouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyOpenRouterKey, trimmed);
        break;
      case 'deepseek':
        deepSeekKey.value = trimmed;
        deepSeekKeyController.text = trimmed;
        await _keys.write(AppConstants.keyDeepSeekKey, trimmed);
        break;
      case 'zai':
        zaiKey.value = trimmed;
        zaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyZaiKey, trimmed);
        break;
      case 'groq':
        groqKey.value = trimmed;
        groqKeyController.text = trimmed;
        await _keys.write(AppConstants.keyGroqKey, trimmed);
        break;
      case 'mistral':
        mistralKey.value = trimmed;
        mistralKeyController.text = trimmed;
        await _keys.write(AppConstants.keyMistralKey, trimmed);
        break;
      case 'together':
        togetherKey.value = trimmed;
        togetherKeyController.text = trimmed;
        await _keys.write(AppConstants.keyTogetherKey, trimmed);
        break;
      case 'xai':
        xaiKey.value = trimmed;
        xaiKeyController.text = trimmed;
        await _keys.write(AppConstants.keyXaiKey, trimmed);
        break;
      case 'perplexity':
        perplexityKey.value = trimmed;
        perplexityKeyController.text = trimmed;
        await _keys.write(AppConstants.keyPerplexityKey, trimmed);
        break;
      case 'cerebras':
        cerebrasKey.value = trimmed;
        cerebrasKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCerebrasKey, trimmed);
        break;
      case 'fireworks':
        fireworksKey.value = trimmed;
        fireworksKeyController.text = trimmed;
        await _keys.write(AppConstants.keyFireworksKey, trimmed);
        break;
      case 'cohere':
        cohereKey.value = trimmed;
        cohereKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCohereKey, trimmed);
        break;
      case 'huggingface':
        huggingfaceKey.value = trimmed;
        huggingfaceKeyController.text = trimmed;
        await _keys.write(AppConstants.keyHuggingFaceKey, trimmed);
        break;
      case 'xkiro':
        xkiroKey.value = trimmed;
        xkiroKeyController.text = trimmed;
        await _keys.write(AppConstants.keyXkiroKey, trimmed);
        break;
      case 'tokenrouter':
        tokenrouterKey.value = trimmed;
        tokenrouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyTokenRouterKey, trimmed);
        break;
      case 'agentrouter':
        agentrouterKey.value = trimmed;
        agentrouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyAgentRouterKey, trimmed);
        break;
      case 'orcarouter':
        orcarouterKey.value = trimmed;
        orcarouterKeyController.text = trimmed;
        await _keys.write(AppConstants.keyOrcaRouterKey, trimmed);
        break;
      case 'apinex':
        apinexKey.value = trimmed;
        apinexKeyController.text = trimmed;
        await _keys.write(AppConstants.keyApinexKey, trimmed);
        break;
      case 'custom':
        customCloudKey.value = trimmed;
        customCloudKeyController.text = trimmed;
        await _keys.write(AppConstants.keyCustomCloudKey, trimmed);
        break;
    }
  }

  void debouncedSetApiKey(String provider, String key) {
    _apiKeyDebounceTimer?.cancel();
    _apiKeyDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      setApiKey(provider, key);
    });
  }

  void cancelApiKeyDebounce() {
    _apiKeyDebounceTimer?.cancel();
  }

  Future<void> removeApiKey(String provider) async {
    await setApiKey(provider, '');
  }

  Future<void> setCloudModel(String provider, String model) async {
    switch (provider) {
      case 'openai':
        openaiModel.value = model;
        openaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyOpenaiModel, model);
        break;
      case 'anthropic':
        anthropicModel.value = model;
        anthropicModelController.text = model;
        await _hive.setSetting(AppConstants.keyAnthropicModel, model);
        break;
      case 'google':
        googleModel.value = model;
        googleModelController.text = model;
        await _hive.setSetting(AppConstants.keyGoogleModel, model);
        break;
      case 'kimi':
        kimiModel.value = model;
        kimiModelController.text = model;
        await _hive.setSetting(AppConstants.keyKimiModel, model);
        break;
      case 'stability':
        stabilityModel.value = model;
        stabilityModelController.text = model;
        await _hive.setSetting(AppConstants.keyStabilityModel, model);
        break;
      case 'nvidia':
        nvidiaModel.value = model;
        nvidiaModelController.text = model;
        await _hive.setSetting(AppConstants.keyNvidiaModel, model);
        break;
      case 'openrouter':
        openRouterModel.value = model;
        openRouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyOpenRouterModel, model);
        break;
      case 'deepseek':
        deepSeekModel.value = model;
        deepSeekModelController.text = model;
        await _hive.setSetting(AppConstants.keyDeepSeekModel, model);
        break;
      case 'zai':
        zaiModel.value = model;
        zaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyZaiModel, model);
        break;
      case 'groq':
        groqModel.value = model;
        groqModelController.text = model;
        await _hive.setSetting(AppConstants.keyGroqModel, model);
        break;
      case 'mistral':
        mistralModel.value = model;
        mistralModelController.text = model;
        await _hive.setSetting(AppConstants.keyMistralModel, model);
        break;
      case 'together':
        togetherModel.value = model;
        togetherModelController.text = model;
        await _hive.setSetting(AppConstants.keyTogetherModel, model);
        break;
      case 'xai':
        xaiModel.value = model;
        xaiModelController.text = model;
        await _hive.setSetting(AppConstants.keyXaiModel, model);
        break;
      case 'perplexity':
        perplexityModel.value = model;
        perplexityModelController.text = model;
        await _hive.setSetting(AppConstants.keyPerplexityModel, model);
        break;
      case 'cerebras':
        cerebrasModel.value = model;
        cerebrasModelController.text = model;
        await _hive.setSetting(AppConstants.keyCerebrasModel, model);
        break;
      case 'fireworks':
        fireworksModel.value = model;
        fireworksModelController.text = model;
        await _hive.setSetting(AppConstants.keyFireworksModel, model);
        break;
      case 'cohere':
        cohereModel.value = model;
        cohereModelController.text = model;
        await _hive.setSetting(AppConstants.keyCohereModel, model);
        break;
      case 'huggingface':
        huggingfaceModel.value = model;
        huggingfaceModelController.text = model;
        await _hive.setSetting(AppConstants.keyHuggingFaceModel, model);
        break;
      case 'xkiro':
        xkiroModel.value = model;
        xkiroModelController.text = model;
        await _hive.setSetting(AppConstants.keyXkiroModel, model);
        break;
      case 'tokenrouter':
        tokenrouterModel.value = model;
        tokenrouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyTokenRouterModel, model);
        break;
      case 'agentrouter':
        agentrouterModel.value = model;
        agentrouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyAgentRouterModel, model);
        break;
      case 'orcarouter':
        orcarouterModel.value = model;
        orcarouterModelController.text = model;
        await _hive.setSetting(AppConstants.keyOrcaRouterModel, model);
        break;
      case 'apinex':
        apinexModel.value = model;
        apinexModelController.text = model;
        await _hive.setSetting(AppConstants.keyApinexModel, model);
        break;
      case 'custom':
        customCloudModel.value = model;
        customCloudModelController.text = model;
        await _hive.setSetting(AppConstants.keyCustomCloudModel, model);
        break;
    }
  }

  Future<void> setCustomCloudConfig({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final normalizedName = name.trim().isEmpty ? 'Custom API' : name.trim();
    final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    customCloudName.value = normalizedName;
    customCloudBaseUrl.value = normalizedBaseUrl;
    customCloudKey.value = apiKey.trim();
    customCloudModel.value = model.trim();

    final profile = <String, String>{
      'name': customCloudName.value,
      'baseUrl': customCloudBaseUrl.value,
      'apiKey': customCloudKey.value,
      'model': customCloudModel.value,
    };
    final index = customCloudProfileIndex.value;
    if (index >= 0 && index < customCloudProfiles.length) {
      customCloudProfiles[index] = profile;
    } else {
      customCloudProfiles.add(profile);
      customCloudProfileIndex.value = customCloudProfiles.length - 1;
    }

    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    customCloudModelController.text = customCloudModel.value;

    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudBaseUrl, customCloudBaseUrl.value);
    await _keys.write(AppConstants.keyCustomCloudKey, customCloudKey.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudModel, customCloudModel.value);
    await _saveCustomCloudProfiles();
  }

  Future<void> clearCustomCloudConfig() async {
    final index = customCloudProfileIndex.value;
    if (index >= 0 && index < customCloudProfiles.length) {
      customCloudProfiles.removeAt(index);
    }
    if (customCloudProfiles.isNotEmpty) {
      await selectCustomCloudProfile(
          index.clamp(0, customCloudProfiles.length - 1).toInt());
      return;
    }
    customCloudName.value = 'Custom API';
    customCloudBaseUrl.value = '';
    customCloudKey.value = '';
    customCloudModel.value = '';

    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.clear();
    customCloudKeyController.clear();
    customCloudModelController.clear();

    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(AppConstants.keyCustomCloudBaseUrl, '');
    await _keys.write(AppConstants.keyCustomCloudKey, '');
    await _hive.setSetting(AppConstants.keyCustomCloudModel, '');
    customCloudProfileIndex.value = -1;
    await _saveCustomCloudProfiles();
  }

  void beginNewCustomCloudProfile() {
    customCloudProfileIndex.value = -1;
    customCloudName.value = 'Custom API';
    customCloudBaseUrl.value = '';
    customCloudKey.value = '';
    customCloudModel.value = '';
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.clear();
    customCloudKeyController.clear();
    customCloudModelController.clear();
  }

  Future<void> selectCustomCloudProfile(int index) async {
    if (index < 0 || index >= customCloudProfiles.length) return;
    customCloudProfileIndex.value = index;
    final profile = customCloudProfiles[index];
    customCloudName.value = profile['name'] ?? 'Custom API';
    customCloudBaseUrl.value = profile['baseUrl'] ?? '';
    customCloudKey.value = profile['apiKey'] ?? '';
    customCloudModel.value = profile['model'] ?? '';
    customCloudNameController.text = customCloudName.value;
    customCloudBaseUrlController.text = customCloudBaseUrl.value;
    customCloudKeyController.text = customCloudKey.value;
    customCloudModelController.text = customCloudModel.value;
    await _hive.setSetting(
        AppConstants.keyCustomCloudName, customCloudName.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudBaseUrl, customCloudBaseUrl.value);
    await _keys.write(AppConstants.keyCustomCloudKey, customCloudKey.value);
    await _hive.setSetting(
        AppConstants.keyCustomCloudModel, customCloudModel.value);
    await _hive.setSetting(AppConstants.keyCustomCloudProfileIndex, index);
  }

  void _loadCustomCloudProfiles() {
    final raw = _hive.getSetting<List>(AppConstants.keyCustomCloudProfiles);
    if (raw != null) {
      customCloudProfiles.assignAll(raw.whereType<Map>().map((profile) =>
          profile.map((key, value) =>
              MapEntry(key.toString(), value?.toString() ?? ''))));
      // Custom-profile API keys moved to secure storage: read them back
      // from SecureKeyStore (old Hive copies were wiped by migration).
      for (var i = 0; i < customCloudProfiles.length; i++) {
        final p = customCloudProfiles[i];
        final hiveKey = '${AppConstants.keyCustomCloudKey}_p$i';
        final secureKey = _keys.read(hiveKey);
        if (secureKey.isNotEmpty) {
          p['apiKey'] = secureKey;
        } else if ((p['apiKey'] ?? '').isNotEmpty) {
          // Legacy inline key: move it now.
          unawaited(_keys.write(hiveKey, p['apiKey']!));
        }
      }
    }
    if (customCloudProfiles.isEmpty && customCloudBaseUrl.value.isNotEmpty) {
      final hiveKey =
          '${AppConstants.keyCustomCloudKey}_p${customCloudProfiles.length}';
      customCloudProfiles.add({
        'name': customCloudName.value,
        'baseUrl': customCloudBaseUrl.value,
        'apiKey': _keys.read(hiveKey).isNotEmpty
            ? _keys.read(hiveKey)
            : customCloudKey.value,
        'model': customCloudModel.value,
      });
    }
    if (customCloudProfiles.isEmpty) return;
    final savedIndex = _hive.getSetting<int>(
            AppConstants.keyCustomCloudProfileIndex,
            defaultValue: 0) ??
        0;
    final index = savedIndex.clamp(0, customCloudProfiles.length - 1).toInt();
    customCloudProfileIndex.value = index;
    final profile = customCloudProfiles[index];
    customCloudName.value = profile['name'] ?? 'Custom API';
    customCloudBaseUrl.value = profile['baseUrl'] ?? '';
    customCloudKey.value = profile['apiKey'] ?? '';
    customCloudModel.value = profile['model'] ?? '';
  }

  Future<void> _saveCustomCloudProfiles() async {
    // Persist API keys in secure storage (indexed), strip them from the
    // plaintext profile list saved to Hive.
    final sanitized = <Map<String, String>>[];
    for (var i = 0; i < customCloudProfiles.length; i++) {
      final p = Map<String, String>.from(customCloudProfiles[i]);
      await _keys.write(
          '${AppConstants.keyCustomCloudKey}_p$i', p['apiKey'] ?? '');
      p['apiKey'] = '';
      sanitized.add(p);
    }
    await _hive.setSetting(AppConstants.keyCustomCloudProfiles, sanitized);
    await _hive.setSetting(
        AppConstants.keyCustomCloudProfileIndex, customCloudProfileIndex.value);
  }

  Future<void> setGlobalSystemPrompt(String prompt) async {
    final normalized =
        prompt.trim().isEmpty ? AppConstants.systemPrompt : prompt.trim();
    globalSystemPrompt.value = normalized;
    globalSystemPromptController.text = normalized;
    await _hive.setSetting(AppConstants.keyGlobalSystemPrompt, normalized);
  }

  String baseSystemPromptForModel(String modelName) {
    final prompt = globalSystemPrompt.value.trim();
    final hasCustomPrompt =
        prompt.isNotEmpty && prompt != AppConstants.systemPrompt;
    if (hasCustomPrompt) return prompt;
    if (AppConstants.isUncensoredModelName(modelName)) {
      return AppConstants.uncensoredSystemPrompt;
    }
    return AppConstants.systemPrompt;
  }

  String effectiveSystemPromptForModel(String modelName) {
    return SkillInjector.injectInto(baseSystemPromptForModel(modelName));
  }

  /// Per-prompt selective skill injection — returns the system prompt
  /// with only the skills relevant to [userPrompt] appended.
  String effectiveSystemPromptForPrompt(String modelName, String userPrompt) {
    final base = baseSystemPromptForModel(modelName);
    final relevant = SkillInjector.selectRelevantSkills(userPrompt);
    if (relevant.isEmpty) return base;
    return '$base${SkillInjector.buildForSkills(relevant)}';
  }

  Future<void> refreshNvidiaModels() async {
    if (nvidiaKey.value.trim().isEmpty) return;
    isLoadingNvidiaModels.value = true;
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.nvidiaEndpoint}/models'),
        headers: {'Authorization': 'Bearer ${nvidiaKey.value.trim()}'},
      );
      if (response.statusCode != 200) {
        Get.find<AppLogService>().warning(
          'NVIDIA model list request failed',
          details: '${response.statusCode}: ${response.body}',
          category: LogCategory.cloud,
        );
        return;
      }
      final data = jsonDecode(response.body);
      final rawModels = data['data'] as List? ?? [];
      nvidiaModels.value = rawModels
          .map((model) => model is Map ? model['id']?.toString() : null)
          .whereType<String>()
          .toList();
    } catch (e) {
      Get.find<AppLogService>().warning('NVIDIA model list request failed',
          details: e, category: LogCategory.cloud);
    } finally {
      isLoadingNvidiaModels.value = false;
    }
  }

  void debouncedSetCloudModel(String provider, String model) {
    _modelDebounceTimer?.cancel();
    _modelDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      setCloudModel(provider, model);
    });
  }

  void cancelModelDebounce() {
    _modelDebounceTimer?.cancel();
  }
}
