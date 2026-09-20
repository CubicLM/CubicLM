/// Per-provider models, custom profiles, and selection.
///
/// Split from `cloud_model_controller.dart` - behavior is unchanged.
/// Contains: verifyApiKey(), saveApiKey(), removeApiKey(), ensureDefaultModels(), canFetchModels()
///   canSelectModel(), selectModel(), deactivateCloudProvider(), saveCustomProvider()
///   clearCustomProvider(), customCloudProfiles, value, selectCustomProfile()
///   beginNewCustomProfile(), validateCustomProvider()
part of 'cloud_model_controller.dart';

extension CloudModelControllerModels on CloudModelController {
  Future<String?> verifyApiKey(String provider, String candidate) async {
    final key = candidate.trim();
    if (key.isEmpty) return 'Paste a key first.';
    // Wrong-key-type fast path: Google AI Studio keys always start
    // with "AIza" — anything else (e.g. "AQ.…") is rejected by Google
    // before any quota/model check, so say so without a network call.
    if (provider == 'google' && !key.startsWith('AIza')) {
      return 'Not a Gemini API key — AI Studio keys start with "AIza". '
          'Create one free at aistudio.google.com/apikey.';
    }
    try {
      final cloudProvider = CloudProviderRegistry.getById(provider);
      final urls = cloudProvider?.getModelListCandidates(key) ??
          const ['https://api.openai.com/v1/models'];
      final headers = cloudProvider?.buildAuthHeaders(key) ??
          {'Authorization': 'Bearer $key'};
      for (final url in urls.take(2)) {
        try {
          final resp = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200) {
            final ids = _parseModelIds(provider, resp.body);
            if (ids.isNotEmpty) {
              verifiedModelCountByProvider[provider] = ids.length;
              return null;
            }
          } else if (resp.statusCode == 401 || resp.statusCode == 403) {
            return 'Invalid key (${resp.statusCode}) — check for typos.';
          } else if (resp.statusCode == 400 &&
              resp.body.contains('API_KEY_INVALID')) {
            // Google's "not a valid key" shape (wrong key type).
            return 'Invalid key (400) — this key is not valid for the Gemini API.';
          }
        } catch (_) {
          continue;
        }
      }
      return 'Verification failed — endpoint unreachable or key rejected.';
    } catch (e) {
      return 'Verification failed: $e';
    }
  }

  Future<void> saveApiKey(String provider, String value) async {
    await _settings.setApiKey(provider, value);
    // Provider id only — never the key.
    AppLogService.trailAction(value.isEmpty
        ? 'cloud key removed ($provider)'
        : 'cloud key saved ($provider)');
    if (value.isNotEmpty) {
      final hint = keyFormatHint(provider, value);
      if (hint != null) {
        AppSnackbar.showTop('Key looks unusual', hint,
            logHistory: false);
      }
      modelsByProvider.remove(provider);
      modelTagsByProvider.remove(provider);
      fetchedAtByProvider.remove(provider);
      // First-set timestamp drives time-sort (kept, not overwritten).
      try {
        if ((_hive.getSetting<String>('${CloudModelController._keyTimePrefix}$provider') ?? '')
            .isEmpty) {
          await _hive.setSetting(
              '${CloudModelController._keyTimePrefix}$provider',
              DateTime.now().toIso8601String());
        }
      } catch (_) {}
      Future.microtask(() => refreshModels(provider));
    }
  }

  Future<void> removeApiKey(String provider) async {
    await _settings.removeApiKey(provider);
    _unpin(provider);
    try {
      await _hive.deleteSetting('${CloudModelController._keyTimePrefix}$provider');
    } catch (_) {}
    modelsByProvider.remove(provider);
    modelTagsByProvider.remove(provider);
    fetchedAtByProvider.remove(provider);
    isLoadingProvider.remove(provider);
    errorByProvider.remove(provider);
    companyFilterByProvider.remove(provider);
    await _hive.deleteSetting('${CloudModelController._cachePrefix}$provider');
    await _hive.deleteSetting('${CloudModelController._cacheTimePrefix}$provider');
    await _hive.deleteSetting('${CloudModelController._workingUrlPrefix}$provider');
  }

  void ensureDefaultModels(String provider) {
    if (apiKeyFor(provider).isEmpty) return;
    final defaults = CloudModelController._defaultModelsByProvider[provider];
    if (defaults == null || defaults.isEmpty) return;

    final existing = modelsByProvider[provider] ?? const <String>[];
    if (existing.isNotEmpty) return;

    final withActive = [...defaults];
    final active = activeModelFor(provider);
    if (active.isNotEmpty && !withActive.contains(active)) {
      withActive.add(active);
    }
    modelsByProvider[provider] = withActive;

    if (provider == 'zai') {
      modelTagsByProvider[provider] = _zaiFreeTags(defaults);
    }
  }

  bool canFetchModels(String provider) {
    if (provider == 'custom') return false;
    return apiKeyFor(provider).isNotEmpty;
  }

  bool canSelectModel(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  Future<void> selectModel(
    String provider,
    String modelId, {
    bool showSnackbar = true,
  }) async {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (!_isBuiltInProvider(provider) && provider != 'custom') {
      _dynamicActiveModel[provider] = normalized;
      await _hive.setSetting(_dynamicKey(provider), normalized);
      // Ensure the selected model stays in the list even after refresh.
      final list = modelsByProvider[provider] ?? [];
      if (!list.contains(normalized)) {
        modelsByProvider[provider] = [...list, normalized];
      }
      await _settings.setCloudProvider(provider);
      await _settings.setInferenceMode('cloud');
      if (!showSnackbar) return;
      AppSnackbar.cloudActive('$provider · $normalized');
      return;
    }
    await _settings.setCloudProvider(provider);
    await _settings.setCloudModel(provider, normalized);
    await _settings.setInferenceMode('cloud');
    if (!showSnackbar) return;
    AppSnackbar.cloudActive('$provider · $normalized');
  }

  /// Deactivates the active cloud provider: switches inference back to
  /// local mode and auto-loads the last downloaded local model so chat
  /// keeps working without any cloud API.
  Future<void> deactivateCloudProvider() async {
    // Reset to a neutral provider so nothing reads an empty ID.
    await _settings.setCloudProvider('openrouter');
    // Switch back to local inference immediately.
    await _settings.setInferenceMode('local');

    final inference = Get.find<InferenceService>();
    final imageService = Get.find<LocalImageService>();

    // If a local model is already resident we're done.
    if (inference.isModelLoaded.value || imageService.isModelLoaded.value) {
      AppSnackbar.localActive(inference.loadedModelName.value);
      return;
    }

    // Auto-load the last downloaded local text model (path validated —
    // same guards as the startup resume dialog).
    String? textName =
        _hive.getSetting<String>(AppConstants.keyLocalModelName);
    String? textPath = _hive.getSetting<String>(AppConstants.keyLocalModelPath);
    String? textRuntime =
        _hive.getSetting<String>(AppConstants.keyLocalModelRuntime);

    bool pathOk(String? p) {
      if (p == null || p.isEmpty) return false;
      try {
        final f = File(p);
        return f.existsSync() && f.lengthSync() > 0;
      } catch (_) {
        return false;
      }
    }

    if (!pathOk(textPath)) {
      // Clean stale pointers like the resume dialog does.
      await _hive.setSetting(AppConstants.keyLocalModelPath, '');
      await _hive.setSetting(AppConstants.keyLocalModelName, '');
      await _hive.setSetting(AppConstants.keyLocalModelRuntime, '');
      await _hive.setSetting(AppConstants.keyLocalModelBackend, '');
      textName = null;
      textPath = null;
      textRuntime = null;
    }

    if (textName != null && textName.isNotEmpty && pathOk(textPath)) {
      AppSnackbar.showTop('Switching back', 'Loading $textName…');
      try {
        await inference.loadModel(
          textPath!,
          modelName: textName,
          modelRuntime: textRuntime,
        );
      } catch (_) {}
      return;
    }

    // Fall back to a downloaded image model if no text model exists.
    final imageName =
        _hive.getSetting<String>(AppConstants.keyImageModelName);
    final imagePath = _hive.getSetting<String>(AppConstants.keyImageModelPath);
    if (imageName != null && imageName.isNotEmpty && pathOk(imagePath)) {
      AppSnackbar.showTop('Switching back', 'Loading $imageName…');
      try {
        await Get.find<LocalImageService>().loadModel(imagePath!,
            modelName: imageName);
      } catch (_) {}
      return;
    }

    AppSnackbar.showTop('No local model',
        'Download one from Explore → Local Models',
        duration: const Duration(seconds: 3));
  }

  Future<void> saveCustomProvider() async {
    final validationError = validateCustomProvider();
    if (validationError != null) {
      customProviderError.value = validationError;
      return;
    }
    customProviderError.value = '';
    await _settings.setCustomCloudConfig(
      name: customNameController.text,
      baseUrl: customBaseUrlController.text,
      apiKey: customApiKeyController.text,
      model: customModelController.text,
    );
    await selectModel(
      'custom',
      _settings.customCloudModel.value,
      showSnackbar: false,
    );
  }

  Future<void> clearCustomProvider() async {
    await _settings.clearCustomCloudConfig();
    customProviderError.value = '';
    _syncCustomControllers();
  }

  List<Map<String, String>> get customProfiles => _settings.customCloudProfiles;

  int get customProfileIndex => _settings.customCloudProfileIndex.value;

  Future<void> selectCustomProfile(int index) async {
    await _settings.selectCustomCloudProfile(index);
    _syncCustomControllers();
    customProviderError.value = '';
  }

  void beginNewCustomProfile() {
    _settings.beginNewCustomCloudProfile();
    _syncCustomControllers();
    customProviderError.value = '';
  }

  String? validateCustomProvider() {
    final baseUrl = customBaseUrlController.text.trim();
    final apiKey = customApiKeyController.text.trim();
    final model = customModelController.text.trim();

    if (baseUrl.isEmpty) return 'Base URL is required.';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return 'Enter a valid OpenAI-compatible base URL.';
    }
    if (apiKey.isEmpty) return 'API key is required.';
    if (model.isEmpty) return 'Model ID is required.';
    return null;
  }
}
