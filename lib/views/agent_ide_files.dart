/// Files pane, tree, console, editor, and file helpers.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _tabBar(), _filesPane(), _buildFileTree(), _renderTree(), _consolePane(), _logColor()
///   _fileSkeleton(), _iconFor(), _allFilePaths(), _fileEditor()
part of 'agent_ide_view.dart';

extension _AgentIdeFiles on _AgentIdeViewState {
  Widget _tabBar(BuildContext context, bool isDark) {
    return Obx(() {
      if (_openTabs.isEmpty) return const SizedBox.shrink();
      return Container(
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16161E) : const Color(0xFFF3F4F6),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.white10 : Dt.hairline,
            ),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _openTabs.length,
          itemBuilder: (context, i) {
            final path = _openTabs[i];
            final active = path == _openFile;
            final name = path.split('/').last;

            return InkWell(
              onTap: () => _refresh(() => _openFile = path),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active
                      ? (isDark ? AppColors.surface : Colors.white)
                      : Colors.transparent,
                  border: Border(
                    right: BorderSide(color: isDark ? Colors.white10 : Dt.hairline),
                    bottom: BorderSide(
                      color: active ? Dt.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconFor(path), size: 14, color: active ? Dt.accent : Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? (isDark ? Colors.white : Colors.black87)
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        _openTabs.removeAt(i);
                        if (active) {
                          _refresh(() => _openFile = _openTabs.isNotEmpty ? _openTabs.last : null);
                        }
                      },
                      child: Icon(LucideIcons.x,
                          size: 12, color: active ? Dt.accent : Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _filesPane(BuildContext context, bool isDark) {
    if (c.project.value == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Build a project above — its files will land here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.5, color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return Obx(() {
      final paths = _allFilePaths();
      final root = _buildFileTree(paths);
      final extra =
          c.streamingFiles.keys.where((k) => !c.files.contains(k)).length;
      final total = c.files.length + extra;

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  extra > 0 ? '$total files ($extra writing…)' : '$total files',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).hintColor)),
            ),
            TextButton.icon(
              onPressed: () => _showGlobalSearch(context, isDark),
              icon: const Icon(LucideIcons.search, size: 15),
              label: const Text('Search Content'),
            ),
            TextButton.icon(
              onPressed: () => _showAssetGenDialog(context, isDark),
              icon: const Icon(LucideIcons.sparkles, size: 15),
              label: const Text('Gen Asset'),
            ),
            TextButton.icon(
              onPressed: () => showAddDialog(context, isDark,
                  onPickFile: (p) => _openFileTab(p ?? '')),
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('Add'),
            ),
          ]),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search in code…',
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onSubmitted: (q) => showSearchResults(context, isDark, q,
                onPickFile: (p) => _openFileTab(p ?? '')),
          ),
          const SizedBox(height: 12),
          if (c.generating.value && paths.isEmpty)
            ...List.generate(5, (i) => _fileSkeleton(isDark))
          else
            ..._renderTree(context, isDark, root.children, 0),
          if (_openTabs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _tabBar(context, isDark),
            if (_openFile != null) _fileEditor(context, isDark, _openFile!),
          ],
        ],
      );
    });
  }

  FileNode _buildFileTree(List<String> paths) {
    final root = FileNode(name: '', path: '', isDir: true, children: []);
    for (final path in paths) {
      final parts = path.split('/');
      FileNode current = root;
      String currentPath = '';
      for (int i = 0; i < parts.length; i++) {
        final name = parts[i];
        currentPath = currentPath.isEmpty ? name : '$currentPath/$name';
        final isLast = i == parts.length - 1;
        var existing = current.children.firstWhereOrNull((n) => n.name == name);
        if (existing == null) {
          existing = FileNode(
            name: name,
            path: currentPath,
            isDir: !isLast,
            children: [],
          );
          current.children.add(existing);
          current.children.sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        }
        current = existing;
      }
    }
    return root;
  }

  List<Widget> _renderTree(
      BuildContext context, bool isDark, List<FileNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      final isExpanded = _expandedFolders.contains(node.path);
      final isWriting = c.streamingFiles.containsKey(node.path);

      items.add(
        InkWell(
          onTap: () {
            if (node.isDir) {
              if (isExpanded) {
                _expandedFolders.remove(node.path);
              } else {
                _expandedFolders.add(node.path);
              }
            } else {
              _openFileTab(node.path);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: depth > 0
                            ? Theme.of(context).dividerColor.withValues(alpha: 0.1)
                            : Colors.transparent,
                        width: 1)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    node.isDir
                        ? (isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight)
                        : _iconFor(node.path),
                    size: node.isDir ? 14 : 16,
                    color: node.isDir ? Theme.of(context).hintColor : Dt.accent,
                  ),
                  const SizedBox(width: 8),
                  if (node.isDir)
                    const Icon(LucideIcons.folder, size: 16, color: Color(0xFFF59E0B)),
                  if (node.isDir) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: node.isDir ? FontWeight.w600 : FontWeight.w400,
                        color: node.path == _openFile ? Dt.accent : (isDark ? AppColors.textPrimary : Dt.textPrimary),
                      ),
                    ),
                  ),
                  if (isWriting)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Dt.accent,
                      ),
                    ),
                  if (!node.isDir)
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.moreVertical, size: 14),
                      onSelected: (v) async {
                        if (v == 'delete') {
                          final ok = await Get.dialog<bool>(AlertDialog(
                            title: const Text('Delete file?'),
                            content: Text('"${node.path}" will be removed.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Get.back(result: false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error),
                                onPressed: () => Get.back(result: true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ));
                          if (ok != true) return;
                          final ws = Get.find<AgentWorkspaceService>();
                          await ws.deleteFile(c.project.value!.id, node.path);
                          if (_openFile == node.path) {
                            _refresh(() => _openFile = null);
                          }
                          await c.notifyFilesChanged();
                        } else if (v == 'rename') {
                          showRenameDialog(context, isDark, node.path,
                              openFile: _openFile,
                              onPickFile: (p) => _openFileTab(p ?? ''));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename', style: TextStyle(fontSize: 14))),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(
                                    fontSize: 14, color: AppColors.error))),
                      ],
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      );

      if (node.isDir && isExpanded) {
        items.addAll(_renderTree(context, isDark, node.children, depth + 1));
      }
    }
    return items;
  }

  Widget _consolePane(BuildContext context, bool isDark) {
    return Obx(() {
      if (c.consoleBuffer.isEmpty) {
        return Center(
          child: Text('No logs captured yet.', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: c.consoleBuffer.length,
        itemBuilder: (context, i) {
          final log = c.consoleBuffer[i];
          final level = log['level'].toString().toLowerCase();
          final color = _logColor(level);
          final isError = level == 'error';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[$level]',
                  style: GoogleFonts.firaCode(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    log['message'],
                    style: GoogleFonts.firaCode(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                if (isError)
                  Tooltip(
                    message: 'Fix this error with AI',
                    child: InkWell(
                      onTap: () {
                        c.consoleError.value = log['message'];
                        c.repairFromError();
                      },
                      child: const Icon(LucideIcons.sparkles, size: 14, color: Dt.accent),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    });
  }

  Color _logColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.redAccent;
      case 'warning':
        return Colors.orangeAccent;
      case 'debug':
        return Colors.blueAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _fileSkeleton(bool isDark) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black12, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Container(width: 120, height: 12, decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black12, borderRadius: BorderRadius.circular(4))),
        ],
      ),
    );
  }

  IconData _iconFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html') || p.endsWith('.htm')) {
      return LucideIcons.globe;
    }
    if (p.endsWith('.css')) return LucideIcons.palette;
    if (p.endsWith('.js') || p.endsWith('.jsx') || p.endsWith('.ts')) {
      return LucideIcons.fileCode2;
    }
    if (p.endsWith('.json')) return LucideIcons.braces;
    if (p.endsWith('.md')) return LucideIcons.fileText;
    if (p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.svg')) {
      return LucideIcons.image;
    }
    return LucideIcons.file;
  }

  List<String> _allFilePaths() {
    final out = [...c.files];
    for (final k in c.streamingFiles.keys) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  Widget _fileEditor(BuildContext context, bool isDark, String path) {
    if (c.streamingActive.value && c.streamingFiles.containsKey(path)) {
      return StreamingFileCard(path: path, isDark: isDark);
    }
    return FutureBuilder<String?>(
      key: ValueKey('editor-$path-${c.revision.value}'),
      future: c.readFile(path),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return FileEditorCard(
          key: ValueKey('card-$path'),
          path: path,
          initial: snap.data ?? '',
          isDark: isDark,
        );
      },
    );
  }
}

