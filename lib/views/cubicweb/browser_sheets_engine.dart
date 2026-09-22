/// Search engine sheet, add-engine dialog, time-ago.
///
/// Split from `browser_sheets.dart` (part of `browser_view.dart`) - behavior is unchanged.
/// Contains: _showEngineSheet(), _showAddEngineDialog(), _ago()
part of 'browser_view.dart';

extension _BrowserSheetsEngine on _BrowserViewState {
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
