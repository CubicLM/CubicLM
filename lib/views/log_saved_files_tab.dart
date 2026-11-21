/// Saved-files tab for the log viewer (all app exports on disk).
///
/// Shows every file the app generated or downloaded — any type — grouped
/// as a tree: folder (feature) → file type → files, each row showing the
/// folder path. Supports per-file view/share/swipe-delete plus multi
/// select (tap checkbox or long-press) with mark-all per folder, delete
/// and share of the selection.
library;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';

/// Live count of saved files (consumed by the LogView tab label).
final ValueNotifier<int> savedFilesCount = ValueNotifier<int>(0);

class LogSavedFilesTab extends StatefulWidget {
  final bool isDark;
  const LogSavedFilesTab({super.key, required this.isDark});

  @override
  State<LogSavedFilesTab> createState() => LogSavedFilesTabState();
}

class LogSavedFilesTabState extends State<LogSavedFilesTab> {
  List<ExportedFile> _files = [];
  bool _loading = true;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    ExportFile.savedVersion.addListener(_onSaved);
  }

  @override
  void dispose() {
    ExportFile.savedVersion.removeListener(_onSaved);
    super.dispose();
  }

  void _onSaved() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final files = await ExportFile.listAllFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
      _selected.removeWhere((p) => !files.any((f) => f.path == p));
    });
    savedFilesCount.value = files.length;
  }

  // ── Tree model ────────────────────────────────────────────────────

  /// folder → files (newest first).
  Map<String, List<ExportedFile>> get _grouped {
    final map = <String, List<ExportedFile>>{};
    for (final f in _files) {
      map.putIfAbsent(f.folderLabel, () => []).add(f);
    }
    return map;
  }

  static const _folderOrder = [
    'System Logs',
    'Chat Exports',
    'Slide Maker',
    'CubicWeb Builder',
    'CubicWeb Browser',
    'CubicApp Builder',
    'CubicDataSheet',
    'Agent Runs',
    'Backups',
  ];

  int _folderRank(String label) {
    final i = _folderOrder.indexOf(label);
    return i < 0 ? _folderOrder.length : i;
  }

  List<ExportedFile> get _selectedFiles =>
      _files.where((f) => _selected.contains(f.path)).toList();

  void _toggleSelect(ExportedFile f) {
    setState(() {
      if (_selected.contains(f.path)) {
        _selected.remove(f.path);
      } else {
        _selected.add(f.path);
      }
    });
  }

  void _selectFolder(String folder, List<ExportedFile> files) {
    final allIn = files.every((f) => _selected.contains(f.path));
    setState(() {
      for (final f in files) {
        if (allIn) {
          _selected.remove(f.path);
        } else {
          _selected.add(f.path);
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_files.isEmpty || _selected.length == _files.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_files.map((f) => f.path));
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────

  Future<void> _deleteFiles(List<ExportedFile> files) async {
    if (files.isEmpty) return;
    final label = files.length == 1 ? files.first.name : '${files.length} files';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(files.length == 1 ? 'Delete file?' : 'Delete ${files.length} files?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text('$label will be permanently removed from the device.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var done = 0;
    for (final f in files) {
      if (await ExportFile.deleteFile(f.path)) done++;
    }
    _selected.clear();
    await _load();
    AppSnackbar.showTop('Deleted', '$done of ${files.length} file(s)',
        icon: LucideIcons.trash2,
        duration: const Duration(seconds: 2),
        logHistory: false);
  }

  Future<void> _shareFiles(List<ExportedFile> files) async {
    if (files.isEmpty) return;
    if (files.length == 1) return _shareFile(files.first);
    // Multi-share: stage each file, then share the batch.
    var shared = 0;
    for (final f in files.take(10)) {
      try {
        final bytes = await ExportFile.readExportFile(f.path);
        if (bytes == null) continue;
        final ok = await ExportFile.shareBytes(bytes: bytes, fileName: f.name);
        if (ok) shared++;
      } catch (_) {}
    }
    if (shared == 0) {
      AppSnackbar.showTop('Share failed', 'Could not share the files.',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    } else {
      AppSnackbar.showTop('Shared', '$shared of ${files.length} file(s)',
          duration: const Duration(seconds: 2), logHistory: false);
    }
  }

  Future<void> _shareFile(ExportedFile f) async {
    try {
      final bytes = await ExportFile.readExportFile(f.path);
      if (bytes == null) {
        AppSnackbar.showTop('Share failed', 'Could not read file',
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
        return;
      }
      final ok = await ExportFile.shareBytes(bytes: bytes, fileName: f.name);
      if (!ok) {
        final saved = await ExportFile.saveToAppFolder(
          bytes: bytes,
          fileName: f.name,
          category: 'logs',
        );
        AppSnackbar.showTop(
            saved != null ? 'Share unavailable — saved instead' : 'Share failed',
            saved ?? 'Could not share ${f.name}',
            icon: LucideIcons.alertTriangle,
            type: saved != null ? 'success' : 'error',
            iconName: 'alert');
      }
    } catch (e) {
      AppSnackbar.showTop('Share failed', '$e',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    }
  }

  Future<void> _viewFile(ExportedFile f) async {
    try {
      final bytes = await ExportFile.readExportFile(f.path);
      if (!mounted) return;
      final isTexty = ['text', 'code', 'data', 'pdf'].contains(f.kind);
      if (bytes == null) {
        AppSnackbar.showTop('Open failed', 'Could not read ${f.name}',
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
        return;
      }
      if (f.kind == 'image') {
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
        return;
      }
      if (!isTexty) {
        // Binary/unknown types: share the file instead of rendering it.
        await _shareFile(f);
        return;
      }
      final text = String.fromCharCodes(bytes);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(f), size: 16, color: Dt.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(text,
                          style: GoogleFonts.firaCode(
                              fontSize: 11,
                              height: 1.5,
                              color: const Color(0xFFE2E8F0))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      AppSnackbar.showTop('Open failed', '$e',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.folderOpen,
                size: 40,
                color: Theme.of(context).hintColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No saved files yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Exports, downloads and generated files from every tool appear here with their folder paths',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).hintColor.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      );
    }
    final groups = _grouped;
    final folders = groups.keys.toList()
      ..sort((a, b) {
        final r = _folderRank(a).compareTo(_folderRank(b));
        return r != 0 ? r : a.toLowerCase().compareTo(b.toLowerCase());
      });
    final selecting = _selected.isNotEmpty;

    return Column(
      children: [
        _selectionBar(context, selecting),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: folders.length,
              itemBuilder: (context, fi) {
                final folder = folders[fi];
                final files = groups[folder]!;
                return _folderSection(context, folder, files);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectionBar(BuildContext context, bool selecting) {
    final totalBytes = _selectedFiles.fold<int>(0, (s, f) => s + f.sizeBytes);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _selectAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selected.length == _files.length && _files.isNotEmpty
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 16,
                    color: _selected.length == _files.length && _files.isNotEmpty
                        ? Dt.accent
                        : Theme.of(context).hintColor,
                  ),
                  const SizedBox(width: 6),
                  Text('Mark all',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (selecting) ...[
            Text('${_selected.length} · ${_fmtBytes(totalBytes)}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Dt.accent)),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Share selected',
              icon: Icon(LucideIcons.share2,
                  size: 18, color: Theme.of(context).hintColor),
              onPressed: () => _shareFiles(_selectedFiles),
            ),
            IconButton(
              tooltip: 'Delete selected',
              icon: const Icon(LucideIcons.trash2,
                  size: 18, color: AppColors.error),
              onPressed: () => _deleteFiles(_selectedFiles),
            ),
          ] else
            Text('${_files.length} files',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _folderSection(
      BuildContext context, String folder, List<ExportedFile> files) {
    final isDark = widget.isDark;
    final totalBytes = files.fold<int>(0, (s, f) => s + f.sizeBytes);
    final allIn = files.every((f) => _selected.contains(f.path));
    // Group by file kind inside the folder.
    final kinds = <String, List<ExportedFile>>{};
    for (final f in files) {
      kinds.putIfAbsent(f.kind, () => []).add(f);
    }
    final kindNames = kinds.keys.toList()
      ..sort((a, b) => kinds[b]!.length.compareTo(kinds[a]!.length));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Folder header (feature folder + path + select-all).
            InkWell(
              onTap: () => _selectFolder(folder, files),
              child: Container(
                padding: const EdgeInsets.all(12),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                child: Row(
                  children: [
                    Icon(
                      allIn ? Icons.check_box : Icons.folder_special_outlined,
                      size: 18,
                      color: allIn ? Dt.accent : Dt.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(folder.isEmpty ? 'CubicLM (root)' : folder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            '${ExportFile.exportLocationLabel()}/${folder.isEmpty ? '' : '$folder/'}'
                                .replaceAll('//', '/'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                                fontSize: 9.5,
                                color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                    Text('${files.length} · ${_fmtBytes(totalBytes)}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ),
            // Type groups → file rows.
            for (final kind in kindNames)
              ..._kindGroup(context, kind, kinds[kind]!),
          ],
        ),
      ),
    );
  }

  List<Widget> _kindGroup(
      BuildContext context, String kind, List<ExportedFile> files) {
    final rows = <Widget>[];
    rows.add(Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: [
          Icon(_iconForKind(kind), size: 12, color: _colorForKind(kind)),
          const SizedBox(width: 6),
          Text(_labelForKind(kind),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Theme.of(context).hintColor)),
          const SizedBox(width: 6),
          Text('${files.length}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, color: Theme.of(context).hintColor)),
        ],
      ),
    ));
    for (final f in files) {
      rows.add(_fileRow(context, f));
    }
    return rows;
  }

  Widget _fileRow(BuildContext context, ExportedFile f) {
    final selected = _selected.contains(f.path);
    return Dismissible(
      key: ValueKey(f.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error.withValues(alpha: 0.15),
        child: const Icon(LucideIcons.trash2, color: AppColors.error, size: 20),
      ),
      confirmDismiss: (_) async {
        await _deleteFiles([f]);
        return false; // selection dialog drives it; keep the row mounted
      },
      child: InkWell(
        onTap: () => _toggleSelect(f),
        onLongPress: () => _viewFile(f),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: selected ? Dt.accent : Theme.of(context).hintColor,
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _colorForKind(f.kind).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconFor(f), size: 15, color: _colorForKind(f.kind)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface)),
                    if (f.folderLabel.isNotEmpty)
                      Text(f.folderLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(
                              fontSize: 9,
                              color: Theme.of(context).hintColor
                                  .withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Text('${f.sizeLabel} · ${f.dateLabel}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                icon: Icon(_iconFor(f),
                    size: 15, color: Theme.of(context).hintColor),
                onPressed: () => _viewFile(f),
              ),
              IconButton(
                tooltip: 'Share',
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.share2,
                    size: 15, color: Theme.of(context).hintColor),
                onPressed: () => _shareFile(f),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Type helpers ──────────────────────────────────────────────────

  IconData _iconFor(ExportedFile f) => _iconForKind(f.kind);

  IconData _iconForKind(String kind) => switch (kind) {
        'pdf' => LucideIcons.fileText,
        'image' => LucideIcons.image,
        'video' => LucideIcons.video,
        'audio' => LucideIcons.music,
        'archive' => LucideIcons.folderArchive,
        'slides' => LucideIcons.presentation,
        'docs' => LucideIcons.fileType,
        'data' => LucideIcons.braces,
        'code' => LucideIcons.fileCode2,
        'text' => LucideIcons.fileText,
        _ => LucideIcons.file,
      };

  Color _colorForKind(String kind) => switch (kind) {
        'pdf' => const Color(0xFFEF4444),
        'image' => const Color(0xFF8B5CF6),
        'video' => const Color(0xFFEC4899),
        'audio' => const Color(0xFFF97316),
        'archive' => const Color(0xFFD97706),
        'slides' => const Color(0xFF0EA5E9),
        'docs' => const Color(0xFF3B82F6),
        'data' => const Color(0xFF14B8A6),
        'code' => const Color(0xFF6366F1),
        'text' => const Color(0xFF64748B),
        _ => const Color(0xFF94A3B8),
      };

  String _labelForKind(String kind) => switch (kind) {
        'pdf' => 'PDF',
        'image' => 'Images',
        'video' => 'Videos',
        'audio' => 'Audio',
        'archive' => 'Archives',
        'slides' => 'Slides',
        'docs' => 'Documents',
        'data' => 'Data',
        'code' => 'Code',
        'text' => 'Text & Logs',
        _ => 'Other',
      };

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
