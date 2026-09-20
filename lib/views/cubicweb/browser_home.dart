// ignore_for_file: library_private_types_in_public_api

/// Home-tab content for the CubicWeb browser state: empty state,
/// speed dial, continue strip, news feed, AI corner and dashboard.
///
/// Part of `browser_view.dart` (same library) — shares its imports,
/// state fields and private members. Split out so the view file stays
/// navigable; behavior is unchanged.
/// Contains: _emptyState(), _buildNewsFeed(), _buildAiBanner(), _buildDashboardWidgets(), _buildSavingsCard()
///   _buildStatCard(), _buildQuickLink(), _buildAddShortcutTile(), _showAddShortcutDialog()
part of 'browser_view.dart';

extension BrowserHome on _BrowserViewState {
  Widget _emptyState(BuildContext context, bool isDark) {
    return Obx(() {
      final wallpaper = _settings.browserWallpaperPath.value;
      return Stack(
        children: [
          if (wallpaper.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: isDark ? 0.3 : 0.5,
                child: Image.file(
                  File(wallpaper),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              const SizedBox(height: 50),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Dt.accentGx.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.globe,
                      size: 40, color: Dt.accentGx),
                ),
              ),
              const SizedBox(height: 24),
              // Compact Search Box
              GestureDetector(
                onTap: () {
                  _urlCtrl.clear();
                  _suggestFocus.requestFocus();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Dt.cardDark : Dt.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Dt.borderColor(isDark).withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.search,
                          size: 18, color: Dt.accentGx),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search or type URL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.mic, size: 18, color: Colors.grey),
                        onPressed: () => _startVoiceControl(),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.qrCode, size: 18, color: Colors.grey),
                        onPressed: () => _showQrScanner(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: _settings.browserSpeedDial.length + 1,
                itemBuilder: (context, i) {
                  if (i == _settings.browserSpeedDial.length) {
                    return _buildAddShortcutTile(isDark);
                  }
                  final item = _settings.browserSpeedDial[i];
                  return _buildQuickLink(item['title'] ?? '', item['url'] ?? '',
                      LucideIcons.globe, isDark,
                      onLongPress: () =>
                          _settings.removeBrowserSpeedDialItem(item['url']!));
                },
              ),
              const SizedBox(height: 32),
              _buildDashboardWidgets(isDark),
              const SizedBox(height: 32),
              _buildAiBanner(isDark),
              _buildNewsFeed(isDark),
              const SizedBox(height: 60),
            ],
          ),
          // Floating Booster
          Positioned(
            right: 16,
            bottom: 80,
            child: _buildResourceMonitor(isDark),
          ),
        ],
      );
    });
  }



  Widget _buildNewsFeed(bool isDark) {
    final newsService = Get.find<NewsService>();
    return Obx(() {
      if (newsService.news.isEmpty && !newsService.isLoading.value) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI Trending News',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (newsService.isLoading.value)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  onPressed: () => newsService.fetchNews(force: true),
                ),
              IconButton(
                icon: const Icon(LucideIcons.settings, size: 14),
                onPressed: () => _showNewsCategorySheet(isDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...newsService.news.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Dt.cardDark : Dt.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Dt.borderColor(isDark)),
                ),
                child: InkWell(
                  onTap: () => _go(item.link),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.summary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.summary,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      );
    });
  }

  Widget _buildAiBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Dt.accentGx.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.accentGx.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, color: Dt.accentGx, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI CORNER',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Dt.accentGx)),
                Text('Explore new models and skills.',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Get.find<HomeController>().changeTab(1),
            child: const Text('VISIT'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardWidgets(bool isDark) {
    final stats = Get.isRegistered<StatsService>() ? Get.find<StatsService>() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'AI Activity',
                stats == null ? '0' : '${stats.snapshot()[StatsService.eventChatSent] ?? 0}',
                LucideIcons.messageSquare,
                isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'RAM Load',
                '${(Get.find<DeviceInfoService>().totalRamGB.value - Get.find<DeviceInfoService>().availableRamGB.value).toStringAsFixed(1)} GB',
                LucideIcons.cpu,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSavingsCard(isDark),
      ],
    );
  }

  Widget _buildSavingsCard(bool isDark) {
    return Obx(() {
      final bytes = _settings.browserTotalDataSaved.value;
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Dt.borderColor(isDark)),
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.green.withValues(alpha: 0.1), Colors.transparent]
                : [Colors.green.withValues(alpha: 0.05), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.zap, color: Colors.green, size: 24),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$mb MB SAVED',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Data & Tracker protection active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatCard(String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Dt.accent),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLink(
      String name, String url, IconData icon, bool isDark,
      {VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: () => _go(url),
      onLongPress: onLongPress,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Dt.cardDark : Dt.card,
              shape: BoxShape.circle,
              border: Border.all(color: Dt.borderColor(isDark)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: Dt.accent),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddShortcutTile(bool isDark) {
    return GestureDetector(
      onTap: () => _showAddShortcutDialog(isDark),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Dt.cardDark : Dt.card,
              shape: BoxShape.circle,
              border: Border.all(color: Dt.borderColor(isDark), style: BorderStyle.none),
              // Use a dashed border or just a plus icon
            ),
            child: Icon(LucideIcons.plus,
                size: 24, color: Dt.accent.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          Text(
            'Add',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddShortcutDialog(bool isDark) {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Add Shortcut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'URL (https://...)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              var url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              if (!url.contains('://')) url = 'https://$url';
              _settings.addBrowserSpeedDialItem(titleCtrl.text, url);
              Get.back();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
