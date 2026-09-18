import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../core/routes.dart';
import '../../services/chat_backup.dart';
import '../../services/download_service.dart';
import '../../services/hive_service.dart';
import '../../services/stats_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/export_file.dart';
import '../log_view.dart';
import 'apple_widgets.dart';

/// Data tab: backups, export/import, usage stats (moved from General)
/// plus System logs (moved from Config).
class DataView extends GetView<SettingsController> {
  const DataView({super.key});

  @override
  Widget build(BuildContext context) {
    // NOTE: no outer Obx here — each tile subscribes to its own
    // observables below. An outer Obx with no direct .value reads
    // throws GetX "improper use" at runtime.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            sectionLabel(context, 'DATA'),
            appleGroupedCard(context, isDark, children: [
              appleListTile(
                context,
                isDark,
                leading: const Icon(LucideIcons.download,
                    size: 20, color: Dt.accent),
                title: 'Export all chats',
                subtitle: 'Save every conversation as a JSON backup',
                onTap: () => _exportAllChats(),
              ),
              appleListTile(
                context,
                isDark,
                leading: const Icon(LucideIcons.upload,
                    size: 20, color: Dt.accent),
                title: 'Import chats',
                subtitle: 'Restore from a CubicLM backup file',
                onTap: () => _importChats(),
              ),
              Obx(() {
                final chat = Get.isRegistered<ChatController>()
                    ? Get.find<ChatController>()
                    : Get.put(ChatController());
                return appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.history,
                      size: 20, color: Dt.accent),
                  title: 'Auto backup',
                  subtitle: chat.autoBackupEnabled.value
                      ? 'Silent JSON every ${chat.autoBackupDays.value}d (last 3 kept)'
                      : 'Off — only manual exports',
                  trailing: Switch.adaptive(
                    value: chat.autoBackupEnabled.value,
                    activeThumbColor: Dt.accent,
                    onChanged: (v) => chat.setAutoBackup(v),
                  ),
                );
              }),
              Obx(() {
                final chat = Get.isRegistered<ChatController>()
                    ? Get.find<ChatController>()
                    : Get.put(ChatController());
                if (!chat.autoBackupEnabled.value) {
                  return const SizedBox.shrink();
                }
                return appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.calendarClock,
                      size: 20, color: Dt.accent),
                  title: 'Backup every',
                  subtitle:
                      'Every ${chat.autoBackupDays.value} days (unencrypted)',
                  onTap: () => _pickAutoBackupDays(context, chat),
                );
              }),
              appleListTile(
                context,
                isDark,
                leading: const Icon(LucideIcons.settings2,
                    size: 20, color: Dt.accent),
                title: 'Export settings',
                subtitle: 'Preferences without API keys',
                onTap: () => _exportSettings(),
              ),
              appleListTile(
                context,
                isDark,
                leading: const Icon(LucideIcons.settings,
                    size: 20, color: Dt.accent),
                title: 'Import settings',
                subtitle: 'Restore preferences (keys never transfer)',
                onTap: () => _importSettings(),
              ),
              if (!kIsWeb)
                Obx(() {
                  // Subscribe to the Rx prefs so the label refreshes
                  // right after a change (the label itself reads Hive).
                  controller.exportSubfolder.value;
                  controller.exportCustomDir.value;
                  controller.exportTreeUri.value;
                  controller.exportTreeName.value;
                  return appleListTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.folderOutput,
                        size: 20, color: Dt.accent),
                    title: 'Export folder',
                    subtitle: ExportFile.exportLocationLabel(),
                    trailing: IconButton(
                      tooltip: 'How this works',
                      icon: const Icon(LucideIcons.info, size: 19),
                      onPressed: () => _showExportFolderInfo(context),
                    ),
                    onTap: () => _pickExportFolder(context, isDark),
                  );
                }),
              FutureBuilder<String>(
                future: Get.isRegistered<DownloadService>()
                    ? Get.find<DownloadService>().modelsDir
                    : Future.value(''),
                builder: (ctx, snap) {
                  final full = snap.data ?? '';
                  if (full.isEmpty) return const SizedBox.shrink();
                  final short = full.replaceFirst(
                      RegExp(r'^/data/(user/\d+/|data/)com\.cubiclm\.app/'),
                      'app-private/');
                  return appleListTile(
                    context,
                    isDark,
                    leading: const Icon(LucideIcons.cpu,
                        size: 20, color: Dt.accent),
                    title: 'Model files location',
                    subtitle: '$short (app-private, cannot move)',
                    trailing: IconButton(
                      tooltip: 'Copy full path',
                      icon: const Icon(LucideIcons.copy, size: 19),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: full));
                        Get.snackbar('Copied',
                            'Model folder path copied.',
                            snackPosition: SnackPosition.BOTTOM,
                            duration: const Duration(seconds: 2));
                      },
                    ),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: full));
                      Get.snackbar('Copied', 'Model folder path copied.',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2));
                    },
                  );
                },
              ),
              Obx(() {
                final stats = Get.isRegistered<StatsService>()
                    ? Get.find<StatsService>()
                    : Get.put(StatsService());
                final on = stats.enabled.value;
                final counts = on ? stats.snapshot() : <String, int>{};
                final total = counts.values.fold<int>(0, (a, b) => a + b);
                return appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.barChart3,
                      size: 20, color: Dt.accent),
                  title: 'Usage statistics',
                  subtitle: !on
                      ? 'Off — nothing is counted'
                      : total == 0
                          ? 'On — no events yet'
                          : '$total events counted (device only)',
                  trailing: Switch.adaptive(
                    value: on,
                    activeThumbColor: Dt.accent,
                    onChanged: (nv) => stats.setEnabled(nv),
                  ),
                  showDivider: false,
                  onTap: on ? () => _showStats(context, stats) : null,
                );
              }),
              appleListTile(
                context,
                isDark,
                leading: const Icon(LucideIcons.graduationCap,
                    size: 20, color: Dt.accent),
                title: 'Replay onboarding',
                subtitle: 'Walk through setup again',
                showDivider: false,
                onTap: () async {
                  await controller.resetOnboarding();
                  // Push (don't offAllNamed): keeps the home stack and its
                  // controllers alive underneath. offAllNamed from here
                  // would dispose lazy controllers (Chat/Home/Model) and
                  // break the return trip. Onboarding finishes with its
                  // own offAllNamed(home), which rebuilds cleanly.
                  Get.toNamed(AppRoutes.onboarding);
                },
              ),
            ]),
            const SizedBox(height: 28),
            sectionLabel(context, 'settings_section_diagnostics'.tr),
            appleGroupedCard(context, isDark, children: [
              appleListTile(
                context,
                isDark,
                leading: iconBox(AppColors.info, LucideIcons.terminal),
                title: 'settings_system_logs'.tr,
                subtitle: 'settings_system_logs_desc'.tr,
                trailing: const Icon(LucideIcons.chevronRight, size: 20),
                showDivider: false,
                onTap: () => Get.to(() => const LogView()),
              ),
            ]),
            const SizedBox(height: 50),
          ],
        );
  }

  // ── Backup / Restore ──
  Future<void> _exportAllChats() async {
    final opts = await _showBackupOptionsDialog();
    if (opts == null) return; // cancelled
    try {
      if (!Get.isRegistered<ChatController>()) {
        Get.put(ChatController());
      }
      final err = await exportAllChats(
        Get.find<HiveService>(),
        includeImages: opts.includeImages,
        passphrase: opts.passphrase.isEmpty ? null : opts.passphrase,
      );
      if (err == 'empty') {
        AppSnackbar.showTop(
            'Nothing to export', 'No chats found. Start a conversation first.',
            icon: LucideIcons.info, type: 'general', logHistory: false);
      } else if (err == 'cancelled') {
        // User dismissed the desktop save dialog — stay silent.
        return;
      } else if (err != null) {
        AppSnackbar.showTop(
            'Export failed', 'Something went wrong while creating the backup.',
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
      } else if (opts.passphrase.isNotEmpty) {
        AppSnackbar.showTop('Encrypted backup saved',
            'Keep your passphrase safe — it cannot be recovered.',
            icon: LucideIcons.lock, type: 'success', iconName: 'lock');
      }
    } catch (_) {
      AppSnackbar.showTop(
          'Export failed', 'Something went wrong while creating the backup.',
          icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
    }
  }

  /// Export options: include images + optional passphrase encryption.
  Future<_BackupOptions?> _showBackupOptionsDialog() async {
    var includeImages = false;
    final passCtrl = TextEditingController();
    try {
      return await Get.dialog<_BackupOptions>(
        AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Export backup'),
          content: StatefulBuilder(
            builder: (ctx, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: includeImages,
                  onChanged: (v) => setState(() => includeImages = v ?? false),
                  title: const Text('Include images'),
                  subtitle: const Text(
                      'Much larger file. Needed to restore pictures.'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase (optional)',
                    hintText: 'Encrypts the backup (AES-256)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Get.back(
                result: _BackupOptions(
                  includeImages: includeImages,
                  passphrase: passCtrl.text,
                ),
              ),
              child: const Text('Export'),
            ),
          ],
        ),
      );
    } finally {
      passCtrl.dispose();
    }
  }

  void _showStats(BuildContext context, StatsService stats) {
    final counts = stats.snapshot();
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Usage statistics',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Counted on this device only. Nothing leaves the app.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(ctx).hintColor)),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text('No events yet.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14)),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(StatsService.label(e.key),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Text('${e.value}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Dt.accent)),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await stats.reset();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Reset',
                style: GoogleFonts.plusJakartaSans(color: AppColors.error)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSettings() async {
    try {
      if (!Get.isRegistered<ChatController>()) Get.put(ChatController());
      final err = await exportSettings(Get.find<HiveService>());
      if (err == null) {
        AppSnackbar.showTop('Settings exported',
            'API keys were excluded. Import them manually on the new device.',
            icon: LucideIcons.check, type: 'general', logHistory: false);
      } else if (err != 'cancelled') {
        AppSnackbar.showTop('Export failed', err,
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
      }
    } catch (_) {}
  }

  Future<void> _importSettings() async {
    try {
      if (!Get.isRegistered<ChatController>()) Get.put(ChatController());
      final err = await importSettings(Get.find<HiveService>());
      if (err == null) {
        AppSnackbar.showTop('Settings imported',
            'Applied. Restart the app if something looks stale.',
            icon: LucideIcons.check, type: 'general', logHistory: false);
      } else if (err != 'cancelled') {
        AppSnackbar.showTop('Import failed', err,
            icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
      }
    } catch (_) {}
  }

  Widget _infoRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  /// Explains where exports go: default folder, custom picks, and why
  /// files survive app uninstall.
  void _showExportFolderInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export folder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Default',
                  'Every export saves straight into Download/CubicLM — no folder picker every time.'),
              _infoRow('Custom folder',
                  'Choose folder opens the system file manager: browse, create or select any folder once. The app remembers it (permission survives reboot). Reset returns to the default.'),
              _infoRow('Uninstall-safe',
                  'Files in Download stay on your device even if CubicLM is uninstalled.'),
              _infoRow('Share',
                  'Every export notice has a Share button to send the file to Drive, chat apps or email.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Export destination picker. Android opens the system file manager
  /// (SAF tree picker: browse, create and select any folder); desktop
  /// can rename the subfolder or pick any folder outright.
  Future<void> _pickExportFolder(BuildContext context, bool isDark) async {
    final s = controller;
    final nameCtrl = TextEditingController(text: s.exportSubfolder.value);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final isAndroid = Platform.isAndroid;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export folder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current:\n${ExportFile.exportLocationLabel()}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              const SizedBox(height: 12),
              if (isAndroid) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(LucideIcons.folderOpen, size: 16),
                    label: const Text('Choose folder…'),
                    onPressed: () async {
                      final picked = await ExportFile.pickExportFolder();
                      if (picked != null) {
                        await s.setExportTree(picked['uri']!, picked['name']!);
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                    'Opens the system file manager — browse, create or select any folder.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Dt.textSecondary)),
              ] else ...[
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Folder name',
                    hintText: 'CubicLM',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (isDesktop) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(LucideIcons.folderOpen, size: 16),
                  label: const Text('Pick custom folder…'),
                  onPressed: () async {
                    try {
                      final dir = await FilePicker.getDirectoryPath(
                          dialogTitle: 'Export folder');
                      if (dir != null && dir.isNotEmpty) {
                        await s.setExportCustomDir(dir);
                        if (context.mounted) Navigator.pop(context);
                      }
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await s.resetExportDir();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (!isAndroid)
            FilledButton(
              onPressed: () async {
                // A custom desktop dir wins while set; saving a name here
                // clears it so the name actually takes effect.
                await s.setExportCustomDir('');
                await s.setExportSubfolder(nameCtrl.text);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
        ],
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _importChats() async {
    try {
      if (!Get.isRegistered<ChatController>()) {
        Get.put(ChatController());
      }
      final chat = Get.find<ChatController>();
      final err = await chat.importChats();
      switch (err) {
        case 'cancelled':
          return;
        case 'locked':
          // Encrypted backup — ask passphrase and retry once.
          final pass = await _showPassphraseDialog();
          if (pass == null || pass.isEmpty) return;
          final retry = await chat.importChats(passphrase: pass);
          if (retry == null || retry.startsWith('ok:')) {
            _showRestoreDone(retry);
          } else {
            _showImportError(retry);
          }
          return;
        case 'invalid':
          AppSnackbar.showTop('Invalid file',
              'Not a CubicLM backup — or the passphrase is wrong.',
              icon: LucideIcons.alertTriangle,
              type: 'error',
              iconName: 'alert');
          return;
        case 'nothing':
          AppSnackbar.showTop(
              'Nothing new', 'All chats in that backup already exist here.',
              icon: LucideIcons.info, type: 'general', logHistory: false);
          return;
        case 'error':
          AppSnackbar.showTop(
              'Import failed', 'Something went wrong while reading the backup.',
              icon: LucideIcons.alertTriangle,
              type: 'error',
              iconName: 'alert');
          return;
        default:
          if (err != null && err.startsWith('ok:')) {
            _showRestoreDone(err);
          }
      }
    } catch (_) {
      AppSnackbar.showTop(
          'Import failed', 'Something went wrong while reading the backup.',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  void _showRestoreDone(String? err) {
    final parts = (err ?? '').split(':');
    final sessions = parts.length > 1 ? parts[1] : '0';
    final messages = parts.length > 2 ? parts[2] : '0';
    AppSnackbar.showTop(
        'Backup restored', '$sessions chats and $messages messages imported.',
        icon: LucideIcons.checkCircle2, type: 'success', iconName: 'check');
  }

  void _showImportError(String err) {
    if (err == 'invalid') {
      AppSnackbar.showTop(
          'Invalid file', 'Not a CubicLM backup — or the passphrase is wrong.',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    } else {
      AppSnackbar.showTop(
          'Import failed', 'Something went wrong while reading the backup.',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<String?> _showPassphraseDialog() async {
    final c = TextEditingController();
    try {
      return await Get.dialog<String>(
        AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Encrypted backup'),
          content: TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Get.back(result: c.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: c.text),
              child: const Text('Unlock'),
            ),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
  }

  Future<void> _pickAutoBackupDays(
      BuildContext context, ChatController chat) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: const Text('Auto backup every'),
        children: [
          for (final d in ChatController.autoBackupDayOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, d),
              child: Text(d == 1 ? 'Every day' : 'Every $d days'),
            ),
        ],
      ),
    );
    if (picked != null) await chat.setAutoBackup(true, picked);
  }
}

/// Backup export choices from the export-options dialog.
class _BackupOptions {
  final bool includeImages;
  final String passphrase;
  const _BackupOptions({required this.includeImages, required this.passphrase});
}
