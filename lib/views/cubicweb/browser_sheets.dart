// ignore_for_file: library_private_types_in_public_api

/// Bottom sheets and dialogs for the CubicWeb browser state: menu,
/// tabs, bookmarks, history, downloads, privacy, shield, link, video,
/// engine, toolbar, saved pages, AI helpers and shortcut editors.
///
/// Part of `browser_view.dart` (same library) — shares its imports,
/// state fields and private members. Split out so the view file stays
/// navigable; behavior is unchanged.
/// Contains: _sheetHandle(), _sheetDecor(), _showMenu(), _buildMenuPage(), _buildMenuItem()
///   _buildDataSavedPill(), _showGxLimiterSheet(), _profileBtn(), _showNewsCategorySheet()
///   _showShieldSheet(), _showLinkSheet(), _showHistorySheet(), _showBookmarksSheet()
///   _showSavedPagesSheet(), _showDownloadsSheet(), _buildDownloadRow(), _showPrivacyDashboard()
///   _showTabGroupDialog(), _showVideoDownloadSheet(), _showToolbarConfigSheet()
///   _showWritingAssistant(), _triggerAssistantAction(), _showAiThemeGenerator(), _generateAiTheme()
///   _toggleListeningMode(), _showEngineSheet(), _showAddEngineDialog(), _ago()
part of 'browser_view.dart';

extension BrowserSheets on _BrowserViewState {
  // ── Sheets ────────────────────────────────────────────────────────

  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  BoxDecoration _sheetDecor(bool isDark) {
    final custom = _settings.browserCustomTheme;
    final bgColor =
        _parseColor(custom['bg'], isDark ? Dt.cardDark : Dt.card);
    return BoxDecoration(
      color: bgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    );
  }

  void _showMenu(BuildContext context, bool isDark, WebTab? tab) {
    if (tab == null) return;
    final url = tab.url.value;
    final hasPage = url.isNotEmpty && url != 'about:blank';

    final List<Widget> page1 = [
      _buildMenuItem('Bookmarks', LucideIcons.bookmark, () {
        Get.back();
        _showBookmarksSheet(context, isDark);
      }),
      _buildMenuItem('History', LucideIcons.history, () {
        Get.back();
        _showHistorySheet(context, isDark);
      }),
      _buildMenuItem('Downloads', LucideIcons.download, () {
        Get.back();
        _showDownloadsSheet(context, isDark);
      }),
      _buildMenuItem('Files', LucideIcons.folder, () {
        Get.back();
        Get.to(() => const BrowserFilesView());
      }),
      _buildMenuItem('AI Notes', LucideIcons.bookMarked, () {
        Get.back();
        _scaffoldKey.currentState?.openEndDrawer();
      }),
      _buildMenuItem('Offline', LucideIcons.cloudOff, () {
        Get.back();
        _saveForOffline(tab);
      }, enabled: hasPage),
      _buildMenuItem('As PDF', LucideIcons.fileDown, () {
        Get.back();
        _saveAsPdf(tab);
      }, enabled: hasPage),
      _buildMenuItem('Find', LucideIcons.fileSearch, () {
        Get.back();
        _startFind();
      }, enabled: hasPage),
    ];

    final List<Widget> page2 = [
      _buildMenuItem('Screenshot', LucideIcons.camera, () {
        Get.back();
        _takeScreenshot(tab);
      }, enabled: hasPage),
      _buildMenuItem('Capture All', LucideIcons.scan, () {
        Get.back();
        _takeLongScreenshot(tab);
      }, enabled: hasPage),
      _buildMenuItem('QR Handoff', LucideIcons.monitorUp, () {
        Get.back();
        _showQrHandoff(tab);
      }, enabled: hasPage),
      _buildMenuItem('Group', LucideIcons.library, () {
        Get.back();
        _showTabGroupDialog(tab);
      }),
      _buildMenuItem('Extract', LucideIcons.clipboardList, () {
        Get.back();
        _extractToChat(tab);
      }, enabled: hasPage),
      _buildMenuItem('Auto-fill', LucideIcons.userCheck, () {
        Get.back();
        _autoFillIdentity(tab);
      }, enabled: hasPage),
      _buildMenuItem('Site Rules', LucideIcons.bot, () {
        Get.back();
        _showSiteRulesSheet(tab);
      }),
      _buildMenuItem('Night', LucideIcons.moon, () {
        _toggleDarkMode(tab);
      }, isActive: _settings.browserForcedDark.value),
    ];

    final List<Widget> page3 = [
      _buildMenuItem('Desktop', LucideIcons.monitor, () {
        Get.back();
        _toggleDesktopMode(tab);
      }, isActive: tab.desktopMode.value),
      _buildMenuItem('Wipe', LucideIcons.bomb, () async {
        Get.back();
        await _browser.privacyBomb();
      }),
      _buildMenuItem('Limiter', LucideIcons.gauge, () {
        Get.back();
        _showGxLimiterSheet(context, isDark);
      }),
      _buildMenuItem('Wallpaper', LucideIcons.image, () {
        Get.back();
        _pickWallpaper();
      }),
    ];

    final RxInt currentPage = 0.obs;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Dt.canvasDark : Dt.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Center Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildDataSavedPill(isDark),
                  ),
                  Text(
                    'CUBICWEB',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.shieldCheck, size: 18, color: Colors.green),
                          onPressed: () { Get.back(); _showPrivacyDashboard(context, isDark, tab); },
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.bookOpen, size: 18, color: Colors.amber),
                          onPressed: () async {
                            Get.back();
                            final html = await tab.webController?.evaluateJavascript(source: AdblockService.readerJs);
                            if (!context.mounted) return;
                            if (html != null && html.toString().isNotEmpty) {
                              _showReaderView(context, isDark, tab, html.toString());
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: PageView(
                onPageChanged: (idx) => currentPage.value = idx,
                children: [
                  _buildMenuPage(page1),
                  _buildMenuPage(page2),
                  _buildMenuPage(page3),
                ],
              ),
            ),
            Obx(() => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      3,
                      (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: currentPage.value == index
                                  ? Dt.accent
                                  : Colors.grey.withValues(alpha: 0.3),
                            ),
                          )),
                )),
            const SizedBox(height: 20),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.settings, size: 20),
                    onPressed: () {
                      Get.back();
                      Get.toNamed('/app-settings');
                    },
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.eraser, size: 20),
                    tooltip: 'Clear Data',
                    onPressed: () {
                      Get.back();
                      _clearBrowsingData(tab);
                    },
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.search, size: 20),
                    tooltip: 'Search Engine',
                    onPressed: () {
                      Get.back();
                      _showEngineSheet(context, isDark);
                    },
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.layout, size: 20),
                    tooltip: 'Toolbar',
                    onPressed: () {
                      Get.back();
                      _showToolbarConfigSheet(isDark);
                    },
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.palette, size: 20),
                    tooltip: 'AI Theme',
                    onPressed: () {
                      Get.back();
                      _showAiThemeGenerator();
                    },
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(LucideIcons.power,
                        color: Colors.red, size: 20),
                    onPressed: () => SystemNavigator.pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildMenuPage(List<Widget> items) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: items,
    );
  }

  Widget _buildMenuItem(String label, IconData icon, VoidCallback onTap,
      {bool enabled = true, bool isActive = false}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: Get.width / 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive ? Dt.accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isActive ? Colors.white : null, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Dt.accent : null,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataSavedPill(bool isDark) {
    return Obx(() {
      final bytes = _settings.browserTotalDataSaved.value;
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.zap, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              '$mb MB Saved',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    });
  }

  void _showGxLimiterSheet(BuildContext context, bool isDark) {
    if (!Get.isRegistered<DeviceInfoService>()) return;
    final dev = Get.find<DeviceInfoService>();

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Row(
              children: [
                const Icon(LucideIcons.zap, color: Dt.accentGx, size: 20),
                const SizedBox(width: 12),
                Text('GX Resource Limiter',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Obx(() => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Limiter'),
              trailing: Switch(
                value: _settings.browserLimiterEnabled.value,
                onChanged: (v) => _settings.setBrowserLimiterEnabled(v),
              ),
            )),
            const Divider(),
            Obx(() {
              final total = dev.totalRamGB.value * 1024; // MB
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('RAM Limiter', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_settings.browserRamLimit.value} MB / ${total.toStringAsFixed(0)} MB'),
                    ],
                  ),
                  Slider(
                    value: _settings.browserRamLimit.value.toDouble(),
                    min: 256,
                    max: total,
                    divisions: 10,
                    activeColor: Dt.accentGx,
                    onChanged: _settings.browserLimiterEnabled.value
                        ? (v) => _settings.setBrowserRamLimit(v.round())
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CPU Limiter', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${(_settings.browserCpuLimit.value * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                  Slider(
                    value: _settings.browserCpuLimit.value,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    activeColor: Dt.accentGx,
                    onChanged: _settings.browserLimiterEnabled.value
                        ? (v) => _settings.setBrowserCpuLimit(v)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Soft limits will automatically hibernate background tabs when exceeded.',
                    style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                  ),
                  const Divider(height: 32),
                  Text('Performance Profile', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _profileBtn('eco', LucideIcons.leaf),
                      _profileBtn('balanced', LucideIcons.scale),
                      _profileBtn('beast', LucideIcons.zap),
                    ],
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }



  Widget _profileBtn(String id, IconData icon) {
    return Obx(() {
      final selected = _settings.browserPerformanceProfile.value == id;
      return IconButton(
        icon: Icon(icon, color: selected ? Dt.accentGx : Colors.grey),
        onPressed: () {
          _haptic();
          _settings.setBrowserPerformanceProfile(id);
        },
        tooltip: id.capitalizeFirst,
      );
    });
  }

  void _showNewsCategorySheet(bool isDark) {
    final cats = ['artificial intelligence', 'technology', 'science', 'business', 'health', 'entertainment'];
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('News Categories', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats.map((c) {
                return Obx(() {
                  final selected = _settings.browserNewsCategories.contains(c);
                  return FilterChip(
                    label: Text(c.capitalizeFirst!),
                    selected: selected,
                    onSelected: (_) {
                      _settings.toggleNewsCategory(c);
                      Get.find<NewsService>().fetchNews(force: true);
                    },
                  );
                });
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showShieldSheet(BuildContext context, bool isDark, WebTab tab) {
    final host = AdblockService.hostOf(tab.url.value) ?? '';
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.shieldCheck),
                  title: const Text('Trackers blocked'),
                  subtitle: host.isEmpty
                      ? null
                      : Text('on $host · this page load'),
                  trailing: Text(
                    '${tab.blockedCount.value}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                )),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.eyeOff),
                  title: const Text('Allow ads on this site'),
                  subtitle: host.isEmpty ? null : Text(host),
                  trailing: Switch(
                    value: host.isNotEmpty &&
                        _settings.isAllowlisted('https://$host/'),
                    onChanged: host.isEmpty
                        ? null
                        : (_) async {
                            final nowOn = await _settings
                                .toggleAllowlist(host);
                            _toast(
                                nowOn ? 'Allowlisted' : 'Blocklisted',
                                nowOn
                                    ? 'Ads allowed on $host.'
                                    : 'Ad-block restored on $host.');
                            _reload(tab);
                          },
                  ),
                )),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.shield),
                  title: const Text('Ad-block everywhere'),
                  trailing: Switch(
                    value: _settings.adblockEnabled.value,
                    onChanged: (v) =>
                        _settings.setAdblockEnabled(v),
                  ),
                )),
            ListTile(
              leading: const Icon(LucideIcons.mousePointer),
              title: const Text('Block Element Manually'),
              subtitle: const Text('Pick and hide parts of this page'),
              onTap: () {
                Get.back();
                _startElementPicker(tab);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkSheet(
      BuildContext context, bool isDark, WebTab tab, String link,
      {bool isImage = false}) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(link,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            ),
            ListTile(
              leading: const Icon(LucideIcons.plus),
              title: const Text('Open in new tab'),
              onTap: () {
                Get.back();
                _openInNewTab(link);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.copy),
              title: const Text('Copy link'),
              onTap: () {
                Get.back();
                _copyLink(link);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.share),
              title: const Text('Share link'),
              onTap: () {
                Get.back();
                _shareLink(link);
              },
            ),
            if (isImage)
              ListTile(
                leading: const Icon(LucideIcons.download),
                title: const Text('Download image'),
                onTap: () {
                  Get.back();
                  _downloadFile(link);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('History',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Row(children: [
              Text('session only',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Theme.of(context).hintColor)),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                tooltip: 'Clear history',
                onPressed: () => _browser.clearVisits(),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_browser.visits.isEmpty) {
                return Center(
                    child: Text('No pages visited yet this session.',
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _browser.visits.length,
                itemBuilder: (context, i) {
                  final v = _browser.visits[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.globe, size: 18),
                    title: Text(v.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(v.url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(_ago(v.at),
                        style:
                            GoogleFonts.plusJakartaSans(fontSize: 11)),
                    onTap: () {
                      Get.back();
                      _go(v.url);
                    },
                  );
                },
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _showBookmarksSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Bookmarks',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text('saved on this device',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_settings.browserBookmarks.isEmpty) {
                return Center(
                    child: Text(
                        'No bookmarks yet.\nUse ⋮ → Bookmark this page.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _settings.browserBookmarks.length,
                itemBuilder: (context, i) {
                  final b = _settings.browserBookmarks[i];
                  final title = b['title'] ?? '';
                  final url = b['url'] ?? '';
                  return ListTile(
                    dense: true,
                    leading:
                        const Icon(LucideIcons.bookmark, size: 18),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      onPressed: () =>
                          _settings.removeBookmark(url),
                    ),
                    onTap: () {
                      Get.back();
                      _go(url);
                    },
                  );
                },
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _showSavedPagesSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Saved Pages',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text('offline reading',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_browser.offlinePages.isEmpty) {
                return Center(
                    child: Text('No saved pages yet.\nUse ⋮ → Save for Offline.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _browser.offlinePages.length,
                itemBuilder: (context, i) {
                  final p = _browser.offlinePages[i];
                  final title = p['title'] ?? '';
                  final url = p['url'] ?? '';
                  final path = p['path'] ?? '';
                  final host = Uri.tryParse(url)?.host ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.fileText, size: 18),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(host.isNotEmpty ? host : url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      onPressed: () => _browser.deleteOfflinePage(i),
                    ),
                    onTap: () {
                      Get.back();
                      if (path.isNotEmpty) {
                        _loadUrl(_browser.currentTab!, 'file://$path');
                      }
                    },
                  );
                },
              );
            }),
          ),
        ]),
      ),
    );
  }

  /// UC-style download manager: live progress, pause / resume / retry.
  void _showDownloadsSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Downloads',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => _dl.clearFinished(),
              child: const Text('Clear finished'),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_dl.downloads.isEmpty) {
                return Center(
                    child: Text(
                        'No downloads yet.\nFiles you download appear here with progress.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _dl.downloads.length,
                itemBuilder: (context, i) =>
                    _buildDownloadRow(_dl.downloads[i], isDark),
              );
            }),
          ),
        ]),
      ),
    );
  }

  Widget _buildDownloadRow(BrowserDownload d, bool isDark) {
    return Obx(() {
      final st = d.status.value;
      final IconData icon;
      final Color color;
      switch (st) {
        case BrowserDownloadStatus.downloading:
        case BrowserDownloadStatus.queued:
          icon = LucideIcons.download;
          color = Dt.accent;
          break;
        case BrowserDownloadStatus.paused:
          icon = LucideIcons.pause;
          color = Colors.orange;
          break;
        case BrowserDownloadStatus.completed:
          icon = LucideIcons.checkCircle2;
          color = Colors.green;
          break;
        case BrowserDownloadStatus.failed:
          icon = LucideIcons.alertTriangle;
          color = Colors.red;
          break;
        case BrowserDownloadStatus.canceled:
          icon = LucideIcons.ban;
          color = Theme.of(context).hintColor;
          break;
      }
      final showBar = st == BrowserDownloadStatus.downloading ||
          st == BrowserDownloadStatus.paused;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Dt.borderColor(isDark)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      st == BrowserDownloadStatus.failed && d.error.value.isNotEmpty
                          ? d.error.value
                          : '${d.progressLabel} · ${st.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ),
              if (st == BrowserDownloadStatus.downloading ||
                  st == BrowserDownloadStatus.queued)
                IconButton(
                  tooltip: 'Pause',
                  icon: const Icon(LucideIcons.pause, size: 18),
                  onPressed: () => _dl.pause(d.id),
                ),
              if (st == BrowserDownloadStatus.paused)
                IconButton(
                  tooltip: 'Resume',
                  icon: const Icon(LucideIcons.play, size: 18),
                  onPressed: () => _dl.resume(d.id),
                ),
              if (st == BrowserDownloadStatus.failed ||
                  st == BrowserDownloadStatus.canceled)
                IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(LucideIcons.rotateCcw, size: 18),
                  onPressed: () => _dl.retry(d.id),
                ),
              if (st == BrowserDownloadStatus.downloading ||
                  st == BrowserDownloadStatus.queued ||
                  st == BrowserDownloadStatus.paused)
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => _dl.cancel(d.id),
                ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(LucideIcons.trash2,
                    size: 16, color: Theme.of(context).hintColor),
                onPressed: () => _dl.remove(d.id),
              ),
            ]),
            if (showBar) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.total.value > 0 ? d.progress : null,
                  minHeight: 4,
                  backgroundColor:
                      Theme.of(context).hintColor.withValues(alpha: 0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Dt.accent),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  void _showPrivacyDashboard(BuildContext context, bool isDark, WebTab tab) {    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          children: [
            _sheetHandle(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Privacy Dashboard',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: () => Get.back(),
              ),
            ]),
            const SizedBox(height: 16),
            Obx(() => ListTile(
                  leading:
                      const Icon(LucideIcons.shieldCheck, color: Colors.green),
                  title: Text('${tab.blockedCount.value} Trackers blocked'),
                  subtitle: const Text('on this page'),
                )),
            const Divider(),
            Expanded(
              child: Obx(() {
                if (tab.blockedHosts.isEmpty) {
                  return Center(
                      child: Text('No trackers detected on this page.',
                          style: GoogleFonts.plusJakartaSans(
                              color: Theme.of(context).hintColor)));
                }
                return ListView.builder(
                  itemCount: tab.blockedHosts.length,
                  itemBuilder: (context, i) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(LucideIcons.activity, size: 16),
                      title: Text(tab.blockedHosts[i]),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showTabGroupDialog(WebTab tab) {
    final ctrl = TextEditingController(text: tab.groupName.value);
    Get.dialog(
      AlertDialog(
        title: const Text('Tab Grouping'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Enter group name (e.g. Work)',
            labelText: 'Group Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _browser.setTabGroup(_browser.tabs.indexOf(tab), '');
              Get.back();
            },
            child: const Text('Remove Group'),
          ),
          TextButton(
            onPressed: () {
              _browser.setTabGroup(_browser.tabs.indexOf(tab), ctrl.text);
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showVideoDownloadSheet(BuildContext context, bool isDark, WebTab tab) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.5,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          children: [
            _sheetHandle(),
            Text('Videos Detected',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: Obx(() => ListView.builder(
                    itemCount: tab.detectedVideos.length,
                    itemBuilder: (context, i) {
                      final url = tab.detectedVideos[i];
                      final name = url.split('/').last.split('?').first;
                      return ListTile(
                        leading: const Icon(LucideIcons.video, size: 18),
                        title: Text(name.isEmpty ? 'Video $i' : name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_settings.browserPipEnabled.value)
                              IconButton(
                                icon: const Icon(LucideIcons.externalLink, size: 16),
                                tooltip: 'Pop-out',
                                onPressed: () {
                                  Get.back();
                                  refreshBrowserUi(() => _pipUrl = url);
                                },
                              ),
                            IconButton(
                              icon: const Icon(LucideIcons.download, size: 18),
                              onPressed: () {
                                Get.back();
                                _downloadFile(url, suggested: name);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  )),
            ),
          ],
        ),
      ),
    );
  }

  void _showToolbarConfigSheet(bool isDark) {
    final available = [
      'back',
      'forward',
      'home',
      'tabs',
      'menu',
      'qr',
      'snapshot',
      'summarize',
      'translate',
      'split',
      'downloads'
    ];
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('Custom Toolbar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: available.map((id) {
                return Obx(() {
                  final selected = _settings.browserToolbarTools.contains(id);
                  return FilterChip(
                    label: Text(id.capitalizeFirst!),
                    selected: selected,
                    onSelected: (v) {
                      final current = _settings.browserToolbarTools.toList();
                      if (v) {
                        if (current.length < 5) current.add(id);
                      } else {
                        if (current.length > 2) current.remove(id);
                      }
                      _settings.setBrowserToolbarConfig(current);
                    },
                  );
                });
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Max 5 tools recommended', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showWritingAssistant() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('Writing Assistant', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter text to improve...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Improve');
                  },
                  child: const Text('Improve'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Simplify');
                  },
                  child: const Text('Simplify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerAssistantAction(String text, String action) async {
    if (text.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Assistant', 'Processing text...');
    Get.find<HomeController>().changeTab(0);
    await chat.askInNewChat('$action this text for me:\n\n$text');
  }

  void _showAiThemeGenerator() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('AI Theme Generator', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Describe a theme (e.g. Neon Cyberpunk)...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Get.back();
                _generateAiTheme(ctrl.text);
              },
              child: const Text('Generate Theme'),
            ),
            if (_settings.browserCustomTheme.isNotEmpty)
              TextButton(
                onPressed: () {
                  Get.back();
                  _settings.applyAiTheme({});
                },
                child: const Text('Reset Theme', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAiTheme(String prompt) async {
    if (prompt.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Theme', 'Generating color palette...');

    final result = await chat.askOnce(
      'Generate a color palette for a browser theme based on this prompt: "$prompt". Return ONLY a JSON object with these keys: "accent", "bg", "secondary". Use hex codes (e.g. #FF0000).',
    );

    if (result == null) return;
    try {
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(result);
      if (match != null) {
        final data = jsonDecode(match.group(0)!);
        if (data is Map) {
          final theme = data.map((k, v) => MapEntry(k.toString(), v.toString()));
          await _settings.applyAiTheme(theme);
          _toast('AI Theme', 'New theme applied!');
        }
      }
    } catch (_) {
      _toast('AI Theme', 'Failed to parse colors.');
    }
  }

  Future<void> _toggleListeningMode(WebTab tab) async {
    final tts = Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
    if (tts == null) return;

    if (_isReading.value) {
      await tts.stop();
      _isReading.value = false;
      return;
    }

    final page = await _extractPage(tab);
    if (page == null || (page['text'] ?? '').isEmpty) {
      _toast('Empty page', 'Nothing to read.');
      return;
    }

    _isReading.value = true;
    _toast('Listening Mode', 'Reading page...');
    await tts.speak(page['text']!);
    _isReading.value = false;
  }

  void _showEngineSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Search engine',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            ...BrowserSearchEngines.engines.map(
              (e) => Obx(() {
                final selected =
                    _settings.browserSearchEngine.value == e.id;
                return ListTile(
                  dense: true,
                  title: Text(e.name),
                  trailing: selected
                      ? const Icon(LucideIcons.check,
                          color: Dt.accent)
                      : null,
                  onTap: () {
                    _settings.setBrowserSearchEngine(e.id);
                    Get.back();
                  },
                );
              }),
            ),
            ..._settings.browserCustomEngines.asMap().entries.map((entry) => Obx(() {
                  final i = entry.key;
                  final e = entry.value;
                  final id = e['name']!;
                  final selected = _settings.browserSearchEngine.value == id;
                  return ListTile(
                    dense: true,
                    title: Text(id),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) const Icon(LucideIcons.check, color: Dt.accent),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 16),
                          onPressed: () => _settings.removeCustomSearchEngine(i),
                        ),
                      ],
                    ),
                    onTap: () {
                      _settings.setBrowserSearchEngine(id);
                      Get.back();
                    },
                  );
                })),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.plus),
              title: const Text('Add Custom Engine'),
              onTap: () => _showAddEngineDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEngineDialog() {
    final nameCtrl = TextEditingController();
    final templateCtrl = TextEditingController(text: 'https://search.com/search?q=%s');
    Get.dialog(
      AlertDialog(
        title: const Text('Add Search Engine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: templateCtrl, decoration: const InputDecoration(labelText: 'URL Template (%s for query)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _settings.addCustomSearchEngine(nameCtrl.text, templateCtrl.text);
              Get.back();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
