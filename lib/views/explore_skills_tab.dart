/// Explore Skills tab: list, preview, import, delete.
///
/// Split from `explore_skills_mcp_tabs.dart` - behavior is unchanged.
/// Contains: ExploreSkillsTab(), build(), _skillTile(), _showPreview(), _shareSkill(), _confirmDelete()
///   _showImportOptions(), _importOptionTile(), _importFromFile(), _browseGithub(), _importFromUrl()
///   _showImportPreview(), name, desc, author, _ImportPreviewResult(), isDark, _UrlImportDialog()
///   createState(), TextEditingController(), dispose(), build(), isDark, content, initialName
///   initialDesc, initialAuthor, _ImportPreviewDialog(), createState(), TextEditingController()
///   TextEditingController(), TextEditingController(), dispose(), build()
library;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../core/colors.dart';
import '../models/skill_model.dart';
import '../services/skills/skill_registry_service.dart';
import '../services/skills/url_skill_source.dart';
import '../theme/design_tokens.dart';

import 'github_browse_sheet.dart';

// â”€â”€ Explore Skills Tab â”€â”€

class ExploreSkillsTab extends StatelessWidget {
  const ExploreSkillsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final registry = Get.find<SkillRegistryService>();
    return Obx(() {
      final all = registry.skills.toList();
      final enabledCount = all.where((s) => s.enabled).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(LucideIcons.sparkles, size: 18, color: Dt.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Skills',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                      all.isEmpty
                          ? 'No skills yet â€” import one'
                          : '$enabledCount of ${all.length} enabled',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showImportOptions(context),
                icon: const Icon(LucideIcons.upload, size: 16),
                label: Text('Import',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            'Skills are offline instruction blocks appended to the system prompt. Enable any combination â€” they work for local and cloud models.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, height: 1.4, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 14),
          if (all.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline),
              ),
              child: Column(children: [
                Icon(LucideIcons.sparkles, size: 28, color: Theme.of(context).hintColor),
                const SizedBox(height: 8),
                Text('No skills installed',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Tap Import â†’ From file / Browse GitHub / From URL',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: Theme.of(context).hintColor)),
              ]),
            )
          else
            for (final s in all) _skillTile(context, isDark, s),
        ],
      );
    });
  }

  Widget _skillTile(BuildContext context, bool isDark, SkillModel skill) {
    final registry = Get.find<SkillRegistryService>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: skill.enabled
                ? Dt.accent.withValues(alpha: 0.2)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: skill.enabled
                  ? Dt.accent.withValues(alpha: 0.15)
                  : Theme.of(context).hintColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                skill.isBuiltIn ? LucideIcons.award : LucideIcons.fileText,
                size: 18,
                color: skill.enabled ? Dt.accent : Theme.of(context).hintColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(skill.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700))),
                  if (skill.isBuiltIn)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('BUILT-IN',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: AppColors.info)),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Theme.of(context).hintColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(skill.source,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                        height: 1.3)),
                const SizedBox(height: 2),
                Text('${skill.author} Â· v${skill.version}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context).hintColor.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Switch(
                value: skill.enabled,
                activeThumbColor: Dt.accent,
                onChanged: (v) => v ? registry.enable(skill.id) : registry.disable(skill.id)),
            InkWell(
              onTap: () => _showPreview(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.eye, size: 18, color: Theme.of(context).hintColor)),
            ),
            InkWell(
              onTap: () => _confirmDelete(context, isDark, skill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.trash2, size: 18, color: AppColors.error.withValues(alpha: 0.8))),
            ),
          ]),
        ],
      ),
    );
  }

  void _showPreview(BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(skill.name, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${skill.author} Â· v${skill.version} Â· ${skill.source}',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 4),
          Text(skill.description,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
                child: Text(skill.content, style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4))),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        FilledButton.tonal(
          onPressed: () => _shareSkill(skill),
          child: const Text('Share .md'),
        ),
      ],
    ));
  }

  /// Share a skill as a markdown bundle (frontmatter + content) so it can
  /// be imported on another device via Import → From file.
  void _shareSkill(SkillModel skill) {
    try {
      final buf = StringBuffer()
        ..writeln('---')
        ..writeln('name: ${skill.name}')
        ..writeln('description: ${skill.description}')
        ..writeln('author: ${skill.author}')
        ..writeln('version: ${skill.version}')
        ..writeln('---')
        ..writeln()
        ..writeln(skill.content.trim());
      Share.share(buf.toString(), subject: '${skill.name} (CubicLM skill)');
    } catch (_) {}
  }

  void _confirmDelete(BuildContext context, bool isDark, SkillModel skill) {
    Get.dialog(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Delete skill?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text('Delete "${skill.name}"? This cannot be undone.', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              Get.find<SkillRegistryService>().delete(skill.id);
            },
            child: const Text('Delete')),
      ],
    ));
  }

  void _showImportOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
            color: isDark ? Dt.cardDark : Dt.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).hintColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Import Skill',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('All imports show a preview before saving.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          _importOptionTile(context, isDark,
              icon: LucideIcons.fileText,
              title: 'From file',
              subtitle: 'Pick a .md file from your device',
              onTap: () {
                Get.back();
                _importFromFile(context);
              }),
          _importOptionTile(context, isDark,
              icon: LucideIcons.github,
              title: 'Browse Anthropic skills',
              subtitle: 'Flat list from anthropics/skills on GitHub',
              onTap: () {
                Get.back();
                _browseGithub(context);
              }),
          _importOptionTile(context, isDark,
              icon: LucideIcons.link2,
              title: 'From URL',
              subtitle: 'Paste any direct link to a raw markdown file',
              onTap: () {
                Get.back();
                _importFromUrl(context);
              },
              showDivider: false),
        ]),
      ),
    );
  }

  Widget _importOptionTile(BuildContext context, bool isDark,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      bool showDivider = true}) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: Dt.accent)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Theme.of(context).hintColor, height: 1.3)),
            ])),
            Icon(LucideIcons.chevronRight, size: 18, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 1,
            indent: 50,
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
    ]);
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['md', 'markdown', 'txt'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String? content;
      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
      if (content == null || content.trim().isEmpty) {
        Get.snackbar('Import failed', 'File is empty', snackPosition: SnackPosition.BOTTOM);
        return;
      }
      String name = file.name.replaceAll(RegExp(r'\.(md|markdown|txt)$', caseSensitive: false), '');
      name = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
      if (name.isEmpty) name = 'Imported Skill';
      if (!context.mounted) return;
      await _showImportPreview(context, content, initialName: name, source: 'file');
    } catch (e) {
      Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _browseGithub(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      GithubBrowseSheet(isDark: isDark),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Future<void> _importFromUrl(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entered = await Get.dialog<String?>(
      _UrlImportDialog(isDark: isDark),
      barrierDismissible: true,
    );
    final url = entered?.trim() ?? '';
    if (url.isEmpty) return;
    if (!context.mounted) return;
    Get.dialog(
      Center(
          child: Container(
              padding: const EdgeInsets.all(24),
              decoration:
                  BoxDecoration(color: isDark ? Dt.cardDark : Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: Dt.accent),
                const SizedBox(height: 12),
                Text('Fetchingâ€¦', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              ]))),
      barrierDismissible: false,
    );
    try {
      final content = await UrlSkillSource().fetchFromUrl(url);
      if (!context.mounted) return;
      Get.back();
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = fm['name']?.isNotEmpty == true
          ? fm['name']!
          : Uri.tryParse(url)?.pathSegments.last
                  .replaceAll(RegExp(r'\.(md|markdown)$', caseSensitive: false), '')
                  .replaceAll(RegExp(r'[-_]+'), ' ')
                  .trim() ??
              'Imported Skill';
      final desc = fm['description'] ?? '';
      final author = fm['author'] ?? 'URL';
      await _showImportPreview(context, content,
          initialName: name, initialDesc: desc, initialAuthor: author, source: 'url');
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Fetch failed', '$e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.error, colorText: Colors.white);
    }
  }

  Future<void> _showImportPreview(BuildContext context, String content,
      {required String initialName,
      String initialDesc = '',
      String initialAuthor = 'User',
      String source = 'file'}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await Get.dialog<_ImportPreviewResult?>(
      _ImportPreviewDialog(
        isDark: isDark,
        content: content,
        initialName: initialName,
        initialDesc: initialDesc,
        initialAuthor: initialAuthor,
      ),
      barrierDismissible: true,
    );
    if (result == null) return;
    try {
      await Get.find<SkillRegistryService>().importFromMarkdown(content,
          name: result.name, description: result.desc, author: result.author, source: source, enabled: true);
      Get.snackbar('Skill imported', result.name.trim(),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.success, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Import failed', '$e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}

/// Result payload for the URL-import dialog (avoids poking a disposed
/// TextEditingController â€” the controller lives inside the dialog State).
class _ImportPreviewResult {
  final String name;
  final String desc;
  final String author;
  const _ImportPreviewResult(this.name, this.desc, this.author);
}

/// Prompts for a raw skill URL. Pops with the trimmed URL string, or null if
/// cancelled. Owns its TextEditingController so it's disposed only after the
/// dialog's exit animation finishes (State.dispose).
class _UrlImportDialog extends StatefulWidget {
  final bool isDark;
  const _UrlImportDialog({required this.isDark});

  @override
  State<_UrlImportDialog> createState() => _UrlImportDialogState();
}

class _UrlImportDialogState extends State<_UrlImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Import from URL',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste a direct link to a raw markdown file.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    hintText: 'https://raw.githubusercontent.com/.../SKILL.md',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14))),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Fetch')),
      ],
    );
  }
}
/// Skill import preview (name / description / author + content preview).
/// Owns its controllers so dispose timing is always safe.
class _ImportPreviewDialog extends StatefulWidget {
  final bool isDark;
  final String content;
  final String initialName;
  final String initialDesc;
  final String initialAuthor;
  const _ImportPreviewDialog({
    required this.isDark,
    required this.content,
    required this.initialName,
    required this.initialDesc,
    required this.initialAuthor,
  });

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late final _nameCtrl = TextEditingController(text: widget.initialName);
  late final _descCtrl = TextEditingController(text: widget.initialDesc);
  late final _authorCtrl = TextEditingController(text: widget.initialAuthor);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final content = widget.content;
    return AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Dt.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Import Skill',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),
              const SizedBox(height: 10),
              TextField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),
              const SizedBox(height: 10),
              TextField(
                  controller: _authorCtrl,
                  decoration: InputDecoration(
                      labelText: 'Author',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),              const SizedBox(height: 14),
              Text('Preview — ${content.length} chars',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Dt.pillMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Dt.hairline)),
                child: SingleChildScrollView(
                    child: Text(
                        content.length > 4000
                            ? '${content.substring(0, 4000)}\n…(truncated)'
                            : content,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, height: 1.4))),
              ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Navigator.pop(
                context,
                _ImportPreviewResult(
                    _nameCtrl.text.trim(),
                    _descCtrl.text.trim(),
                    _authorCtrl.text.trim())),
            child: const Text('Import')),
      ],
    );
  }
}
