/// Saved-files tab for the log viewer (exports on disk).
///
/// Split from `log_view.dart` - behavior is unchanged.
///
/// Contains: isDark, LogSavedFilesTab(), createState(), true, initState(), dispose(), _onSaved(), _load()
///   build(), _viewFile(), _shareFile()
library;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import 'package:lucide_icons/lucide_icons.dart';
class LogSavedFilesTab extends StatefulWidget {
  final bool isDark;
  const LogSavedFilesTab({super.key, required this.isDark});

  @override
  State<LogSavedFilesTab> createState() => LogSavedFilesTabState();
}

class LogSavedFilesTabState extends State<LogSavedFilesTab> {
  List<ExportedFile> _files = [];
  bool _loading = true;

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
    setState(() => _loading = true);
    final files = await ExportFile.listSavedLogFiles();
    if (mounted) setState(() { _files = files; _loading = false; });
  }

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
            Icon(LucideIcons.fileText,
                size: 40, color: Theme.of(context).hintColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No saved log files',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Text('Export logs from the menu above',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor.withValues(alpha: 0.7))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final f = _files[index];
          return Dismissible(
            key: ValueKey(f.path),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.trash2,
                  color: AppColors.error, size: 20),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete file?',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800)),
                  content: Text(f.name,
                      style: GoogleFonts.firaCode(fontSize: 11)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel', style: GoogleFonts.plusJakartaSans())),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Delete',
                            style: GoogleFonts.plusJakartaSans(color: AppColors.error, fontWeight: FontWeight.bold))),
                  ],
                ),
              );
            },
            onDismissed: (_) async {
              await ExportFile.deleteFile(f.path);
              setState(() => _files.removeAt(index));
              AppSnackbar.showTop('Deleted', f.name,
                  icon: LucideIcons.trash2,
                  duration: const Duration(seconds: 2),
                  logHistory: false);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: widget.isDark ? 0.15 : 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
                border: Border.all(
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Dt.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(LucideIcons.fileText,
                            size: 18, color: Dt.accent),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 4),
                            Text('${f.sizeLabel}  ·  ${f.dateLabel}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Theme.of(context).hintColor,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'View',
                        icon: Icon(LucideIcons.eye,
                            size: 16, color: Theme.of(context).hintColor),
                        onPressed: () => _viewFile(f),
                      ),
                      IconButton(
                        tooltip: 'Share',
                        icon: Icon(LucideIcons.share2,
                            size: 16, color: Theme.of(context).hintColor),
                        onPressed: () => _shareFile(f),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _viewFile(ExportedFile f) async {
    try {
      String? text;
      if (f.path.startsWith('content://')) {
        final bytes = await ExportFile.readExportFile(f.path);
        if (bytes != null) text = String.fromCharCodes(bytes);
      } else {
        text = await File(f.path).readAsString();
      }
      if (!mounted || text == null) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.fileText,
                        size: 16, color: Dt.accent),
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
                      child: SelectableText(text ?? '',
                          style: GoogleFonts.firaCode(
                              fontSize: 11, height: 1.5, color: const Color(0xFFE2E8F0))),
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
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<void> _shareFile(ExportedFile f) async {
    try {
      Uint8List bytes;
      if (f.path.startsWith('content://')) {
        final b = await ExportFile.readExportFile(f.path);
        if (b == null) {
          AppSnackbar.showTop('Share failed', 'Could not read file',
              icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
          return;
        }
        bytes = b;
      } else {
        bytes = await File(f.path).readAsBytes();
      }
      await ExportFile.shareBytes(bytes: bytes, fileName: f.name);
    } catch (e) {
      AppSnackbar.showTop('Share failed', '$e',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }
}
