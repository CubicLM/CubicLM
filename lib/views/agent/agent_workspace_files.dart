/// Agent Workspace — Files tab: project tree, viewer, changed-file diffs.
///
/// OpenCode/Claude-Code parity for working with an imported project:
/// hierarchical tree (jail-safe relative paths), read-only viewer with
/// line numbers + rename/delete, and the per-file accept/undo diff cards
/// backed by the run checkpoint.
part of 'agent_workspace_view.dart';

/// One node of the project file tree.
class WsFileNode {
  final String name;
  final String path;
  final bool isDir;
  final List<WsFileNode> children = [];

  WsFileNode({required this.name, required this.path, required this.isDir});
}

extension _AgentWorkspaceFiles on _AgentWorkspaceViewState {
  Widget _filesPane(BuildContext context, bool isDark) {
    if (controller.projectId.value == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Import a folder (sidebar on desktop, Project card above on mobile) —\nits files will appear here and the agent will be jailed to it.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.6, color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return Obx(() {
      final root = _buildWsTree(controller.files.toList());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 280,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                          children: [
                            _filesHeader(context),
                            ..._renderWsTree(
                                context, isDark, root.children, 0),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Dt.hairline),
                      Expanded(child: _fileViewerPane(context, isDark)),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    children: [
                      _filesHeader(context),
                      ..._renderWsTree(
                          context, isDark, root.children, 0),
                      if (_openFile != null) ...[
                        const SizedBox(height: 12),
                        _fileViewerCard(context, isDark, _openFile!),
                      ],
                      const SizedBox(height: 16),
                      _changedFilesPane(context, isDark),
                    ],
                  ),
          ),
          if (isWide) _changedFilesPane(context, isDark),
        ],
      );
    });
  }

  Widget _filesHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${controller.files.length} files',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).hintColor),
      ),
    );
  }

  WsFileNode _buildWsTree(List<String> paths) {
    final root = WsFileNode(name: '', path: '', isDir: true);
    for (final path in paths) {
      final parts = path.split('/');
      WsFileNode current = root;
      var currentPath = '';
      for (var i = 0; i < parts.length; i++) {
        final name = parts[i];
        currentPath =
            currentPath.isEmpty ? name : '$currentPath/$name';
        final isLast = i == parts.length - 1;
        var existing = current.children
            .firstWhereOrNull((n) => n.name == name);
        if (existing == null) {
          existing = WsFileNode(
              name: name,
              path: currentPath,
              isDir: !isLast);
          current.children.add(existing);
          current.children.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name
                .toLowerCase()
                .compareTo(b.name.toLowerCase());
          });
        }
        current = existing;
      }
    }
    return root;
  }

  List<Widget> _renderWsTree(BuildContext context, bool isDark,
      List<WsFileNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      final isExpanded = _expandedFolders.contains(node.path);
      final changed = controller.changedFiles.contains(node.path);
      items.add(InkWell(
        onTap: () {
          if (node.isDir) {
            isExpanded
                ? _expandedFolders.remove(node.path)
                : _expandedFolders.add(node.path);
          } else {
            controller.openProjectFile(node.path);
            _openFile = node.path;
            if (!isWide) _tabs.animateTo(1);
            _refresh(() {});
          }
        },
        child: Container(
          height: 34,
          padding: EdgeInsets.only(left: depth * 14.0),
          child: Row(
            children: [
              Icon(
                node.isDir
                    ? (isExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight)
                    : _fileIconFor(node.path),
                size: node.isDir ? 14 : 15,
                color: node.isDir
                    ? Theme.of(context).hintColor
                    : Dt.accent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              if (node.isDir)
                const Icon(LucideIcons.folder,
                    size: 14, color: Color(0xFFF59E0B)),
              if (node.isDir) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaCode(
                    fontSize: 11.5,
                    color: node.path == (_openFile ?? controller.openFile.value)
                        ? Dt.accent
                        : (changed ? Colors.green : null),
                  ),
                ),
              ),
              if (changed)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.green),
                ),
              if (!node.isDir)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.moreVertical, size: 13),
                  onSelected: (v) async {
                    if (v == 'mention') {
                      controller.insertMention(node.path);
                    } else if (v == 'rename') {
                      _renameDialog(context, node.path);
                    } else if (v == 'delete') {
                      _deleteDialog(context, node.path);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'mention',
                        child: Text('Mention in prompt',
                            style: TextStyle(fontSize: 13))),
                    PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename',
                            style: TextStyle(fontSize: 13))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(
                                fontSize: 13, color: Colors.red))),
                  ],
                ),
            ],
          ),
        ),
      ));
      if (node.isDir && isExpanded) {
        items.addAll(
            _renderWsTree(context, isDark, node.children, depth + 1));
      }
    }
    return items;
  }

  Future<void> _deleteDialog(BuildContext context, String path) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      title: const Text('Delete file?'),
      content: Text('"$path" will be removed.'),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel')),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Get.back(result: true),
          child: const Text('Delete'),
        ),
      ],
    ));
    if (ok != true) return;
    final pid = controller.projectId.value;
    if (pid == null) return;
    await Get.find<AgentWorkspaceService>().deleteFile(pid, path);
    if (_openFile == path || controller.openFile.value == path) {
      controller.openFile.value = null;
      _openFile = null;
    }
    await controller.refreshFiles();
    _refresh(() {});
  }

  Future<void> _renameDialog(BuildContext context, String oldPath) async {
    final ctrl = TextEditingController(text: oldPath);
    final newPath = await Get.dialog<String>(AlertDialog(
      title: const Text('Rename file'),
      content: TextField(
        controller: ctrl,
        style: GoogleFonts.firaCode(fontSize: 12),
        decoration: const InputDecoration(hintText: 'relative/path'),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Get.back(result: ctrl.text.trim()),
            child: const Text('Rename')),
      ],
    ));
    if (newPath == null || newPath.isEmpty || newPath == oldPath) return;
    final pid = controller.projectId.value;
    if (pid == null) return;
    await Get.find<AgentWorkspaceService>()
        .renameFile(pid, oldPath, newPath);
    if (_openFile == oldPath) _openFile = newPath;
    await controller.refreshFiles();
    _refresh(() {});
  }

  // ── Viewer ───────────────────────────────────────────────────────

  Widget _fileViewerPane(BuildContext context, bool isDark) {
    return Obx(() {
      final path = controller.openFile.value ?? _openFile;
      if (path == null) {
        return Center(
          child: Text('Select a file to view it.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: Theme.of(context).hintColor)),
        );
      }
      return _fileViewerCard(context, isDark, path);
    });
  }

  Widget _fileViewerCard(
      BuildContext context, bool isDark, String path) {
    final pid = controller.projectId.value;
    final ws = Get.isRegistered<AgentWorkspaceService>()
        ? Get.find<AgentWorkspaceService>()
        : null;
    return FutureBuilder<({String text, bool truncated})>(
      key: ValueKey('viewer-$path-$pid'),
      future: (pid == null || ws == null)
          ? Future.value((text: '', truncated: false))
          : ws.readFilePreview(pid, path),
      builder: (context, snap) {
        final rec = snap.data;
        if (snap.connectionState != ConnectionState.done || rec == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
      return Container(
        margin: EdgeInsets.all(isWide ? 12 : 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111116) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF7F7FA),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Row(
                children: [
                  Icon(_fileIconFor(path),
                      size: 14, color: Theme.of(context).hintColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(fontSize: 11.5),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(LucideIcons.atSign, size: 13),
                    label: const Text('Mention',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.insertMention(path),
                  ),
                  if (rec.truncated)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('truncated',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: AppColors.warning)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _numberedCode(context, rec.text, isDark),
              ),
            ),
          ],
        ),
      );
      }
    );
  }

  Widget _numberedCode(BuildContext context, String text, bool isDark) {
    final lines = text.split('\n');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 1; i <= lines.length; i++)
                Text('$i',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.firaCode(
                        fontSize: 11,
                        height: 1.5,
                        color:
                            Theme.of(context).hintColor.withValues(alpha: 0.5))),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            text,
            style: GoogleFonts.firaCode(
                fontSize: 11.5,
                height: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF1F2430)),
          ),
        ),
      ],
    );
  }

  // ── Changed files (diff + accept/undo) ───────────────────────────

  Widget _changedFilesPane(BuildContext context, bool isDark) {
    return Obx(() {
      final files = controller.changedFiles.toList();
      final cpId = controller.checkpointId.value;
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.fileDiff, size: 15, color: Dt.accent),
                const SizedBox(width: 8),
                Text('Changed files',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [
                    if (files.isNotEmpty)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0)),
                        onPressed: controller.running.value
                            ? null
                            : () => controller.undoAll(),
                        child: const Text('Undo all',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    if (files.isNotEmpty)
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Dt.accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0)),
                        onPressed: controller.running.value
                            ? null
                            : () => controller.acceptAll(),
                        child: const Text('Accept all',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    if (cpId != null)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0)),
                        onPressed: controller.running.value
                            ? null
                            : () => controller.rollbackCheckpoint(),
                        child: const Text('Rollback',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (files.isEmpty && cpId == null)
              Text('No changes yet.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context).hintColor))
            else if (files.isEmpty)
              Text('Working tree matches the checkpoint baseline.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context).hintColor)),
            for (final f in files) _diffFileCard(context, f, isDark),
          ],
        ),
      );
    });
  }

  Widget _diffFileCard(BuildContext context, String filePath, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<List<DiffLine>>(
            key: ValueKey('diff-$filePath-${controller.changedFiles.length}'),
            future: _computeDiff(controller, filePath),
            builder: (_, snap) {
              final diffLines = snap.data;
              if (diffLines == null || diffLines.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(_fileIconFor(filePath),
                          size: 14, color: Theme.of(context).hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(filePath,
                            style: GoogleFonts.firaCode(fontSize: 11.5)),
                      ),
                    ],
                  ),
                );
              }
              return DiffViewer(filePath: filePath, lines: diffLines);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.undoFile(filePath),
                child: const Text('Undo', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.acceptFile(filePath),
                child: const Text('Accept', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<List<DiffLine>> _computeDiff(
      AgentRunnerController c, String filePath) async {
    try {
      final ws = Get.find<AgentWorkspaceService>();
      final cpId = c.checkpointId.value;
      final pid = c.projectId.value;
      if (cpId == null || pid == null) return const [];
      final oldBytes = await ws.readCheckpointFile(pid, cpId, filePath);
      final oldContent =
          oldBytes != null ? String.fromCharCodes(oldBytes) : '';
      final newContent = await ws.readFile(pid, filePath) ?? '';
      return buildDiffLines(oldContent, newContent);
    } catch (_) {
      return const [];
    }
  }
}

/// Icon for a file path (heuristic by extension).
IconData _fileIconFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.html') || p.endsWith('.htm')) return LucideIcons.globe;
  if (p.endsWith('.css')) return LucideIcons.palette;
  if (p.endsWith('.js') ||
      p.endsWith('.mjs') ||
      p.endsWith('.jsx') ||
      p.endsWith('.ts') ||
      p.endsWith('.tsx')) {
    return LucideIcons.fileCode2;
  }
  if (p.endsWith('.dart')) return LucideIcons.fileCode;
  if (p.endsWith('.json')) return LucideIcons.braces;
  if (p.endsWith('.yaml') || p.endsWith('.yml')) return LucideIcons.settings2;
  if (p.endsWith('.md')) return LucideIcons.fileText;
  if (p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.svg')) {
    return LucideIcons.image;
  }
  if (p.endsWith('.php')) return LucideIcons.fileCode2;
  if (p.endsWith('.c') || p.endsWith('.cpp') || p.endsWith('.h')) {
    return LucideIcons.fileCode;
  }
  if (p.endsWith('.py')) return LucideIcons.fileCode;
  if (p.endsWith('.sh')) return LucideIcons.terminal;
  return LucideIcons.file;
}
