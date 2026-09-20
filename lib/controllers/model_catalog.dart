/// OTA/bundled catalog, custom URL models, and refresh plumbing.
///
/// Split from `model_controller.dart` - behavior is unchanged.
/// Contains: _bundledCatalog(), _applyCatalog(), _refreshCatalog(), _fetchCatalog(), _parseCatalog()
///   _mergeCatalog(), _loadCustomModels(), _saveCustomModels()
part of 'model_controller.dart';

extension ModelControllerCatalog on ModelController {
  /// Bundled fallback: the Dart const list (always available offline).
  List<AiModel> _bundledCatalog() =>
      AppConstants.availableModels.map((m) => AiModel.fromMap(m)).toList();

  void _applyCatalog(List<AiModel> catalog) {
    availableModels.value = catalog..addAll(customModels);
  }

  /// Fetches the OTA catalog, validates entries, and merges (remote wins
  /// by filename). Falls back to the cached JSON, then the bundled const.
  Future<void> _refreshCatalog() async {
    try {
      final lastFetch =
          _hive.getSetting<int>(ModelController._catalogFetchMsKey, defaultValue: 0) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final fresh =
          now - lastFetch < ModelController._catalogCooldown.inMilliseconds && lastFetch > 0;
      if (!fresh) {
        final remote = await _fetchCatalog();
        if (remote != null) {
          await _hive.setSetting(
              ModelController._catalogCacheKey, jsonEncode(remote.map((m) => m.toMap()).toList()));
          await _hive.setSetting(ModelController._catalogFetchMsKey, now);
          _applyCatalog(_mergeCatalog(_bundledCatalog(), remote));
          await refreshDownloaded();
          return;
        }
        await _hive.setSetting(ModelController._catalogFetchMsKey, now);
      }
      // Offline / fetch failed: last-good cache, else keep bundled.
      final cached = _hive.getSetting<String>(ModelController._catalogCacheKey);
      if (cached != null && cached.isNotEmpty) {
        final parsed = _parseCatalog(cached);
        if (parsed.isNotEmpty) {
          _applyCatalog(_mergeCatalog(_bundledCatalog(), parsed));
          await refreshDownloaded();
        }
      }
    } catch (_) {
      // Catalog is best-effort — bundled list always works.
    }
  }

  /// Downloads + validates the remote catalog. Returns null on any failure.
  Future<List<AiModel>?> _fetchCatalog() async {
    try {
      final res = await Dio()
          .get<String>(
            ModelController._catalogUrl,
            options: Options(
              responseType: ResponseType.plain,
              headers: {'Accept': 'application/json'},
            ),
          )
          .timeout(const Duration(seconds: 10));
      final body = res.data;
      if (res.statusCode != 200 || body == null || body.isEmpty) {
        return null;
      }
      return _parseCatalog(body);
    } catch (_) {
      return null;
    }
  }

  /// Parses + validates catalog JSON. Only https URLs with known model
  /// extensions are accepted (max 500 entries).
  List<AiModel> _parseCatalog(String raw) {
    final out = <AiModel>[];
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['models'] : decoded;
      if (list is! List) return out;
      for (final item in list.take(500)) {
        if (item is! Map) continue;
        final dyn = Map<String, dynamic>.from(item);
        final filename = (dyn['filename']?.toString() ?? '').trim();
        final url = (dyn['url']?.toString() ?? '').trim();
        if (filename.isEmpty || url.isEmpty) continue;
        final lower = url.toLowerCase();
        if (!lower.startsWith('https://')) continue;
        final flow = filename.toLowerCase();
        if (!flow.endsWith('.gguf') &&
            !flow.endsWith('.litertlm') &&
            !flow.endsWith('.safetensors')) {
          continue;
        }
        if ((dyn['name']?.toString() ?? '').trim().isEmpty) {
          dyn['name'] = filename;
        }
        out.add(AiModel.fromDynamic(dyn));
      }
    } catch (_) {}
    return out;
  }

  /// Merges remote entries over bundled ones by filename.
  List<AiModel> _mergeCatalog(List<AiModel> base, List<AiModel> remote) {
    final merged = <AiModel>[...base];
    for (final r in remote) {
      final idx = merged.indexWhere((m) => m.filename == r.filename);
      if (idx >= 0) {
        merged[idx] = r;
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  void _loadCustomModels() {
    final raw =
        _hive.getSetting<List>(ModelController._customModelsKey, defaultValue: []) ?? [];
    customModels.value = raw
        .whereType<Map>()
        .map((m) => AiModel.fromMap(Map<String, String>.from(m)))
        .toList();
  }

  Future<void> _saveCustomModels() async {
    await _hive.setSetting(
      ModelController._customModelsKey,
      customModels.map((m) => m.toMap()).toList(),
    );
  }
}
