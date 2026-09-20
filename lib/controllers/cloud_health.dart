/// Model health probes, testing, and persistence.
///
/// Split from `cloud_model_controller.dart` - behavior is unchanged.
/// Contains: refreshModels(), importModels(), isTesting(), testAllModels(), cancelTesting(), _probeModel()
///   healthFor(), _setOneHealth(), _setHealth(), _saveHealth(), _loadHealth()
part of 'cloud_model_controller.dart';

extension CloudModelControllerHealth on CloudModelController {
  Future<void> refreshModels(String provider) async {
    if (provider == 'custom') {
      await refreshCustomModels();
      return;
    }

    if (apiKeyFor(provider).isEmpty) {
      errorByProvider.remove(provider);
      return;
    }

    isLoadingProvider[provider] = true;
    errorByProvider.remove(provider);
    companyFilterByProvider.remove(provider);

    if (provider == 'zai') {
      final defaults = CloudModelController._defaultModelsByProvider[provider] ?? const [];
      final withActive = [...defaults];
      final activeZai = activeModelFor(provider);
      if (activeZai.isNotEmpty && !withActive.contains(activeZai)) {
        withActive.add(activeZai);
      }
      modelsByProvider[provider] = withActive;
      modelTagsByProvider[provider] = _zaiFreeTags(defaults);
      fetchedAtByProvider[provider] = DateTime.now();
      await _hive.setSetting('${CloudModelController._cachePrefix}$provider', defaults);
      await _hive.setSetting(
          '${CloudModelController._cacheTimePrefix}$provider', DateTime.now().toIso8601String());
      isLoadingProvider[provider] = false;
      return;
    }

    try {
      final candidates = _modelListUrlCandidates(provider);
      final cloudProvider = CloudProviderRegistry.getById(provider);
      final headers = cloudProvider?.buildAuthHeaders(apiKeyFor(provider)) ??
          {'Authorization': 'Bearer ${apiKeyFor(provider)}'};
      http.Response? response;
      String? workingUrl;

      for (final url in candidates) {
        try {
          final resp =
              await http.get(Uri.parse(url), headers: headers).timeout(
                    const Duration(seconds: 15),
                  );
          if (resp.statusCode == 200) {
            final ids = _parseModelIds(provider, resp.body);
            if (ids.isNotEmpty) {
              response = resp;
              workingUrl = url;
              break;
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (response == null || workingUrl == null) {
        final defaults = CloudModelController._defaultModelsByProvider[provider];
        if (defaults != null && defaults.isNotEmpty) {
          final withActive = [...defaults];
          final activeFallback = activeModelFor(provider);
          if (activeFallback.isNotEmpty && !withActive.contains(activeFallback)) {
            withActive.add(activeFallback);
          }
          modelsByProvider[provider] = withActive;
          fetchedAtByProvider[provider] = DateTime.now();
          await _hive.setSetting('${CloudModelController._cachePrefix}$provider', defaults);
          await _hive.setSetting(
              '${CloudModelController._cacheTimePrefix}$provider', DateTime.now().toIso8601String());
        } else {
          errorByProvider[provider] = 'Failed to fetch model list';
        }
        return;
      }

      final ids = _parseModelIds(provider, response.body);
      final active = activeModelFor(provider);
      if (active.isNotEmpty && !ids.contains(active)) {
        ids.add(active);
      }
      modelsByProvider[provider] = ids;
      modelTagsByProvider[provider] = _parseModelTags(provider, response.body);
      final fetchedAt = DateTime.now();
      fetchedAtByProvider[provider] = fetchedAt;
      await _hive.setSetting('${CloudModelController._cachePrefix}$provider', ids);
      await _hive.setSetting(
          '${CloudModelController._cacheTimePrefix}$provider', fetchedAt.toIso8601String());
      await _hive.setSetting('${CloudModelController._workingUrlPrefix}$provider', workingUrl);
      // NOTE: no auto-detected vendor cards — aggregator models stay
      // inside their source card (company chips filter by vendor).
    } catch (e) {
      errorByProvider[provider] = '$e';
      Get.find<AppLogService>().warning(
        'Model list request failed for $provider',
        details: e,
        category: LogCategory.cloud,
      );
    } finally {
      isLoadingProvider[provider] = false;
    }
  }

  /// Explicit "Import from /models": fetch the provider's live model
  /// list and report how many NEW ids arrived (0 = already current).
  /// Returns the new-model count, or -1 when there is no API key.
  Future<int> importModels(String provider) async {
    if (provider != 'custom' && apiKeyFor(provider).isEmpty) {
      AppSnackbar.showTop('API key needed',
          'Add an API key for this provider first, then import.',
          logHistory: false);
      return -1;
    }
    final before =
        Set<String>.from(modelsByProvider[provider] ?? const <String>[]);
    await refreshModels(provider);
    final after = modelsByProvider[provider] ?? const <String>[];
    final fresh = findNewModels(before.toList(), after);
    if (errorByProvider[provider]?.isNotEmpty == true) {
      AppSnackbar.showTop(
          'Import failed', errorByProvider[provider] ?? 'Unknown error',
          logHistory: false);
      return 0;
    }
    if (fresh.isEmpty) {
      AppSnackbar.showTop('Already up to date',
          '${after.length} models — nothing new on /models.',
          logHistory: false);
    } else {
      AppSnackbar.showTop('Imported ${fresh.length} new model${fresh.length == 1 ? '' : 's'}',
          fresh.take(3).join(', ') +
              (fresh.length > 3 ? ' (+${fresh.length - 3} more)' : ''),
          logHistory: false);
    }
    return fresh.length;
  }

  // ── Test all models ──

  bool isTesting(String provider) =>
      testingByProvider[provider] == true;

  /// Ping every listed model with one tiny chat call (concurrency 3).
  /// A probe checks the CONNECTION, not the full reply: instant error
  /// = failed fast; first stream chunk (even an empty/thought opener
  /// from a reasoning model) = online immediately, no waiting for the
  /// final text. First-chunk window is 15s; transient failures
  /// (429/5xx/timeout) get ONE retry after 5s so burst probing doesn't
  /// mass-mark working models as failed.
  /// Records online/failed + latency per model. Cancel via
  /// [cancelTesting]. Skipped entirely without an API key.
  Future<void> testAllModels(String provider) async {
    if (isTesting(provider)) return;
    if (provider != 'custom' && apiKeyFor(provider).isEmpty) {
      AppSnackbar.showTop('API key needed',
          'Add an API key for this provider first, then test.',
          logHistory: false);
      return;
    }
    final models = [...(modelsByProvider[provider] ?? const <String>[])];
    if (models.isEmpty) {
      AppSnackbar.showTop(
          'Nothing to test', 'Import the model list first.',
          logHistory: false);
      return;
    }
    testingByProvider[provider] = true;
    testTotalByProvider[provider] = models.length;
    testDoneByProvider[provider] = 0;
    _testCancel[provider] = false;
    _setHealth(
        provider,
        Map<String, ModelHealth>.from(modelHealthByProvider[provider] ?? {}),
        persist: false);
    try {
      CloudService cloud;
      try {
        cloud = Get.find<CloudService>();
      } catch (_) {
        AppSnackbar.showTop(
            'Cloud unavailable', 'CloudService is not running.',
            logHistory: false);
        return;
      }
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          if (_testCancel[provider] == true) return;
          final i = cursor++;
          if (i >= models.length) return;
          // Gentle stagger so 3 workers don't burst-fire (fewer 429s).
          if (i > 0) await Future.delayed(const Duration(milliseconds: 250));
          final model = models[i];
          _setOneHealth(
              provider,
              ModelHealth(
                  modelId: model,
                  status: ModelHealthStatus.testing,
                  checkedAtMs:
                      DateTime.now().millisecondsSinceEpoch));
          final sw = Stopwatch()..start();
          try {
            await _probeModel(cloud, provider, model);
            sw.stop();
            _setOneHealth(
                provider,
                ModelHealth(
                    modelId: model,
                    status: ModelHealthStatus.online,
                    latencyMs: sw.elapsedMilliseconds,
                    checkedAtMs:
                        DateTime.now().millisecondsSinceEpoch));
          } catch (e) {
            sw.stop();
            _setOneHealth(
                provider,
                ModelHealth(
                    modelId: model,
                    status: ModelHealthStatus.failed,
                    latencyMs: sw.elapsedMilliseconds,
                    error: summarizeModelError(e),
                    checkedAtMs:
                        DateTime.now().millisecondsSinceEpoch));
          } finally {
            testDoneByProvider[provider] =
                (testDoneByProvider[provider] ?? 0) + 1;
          }
        }
      }

      await Future.wait([worker(), worker(), worker()]);
      await _saveHealth(provider);
      final ok = (modelHealthByProvider[provider] ?? {})
          .values
          .where((h) => h.status == ModelHealthStatus.online)
          .length;
      final bad = (modelHealthByProvider[provider] ?? {})
          .values
          .where((h) => h.status == ModelHealthStatus.failed)
          .length;
      AppSnackbar.showTop(
          _testCancel[provider] == true
              ? 'Testing cancelled'
              : 'Testing done',
          '$ok online · $bad failed',
          logHistory: false);
    } finally {
      testingByProvider[provider] = false;
      _testCancel.remove(provider);
    }
  }

  void cancelTesting(String provider) {
    _testCancel[provider] = true;
  }

  /// One model probe: streams 'Reply with: ok' and succeeds on the
  /// FIRST chunk — even an empty one (reasoning openers, role deltas).
  /// A chunk means key accepted + model serving; waiting for the full
  /// text would only waste time. Transient errors get a single retry
  /// after 5s backoff.
  Future<void> _probeModel(
      CloudService cloud, String provider, String model) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(seconds: 5));
      }
      try {
        var gotChunk = false;
        await for (final _ in cloud
            .streamMessageAs(
              providerId: provider,
              model: model,
              messages: const [
                {'role': 'user', 'content': 'Reply with: ok'}
              ],
            )
            .timeout(const Duration(seconds: 15))) {
          gotChunk = true;
          break;
        }
        if (!gotChunk) throw Exception('Empty response stream');
        return;
      } catch (e) {
        lastError = e;
        if (_testCancel[provider] == true) rethrow;
        if (attempt == 0 && isRetryableProbeError(summarizeModelError(e))) {
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('Probe failed');
  }


  // ── Health store ──

  ModelHealth? healthFor(String provider, String model) =>
      modelHealthByProvider[provider]?[model];

  /// (online, failed) counts for badges.
  (int, int) healthSummaryFor(String provider) {
    var ok = 0;
    var bad = 0;
    for (final h in (modelHealthByProvider[provider] ?? {}).values) {
      if (h.status == ModelHealthStatus.online) ok++;
      if (h.status == ModelHealthStatus.failed) bad++;
    }
    return (ok, bad);
  }

  void _setOneHealth(String provider, ModelHealth h) {
    final map =
        Map<String, ModelHealth>.from(modelHealthByProvider[provider] ?? {});
    map[h.modelId] = h;
    _setHealth(provider, map, persist: false);
  }

  void _setHealth(String provider, Map<String, ModelHealth> map,
      {bool persist = true}) {
    modelHealthByProvider[provider] = map;
    if (persist) unawaited(_saveHealth(provider));
  }

  Future<void> _saveHealth(String provider) async {
    try {
      final map = modelHealthByProvider[provider] ?? {};
      // Cap stored rows to models still listed (stale ids dropped).
      final listed = (modelsByProvider[provider] ?? const <String>[]).toSet();
      final rows = map.values
          .where((h) => listed.contains(h.modelId))
          .map((h) => h.toMap())
          .toList();
      await _hive.setSetting('${CloudModelController._healthPrefix}$provider', rows);
    } catch (_) {}
  }

  void _loadHealth(String provider) {
    try {
      final raw = _hive.getSetting<List>('${CloudModelController._healthPrefix}$provider');
      if (raw == null) return;
      final map = <String, ModelHealth>{};
      for (final m in raw.whereType<Map>()) {
        try {
          final h = ModelHealth.fromMap(m);
          if (h.modelId.isNotEmpty) map[h.modelId] = h;
        } catch (_) {}
      }
      if (map.isNotEmpty) modelHealthByProvider[provider] = map;
    } catch (_) {}
  }
}
