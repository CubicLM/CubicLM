/// Preview, dev-tools, terminal, and status panes.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _previewPane(), _devToolsPane(), _devTabBtn(), _terminalPane(), _buildStatusView()
part of 'agent_ide_view.dart';

extension _AgentIdePanes on _AgentIdeViewState {
  Widget _previewPane(BuildContext context, bool isDark, int revision) {
    final status = c.buildStatus.value;
    final working = c.generating.value || c.fixing.value || status != null;
    final live = c.streamingActive.value && c.livePreviewReady.value;

    if (working && !live) {
      return _buildStatusView(context, isDark, status);
    }
    final url = c.previewUrl.value;
    if (url == null || url.isEmpty) {
      return Center(
        child: Text('Preview unavailable.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Theme.of(context).hintColor)),
      );
    }
    // On short screens the fixed children (diagnosis card + 240px devtools)
    // can squeeze AgentPreview's Expanded below its 40px header → the
    // logged 39px bottom overflow. Scale devtools with available height so
    // the preview keeps room; AgentPreview itself guards <120px.
    return LayoutBuilder(builder: (context, constraints) {
      final devH = constraints.maxHeight.isFinite
          ? (constraints.maxHeight * 0.32).clamp(110.0, 240.0)
          : 240.0;
      return Column(children: [
        _previewDiagnosisCard(context, isDark),
        if (working) _liveProgressPill(context, isDark, status),
        Expanded(
          child: AgentPreview(
            url: url,
            pickMode: c.elementPickMode.value,
            onConsoleError: (e) => c.onConsoleError(e),
            onElementPicked: (info) => c.onElementPicked(info),
          ),
        ),
        _devToolsPane(context, isDark, height: devH),
      ]);
    });
  }

  Widget _devToolsPane(BuildContext context, bool isDark, {double height = 240}) {
    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Dt.hairline),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          // DevTools Header/Tabs
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                _devTabBtn('console', LucideIcons.terminal, 'Console'),
                _devTabBtn('terminal', LucideIcons.command, 'Terminal'),
                const Spacer(),
                if (_devTab == 'console')
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.grey),
                    onPressed: () => c.clearConsole(),
                  ),
                if (_devTab == 'terminal')
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.grey),
                    onPressed: () => c.clearTerminal(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _devTab == 'console' ? _consolePane(context, isDark) : _terminalPane(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _devTabBtn(String id, IconData icon, String label) {
    final active = _devTab == id;
    return InkWell(
      onTap: () => _refresh(() => _devTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? Dt.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: active ? Dt.accent : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _terminalPane(BuildContext context, bool isDark) {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            final lines = c.terminal.toList();
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                return Text(
                  lines[i],
                  style: GoogleFonts.firaCode(fontSize: 11, color: _termColor(lines[i])),
                );
              },
            );
          }),
        ),
        // Terminal Input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: const Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Obx(() {
                final symbol = c.activeCliId.value != null ? '›' : r'$';
                return Text(
                  symbol,
                  style: const TextStyle(color: Dt.accent, fontWeight: FontWeight.bold),
                );
              }),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _termCtrl,
                  style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white70),
                  decoration: const InputDecoration(
                    hintText: 'Type command or response...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      c.sendStdin(val);
                      _termCtrl.clear();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusView(BuildContext context, bool isDark, String? status) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Obx(() => c.attachedImage.value != null
            ? Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(LucideIcons.image, size: 13, color: Dt.accent),
                  const SizedBox(width: 6),
                  Text('Screenshot attached',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: Dt.accent)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => c.clearAttachment(),
                    child:
                        const Icon(LucideIcons.x, size: 12, color: Dt.accent),
                  ),
                ]),
              )
            : const SizedBox.shrink()),
        Row(children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(status ?? 'Working…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Obx(() => ListView.builder(
                itemCount: c.terminal.length > 12 ? 12 : c.terminal.length,
                itemBuilder: (_, i) {
                  final lines = c.terminal.toList();
                  final line =
                      lines[lines.length - (i < lines.length ? i + 1 : 1)];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 11, height: 1.5, color: _termColor(line)),
                    ),
                  );
                },
              )),
        ),
        Text('Output appears here when the structure is complete.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: const Color(0xFF8E8B85))),
      ]),
    );
  }
}
