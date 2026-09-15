/// CubicApp Builder — AI-powered Android app builder (Toolkit).
///
/// Pick a template → describe your app → AI generates the full project →
/// export as ZIP with GitHub Actions workflow → push to GitHub for APK.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/cubicapp/cubicapp_templates.dart';
import '../services/inference_service.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';

class CubicAppBuilderView extends StatefulWidget {
  const CubicAppBuilderView({super.key});

  @override
  State<CubicAppBuilderView> createState() => _CubicAppBuilderViewState();
}

class _CubicAppBuilderViewState extends State<CubicAppBuilderView> {
  final _promptCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  final _chatMsgs = <_ChatMsg>[].obs;
  final _generatedFiles = <String, String>{}.obs;
  final _generating = false.obs;
  final _selectedTemplate = Rxn<CubicAppTemplate>();
  final _tab = 'preview'.obs; // preview | files | chat
  String? _openFile;
  final _expandedFolders = <String>{};

  @override
  void initState() {
    super.initState();
    AppLogService.trackScreen('CubicApp Builder');
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  // ─── AI generation ──────────────────────────────────────────────────

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _generating.value) return;

    _chatMsgs.add(_ChatMsg(role: 'user', text: prompt));
    _promptCtrl.clear();
    _generating.value = true;
    _tab.value = 'chat';

    try {
      final template = _selectedTemplate.value;
      if (template == null) {
        _chatMsgs.add(const _ChatMsg(
            role: 'assistant',
            text: 'Pick a template first, then describe your app.'));
        return;
      }

      // Build system prompt with template context
      final sys = _buildSystemPrompt(template, prompt);

      // Generate via cloud or local
      final settings = Get.find<SettingsController>();
      final buf = StringBuffer();

      if (settings.inferenceMode.value == 'cloud') {
        final cloud = Get.find<CloudService>();
        await for (final chunk in cloud.streamMessage([
          {'role': 'system', 'content': sys},
          {'role': 'user', 'content': prompt},
        ],
            temperature: settings.temperature.value,
            maxTokens: settings.autoTuneParams.value
                ? null
                : settings.maxTokens.value)) {
          buf.write(chunk);
        }
      } else {
        final inference = Get.find<InferenceService>();
        if (!inference.isModelLoaded.value) {
          throw Exception(
              'No local model loaded. Switch to Cloud mode or load a model in Explore.');
        }
        await inference.generate(
          prompt: prompt,
          systemPrompt: sys,
          source: 'cubicapp',
          onToken: (t) => buf.write(t),
        );
      }

      final raw = buf.toString().trim();
      if (raw.isEmpty) throw Exception('AI returned empty response.');

      // Parse AI-generated files and merge with template base
      final aiFiles = parseAiGeneratedFiles(raw);
      final baseFiles = buildCubicAppProject(
        template: template,
        appId: 'com.cubicapp.generated',
        appName: 'MyApp',
      );

      // Merge: AI files override template base where paths overlap
      final allFiles = <String, String>{...baseFiles, ...aiFiles};

      _generatedFiles.assignAll(allFiles);

      // Show file count summary
      final fileNames = allFiles.keys.toList()..sort();
      final summary = StringBuffer('**Project generated** (${allFiles.length} files)\n\n');
      for (final f in fileNames) {
        summary.writeln('  $f');
      }

      _chatMsgs.add(_ChatMsg(role: 'assistant', text: summary.toString()));
    } catch (e) {
      _chatMsgs.add(_ChatMsg(role: 'assistant', text: 'Error: $e'));
    } finally {
      _generating.value = false;
      _scrollChat();
    }
  }

  String _buildSystemPrompt(CubicAppTemplate template, String userPrompt) {
    return '''You are CubicApp Builder, an Android project generator.

TEMPLATE: ${template.name}
${template.systemPrompt}

USER REQUEST: $userPrompt

RULES:
1. Generate ALL project files in JSON format:
{"files":[{"path":"relative/path","content":"file content"}]}

2. Include complete, buildable Kotlin/Android code.
3. Files MUST include at least:
   - app/src/main/java/com/cubicapp/generated/MainActivity.kt
   - app/src/main/res/layout/activity_main.xml (if needed)
4. Use Material Design 3 components.
5. Keep code clean and well-organized.
6. Do NOT include build system files (build.gradle, etc.) — those are provided.

Output ONLY the JSON block. No explanation needed.''';
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  // ─── Export as ZIP ──────────────────────────────────────────────────

  Future<void> _exportZip() async {
    if (_generatedFiles.isEmpty) {
      AppSnackbar.showTop('No files to export', 'Generate a project first.');
      return;
    }
    try {
      final archive = Archive();
      for (final entry in _generatedFiles.entries) {
        final bytes = utf8.encode(entry.value);
        archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
      }
      final out = ZipEncoder().encode(archive);
      if (out.isEmpty) throw Exception('ZIP encoder returned nothing.');

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = 'cubicapp_$stamp.zip';
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(out),
        fileName: name,
        mimeType: 'application/zip',
      );
      AppSnackbar.showTop('Exported', '$name saved successfully.');
    } catch (e) {
      AppSnackbar.showTop('Export failed', '$e');
    }
  }

  // ─── Build UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Get.back(),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.smartphone, size: 16, color: Dt.accent),
            ),
            const SizedBox(width: 10),
            Text(
              'CubicApp Builder',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          if (_generatedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.download, size: 18),
              tooltip: 'Export ZIP',
              onPressed: _exportZip,
            ),
        ],
      ),
      body: _selectedTemplate.value == null
          ? _templateGrid(context, isDark)
          : _builderScaffold(context, isDark),
    );
  }

  // ─── Template selection grid ────────────────────────────────────────

  Widget _templateGrid(BuildContext context, bool isDark) {
    final templates = cubicAppTemplates();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Choose a starting template',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Each template includes a complete Android project with Kotlin + Material Design. AI customizes it based on your description.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                height: 1.45,
                color: Theme.of(context).hintColor),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
            ),
            itemCount: templates.length,
            itemBuilder: (context, i) {
              final t = templates[i];
              return _templateCard(context, isDark, t);
            },
          ),
        ),
      ],
    );
  }

  Widget _templateCard(BuildContext context, bool isDark, CubicAppTemplate t) {
    return InkWell(
      onTap: () => _selectedTemplate.value = t,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconForTemplate(t.icon), size: 18, color: Dt.accent),
            ),
            const SizedBox(height: 10),
            Text(t.name,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                t.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, height: 1.4, color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Builder scaffold (after template selected) ─────────────────────

  Widget _builderScaffold(BuildContext context, bool isDark) {
    return Column(
      children: [
        // Tab bar
        _builderTabBar(context, isDark),
        // Content
        Expanded(
          child: Obx(() {
            switch (_tab.value) {
              case 'files':
                return _filesPane(context, isDark);
              case 'chat':
                return _chatPane(context, isDark);
              default:
                return _previewPane(context, isDark);
            }
          }),
        ),
        // Input area
        _inputBar(context, isDark),
      ],
    );
  }

  Widget _builderTabBar(BuildContext context, bool isDark) {
    return Obx(() {
      final hasFiles = _generatedFiles.isNotEmpty;
      return Container(
        height: 44,
        color: isDark ? AppColors.surface : Colors.white,
        child: Row(
          children: [
            _tabBtn(context, 'Preview', 'preview', LucideIcons.eye, isDark),
            _tabBtn(context, 'Files', 'files', LucideIcons.folderOpen, isDark,
                badge: hasFiles ? '${_generatedFiles.length}' : null),
            _tabBtn(context, 'Chat', 'chat', LucideIcons.messageSquare, isDark),
          ],
        ),
      );
    });
  }

  Widget _tabBtn(BuildContext context, String label, String id, IconData icon,
      bool isDark,
      {String? badge}) {
    final active = _tab.value == id;
    return Expanded(
      child: InkWell(
        onTap: () => _tab.value = id,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Dt.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Dt.accent : Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? Dt.accent
                          : Theme.of(context).hintColor)),
              if (badge != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(badge,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Dt.accent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Preview pane ───────────────────────────────────────────────────

  Widget _previewPane(BuildContext context, bool isDark) {
    if (_generatedFiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.smartphone,
                  size: 48,
                  color: Theme.of(context).hintColor.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                'No project yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Describe your app in the chat below and AI will generate the full Android project.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(context, isDark),
        const SizedBox(height: 16),
        _projectSummary(context, isDark),
      ],
    );
  }

  Widget _infoCard(BuildContext context, bool isDark) {
    final t = _selectedTemplate.value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForTemplate(t?.icon ?? 'file'),
                  size: 18, color: Dt.accent),
              const SizedBox(width: 8),
              Text(t?.name ?? 'Project',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This project includes a GitHub Actions workflow that builds the APK automatically when you push to GitHub.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, height: 1.45, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stepBadge('1', 'Push to GitHub'),
              const SizedBox(width: 8),
              Icon(LucideIcons.arrowRight, size: 12, color: Theme.of(context).hintColor),
              const SizedBox(width: 8),
              _stepBadge('2', 'APK builds'),
              const SizedBox(width: 8),
              Icon(LucideIcons.arrowRight, size: 12, color: Theme.of(context).hintColor),
              const SizedBox(width: 8),
              _stepBadge('3', 'Download APK'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBadge(String num, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Dt.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(num,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _projectSummary(BuildContext context, bool isDark) {
    final files = _generatedFiles.keys.toList()..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.folderOpen, size: 16, color: Dt.accent),
              const SizedBox(width: 8),
              Text('${files.length} files',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: _exportZip,
                icon: const Icon(LucideIcons.download, size: 14),
                label: const Text('Export ZIP'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...files.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_iconForFile(f),
                        size: 12,
                        color: Dt.accent.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f,
                          style: GoogleFonts.firaCode(
                              fontSize: 10.5, color: Theme.of(context).hintColor)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Files pane ─────────────────────────────────────────────────────

  Widget _filesPane(BuildContext context, bool isDark) {
    if (_generatedFiles.isEmpty) {
      return Center(
        child: Text('Generate a project to see files here.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: Theme.of(context).hintColor)),
      );
    }

    final paths = _generatedFiles.keys.toList()..sort();
    final root = _buildFileTree(paths);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('${paths.length} files',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        ..._renderTree(context, isDark, root.children, 0),
        if (_openFile != null) ...[
          const SizedBox(height: 16),
          _fileViewer(context, isDark, _openFile!),
        ],
      ],
    );
  }

  _FileNode _buildFileTree(List<String> paths) {
    const root = _FileNode(name: '', path: '', isDir: true, children: []);
    for (final path in paths) {
      final parts = path.split('/');
      _FileNode current = root;
      String currentPath = '';
      for (int i = 0; i < parts.length; i++) {
        final name = parts[i];
        currentPath = currentPath.isEmpty ? name : '$currentPath/$name';
        final isLast = i == parts.length - 1;
        var existing =
            current.children.firstWhereOrNull((n) => n.name == name);
        if (existing == null) {
          existing = _FileNode(
              name: name, path: currentPath, isDir: !isLast, children: []);
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
      BuildContext context, bool isDark, List<_FileNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      final isExpanded = _expandedFolders.contains(node.path);

      items.add(
        InkWell(
          onTap: () {
            if (node.isDir) {
              if (isExpanded) {
                _expandedFolders.remove(node.path);
              } else {
                _expandedFolders.add(node.path);
              }
              setState(() {});
            } else {
              setState(() => _openFile = node.path);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: node.path == _openFile
                    ? Dt.accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border(
                    left: BorderSide(
                        color: depth > 0
                            ? Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.1)
                            : Colors.transparent,
                        width: 1)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    node.isDir
                        ? (isExpanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight)
                        : _iconForFile(node.path),
                    size: node.isDir ? 14 : 14,
                    color: node.isDir
                        ? Theme.of(context).hintColor
                        : Dt.accent,
                  ),
                  if (node.isDir) ...[
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.folder,
                        size: 14, color: Color(0xFFF59E0B)),
                  ],
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight:
                            node.isDir ? FontWeight.w600 : FontWeight.w400,
                        color: node.path == _openFile
                            ? Dt.accent
                            : (isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary),
                      ),
                    ),
                  ),
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

  Widget _fileViewer(BuildContext context, bool isDark, String path) {
    final content = _generatedFiles[path] ?? '';
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(_iconForFile(path), size: 12, color: Dt.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(path.split('/').last,
                      style: GoogleFonts.firaCode(
                          fontSize: 11, color: Colors.white70)),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.copy, size: 12),
                  color: Colors.white54,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    AppSnackbar.showTop('Copied', 'File content copied.');
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                content,
                style: GoogleFonts.firaCode(
                    fontSize: 11, color: Colors.white70, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chat pane ──────────────────────────────────────────────────────

  Widget _chatPane(BuildContext context, bool isDark) {
    return Obx(() {
      if (_chatMsgs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Describe your app and AI will generate the full Android project.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).hintColor),
            ),
          ),
        );
      }
      return ListView.builder(
        controller: _chatScroll,
        padding: const EdgeInsets.all(16),
        itemCount: _chatMsgs.length + (_generating.value ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _chatMsgs.length) {
            return _typingIndicator(isDark);
          }
          final msg = _chatMsgs[i];
          return _chatBubble(context, isDark, msg);
        },
      );
    });
  }

  Widget _chatBubble(BuildContext context, bool isDark, _ChatMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Dt.accent.withValues(alpha: 0.9)
              : (isDark ? AppColors.surface : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: isUser
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Dt.hairline),
        ),
        child: Text(
          msg.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.5,
            color: isUser
                ? Colors.white
                : (isDark ? AppColors.textPrimary : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _typingIndicator(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Dt.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Dt.accent.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 8),
            Text('Generating...',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  // ─── Input bar ──────────────────────────────────────────────────────

  Widget _inputBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(
          top: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Dt.hairline),
                ),
                child: TextField(
                  controller: _promptCtrl,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _selectedTemplate.value == null
                        ? 'Pick a template first...'
                        : 'Describe your Android app...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: Theme.of(context).hintColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _generate(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(() {
              final canSend = _promptCtrl.text.trim().isNotEmpty &&
                  !_generating.value &&
                  _selectedTemplate.value != null;
              return GestureDetector(
                onTap: canSend ? _generate : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: canSend
                        ? Dt.accent
                        : Dt.accent.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.send, size: 16, color: Colors.white),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  IconData _iconForTemplate(String name) {
    switch (name) {
      case 'globe':
        return LucideIcons.globe;
      case 'file':
        return LucideIcons.file;
      case 'stickyNote':
        return LucideIcons.stickyNote;
      case 'checkSquare':
        return LucideIcons.checkSquare;
      case 'calculator':
        return LucideIcons.calculator;
      case 'brainCircuit':
        return LucideIcons.brainCircuit;
      case 'sparkles':
        return LucideIcons.sparkles;
      default:
        return LucideIcons.fileCode2;
    }
  }

  IconData _iconForFile(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.kt')) return LucideIcons.fileCode2;
    if (p.endsWith('.xml')) return LucideIcons.fileCode2;
    if (p.endsWith('.gradle') || p.endsWith('.gradle.kts')) {
      return LucideIcons.settings;
    }
    if (p.endsWith('.json')) return LucideIcons.braces;
    if (p.endsWith('.md')) return LucideIcons.fileText;
    if (p.endsWith('.yml') || p.endsWith('.yaml')) return LucideIcons.fileCode2;
    if (p.endsWith('.gitignore')) return LucideIcons.gitBranch;
    return LucideIcons.file;
  }
}

// ─── Internal models ──────────────────────────────────────────────────────

class _ChatMsg {
  final String role; // user | assistant
  final String text;
  const _ChatMsg({required this.role, required this.text});
}

class _FileNode {
  final String name;
  final String path;
  final bool isDir;
  final List<_FileNode> children;
  const _FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    required this.children,
  });
}
