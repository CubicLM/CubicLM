/// Bottom meter, command palette, ask-bar send, error labels.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _bottomMeter(), _meterItem(), _showCommandPalette(), _sendFromAskBar(), _newProjectReset()
///   _friendlyError(), _pickedLabel()
part of 'agent_ide_view.dart';

extension _AgentIdeCommand on _AgentIdeViewState {
  Widget _bottomMeter(BuildContext context, bool isDark) {
    return Obx(() {
      final hasP = c.project.value != null;
      if (!hasP) return const SizedBox.shrink();

      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.02),
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Dt.hairline)),
        ),
        child: Row(
          children: [
            _meterItem(LucideIcons.coins, '${c.totalTokensUsed.value} tokens', 'Total tokens used'),
            const SizedBox(width: 16),
            _meterItem(LucideIcons.hardDrive, '${c.projectSizeKb.value.toStringAsFixed(1)} KB', 'Project size'),
            const Spacer(),
            if (c.lastRequestTokens.value > 0)
              _meterItem(LucideIcons.zap, '+${c.lastRequestTokens.value}', 'Last request tokens'),
          ],
        ),
      );
    });
  }

  Widget _meterItem(IconData icon, String label, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
        ],
      ),
    );
  }



  void _showCommandPalette(BuildContext context, bool isDark) {
    final commands = [
            {'icon': LucideIcons.plus, 'name': 'New Project', 'action': () => _newProjectReset()},
            {'icon': LucideIcons.search, 'name': 'Global Search', 'action': () => _showGlobalSearch(context, isDark)},
            {'icon': LucideIcons.image, 'name': 'Asset Browser', 'action': () => _showAssetBrowser(context, isDark)},
            {'icon': LucideIcons.gitCompare, 'name': 'Review Changes', 'action': () => c.reviewingChanges.value = true},
            {'icon': LucideIcons.history, 'name': 'Project History', 'action': () => showHistorySheet(context)},
            {'icon': LucideIcons.eye, 'name': 'Switch to Preview', 'action': () => _refresh(() => _tab = 'preview')},
            {'icon': LucideIcons.fileCode, 'name': 'Switch to Code', 'action': () => _refresh(() => _tab = 'files')},
            {'icon': LucideIcons.terminal, 'name': 'Switch to Console', 'action': () => _refresh(() => _tab = 'console')},
            {'icon': LucideIcons.layoutGrid, 'name': 'Switch to Grid', 'action': () => _refresh(() => _tab = 'grid')},
            {'icon': LucideIcons.gitBranch, 'name': 'Switch to Mind Map', 'action': () => _refresh(() => _tab = 'graph')},
          ];

    Get.dialog(
      Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 400,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Type a command...',
                      prefixIcon: Icon(LucideIcons.terminal, size: 18),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: commands.length,
                    itemBuilder: (context, i) {
                      final cmd = commands[i] as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        leading: Icon(cmd['icon'] as IconData, size: 16),
                        title: Text(cmd['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () {
                          Get.back();
                          (cmd['action'] as VoidCallback)();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendFromAskBar() {
    if (c.generating.value || c.fixing.value) {
      c.cancelWork();
      return;
    }
    if (_askCtrl.text.trim().isEmpty && c.attachedImage.value == null) return;
    final text = _askCtrl.text.trim();
    final hasImg = c.attachedImage.value != null;
    c.topic.value =
        text.isEmpty && hasImg ? 'Build from this screenshot' : text;
    _askCtrl.clear();
    final hasProject = c.project.value != null;
    if (hasProject) {
      c.modifyProject();
    } else {
      c.newProject();
    }
  }

  void _newProjectReset() {
    c.project.value = null;
    c.files.clear();
    c.previewUrl.value = null;
    c.transcript.clear();
    c.buildSteps.clear();
    _promptCtrl.clear();
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('too many requests')) {
      return 'Rate limited — wait a moment and try again.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Request timed out — check your connection and try again.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return 'Network error — check your internet connection.';
    }
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden')) {
      return 'API key issue — check your provider settings.';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503')) {
      return 'Server error — the AI provider is temporarily unavailable.';
    }
    if (lower.contains('no local model loaded')) {
      return 'No model loaded — load one in Explore → Local, or switch to Cloud mode.';
    }
    if (lower.contains('model returned nothing')) {
      return 'The AI returned an empty response — try rephrasing your request.';
    }
    if (lower.contains('quota') || lower.contains('insufficient')) {
      return 'Out of credits — check your API provider balance.';
    }
    return raw;
  }

  String _pickedLabel(String info) {
    try {
      final m = jsonDecode(info) as Map<String, dynamic>;
      var tag = (m['tag'] ?? '').toString();
      var text = (m['text'] ?? '').toString().replaceAll('\n', ' ').trim();
      if (text.length > 24) text = '${text.substring(0, 24)}…';
      if (tag.isEmpty && text.isEmpty) return 'Element picked';
      if (tag.isEmpty) return text;
      if (text.isEmpty) return '<$tag> picked';
      return '<$tag> · $text';
    } catch (_) {
      return 'Element picked';
    }
  }
}
