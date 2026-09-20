/// System prompt, asset browser, brand identity, voice, scrolling.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _showSystemPromptSheet(), _showAssetBrowser(), _showBrandIdentitySheet(), _scrollToBottom()
///   _toggleVoice()
part of 'agent_ide_view.dart';

extension _AgentIdeSheets on _AgentIdeViewState {
  void _showSystemPromptSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController(text: c.brandIdentity['systemPrompt'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('builder_edit_instructions'.tr, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'e.g. You are a senior React developer focused on performance...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Dt.accent),
                onPressed: () {
                  c.brandIdentity['systemPrompt'] = ctrl.text.trim();
                  Get.back();
                  AppSnackbar.showTop('Settings Saved', 'AI personality updated for this project.');
                },
                child: Text('common_save'.tr),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }



  void _showAssetBrowser(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        title: Text('builder_project_gallery'.tr),
        content: SizedBox(
          width: 600,
          height: 400,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(LucideIcons.sparkles), text: 'Icons'),
                    Tab(icon: Icon(LucideIcons.type), text: 'Fonts'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Icons Grid
                      GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: AssetsData.lucideIcons.length,
                        itemBuilder: (context, i) {
                          final name = AssetsData.lucideIcons[i];
                          return InkWell(
                            onTap: () {
                              _askCtrl.text += ' icon:$name ';
                              Get.back();
                              _askFocus.requestFocus();
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.sparkles, size: 20),
                                const SizedBox(height: 4),
                                Text(name, style: const TextStyle(fontSize: 8), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          );
                        },
                      ),
                      // Fonts List
                      ListView.builder(
                        itemCount: AssetsData.googleFonts.length,
                        itemBuilder: (context, i) {
                          final name = AssetsData.googleFonts[i];
                          return ListTile(
                            title: Text(name, style: GoogleFonts.getFont(name)),
                            onTap: () {
                              _askCtrl.text += ' font:$name ';
                              Get.back();
                              _askFocus.requestFocus();
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBrandIdentitySheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCtrl = TextEditingController(text: c.brandIdentity['primaryColor'] ?? '#3B82F6');
    final fontCtrl = TextEditingController(text: c.brandIdentity['font'] ?? 'Inter');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brand Identity', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Define your brand styles to keep the AI consistent.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            TextField(
              controller: primaryCtrl,
              decoration: const InputDecoration(
                labelText: 'Primary Color (Hex or Name)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fontCtrl,
              decoration: const InputDecoration(
                labelText: 'Global Font Family',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Dt.accent),
                onPressed: () {
                  c.brandIdentity['primaryColor'] = primaryCtrl.text.trim();
                  c.brandIdentity['font'] = fontCtrl.text.trim();
                  Get.back();
                  AppSnackbar.showTop('Brand Updated', 'AI will now follow these styles.');
                },
                child: const Text('Save Brand'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }


  void _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      _refresh(() => _isListening = false);
    } else {
      final available = await _speech.initialize();
      if (available) {
        _refresh(() => _isListening = true);
        _speech.listen(onResult: (result) {
          _refresh(() {
            _askCtrl.text = result.recognizedWords;
            if (result.finalResult) {
              _isListening = false;
            }
          });
        });
      } else {
        AppSnackbar.showTop('Error', 'Speech recognition unavailable');
      }
    }
  }

}
