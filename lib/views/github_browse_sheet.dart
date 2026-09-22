/// GitHub skill browser bottom sheet.
///
/// Split from `explore_skills_mcp_tabs.dart` - behavior is unchanged.
/// Contains: isDark, GithubBrowseSheet(), createState(), _future, GithubSkillSource(), false, _error
///   initState(), _load(), _import(), build()
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../services/skills/github_skill_source.dart';
import '../services/skills/skill_registry_service.dart';
import '../services/skills/url_skill_source.dart';
import '../theme/design_tokens.dart';

class GithubBrowseSheet extends StatefulWidget {
  final bool isDark;
  const GithubBrowseSheet({super.key, required this.isDark});
  @override
  State<GithubBrowseSheet> createState() => GithubBrowseSheetState();
}

class GithubBrowseSheetState extends State<GithubBrowseSheet> {
  late Future<List<GithubSkillEntry>> _future;
  final _source = GithubSkillSource();
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<GithubSkillEntry>> _load({bool force = false}) async {
    try {
      final list = await _source.listAvailable(forceRefresh: force);
      if (mounted) setState(() => _error = null);
      return list;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      rethrow;
    }
  }

  Future<void> _import(GithubSkillEntry entry) async {
    Get.dialog(
        Center(
            child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: widget.isDark ? Dt.cardDark : Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: Dt.accent),
                  const SizedBox(height: 12),
                  Text('Fetching ${entry.path}â€¦', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                ]))),
        barrierDismissible: false);
    try {
      final content = await _source.fetchSkillContent(entry.path);
      if (!mounted) return;
      Get.back();
      final fm = UrlSkillSource.parseFrontmatter(content);
      final name = entry.name.isNotEmpty ? entry.name : fm['name'] ?? entry.path.split('/').last;
      final desc = entry.description.isNotEmpty ? entry.description : fm['description'] ?? '';
      final ok = await Get.dialog<bool>(AlertDialog(
        backgroundColor: widget.isDark ? Dt.cardDark : Dt.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Import Skill', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).hintColor)),
          ],
          const SizedBox(height: 8),
          Text('From: ${entry.path} (untrusted text)',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                  child: Text(content.length > 4000 ? '${content.substring(0, 4000)}\nâ€¦(truncated)' : content,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, height: 1.4)))),
        ])),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dt.accent),
              onPressed: () => Get.back(result: true),
              child: const Text('Import')),
        ],
      ));
      if (ok != true) return;
      await Get.find<SkillRegistryService>()
          .importFromMarkdown(content, name: name, description: desc, author: 'anthropics/skills', source: 'github', enabled: true);
      Get.snackbar('Skill imported', name,
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.success, colorText: Colors.white);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Import failed', '$e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: AppColors.error, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
          color: widget.isDark ? Dt.cardDark : Dt.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Browse Anthropic skills',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('anthropics/skills â€” flat list, no search',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
            ])),
            IconButton(
                onPressed: () async {
                  setState(() => _refreshing = true);
                  try {
                    final list = await _load(force: true);
                    setState(() {
                      _future = Future.value(list);
                      _refreshing = false;
                    });
                  } catch (_) {
                    setState(() => _refreshing = false);
                  }
                },
                icon: _refreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.refreshCw, size: 18)),
            IconButton(onPressed: () => Get.back(), icon: const Icon(LucideIcons.x, size: 20)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<GithubSkillEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Dt.accent));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,                   children: [
                    const Icon(LucideIcons.alertTriangle, size: 32, color: AppColors.warning),
                    const SizedBox(height: 12),
                    Text('Failed to load',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(_error ?? snap.error.toString(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: () => setState(() => _future = _load(force: true)),
                        style: FilledButton.styleFrom(backgroundColor: Dt.accent),
                        child: const Text('Retry')),
                  ]),
                );
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return Center(
                    child: Text('No skills found',
                        style: GoogleFonts.plusJakartaSans(color: Theme.of(context).hintColor)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 12,
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
                itemBuilder: (_, i) {
                  final e = list[i];
                  final alreadyInstalled = Get.find<SkillRegistryService>()
                      .skills
                      .any((s) => s.source == 'github' && s.name == e.name);
                  return ListTile(
                    leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(LucideIcons.sparkles, size: 18, color: Dt.accent)),
                    title: Text(e.name,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: e.description.isNotEmpty
                        ? Text(e.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor))
                        : Text(e.path,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                    trailing: alreadyInstalled
                        ? const Icon(LucideIcons.check, size: 18, color: AppColors.success)
                        : FilledButton(
                            onPressed: () => _import(e),
                            style: FilledButton.styleFrom(
                                backgroundColor: Dt.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: Text('Import',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
