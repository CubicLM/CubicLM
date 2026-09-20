/// Parameters, browser options, bookmarks, defaults, and composer upsell.
///
/// Split from `settings_controller.dart` - behavior is unchanged.
/// Contains: setTemperature(), setGgufAccelMode(), setLargeModelMode(), setTopP(), setTopK(), setRepeatPenalty(), setMaxTokens(), setContextSize()
///   effectiveContextSize, effectiveMaxTokens, _applyAutoTune(), setAutoTuneParams()
///   setWebFetchEnabled(), setAdblockEnabled(), setBrowserSearchEngine(), setBrowserForcedDark()
///   setBrowserHttpsOnly(), setBrowserDntEnabled(), setBrowserBlockThirdPartyCookies()
///   setBrowserDataSaver(), setBrowserHomepage(), setBrowserTextZoom(), setBrowserSidebarEnabled()
///   setBrowserNightModeIntensity(), _loadSpeedDial(), setBrowserResourceMonitor()
///   setBrowserWallpaper(), setBrowserNightIntensity(), setBrowserHapticsEnabled()
///   addBrowserSidebarShortcut(), removeBrowserSidebarShortcut(), _persistSidebarShortcuts()
///   setBrowserExtremeTextMode(), setBrowserSearchEnhancer(), setBrowserGesturesEnabled()
///   setBrowserPerformanceProfile(), setBrowserAmbientMusicEnabled(), addBrowserDataSaved()
///   addCustomSearchEngine(), removeCustomSearchEngine(), _persistCustomEngines()
///   _loadToolbarConfig(), setBrowserToolbarConfig(), toggleNewsCategory(), setBrowserPipEnabled()
///   setBrowserIdentity(), applyAiTheme(), setBrowserVoiceEnabled(), addAiNote(), removeAiNote()
///   addBlockedSelector(), setBrowserSplitEnabled(), setBrowserHibernationEnabled()
///   setBrowserAutoRenameDownloads(), setLongPasteToFile(), setShowDeepSearch(), setShowWebAccess()
///   setShowLiveVision(), setShowPolishPrompt(), setContextWindowStyle(), addSiteAiRule()
///   removeSiteAiRule(), setBrowserRamLimit(), setBrowserCpuLimit(), setBrowserLimiterEnabled()
///   addBrowserSpeedDialItem(), removeBrowserSpeedDialItem(), reorderBrowserSpeedDial()
///   _persistSpeedDial(), isAllowlisted(), toggleAllowlist(), isBookmarked(), addBookmark()
///   removeBookmark(), _persistBookmarks(), dismissComposerUpsell()
part of 'settings_controller.dart';

extension SettingsControllerBrowser on SettingsController {
  Future<void> setTemperature(double value) async {
    temperature.value = value;
    await _hive.setSetting(AppConstants.keyTemperature, value);
  }

  /// GGUF acceleration override ('auto' | 'cpu' | 'gpu'). Takes effect on
  /// the next model load — the resident model keeps its current offload.
  Future<void> setGgufAccelMode(String mode) async {
    final normalized = switch (mode) {
      'cpu' => 'cpu',
      'gpu' => 'gpu',
      _ => AppConstants.defaultGgufAccelMode,
    };
    ggufAccelMode.value = normalized;
    await _hive.setSetting(AppConstants.keyGgufAccelMode, normalized);
  }

  /// Experimental large-model mode toggle (13B+ attempts on phones).
  Future<void> setLargeModelMode(bool value) async {
    largeModelMode.value = value;
    await _hive.setSetting(AppConstants.keyLargeModelMode, value);
  }

  Future<void> setTopP(double value) async {
    topP.value = value;
    await _hive.setSetting(AppConstants.keyTopP, value);
  }

  Future<void> setTopK(int value) async {
    topK.value = value;
    await _hive.setSetting(AppConstants.keyTopK, value);
  }

  Future<void> setRepeatPenalty(double value) async {
    repeatPenalty.value = value;
    await _hive.setSetting(AppConstants.keyRepeatPenalty, value);
  }

  Future<void> setMaxTokens(int value) async {
    maxTokens.value = value;
    await _hive.setSetting(AppConstants.keyMaxTokens, value);
  }

  Future<void> setContextSize(int value) async {
    int clamped = value;
    if (Get.isRegistered<DeviceInfoService>()) {
      final dev = Get.find<DeviceInfoService>();
      if (clamped > dev.maxSafeContextSize) {
        clamped = dev.maxSafeContextSize;
        Get.snackbar('RAM Guard',
            'Clamped to ${dev.maxSafeContextSize} for ${dev.deviceTier.value} tier',
            snackPosition: SnackPosition.BOTTOM);
      }
      if (!dev.canAllocateContextSize(clamped)) {
        clamped = dev.recommendedContextSize;
        Get.snackbar(
            'RAM Guard', 'Not enough RAM — using ${dev.recommendedContextSize}',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
    contextSize.value = clamped;
    await _hive.setSetting(AppConstants.keyContextSize, clamped);
    _scheduleContextReload();
  }

  // ── Auto Tune ──

  /// RAM-tier context size when Auto is on, else the manual slider value.
  int get effectiveContextSize {
    if (!autoTuneParams.value) return contextSize.value;
    if (Get.isRegistered<DeviceInfoService>()) {
      return Get.find<DeviceInfoService>().recommendedContextSize;
    }
    return contextSize.value;
  }

  /// Output budget: scales with the effective context in Auto mode
  /// (~25% of the window), so long detailed answers never get cut off.
  int get effectiveMaxTokens {
    if (!autoTuneParams.value) return maxTokens.value;
    final ctx = effectiveContextSize;
    return (ctx ~/ 4).clamp(512, 16384);
  }

  /// Persist tuned values into the Hive keys the native loaders read.
  Future<void> _applyAutoTune({bool writeSettings = true}) async {
    final ctx = effectiveContextSize;
    final tok = effectiveMaxTokens;
    contextSize.value = ctx;
    maxTokens.value = tok;
    if (writeSettings) {
      await _hive.setSetting(AppConstants.keyContextSize, ctx);
      await _hive.setSetting(AppConstants.keyMaxTokens, tok);
      _scheduleContextReload();
    }
  }

  Future<void> setAutoTuneParams(bool enabled) async {
    autoTuneParams.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoTuneParams, enabled);
    if (enabled) await _applyAutoTune();
  }

  Future<void> setWebFetchEnabled(bool enabled) async {
    webFetchEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyWebFetchEnabled, enabled);
  }

  Future<void> setAdblockEnabled(bool enabled) async {
    adblockEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAdblockEnabled, enabled);
  }

  Future<void> setBrowserSearchEngine(String engineId) async {
    final id = BrowserSearchEngines.isKnown(engineId) ? engineId : 'duckduckgo';
    browserSearchEngine.value = id;
    await _hive.setSetting(AppConstants.keyBrowserSearchEngine, id);
  }

  Future<void> setBrowserForcedDark(bool enabled) async {
    browserForcedDark.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserForcedDark, enabled);
  }

  Future<void> setBrowserHttpsOnly(bool enabled) async {
    browserHttpsOnly.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserHttpsOnly, enabled);
  }

  Future<void> setBrowserDntEnabled(bool enabled) async {
    browserDntEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserDntEnabled, enabled);
  }

  Future<void> setBrowserBlockThirdPartyCookies(bool enabled) async {
    browserBlockThirdPartyCookies.value = enabled;
    await _hive.setSetting(
        AppConstants.keyBrowserBlockThirdPartyCookies, enabled);
  }

  Future<void> setBrowserDataSaver(bool enabled) async {
    browserDataSaver.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserDataSaver, enabled);
  }

  Future<void> setBrowserHomepage(String url) async {
    browserHomepage.value = url.trim();
    await _hive.setSetting(
        AppConstants.keyBrowserHomepage, browserHomepage.value);
  }

  Future<void> setBrowserTextZoom(int zoom) async {
    browserTextZoom.value = zoom.clamp(50, 200);
    await _hive.setSetting(
        AppConstants.keyBrowserTextZoom, browserTextZoom.value);
  }

  Future<void> setBrowserSidebarEnabled(bool enabled) async {
    browserSidebarEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserSidebarEnabled, enabled);
  }

  Future<void> setBrowserNightModeIntensity(double value) async {
    browserNightModeIntensity.value = value;
    await _hive.setSetting(AppConstants.keyBrowserNightModeIntensity, value);
  }

  void _loadSpeedDial() {
    final saved = SettingsController._decodeBookmarks(
        _hive.getSetting<String>(AppConstants.keyBrowserSpeedDial));
    if (saved.isEmpty) {
      // Seed defaults
      browserSpeedDial.assignAll([
        {'title': 'Wikipedia', 'url': 'https://wikipedia.org'},
        {'title': 'DuckDuckGo', 'url': 'https://duckduckgo.com'},
        {'title': 'arXiv', 'url': 'https://arxiv.org'},
        {'title': 'MDN Docs', 'url': 'https://developer.mozilla.org'},
        {'title': 'GitHub', 'url': 'https://github.com'},
        {'title': 'Flutter', 'url': 'https://flutter.dev'},
      ]);
    } else {
      browserSpeedDial.assignAll(saved);
    }
  }

  Future<void> setBrowserResourceMonitor(bool enabled) async {
    browserResourceMonitor.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserResourceMonitor, enabled);
  }

  Future<void> setBrowserWallpaper(String path) async {
    browserWallpaperPath.value = path;
    await _hive.setSetting(AppConstants.keyBrowserWallpaperPath, path);
  }

  Future<void> setBrowserNightIntensity(double value) async {
    browserNightIntensity.value = value.clamp(0.0, 0.8);
    await _hive.setSetting(
        AppConstants.keyBrowserNightIntensity, browserNightIntensity.value);
  }

  Future<void> setBrowserHapticsEnabled(bool enabled) async {
    browserHapticsEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserHapticsEnabled, enabled);
  }

  Future<void> addBrowserSidebarShortcut(String title, String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    if (browserSidebarShortcuts.any((s) => s['url'] == u)) return;
    browserSidebarShortcuts.add({
      'title': title.trim().isEmpty ? u : title.trim(),
      'url': u,
    });
    await _persistSidebarShortcuts();
  }

  Future<void> removeBrowserSidebarShortcut(String url) async {
    browserSidebarShortcuts.removeWhere((s) => s['url'] == url.trim());
    await _persistSidebarShortcuts();
  }

  Future<void> _persistSidebarShortcuts() async {
    browserSidebarShortcuts.refresh();
    await _hive.setSetting(AppConstants.keyBrowserSidebarShortcuts,
        jsonEncode(browserSidebarShortcuts));
  }

  Future<void> setBrowserExtremeTextMode(bool enabled) async {
    browserExtremeTextMode.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserExtremeTextMode, enabled);
  }

  Future<void> setBrowserSearchEnhancer(bool enabled) async {
    browserSearchEnhancer.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserSearchEnhancer, enabled);
  }

  Future<void> setBrowserGesturesEnabled(bool enabled) async {
    browserGesturesEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserGesturesEnabled, enabled);
  }

  Future<void> setBrowserPerformanceProfile(String profile) async {
    browserPerformanceProfile.value = profile;
    await _hive.setSetting(AppConstants.keyBrowserPerformanceProfile, profile);
    // Apply profile-specific logic
    if (profile == 'eco') {
      await setOrbAnim('chat', 'breathing'); // Low-impact animation
    } else if (profile == 'beast') {
      await setOrbAnim('chat', 'shaping'); // High-impact animation
    }
  }

  Future<void> setBrowserAmbientMusicEnabled(bool enabled) async {
    browserAmbientMusicEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserAmbientMusic, enabled);
  }

  Future<void> addBrowserDataSaved(int bytes) async {
    browserTotalDataSaved.value += bytes;
    await _hive.setSetting(
        AppConstants.keyBrowserTotalDataSaved, browserTotalDataSaved.value);
  }

  Future<void> addCustomSearchEngine(String name, String template) async {
    if (name.trim().isEmpty || template.trim().isEmpty) return;
    browserCustomEngines
        .add({'name': name.trim(), 'template': template.trim()});
    await _persistCustomEngines();
  }

  Future<void> removeCustomSearchEngine(int index) async {
    if (index < 0 || index >= browserCustomEngines.length) return;
    browserCustomEngines.removeAt(index);
    await _persistCustomEngines();
  }

  Future<void> _persistCustomEngines() async {
    browserCustomEngines.refresh();
    await _hive.setSetting(
        AppConstants.keyBrowserCustomEngines, jsonEncode(browserCustomEngines));
  }

  void _loadToolbarConfig() {
    final saved = SettingsController._decodeStringList(
        _hive.getSetting<String>(AppConstants.keyBrowserToolbarConfig));
    if (saved.isEmpty) {
      browserToolbarTools
          .assignAll(['back', 'forward', 'home', 'tabs', 'menu']);
    } else {
      browserToolbarTools.assignAll(saved);
    }
  }

  Future<void> setBrowserToolbarConfig(List<String> tools) async {
    browserToolbarTools.assignAll(tools);
    await _hive.setSetting(
        AppConstants.keyBrowserToolbarConfig, jsonEncode(tools));
  }

  Future<void> toggleNewsCategory(String category) async {
    if (browserNewsCategories.contains(category)) {
      browserNewsCategories.remove(category);
    } else {
      browserNewsCategories.add(category);
    }
    await _hive.setSetting(AppConstants.keyBrowserNewsCategories,
        jsonEncode(browserNewsCategories));
  }

  Future<void> setBrowserPipEnabled(bool enabled) async {
    browserPipEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserPipEnabled, enabled);
  }

  Future<void> setBrowserIdentity(Map<String, String> identity) async {
    browserIdentity.assignAll(identity);
    await _hive.setSetting(AppConstants.keyBrowserIdentity, identity);
  }

  Future<void> applyAiTheme(Map<String, String> theme) async {
    browserCustomTheme.assignAll(theme);
    await _hive.setSetting(AppConstants.keyBrowserAiThemeColors, theme);
  }

  Future<void> setBrowserVoiceEnabled(bool enabled) async {
    browserVoiceEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserVoiceEnabled, enabled);
  }

  Future<void> addAiNote(String title, String content, String url) async {
    browserAiNotes.insert(0, {
      'title': title,
      'content': content,
      'url': url,
      'at': DateTime.now().toIso8601String(),
    });
    await _hive.setSetting(
        AppConstants.keyBrowserAiNotes, browserAiNotes.toList());
  }

  Future<void> removeAiNote(int index) async {
    if (index < 0 || index >= browserAiNotes.length) return;
    browserAiNotes.removeAt(index);
    await _hive.setSetting(
        AppConstants.keyBrowserAiNotes, browserAiNotes.toList());
  }

  Future<void> addBlockedSelector(String host, String selector) async {
    final list = browserBlockedSelectors[host] ?? [];
    if (!list.contains(selector)) {
      list.add(selector);
      browserBlockedSelectors[host] = list;
      await _hive.setSetting(AppConstants.keyBrowserBlockedSelectors,
          Map<String, List<String>>.from(browserBlockedSelectors));
    }
  }

  Future<void> setBrowserSplitEnabled(bool enabled) async {
    browserSplitEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserSplitEnabled, enabled);
  }

  Future<void> setBrowserHibernationEnabled(bool enabled) async {
    browserHibernationEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserHibernationEnabled, enabled);
  }

  Future<void> setBrowserAutoRenameDownloads(bool enabled) async {
    browserAutoRenameDownloads.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserAutoRenameDownloads, enabled);
  }

  Future<void> setLongPasteToFile(bool enabled) async {
    longPasteToFile.value = enabled;
    await _hive.setSetting(AppConstants.keyLongPasteToFile, enabled);
  }

  Future<void> setShowDeepSearch(bool v) async {
    showDeepSearch.value = v;
    await _hive.setSetting(AppConstants.keyShowDeepSearch, v);
  }

  Future<void> setShowWebAccess(bool v) async {
    showWebAccess.value = v;
    await _hive.setSetting(AppConstants.keyShowWebAccess, v);
  }

  Future<void> setShowLiveVision(bool v) async {
    showLiveVision.value = v;
    await _hive.setSetting(AppConstants.keyShowLiveVision, v);
  }

  Future<void> setShowPolishPrompt(bool v) async {
    showPolishPrompt.value = v;
    await _hive.setSetting(AppConstants.keyShowPolishPrompt, v);
  }


  Future<void> setContextWindowStyle(String v) async {
    final style = SettingsController.contextWindowStyles.contains(v) ? v : 'header';
    contextWindowStyle.value = style;
    await _hive.setSetting(AppConstants.keyContextWindowStyle, style);
  }

  Future<void> addSiteAiRule(String host, String action) async {
    browserSiteAiRules[host] = action;
    await _hive.setSetting(AppConstants.keyBrowserSiteAiRules,
        Map<String, String>.from(browserSiteAiRules));
  }

  Future<void> removeSiteAiRule(String host) async {
    browserSiteAiRules.remove(host);
    await _hive.setSetting(AppConstants.keyBrowserSiteAiRules,
        Map<String, String>.from(browserSiteAiRules));
  }

  Future<void> setBrowserRamLimit(int mb) async {
    browserRamLimit.value = mb;
    await _hive.setSetting(AppConstants.keyBrowserRamLimit, mb);
  }

  Future<void> setBrowserCpuLimit(double pct) async {
    browserCpuLimit.value = pct;
    await _hive.setSetting(AppConstants.keyBrowserCpuLimit, pct);
  }

  Future<void> setBrowserLimiterEnabled(bool enabled) async {
    browserLimiterEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyBrowserLimiterEnabled, enabled);
  }

  Future<void> addBrowserSpeedDialItem(String title, String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    if (browserSpeedDial.any((item) => item['url'] == u)) return;
    browserSpeedDial.add({
      'title': title.trim().isEmpty ? u : title.trim(),
      'url': u,
      'addedAt': DateTime.now().toIso8601String(),
    });
    await _persistSpeedDial();
  }

  Future<void> removeBrowserSpeedDialItem(String url) async {
    browserSpeedDial.removeWhere((item) => item['url'] == url.trim());
    await _persistSpeedDial();
  }

  Future<void> reorderBrowserSpeedDial(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = browserSpeedDial.removeAt(oldIndex);
    browserSpeedDial.insert(newIndex, item);
    await _persistSpeedDial();
  }

  Future<void> _persistSpeedDial() async {
    browserSpeedDial.refresh();
    await _hive.setSetting(
        AppConstants.keyBrowserSpeedDial, jsonEncode(browserSpeedDial));
  }

  /// True when [url]'s host (or any parent domain) is allowlisted.
  bool isAllowlisted(String url) {
    if (browserAllowlist.isEmpty) return false;
    try {
      return AdblockService.matchesRules(url, browserAllowlist.toSet());
    } catch (_) {
      return false;
    }
  }

  /// Toggle [host] on the allowlist. Returns true when now allowlisted.
  Future<bool> toggleAllowlist(String host) async {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    if (browserAllowlist.contains(h)) {
      browserAllowlist.remove(h);
    } else {
      browserAllowlist.add(h);
    }
    await _hive.setSetting(
        AppConstants.keyBrowserAllowlist, jsonEncode(browserAllowlist));
    return browserAllowlist.contains(h);
  }

  bool isBookmarked(String url) {
    // Snapshot FIRST so Obx builders always subscribe — even for empty
    // urls. The old early-return fired the GetX empty-scope lint every
    // time the browser ⋮ menu opened on a blank tab.
    final items = browserBookmarks.toList();
    final u = url.trim();
    if (u.isEmpty) return false;
    return items.any((b) => b['url'] == u);
  }

  Future<void> addBookmark(String title, String url) async {
    final u = url.trim();
    if (u.isEmpty || isBookmarked(u)) return;
    browserBookmarks.insert(0, {
      'title': title.trim().isEmpty ? u : title.trim(),
      'url': u,
      'addedAt': DateTime.now().toIso8601String(),
    });
    await _persistBookmarks();
  }

  Future<void> removeBookmark(String url) async {
    browserBookmarks.removeWhere((b) => b['url'] == url.trim());
    await _persistBookmarks();
  }

  Future<void> _persistBookmarks() async {
    browserBookmarks.refresh();
    await _hive.setSetting(
        AppConstants.keyBrowserBookmarks, jsonEncode(browserBookmarks));
  }


  Future<void> dismissComposerUpsell() async {
    composerUpsellDismissed.value = true;
    await _hive.setSetting(AppConstants.keyComposerUpsellDismissed, true);
  }
}
