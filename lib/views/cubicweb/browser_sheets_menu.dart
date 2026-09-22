/// Browser menu sheet, pages, items, data-saver pill.
///
/// Split from `browser_sheets.dart` (part of `browser_view.dart`) - behavior is unchanged.
/// Contains: _sheetHandle(), _sheetDecor(), _showMenu(), _buildMenuPage(), _buildMenuItem()
///   _buildDataSavedPill()
part of 'browser_view.dart';

extension _BrowserSheetsMenu on _BrowserViewState {
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
}
