/// Mention overlay: detection, picker, insertion.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _checkMentions(), _showMentionOverlay(), _insertMention(), _hideMentionOverlay()
part of 'agent_ide_view.dart';

extension _AgentIdeMentions on _AgentIdeViewState {
  void _checkMentions() {
    final text = _askCtrl.text;
    final selection = _askCtrl.selection;
    if (selection.baseOffset <= 0) {
      _hideMentionOverlay();
      return;
    }

    final before = text.substring(0, selection.baseOffset);
    if (before.endsWith('@')) {
      _showMentionOverlay('file');
    } else if (before.endsWith('#')) {
      _showMentionOverlay('icon');
    } else if (before.endsWith(r'$')) {
      _showMentionOverlay('font');
    } else if (!before.contains('@') && !before.contains('#') && !before.contains(r'$')) {
      _hideMentionOverlay();
    }
  }

  void _showMentionOverlay(String type) async {
    _hideMentionOverlay();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    List<Widget> items = [];
    String title = 'REFERENCE';

    if (type == 'file') {
      title = 'REFERENCE FILE OR SYMBOL';
      final files = c.files.toList();
      final symbols = await c.scanProjectSymbols();
      items = [
        ...files.map((f) => ListTile(
          dense: true,
          leading: Icon(_iconFor(f), size: 14, color: Dt.accent),
          title: Text(f, style: const TextStyle(fontSize: 12)),
          onTap: () => _insertMention(f, '@'),
        )),
        ...symbols.map((s) => ListTile(
          dense: true,
          leading: Icon(s['type'] == 'component' ? LucideIcons.component : LucideIcons.functionSquare, size: 14, color: Colors.blueAccent),
          title: Text(s['name'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          subtitle: Text('${s['file']} (L${s['line']})', style: const TextStyle(fontSize: 10)),
          onTap: () => _insertMention(s['name'] ?? '', '@'),
        )),
      ];
    } else if (type == 'icon') {
      title = 'LUCIDE ICONS';
      items = AssetsData.lucideIcons.map((icon) => ListTile(
        dense: true,
        leading: const Icon(LucideIcons.sparkles, size: 14, color: Colors.amber),
        title: Text(icon, style: const TextStyle(fontSize: 12)),
        onTap: () => _insertMention(icon, '#'),
      )).toList();
    } else if (type == 'font') {
      title = 'GOOGLE FONTS';
      items = AssetsData.googleFonts.map((font) => ListTile(
        dense: true,
        leading: const Icon(LucideIcons.type, size: 14, color: Colors.teal),
        title: Text(font, style: GoogleFonts.getFont(font, fontSize: 12)),
        onTap: () => _insertMention(font, r'$'),
      )).toList();
    }

    if (!mounted || items.isEmpty) return;

    _mentionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: _askLayer,
          showWhenUnlinked: false,
          offset: const Offset(0, -220),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white10 : Dt.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: items,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_mentionOverlay!);
  }

  void _insertMention(String value, String trigger) {
    final text = _askCtrl.text;
    final selection = _askCtrl.selection;
    final before = text.substring(0, selection.baseOffset);
    final after = text.substring(selection.baseOffset);
    
    // Prefix for context inject
    String prefix = '';
    if (trigger == '#') prefix = 'icon:';
    if (trigger == r'$') prefix = 'font:';

    final newText = before.substring(0, before.length - 1) + prefix + value + after;
    _askCtrl.text = newText;
    _askCtrl.selection = TextSelection.collapsed(offset: before.length - 1 + prefix.length + value.length);
    _hideMentionOverlay();
  }

  void _hideMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
  }
}
