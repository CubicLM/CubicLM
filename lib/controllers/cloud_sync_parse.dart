/// Auto-sync scheduling and model-list sync/parse.
///
/// Split from `cloud_model_controller.dart` - behavior is unchanged.
/// Contains: setAutoHideFailed(), setSyncIntervalHours(), autoSyncLabel(), syncAllNow(), maybeAutoSync()
///   refreshCustomModels(), _modelListUrlCandidates(), _parseModelIds(), _parseModelTags()
///   _pricingValue(), _zaiFreeTags()
part of 'cloud_model_controller.dart';

extension CloudModelControllerSyncParse on CloudModelController {
  Future<void> setAutoHideFailed(bool v) async {
    autoHideFailed.value = v;
    try {
      await _hive.setSetting(CloudModelController._autoHideKey, v);
    } catch (_) {}
  }

  // ── Auto-sync ──

  Future<void> setSyncIntervalHours(int h) async {
    modelSyncIntervalHours.value = _clampInterval(h);
    try {
      await _hive.setSetting(
          CloudModelController._syncIntervalKey, modelSyncIntervalHours.value);
    } catch (_) {}
  }

  String autoSyncLabel() {
    final raw = _hive.getSetting<String>(CloudModelController._lastAutoSyncKey);
    if (raw == null || raw.isEmpty) return 'Never auto-synced';
    final at = DateTime.tryParse(raw);
    if (at == null) return 'Never auto-synced';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Auto-synced just now';
    if (diff.inHours < 1) return 'Auto-synced ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Auto-synced ${diff.inHours}h ago';
    return 'Auto-synced ${diff.inDays}d ago';
  }

  /// Manual "Sync now": refresh every configured provider right away
  /// and stamp the auto-sync clock.
  Future<void> syncAllNow() async {
    var synced = 0;
    for (final p in providers) {
      if (p.id == 'custom') continue;
      if (apiKeyFor(p.id).isEmpty) continue;
      try {
        await refreshModels(p.id);
        if (errorByProvider[p.id]?.isNotEmpty != true) synced++;
      } catch (_) {}
    }
    try {
      await _hive.setSetting(
          CloudModelController._lastAutoSyncKey, DateTime.now().toIso8601String());
    } catch (_) {}
    AppSnackbar.showTop('Sync complete',
        synced == 0
            ? 'No configured provider to refresh.'
            : '$synced provider${synced == 1 ? '' : 's'} refreshed.',
        logHistory: false);
  }

  /// Background auto-sync on start: refresh every configured provider
  /// whose cache is older than the interval (or never fetched).
  /// Fire-and-forget, per-provider guarded — never blocks startup.
  Future<void> maybeAutoSync() async {
    try {
      final last = _hive.getSetting<String>(CloudModelController._lastAutoSyncKey);
      if (!shouldAutoSync(
          lastSyncIso: last,
          intervalHours: modelSyncIntervalHours.value,
          now: DateTime.now())) {
        return;
      }
      var synced = 0;
      for (final p in providers) {
        if (p.id == 'custom') continue;
        if (apiKeyFor(p.id).isEmpty) continue;
        final fetched = fetchedAtByProvider[p.id];
        final stale = fetched == null ||
            DateTime.now().difference(fetched).inHours >=
                modelSyncIntervalHours.value;
        if (!stale) continue;
        try {
          await refreshModels(p.id);
          synced++;
        } catch (_) {}
      }
      await _hive.setSetting(
          CloudModelController._lastAutoSyncKey, DateTime.now().toIso8601String());
      if (synced > 0) {
        AppSnackbar.showTop('Models auto-synced',
            '$synced provider${synced == 1 ? '' : 's'} refreshed.',
            logHistory: false);
      }
    } catch (_) {}
  }

  Future<void> refreshCustomModels() async {
    final baseUrl = (_settings.customCloudBaseUrl.value)
        .toString()
        .replaceAll(RegExp(r'/+$'), '');
    final apiKey = _settings.customCloudKey.value;
    final manuallyEntered = _settings.customCloudModel.value.trim();

    if (baseUrl.isEmpty) return;

    isLoadingProvider['custom'] = true;
    errorByProvider.remove('custom');

    try {
      http.Response? response;
      final candidates = <String>[];
      if (baseUrl.toLowerCase().endsWith('/models')) {
        candidates.add(baseUrl);
      } else if (baseUrl.toLowerCase().endsWith('/v1')) {
        candidates.add('$baseUrl/models');
      } else {
        candidates.addAll(['$baseUrl/v1/models', '$baseUrl/models', baseUrl]);
      }
      for (final url in candidates) {
        try {
          final uri = Uri.parse(url);
          final headers = <String, String>{
            'Content-Type': 'application/json',
          };
          if (apiKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer $apiKey';
          }
          response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
          if (response.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['data'] as List? ?? [];
        final ids = raw
            .map((m) => m is Map ? m['id']?.toString() : null)
            .whereType<String>()
            .toSet()
            .toList();
        // Always include the manually entered model
        if (manuallyEntered.isNotEmpty && !ids.contains(manuallyEntered)) {
          ids.insert(0, manuallyEntered);
        }
        modelsByProvider['custom'] = ids;
        // Tag all custom models as free (self-hosted = free)
        final tags = <String, List<String>>{};
        for (final id in ids) {
          tags[id] = const ['FREE'];
        }
        modelTagsByProvider['custom'] = tags;
        final fetchedAt = DateTime.now();
        fetchedAtByProvider['custom'] = fetchedAt;
        await _hive.setSetting('${CloudModelController._cachePrefix} custom', ids);
        await _hive.setSetting(
            '${CloudModelController._cacheTimePrefix}custom', fetchedAt.toIso8601String());
      } else {
        // Even if fetch fails, ensure manually entered model is available
        if (manuallyEntered.isNotEmpty) {
          modelsByProvider['custom'] = [manuallyEntered];
          modelTagsByProvider['custom'] = {manuallyEntered: const ['FREE']};
        }
        final detail = response != null
            ? '${response.statusCode}: ${_shortBody(response.body)}'
            : 'Could not connect to $baseUrl';
        errorByProvider['custom'] = detail;
        Get.find<AppLogService>().warning(
          'Custom endpoint model list failed',
          details: detail,
          category: LogCategory.cloud,
        );
      }
    } catch (e) {
      if (manuallyEntered.isNotEmpty) {
        modelsByProvider['custom'] = [manuallyEntered];
        modelTagsByProvider['custom'] = {manuallyEntered: const ['FREE']};
      }
      errorByProvider['custom'] = '$e';
      Get.find<AppLogService>().warning(
        'Custom endpoint model list failed',
        details: e,
        category: LogCategory.cloud,
      );
    } finally {
      isLoadingProvider['custom'] = false;
    }
  }

  List<String> _modelListUrlCandidates(String provider) {
    final key = apiKeyFor(provider);
    final cloudProvider = CloudProviderRegistry.getById(provider);
    if (cloudProvider != null) {
      return cloudProvider.getModelListCandidates(key);
    }

    // Fallback for providers not in registry
    switch (provider) {
      case 'google':
        return [
          '${AppConstants.googleEndpoint}?key=$key',
        ];
      default:
        return ['https://api.openai.com/v1/models'];
    }
  }

  List<String> _parseModelIds(String provider, String body) {
    final data = jsonDecode(body);

    if (provider == 'google') {
      final raw = data['models'] as List? ?? [];
      return raw
          .map((model) => model is Map ? model['name']?.toString() : null)
          .whereType<String>()
          .toSet()
          .toList();
    }

    List<String> tryExtract(Map root) {
      final candidates = ['data', 'models', 'results', 'items', 'model_list'];
      for (final key in candidates) {
        final raw = root[key];
        if (raw is List && raw.isNotEmpty) {
          final ids = raw
              .map((m) {
                if (m is! Map) return null;
                return m['id']?.toString() ??
                    m['name']?.toString() ??
                    m['model']?.toString();
              })
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          if (ids.isNotEmpty) return ids;
        }
      }
      if (root.containsKey('model') && root['model'] is String) {
        return [root['model'] as String];
      }
      return const <String>[];
    }

    if (data is Map<String, dynamic>) {
      final ids = tryExtract(data);
      if (ids.isNotEmpty) return ids;
    }

    if (data is List) {
      final ids = data
          .map((m) {
            if (m is! Map) return null;
            return m['id']?.toString() ??
                m['name']?.toString() ??
                m['model']?.toString();
          })
          .whereType<String>()
          .toSet()
          .toList();
      if (ids.isNotEmpty) return ids;
    }

    return const [];
  }

  Map<String, List<String>> _parseModelTags(String provider, String body) {
    final tags = <String, List<String>>{};

    final data = jsonDecode(body);
    List<dynamic> rawList = const [];
    if (data is Map<String, dynamic>) {
      for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
        if (data[key] is List) {
          rawList = data[key] as List;
          break;
        }
      }
    } else if (data is List) {
      rawList = data;
    }

    const freePatterns = {
      'free', 'flash', 'mini', 'lite', 'nano',
    };

    for (final model in rawList) {
      if (model is! Map) continue;
      final id = model['id']?.toString() ?? model['name']?.toString();
      if (id == null || id.isEmpty) continue;

      final modelTags = <String>[];

      final pricing = model['pricing'];
      if (pricing is Map) {
        final prompt = _pricingValue(pricing['prompt']);
        final completion = _pricingValue(pricing['completion']);
        final request = _pricingValue(pricing['request']);
        if (prompt == 0 && completion == 0 && (request == null || request == 0)) {
          modelTags.add('FREE');
        }
      }

      final lowerId = id.toLowerCase();
      // Robust free detection: any model with :free / -free suffix is free,
      // even if pricing metadata is missing.
      if (lowerId.contains(':free') || lowerId.contains('-free')) {
        if (!modelTags.contains('FREE')) modelTags.add('FREE');
      } else if (modelTags.isEmpty) {
        for (final pattern in freePatterns) {
          if (lowerId.contains(pattern) && lowerId.contains('flash')) {
            modelTags.add('FREE');
            break;
          }
        }
      }

      final contextLength = model['context_length'] ?? model['max_context'];
      if (contextLength is num && contextLength >= 100000) {
        modelTags.add('${(contextLength / 1000).round()}K');
      }

      final owned = model['owned_by']?.toString();
      if (owned != null && owned.isNotEmpty) {
        modelTags.add(owned);
      }

      if (modelTags.isNotEmpty) {
        tags[id] = modelTags;
      }
    }

    return tags;
  }

  double? _pricingValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, List<String>> _zaiFreeTags(List<String> models) {
    const freeSet = {
      'glm-4.7-flash', 'glm-4.5-flash', 'glm-4.6v-flash',
    };
    const contextMap = <String, String>{
      'glm-5.3': '128K', 'glm-5.2': '128K', 'glm-5.1': '128K',
      'glm-5': '128K', 'glm-5-turbo': '128K', 'glm-5v-turbo': '128K',
      'glm-4.7': '128K', 'glm-4.7-flash': '128K', 'glm-4.7-flashx': '128K',
      'glm-4.6': '128K', 'glm-4.5': '128K', 'glm-4.5-x': '128K',
      'glm-4.5-air': '128K', 'glm-4.5-airx': '128K',
      'glm-4.5-flash': '128K', 'glm-4.5v': '128K',
      'glm-4.6v': '128K', 'glm-4.6v-flash': '128K', 'glm-4.6v-flashx': '128K',
      'glm-4-32b-0414-128k': '128K', 'glm-ocr': '128K',
    };
    final tags = <String, List<String>>{};
    for (final id in models) {
      final t = <String>[];
      if (freeSet.contains(id)) t.add('FREE');
      final ctx = contextMap[id];
      if (ctx != null) t.add(ctx);
      t.add('Z.AI');
      tags[id] = t;
    }
    return tags;
  }
}
