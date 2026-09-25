/// Log row actions: fix-with-agent, export/share sheets, file save, chips, time format.
///
/// Split from `log_view.dart` - behavior is unchanged.
/// Contains: _rowAction(), _fixWithAgent(), _showExportSheet(), _saveLogsFile(), _shareLogsFile(), _catChip()
///   _catColor(), _formatTime(), _formatDateTime()
part of 'log_view.dart';

extension _LogViewActions on _LogViewState {
  Widget _rowAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final color =
        accent ? Dt.accent : Theme.of(context).hintColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// Prefill the agent with this row's diagnosis and open the workspace.
  /// The composer picks up `prompt` on build, so the task is visible and
  /// runnable with one tap.
  void _fixWithAgent(
      BuildContext context, AppLogService logs, AppLogEntry entry) {
    try {
      final c = Get.isRegistered<AgentRunnerController>()
          ? Get.find<AgentRunnerController>()
          : Get.put(AgentRunnerController());
      c.prompt.value = logs.diagnosisFor(entry, forAgent: true);
      Get.to(() => const AgentWorkspaceView());
    } catch (e) {
      AppSnackbar.showTop('Cannot open agent', '$e');
    }
  }

  Future<void> _showExportSheet(
      BuildContext context, AppLogService logs, bool isDark) async {
    final bg = Theme.of(context).cardColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final action = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Export logs',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 18, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(LucideIcons.copy, size: 20, color: textColor),
              title: Text('Copy to clipboard',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'copy'),
            ),
            ListTile(
              leading: Icon(LucideIcons.fileText, size: 20, color: textColor),
              title: Text('Save as .txt file',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'file'),
            ),
            ListTile(
              leading: Icon(LucideIcons.share2, size: 20, color: textColor),
              title: Text('Share .txt file',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'share'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: null),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans()),
          ),
        ],
      ),
    );
    if (action == null) return;
    try {
      final text = await logs.exportFullLogs();
      if (!context.mounted) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: text));
        AppSnackbar.showTop(
          'Logs Copied',
          'Deduplicated diagnostic report copied to clipboard.',
          icon: LucideIcons.copyCheck,
          iconName: 'copyCheck',
          duration: const Duration(seconds: 2),
          logHistory: false,
        );
        return;
      }
      if (action == 'share') {
        await _shareLogsFile(logs, text);
        return;
      }
      await _saveLogsFile(context, logs, text);
    } catch (e) {
      AppSnackbar.showTop('Export failed', '$e',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<void> _saveLogsFile(
      BuildContext context, AppLogService logs, String text) async {
    var version = '';
    try {
      if (Get.isRegistered<SettingsController>()) {
        version = Get.find<SettingsController>().appVersion.value;
      }
    } catch (_) {}
    final fileName = logs.exportFileName(version);
    if (kIsWeb) {
      try {
        final bytes = utf8.encode(text);
        if (await downloadWebFile(bytes, fileName, 'text/plain')) {
          AppSnackbar.showTop('Logs saved', fileName,
              icon: LucideIcons.checkCircle2,
              type: 'success',
              iconName: 'check',
              duration: const Duration(seconds: 3),
              logHistory: false);
          return;
        }
      } catch (_) {}
      await Clipboard.setData(ClipboardData(text: text));
      AppSnackbar.showTop(
        'Logs Copied',
        'File save is not available on web — copied instead.',
        icon: LucideIcons.copyCheck,
        iconName: 'copyCheck',
        duration: const Duration(seconds: 3),
        logHistory: false,
      );
      return;
    }
    await ExportFile.quickExport(
      text: text,
      fileName: fileName,
      mimeType: 'text/plain',
      category: 'logs',
    );
  }

  Future<void> _shareLogsFile(AppLogService logs, String text) async {
    var version = '';
    try {
      if (Get.isRegistered<SettingsController>()) {
        version = Get.find<SettingsController>().appVersion.value;
      }
    } catch (_) {}
    final fileName = logs.exportFileName(version);
    final bytes = Uint8List.fromList(utf8.encode(text));
    final ok = await ExportFile.shareBytes(
      bytes: bytes,
      fileName: fileName,
    );
    if (!ok) {
      // Share sheet unavailable/broken (seen on some release builds):
      // fall back to a saved file so the logs still leave the device.
      final saved = await ExportFile.saveToAppFolder(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'text/plain',
        category: 'logs',
      );
      AppSnackbar.showTop(
          saved != null ? 'Share unavailable — saved instead' : 'Share failed',
          saved ?? 'Could not share $fileName',
          icon: LucideIcons.alertTriangle,
          type: saved != null ? 'success' : 'error',
          iconName: 'alert');
    }
  }

  Widget _catChip(BuildContext context, bool isDark,
      {required String label,
      required bool selected,
      required Color color,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? color : Theme.of(context).hintColor)),
            ],
          ),
        ),
      ),
    );
  }

  Color _catColor(LogCategory cat) {
    switch (cat) {
      case LogCategory.system:
        return const Color(0xFF6366F1);
      case LogCategory.model:
        return const Color(0xFFF59E0B);
      case LogCategory.cloud:
        return const Color(0xFF3B82F6);
      case LogCategory.chat:
        return const Color(0xFF10B981);
      case LogCategory.server:
        return const Color(0xFF8B5CF6);
      case LogCategory.image:
        return const Color(0xFFEC4899);
      case LogCategory.agent:
        return const Color(0xFF14B8A6);
      case LogCategory.runtime:
        return const Color(0xFFF97316);
      case LogCategory.terminal:
        return const Color(0xFF64748B);
      case LogCategory.update:
        return const Color(0xFFA855F7);
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDateTime(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${_formatTime(time)}';
}
