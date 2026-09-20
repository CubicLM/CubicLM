/// Asset-gen and global-search dialogs plus file tabs.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _showAssetGenDialog(), _showGlobalSearch(), _openFileTab()
part of 'agent_ide_view.dart';

extension _AgentIdeDialogs on _AgentIdeViewState {
  void _showAssetGenDialog(BuildContext context, bool isDark) {
    final promptCtrl = TextEditingController();
    final pathCtrl = TextEditingController(text: 'assets/logo.png');

    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.sparkles, size: 20, color: Dt.accent),
            SizedBox(width: 10),
            Text('AI Asset Generation'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Generate a high-quality image asset directly into your project.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: promptCtrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g., A minimalist tech logo, 3D abstract hero image...',
                border: OutlineInputBorder(),
                labelText: 'Image Prompt',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(
                hintText: 'assets/image.png',
                border: OutlineInputBorder(),
                labelText: 'Save Path',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () {
              if (promptCtrl.text.trim().isNotEmpty) {
                Get.back();
                c.generateProjectAsset(promptCtrl.text.trim(), pathCtrl.text.trim());
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _showGlobalSearch(BuildContext context, bool isDark) {
    final searchCtrl = TextEditingController();
    final results = <Map<String, dynamic>>[].obs;
    final searching = false.obs;

    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.search, size: 20, color: Dt.accent),
            SizedBox(width: 10),
            Text('Global Project Search'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search for text in all files...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (q) async {
                  if (q.trim().isEmpty) return;
                  searching.value = true;
                  results.value = await c.searchProjectContent(q);
                  searching.value = false;
                },
              ),
              const SizedBox(height: 16),
              Obx(() {
                if (searching.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (results.isEmpty && searchCtrl.text.isNotEmpty) {
                  return const Text('No results found.');
                }
                return SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final r = results[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(_iconFor(r['path']), size: 14),
                        title: Text('${r['path']} (Line ${r['line']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        subtitle: Text(r['text'], maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.firaCode(fontSize: 10)),
                        onTap: () {
                          Get.back();
                          _openFileTab(r['path']);
                        },
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _openFileTab(String path) {
    if (!_openTabs.contains(path)) {
      _openTabs.add(path);
    }
    _refresh(() => _openFile = path);
  }
}
