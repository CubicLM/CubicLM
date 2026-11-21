/// CubicLM Agentic Workspace — main agent screen (IDE layout).
///
/// OpenCode/Claude-Code-style working view for any imported project:
/// - Chat tab: prompt → general agent loop (cloud or on-device) with a
///   chat-style transcript, expandable tool cards, todo plan, and
///   per-file undo/accept + checkpoint rollback.
/// - Files tab: project tree, read-only viewer, changed-file diffs.
/// - Terminal tab: project-jailed shell through the same RunCommandTool
///   the agent uses (risk-classified + approval gated).
/// - Sidebar (desktop ≥840px): project switcher, import, checkpoints.
///
/// File tools are jailed to the selected project; pick none to run Q&A
/// without files.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/agent_runner_controller.dart';
import '../../controllers/file_watcher_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../services/agent/agent_types.dart';
import '../../services/agent_workspace.dart';
import '../../services/diff/lcs_diff.dart';
import '../../services/inference_service.dart';
import '../../services/tools/todo_tools.dart';
import '../../services/workspace/file_watcher.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/attachment_preview.dart';
import '../../widgets/model_switcher_sheet.dart';
import '../chat/template_sheets.dart' show showAddToChatSheet;
import 'diff_viewer.dart';

part 'agent_workspace_chat.dart';
part 'agent_workspace_files.dart';
part 'agent_workspace_terminal.dart';

/// Main agent workspace screen (reached from Toolkit → Agent Workspace).
class AgentWorkspaceView extends StatefulWidget {
  const AgentWorkspaceView({super.key});

  @override
  State<AgentWorkspaceView> createState() => _AgentWorkspaceViewState();
}

class _AgentWorkspaceViewState extends State<AgentWorkspaceView>
    with SingleTickerProviderStateMixin {
  late final AgentRunnerController controller;

  /// setState bridge for `part` extensions (extensions cannot call the
  /// protected [State.setState] directly).
  void _refresh(VoidCallback fn) {
    if (mounted) setState(fn);
  }
  late final TabController _tabs;
  final _promptCtrl = TextEditingController();
  final _promptFocus = FocusNode();
  final _termCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  final _expandedFolders = <String>{}.obs;
  final _expandedTools = <int>{}.obs;
  final _expandedReasoning = <int>{}.obs;
  String? _openFile;

  bool get isWide => Get.width >= 840;

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<AgentRunnerController>()
        ? Get.find<AgentRunnerController>()
        : Get.put(AgentRunnerController());
    _tabs = TabController(length: 3, vsync: this);
    _promptCtrl.text = controller.prompt.value;
    _promptCtrl.addListener(() => controller.prompt.value = _promptCtrl.text);
    // Mentions inserted from the Files tab land in prompt.value — mirror
    // them into the composer only while the user is not typing.
    controller.prompt.listen((v) {
      if (mounted && !_promptFocus.hasFocus && _promptCtrl.text != v) {
        _promptCtrl.text = v;
      }
    });
    ever(controller.projectId, (_) {
      _expandedFolders.clear();
      _openFile = null;
      controller.openFile.value = null;
      _clearTerm();
      _scrollToBottom();
    });
    ever(controller.events, (_) => _scrollToBottom());
    unawaited(controller.refreshFiles());
    unawaited(controller.refreshCheckpoints());
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _promptCtrl.dispose();
    _promptFocus.dispose();
    _termCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final name = controller.projectId.value == null
              ? 'No project'
              : (Get.find<AgentWorkspaceService>()
                      .projects
                      .firstWhereOrNull(
                          (p) => p.id == controller.projectId.value)
                      ?.name ??
                  'Project');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Agent Workspace',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800)),
              Text(name,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor)),
            ],
          );
        }),
        actions: [
          IconButton(
            tooltip: 'Chats',
            icon: const Icon(Icons.forum_outlined, size: 20),
            onPressed: controller.running.value
                ? null
                : () => _openChatSwitcher(context, controller, _promptCtrl),
          ),
          Obx(() => IconButton(
                tooltip: 'Export project ZIP',
                icon: const Icon(Icons.folder_zip_outlined, size: 20),
                onPressed: controller.projectId.value == null ||
                        controller.running.value
                    ? null
                    : () => controller.exportProjectZip(),
              )),
        ],
      ),
      body: SafeArea(
        top: false,
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 290,
                    child: _sidebar(context, isDark),
                  ),
                  const VerticalDivider(width: 1, color: Dt.hairline),
                  Expanded(
                    child: Column(
                      children: [
                        _tabStrip(context, isDark),
                        Expanded(
                          child: TabBarView(
                            controller: _tabs,
                            children: [
                              _chatPane(context, isDark),
                              _filesPane(context, isDark),
                              _terminalPane(context, isDark),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _tabStrip(context, isDark),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _chatPane(context, isDark),
                        _filesPane(context, isDark),
                        _terminalPane(context, isDark),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabStrip(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161E) : const Color(0xFFF7F7FA),
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Dt.hairline),
        ),
      ),
      child: TabBar(
        controller: _tabs,
        indicatorColor: Dt.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w600),
        labelColor: Dt.accent,
        unselectedLabelColor: Theme.of(context).hintColor,
        tabs: const [
          Tab(text: 'Chat', icon: Icon(LucideIcons.messageSquare, size: 16)),
          Tab(text: 'Files', icon: Icon(LucideIcons.folderTree, size: 16)),
          Tab(text: 'Terminal', icon: Icon(LucideIcons.terminal, size: 16)),
        ],
      ),
    );
  }

  // ── Sidebar (desktop) ────────────────────────────────────────────

  Widget _sidebar(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _projectCard(context, isDark),
          const SizedBox(height: 12),
          _checkpointCard(context, isDark),
          const SizedBox(height: 12),
          _watcherCard(context, isDark),
        ],
      ),
    );
  }

  /// Compact project controls shown atop the chat pane on narrow screens.
  Widget _projectBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: _projectCard(context, isDark),
    );
  }

  Widget _projectCard(BuildContext context, bool isDark) {
    final ws = Get.find<AgentWorkspaceService>();
    return Obx(() {
      final projects = ws.projects.toList();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: _cardBox(context, isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.folderOpen, size: 15, color: Dt.accent),
                const SizedBox(width: 8),
                Text('Project',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (controller.importing.value)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: controller.projectId.value,
              isDense: true,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'File tools jail here',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('No project (Q&A only)')),
                for (final p in projects)
                  DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: controller.running.value
                  ? null
                  : (v) => controller.selectProject(v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Import folder',
                        style: TextStyle(fontSize: 12)),
                    onPressed: controller.importing.value ||
                            controller.running.value
                        ? null
                        : () => controller.importFolder(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8)),
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    label: const Text('Rescan',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => controller.refreshFiles(),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _checkpointCard(BuildContext context, bool isDark) {
    if (controller.projectId.value == null) return const SizedBox.shrink();
    return Obx(() {
      final list = controller.checkpoints.toList();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: _cardBox(context, isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.history, size: 15, color: Dt.accent),
                const SizedBox(width: 8),
                Text('Checkpoints',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${list.length}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context).hintColor)),
              ],
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              Text('None yet — one is saved before every agent run.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Theme.of(context).hintColor)),
            for (final cp in list.take(8))
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_outlined, size: 15),
                title: Text(
                  cp.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(cp.timestampMs).toString().substring(0, 16)} · ${cp.fileCount} files',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: Theme.of(context).hintColor),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Restore',
                    icon: const Icon(Icons.restore_rounded,
                        size: 16, color: Dt.accent),
                    onPressed: controller.running.value
                        ? null
                        : () => controller.restoreCheckpoint(cp.id),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 15, color: Colors.red.withValues(alpha: 0.8)),
                    onPressed: controller.running.value
                        ? null
                        : () => controller.deleteCheckpoint(cp.id),
                  ),
                ]),
              ),
          ],
        ),
      );
    });
  }

  Widget _watcherCard(BuildContext context, bool isDark) {
    return Obx(() {
      final pid = controller.projectId.value;
      if (pid != null && pid.isNotEmpty) {
        _startWatchingIfNeeded(pid);
      } else {
        _stopWatchingIfNeeded();
      }
      final watcher = Get.find<FileWatcherController>();
      final changes = watcher.recentChanges.toList();
      if (changes.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: _cardBox(context, isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.activity, size: 15, color: Dt.accent),
                const SizedBox(width: 8),
                Text('File changes',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: () => watcher.clearChanges(),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: Theme.of(context).hintColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final c in changes.take(6))
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  switch (c.kind) {
                    FileChangeKind.added =>
                      Icons.add_circle_outline_rounded,
                    FileChangeKind.modified => Icons.edit_rounded,
                    FileChangeKind.removed =>
                      Icons.remove_circle_outline_rounded,
                  },
                  size: 14,
                  color: switch (c.kind) {
                    FileChangeKind.added => Colors.green,
                    FileChangeKind.modified => Dt.accent,
                    FileChangeKind.removed => Colors.red,
                  },
                ),
                title: Text(
                  c.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.firaCode(fontSize: 11),
                ),
              ),
          ],
        ),
      );
    });
  }

  void _startWatchingIfNeeded(String projectId) {
    final watcher = Get.find<FileWatcherController>();
    if (watcher.isWatching.value) return;
    final ws = Get.find<AgentWorkspaceService>();
    ws.dirFor(projectId).then((dir) {
      if (dir.existsSync()) watcher.startWatching(dir.path);
    });
  }

  void _stopWatchingIfNeeded() {
    final watcher = Get.find<FileWatcherController>();
    if (!watcher.isWatching.value) return;
    watcher.stopWatching();
  }

  BoxDecoration _cardBox(BuildContext context, bool isDark) => BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      );
}
