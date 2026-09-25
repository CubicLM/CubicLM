/// Provider registry, ordering, filters, pins, and key verification.
///
/// Split from `cloud_model_controller.dart` - behavior is unchanged.
/// Contains: _dynamicKey(), _clampInterval(), _initProviders(), _isBuiltInProvider()
///   _purgeDynamicProviders(), _capitalise(), value, activeModelFor(), apiKeyFor()
///   apiKeyControllerFor(), isConfigured(), statusLabel(), keySetAt(), setProviderSortMode()
///   isPinned(), togglePin(), _unpin(), orderedProviders(), unkeyedProviders, providerOrderIndex()
///   filteredProviders, filteredModelsFor(), fetchedLabel(), modelTagsFor(), isFreeModel()
///   freeModelCountFor(), toggleFreeFirst(), availableCompaniesFor(), hasCompanyFilterFor()
///   companyDisplayName(), companyIcon(), setCompanyFilter()
part of 'cloud_model_controller.dart';

extension CloudModelControllerProviders on CloudModelController {
  String _dynamicKey(String provider) => 'dynamic_model_$provider';

  int _clampInterval(int? v) {
    if (v == null) return 24;
    return v.clamp(1, 168);
  }

  void _initProviders() {
    // Build-in providers from registry
    for (final provider in CloudProviderRegistry.all) {
      allProviders.add(CloudProviderInfo(
        id: provider.id,
        name: provider.name,
        description: provider.description,
        icon: provider.icon,
        requiresKeyForList: provider.requiresKeyForList,
        supportsFetch: provider.supportsFetch,
      ));
    }

    // Custom provider (special case)
    if (!allProviders.any((p) => p.id == 'custom')) {
      allProviders.add(const CloudProviderInfo(
        id: 'custom',
        name: 'Custom API',
        description: 'Manual OpenAI-compatible endpoint',
        icon: Icons.tune,
        supportsFetch: false,
      ));
    }

    // No auto-detected vendor cards: aggregator models live inside
    // their source card. Purge leftovers from older builds.
    Future.microtask(_purgeDynamicProviders);
  }

  bool _isBuiltInProvider(String id) {
    return CloudProviderRegistry.contains(id) || id == 'custom';
  }

  /// One-time purge of legacy auto-detected vendor cards (xiaomi, qwen,
  /// …): they duplicated the source card's model list and their ids
  /// can't serve chat. Drops their persisted caches so they never
  /// reappear; the stale-active guard in onInit resets the active
  /// provider if it pointed at one.
  Future<void> _purgeDynamicProviders() async {
    try {
      final raw = _hive.getSetting<List>(CloudModelController._discoveredProvidersKey);
      final ids = <String>[];
      if (raw != null) {
        for (final e in raw) {
          try {
            final m = Map<String, dynamic>.from(e as Map);
            final id = (m['id'] ?? '').toString();
            if (id.isNotEmpty) ids.add(id);
          } catch (_) {}
        }
      }
      for (final id in ids) {
        await _hive.deleteSetting('${CloudModelController._cachePrefix}$id');
        await _hive.deleteSetting('${CloudModelController._cacheTimePrefix}$id');
        await _hive.deleteSetting('${CloudModelController._workingUrlPrefix}$id');
        await _hive.deleteSetting('${CloudModelController._healthPrefix}$id');
        await _hive.deleteSetting(_dynamicKey(id));
        await _hive.deleteSetting('${CloudModelController._keyTimePrefix}$id');
      }
      await _hive.deleteSetting(CloudModelController._discoveredProvidersKey);
    } catch (_) {}
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String get activeProvider => _settings.cloudProvider.value;

  String activeModelFor(String provider) {
    if (!_isBuiltInProvider(provider) && provider != 'custom') {
      final mem = _dynamicActiveModel[provider];
      if (mem != null && mem.isNotEmpty) return mem;
      final saved = _hive.getSetting<String>(_dynamicKey(provider));
      if (saved != null && saved.isNotEmpty) {
        // Restore to memory and ensure visible in list.
        _dynamicActiveModel[provider] = saved;
        final list = modelsByProvider[provider] ?? [];
        if (!list.contains(saved)) {
          modelsByProvider[provider] = [...list, saved];
        }
        return saved;
      }
      return modelsByProvider[provider]?.firstOrNull ?? '';
    }
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterModel.value;
      case 'anthropic':
        return _settings.anthropicModel.value;
      case 'deepseek':
        return _settings.deepSeekModel.value;
      case 'google':
        return _settings.googleModel.value;
      case 'kimi':
        return _settings.kimiModel.value;
      case 'nvidia':
        return _settings.nvidiaModel.value;
      case 'zai':
        return _settings.zaiModel.value;
      case 'groq':
        return _settings.groqModel.value;
      case 'mistral':
        return _settings.mistralModel.value;
      case 'together':
        return _settings.togetherModel.value;
      case 'xai':
        return _settings.xaiModel.value;
      case 'perplexity':
        return _settings.perplexityModel.value;
      case 'cerebras':
        return _settings.cerebrasModel.value;
      case 'fireworks':
        return _settings.fireworksModel.value;
      case 'cohere':
        return _settings.cohereModel.value;
      case 'huggingface':
        return _settings.huggingfaceModel.value;
      case 'xkiro':
        return _settings.xkiroModel.value;
      case 'tokenrouter':
        return _settings.tokenrouterModel.value;
      case 'agentrouter':
        return _settings.agentrouterModel.value;
      case 'orcarouter':
        return _settings.orcarouterModel.value;
      case 'apinex':
        return _settings.apinexModel.value;
      case 'custom':
        return _settings.customCloudModel.value;
      default:
        return _settings.openaiModel.value;
    }
  }

  String apiKeyFor(String provider) {
    // Fail closed: only explicit per-provider keys. No borrowing across
    // providers (that ghost-marked keyless providers as configured).
    switch (provider) {
      case 'openai':
        return _settings.openaiKey.value;
      case 'openrouter':
        return _settings.openRouterKey.value;
      case 'anthropic':
        return _settings.anthropicKey.value;
      case 'deepseek':
        return _settings.deepSeekKey.value;
      case 'google':
        return _settings.googleKey.value;
      case 'kimi':
        return _settings.kimiKey.value;
      case 'nvidia':
        return _settings.nvidiaKey.value;
      case 'zai':
        return _settings.zaiKey.value;
      case 'groq':
        return _settings.groqKey.value;
      case 'mistral':
        return _settings.mistralKey.value;
      case 'together':
        return _settings.togetherKey.value;
      case 'xai':
        return _settings.xaiKey.value;
      case 'perplexity':
        return _settings.perplexityKey.value;
      case 'cerebras':
        return _settings.cerebrasKey.value;
      case 'fireworks':
        return _settings.fireworksKey.value;
      case 'cohere':
        return _settings.cohereKey.value;
      case 'huggingface':
        return _settings.huggingfaceKey.value;
      case 'xkiro':
        return _settings.xkiroKey.value;
      case 'tokenrouter':
        return _settings.tokenrouterKey.value;
      case 'agentrouter':
        return _settings.agentrouterKey.value;
      case 'orcarouter':
        return _settings.orcarouterKey.value;
      case 'apinex':
        return _settings.apinexKey.value;
      case 'stability':
        return _settings.stabilityKey.value;
      case 'custom':
        return _settings.customCloudKey.value;
      default:
        // Fail closed: unknown ids are unconfigured (never borrow
        // another provider's key — that ghost-marks unkeyed providers
        // as configured and leaks keys across providers).
        return '';
    }
  }

  TextEditingController apiKeyControllerFor(String provider) {
    return _settings.apiKeyControllerFor(provider);
  }

  bool isConfigured(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudModel.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  String statusLabel(String provider) {
    return isConfigured(provider) ? 'Connected' : 'Needs Key';
  }

  // ── Provider ordering: custom top, pinned, keyed (time|name), rest ──

  /// When this provider's API key was first set (persisted). Legacy
  /// keys predate tracking → epoch (oldest-first, alpha tiebreak).
  DateTime keySetAt(String provider) {
    try {
      final raw = _hive.getSetting<String>('${CloudModelController._keyTimePrefix}$provider');
      return DateTime.tryParse(raw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> setProviderSortMode(String mode) async {
    providerSortMode.value = (mode == 'name') ? 'name' : 'time';
    try {
      await _hive.setSetting(CloudModelController._sortModeKey, providerSortMode.value);
    } catch (_) {}
  }

  bool isPinned(String provider) => pinnedProviders.contains(provider);

  /// Pin/unpin a KEYED provider (Custom API is always top — pin N/A).
  Future<void> togglePin(String provider) async {
    if (provider == 'custom' || !isConfigured(provider)) return;
    if (pinnedProviders.contains(provider)) {
      pinnedProviders.remove(provider);
    } else {
      pinnedProviders.add(provider);
    }
    try {
      await _hive.setSetting(CloudModelController._pinnedKey, pinnedProviders.toList());
    } catch (_) {}
  }

  void _unpin(String provider) {
    if (pinnedProviders.remove(provider)) {
      // Awaited inside a guarded microtask: a bare unawaited future lets
      // a late platform/Hive error surface as an unhandled async error
      // (flaky "failed after test completion" in parallel test runs).
      Future.microtask(() async {
        try {
          await _hive.setSetting(
              CloudModelController._pinnedKey, pinnedProviders.toList());
        } catch (_) {}
      });
    }
  }

  /// Card display order: Custom API always first, then pinned (pin
  /// order), then key-set (sort mode), then everything else.
  /// Provider list for Model Hub + switchers: Custom first → pinned →
  /// keyed (sorted by time or name). Unkeyed providers are excluded —
  /// they appear in [unkeyedProviders].
  List<CloudProviderInfo> orderedProviders() {
    final byId = {for (final p in allProviders) p.id: p};
    final out = <CloudProviderInfo>[];
    void take(String id) {
      final p = byId.remove(id);
      if (p != null) out.add(p);
    }

    // 1) Custom always first.
    take('custom');

    // 2) Pinned keyed providers (in pin order).
    for (final id in pinnedProviders.toList()) {
      if (id != 'custom' && isConfigured(id)) take(id);
    }

    // 3) Remaining keyed providers — sorted by time or name.
    final keyed = <CloudProviderInfo>[];
    for (final p in byId.values.toList()) {
      if (p.id != 'custom' && isConfigured(p.id)) {
        keyed.add(p);
        byId.remove(p.id);
      }
    }
    if (providerSortMode.value == 'name') {
      keyed.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      keyed.sort((a, b) {
        final c = keySetAt(a.id).compareTo(keySetAt(b.id));
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    out.addAll(keyed);
    return out;
  }

  /// Built-in providers without an API key — shown in a separate
  /// "Add API Key" section at the bottom of the Model Hub.
  /// (Legacy dynamic ids are excluded everywhere; they are purged
  /// on launch and can neither serve nor configure.)
  List<CloudProviderInfo> get unkeyedProviders {
    return allProviders
        .where((p) =>
            p.id != 'custom' &&
            _isBuiltInProvider(p.id) &&
            !isConfigured(p.id))
        .toList();
  }

  /// Display rank for shared switcher sorting (lower = higher).
  int providerOrderIndex(String id) {
    final order = orderedProviders();
    final i = order.indexWhere((p) => p.id == id);
    return i < 0 ? order.length : i;
  }

  List<CloudProviderInfo> get filteredProviders {
    final query = providerSearchQuery.value.toLowerCase().trim();
    if (query.isEmpty) return orderedProviders();
    return orderedProviders().where((p) {
      if (p.name.toLowerCase().contains(query)) return true;
      if (p.id.toLowerCase().contains(query)) return true;
      if (p.description.toLowerCase().contains(query)) return true;
      final models = modelsByProvider[p.id] ?? [];
      return models.any((m) => m.toLowerCase().contains(query));
    }).toList();
  }

  List<String> filteredModelsFor(String provider) {
    final query = (searchByProvider[provider] ?? '').toLowerCase().trim();
    final company = companyFilterByProvider[provider];
    final active = activeModelFor(provider);
    var source = [...(modelsByProvider[provider] ?? const <String>[])];
    if (active.isNotEmpty && !source.contains(active)) {
      source.insert(0, active);
    }
    // Auto-hide failed: drop failed models, but NEVER the active one —
    // hiding the in-use model would strand the picker.
    if (autoHideFailed.value) {
      final health = modelHealthByProvider[provider] ?? const {};
      source = source.where((id) {
        if (id == active) return true;
        return health[id]?.status != ModelHealthStatus.failed;
      }).toList();
    }
    if (company != null && company.isNotEmpty) {
      source = source
          .where((id) => id.toLowerCase().startsWith('$company/'))
          .toList();
    }
    final filtered = query.isEmpty
        ? source
        : source.where((id) => id.toLowerCase().contains(query)).toList();
    final freeFirst = freeFirstByProvider[provider] == true;
    filtered.sort((a, b) {
      if (a == active) return -1;
      if (b == active) return 1;
      if (freeFirst) {
        final aFree = isFreeModel(provider, a);
        final bFree = isFreeModel(provider, b);
        if (aFree != bFree) return aFree ? -1 : 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return filtered;
  }

  String fetchedLabel(String provider) {
    final fetchedAt = fetchedAtByProvider[provider];
    if (fetchedAt == null &&
        (modelsByProvider[provider] ?? const <String>[]).isNotEmpty) {
      return 'Built-in list';
    }
    if (fetchedAt == null) return 'Not fetched yet';
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  List<String> modelTagsFor(String provider, String modelId) {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (provider == 'nvidia') return const ['NIM'];
    return modelTagsByProvider[provider]?[normalized] ??
        modelTagsByProvider[provider]?[modelId] ??
        const <String>[];
  }

  bool isFreeModel(String provider, String modelId) {
    final lower = modelId.toLowerCase();
    return modelTagsFor(provider, modelId).contains('FREE') ||
        lower.contains(':free') ||
        lower.contains('-free');
  }

  int freeModelCountFor(String provider) {
    return (modelsByProvider[provider] ?? const <String>[])
        .where((id) => isFreeModel(provider, id))
        .length;
  }

  void toggleFreeFirst(String provider) {
    freeFirstByProvider[provider] = !(freeFirstByProvider[provider] ?? false);
  }

  /// Auto-detect company prefixes from model IDs (e.g. 'openai' from
  /// 'openai/gpt-5.2'). Used to build the company filter chips for
  /// aggregator providers like OpenRouter — no hardcoding needed.
  List<String> availableCompaniesFor(String provider) {
    final models = modelsByProvider[provider] ?? const <String>[];
    final set = <String>{};
    for (final m in models) {
      final slash = m.indexOf('/');
      if (slash <= 0) continue;
      set.add(m.substring(0, slash));
    }
    final list = set.toList()..sort();
    return list;
  }

  bool hasCompanyFilterFor(String provider) =>
      availableCompaniesFor(provider).length >= 2;

  String companyDisplayName(String prefix) =>
      CloudModelController._knownCompanyNames[prefix.toLowerCase()] ?? _capitalise(prefix);

  IconData? companyIcon(String prefix) =>
      CloudModelController._knownCompanyIcons[prefix.toLowerCase()];

  void setCompanyFilter(String provider, String? prefix) {
    if (prefix == null || prefix.isEmpty) {
      companyFilterByProvider.remove(provider);
    } else {
      companyFilterByProvider[provider] = prefix;
    }
  }
}
