/// CubicLM Agentic Workspace — main agent screen.
///
/// Prompt → general agent loop (cloud or on-device) with a live execution
/// trace, per-file undo/accept, and checkpoint rollback. File tools are
/// jailed to the selected project; pick none to run Q&A without files.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/agent_runner_controller.dart';
import '../../controllers/file_watcher_controller.dart';
import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../services/diff/lcs_diff.dart';
import '../../services/workspace/file_watcher.dart';
import '../../theme/design_tokens.dart';
import 'agent_trace_view.dart';
import 'diff_viewer.dart';

/// Main agent workspace screen (reached from Toolkit → Agent Workspace).
class AgentWorkspaceView extends StatelessWidget {
  const AgentWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<AgentRunnerController>()
        ? Get.find<AgentRunnerController>()
        : Get.put(AgentRunnerController());
    final input = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agent Workspace',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Chats',
            icon: const Icon(Icons.forum_outlined, size: 20),
            onPressed: controller.running.value
                ? null
                : () => _openChatSwitcher(context, controller, input),
          ),
          Obx(() => IconButton(
                tooltip: 'Export project ZIP',
                icon: const Icon(Icons.folder_zip_outlined, size: 20),
                onPressed: controller.projectId.value == null ||
                        controller.running.value
                    ? null
                    : () => controller.exportProjectZip(),
              )),
          Obx(() => Row(
                children: [
                  Text('Local',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                  Switch(
                    value: controller.useLocal.value,
                    activeThumbColor: Dt.accent,
                    onChanged: controller.running.value
                        ? null
                        : (v) => controller.useLocal.value = v,
                  ),
                ],
              )),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _projectPicker(controller),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Obx(() => OutlinedButton.icon(
                        icon: controller.importing.value
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_rounded,
                                size: 16),
                        label: const Text('Import folder'),
                        onPressed: controller.importing.value ||
                                controller.running.value
                            ? null
                            : () => controller.importFolder(),
                      )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Obx(() => Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Plan first',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12)),
                          Switch(
                            value: controller.planMode.value,
                            activeThumbColor: Dt.accent,
                            onChanged: controller.running.value
                                ? null
                                : (v) =>
                                    controller.planMode.value = v,
                          ),
                        ],
                      )),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              minLines: 2,
              maxLines: 5,
              onChanged: (v) => controller.prompt.value = v,
              decoration: InputDecoration(
                hintText:
                    'Describe a task — e.g. "add a settings screen with dark mode toggle"…',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Obx(() => FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: controller.running.value
                        ? AppColors.error
                        : Dt.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(controller.running.value
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(
                    controller.running.value ? 'Stop' : 'Run agent',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    if (controller.running.value) {
                      controller.cancel();
                    } else {
                      controller.prompt.value = input.text;
                      controller.run();
                    }
                  },
                )),
            Obx(() => controller.running.value
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Working… ${controller.elapsed.value}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).hintColor,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink()),
            Obx(() => controller.error.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      controller.error.value!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: AppColors.error),
                    ),
                  )),
            const SizedBox(height: 16),
            Obx(() => controller.todos.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'Plan'),
                      const SizedBox(height: 8),
                      _todoList(context, controller, isDark),
                      const SizedBox(height: 16),
                    ],
                  )),
            _sectionTitle(context, 'Trace'),
            const SizedBox(height: 8),
            Obx(() => AgentTraceView(events: controller.events.toList())),
            const SizedBox(height: 16),
            _fileWatcherSection(context, controller, isDark),
            _sectionTitle(context, 'Changed files'),
            const SizedBox(height: 8),
            Obx(() => _changedFiles(context, controller, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 14, fontWeight: FontWeight.w800),
    );
  }

  Widget _fileWatcherSection(BuildContext context,
      AgentRunnerController controller, bool isDark) {
    return Obx(() {
      final pid = controller.projectId.value;
      // Start/stop watching based on project selection
      if (pid != null && pid.isNotEmpty) {
        _startWatchingIfNeeded(pid);
      } else {
        _stopWatchingIfNeeded();
      }
      final watcher = Get.find<FileWatcherController>();
      final changes = watcher.recentChanges.toList();
      if (changes.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _sectionTitle(context, 'File changes'),
              const Spacer(),
              Text(
                '${changes.length} event${changes.length == 1 ? '' : 's'}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Theme.of(context).hintColor),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => watcher.clearChanges(),
                child: Icon(Icons.close_rounded,
                    size: 14, color: Theme.of(context).hintColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: changes.length,
              itemBuilder: (_, i) {
                final c = changes[i];
                final icon = switch (c.kind) {
                  FileChangeKind.added => Icons.add_circle_outline_rounded,
                  FileChangeKind.modified => Icons.edit_rounded,
                  FileChangeKind.removed => Icons.remove_circle_outline_rounded,
                };
                final color = switch (c.kind) {
                  FileChangeKind.added => Colors.green,
                  FileChangeKind.modified => Dt.accent,
                  FileChangeKind.removed => Colors.red,
                };
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(icon, size: 14, color: color),
                  title: Text(
                    c.path.split('/').last,
                    style: GoogleFonts.firaCode(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    c.path,
                    style: GoogleFonts.firaCode(
                        fontSize: 9, color: Theme.of(context).hintColor),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    });
  }

  void _startWatchingIfNeeded(String projectId) {
    final watcher = Get.find<FileWatcherController>();
    if (watcher.isWatching.value) return;
    // Resolve project directory and start watching
    if (!Get.isRegistered<AgentWorkspaceService>()) return;
    final ws = Get.find<AgentWorkspaceService>();
    ws.dirFor(projectId).then((dir) {
      if (dir.existsSync()) {
        watcher.startWatching(dir.path);
      }
    });
  }

  void _stopWatchingIfNeeded() {
    final watcher = Get.find<FileWatcherController>();
    if (!watcher.isWatching.value) return;
    watcher.stopWatching();
  }

  Widget _projectPicker(AgentRunnerController controller) {
    if (!Get.isRegistered<AgentWorkspaceService>()) {
      return const SizedBox.shrink();
    }
    final ws = Get.find<AgentWorkspaceService>();
    return Obx(() {
      final projects = ws.projects.toList();
      return DropdownButtonFormField<String?>(
        initialValue: controller.projectId.value,
        decoration: InputDecoration(
          labelText: 'Project (optional — file tools jail here)',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(
              value: null, child: Text('No project (Q&A only)')),
          for (final p in projects)
            DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
        ],
        onChanged: controller.running.value
            ? null
            : (v) => controller.selectProject(v),
      );
    });
  }

  /// Chat switcher (Mobile-Harness parity): new / open / delete chats.
  void _openChatSwitcher(BuildContext context,
      AgentRunnerController controller, TextEditingController input) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Obx(() {
          final list = controller.chats.toList();
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New chat'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  controller.newChat();
                  input.clear();
                },
              ),
              const Divider(height: 8),
              if (list.isEmpty)
                const ListTile(title: Text('No chats yet.')),
              for (final c in list)
                ListTile(
                  selected: c.id == controller.activeChatId.value,
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    _chatSubtitle(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete chat',
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () => controller.deleteChat(c.id),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.selectChat(c.id);
                    input.text = controller.prompt.value;
                  },
                ),
            ],
          );
        }),
      ),
    );
  }

  String _chatSubtitle(AgentChat c) {
    final dt =
        DateTime.fromMillisecondsSinceEpoch(c.updatedMs == 0 ? 0 : c.updatedMs);
    final when =
        '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final preview = c.prompt.trim().split('\n').first.trim();
    return preview.isEmpty ? when : '$when · $preview';
  }

  Widget _todoList(BuildContext context,
      AgentRunnerController controller, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          for (final t in controller.todos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    t.status == 'completed'
                        ? Icons.check_circle_rounded
                        : t.status == 'in_progress'
                            ? Icons.play_circle_rounded
                            : Icons.circle_outlined,
                    size: 16,
                    color: t.status == 'completed'
                        ? Colors.green
                        : t.status == 'in_progress'
                            ? Dt.accent
                            : Theme.of(context).hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.content,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.4,
                        decoration: t.status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _changedFiles(BuildContext context,
      AgentRunnerController controller, bool isDark) {
    final files = controller.changedFiles.toList();
    final cpId = controller.checkpointId.value;
    if (files.isEmpty && cpId == null) {
      return Text(
        'No changes yet.',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12, color: Theme.of(context).hintColor),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in files)
          _diffFileCard(context, controller, f, isDark),
        if (files.isNotEmpty || cpId != null)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.undoAll(),
                child: const Text('Undo all'),
              ),
              OutlinedButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.acceptAll(),
                child: const Text('Accept all'),
              ),
              if (cpId != null)
                OutlinedButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.rollbackCheckpoint(),
                  child: const Text('Rollback checkpoint'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _diffFileCard(BuildContext context,
      AgentRunnerController controller, String filePath, bool isDark) {
    return FutureBuilder<List<DiffLine>>(
      future: _computeDiff(controller, filePath),
      builder: (_, snap) {
        final diffLines = snap.data;
        if (diffLines == null || diffLines.isEmpty) {
          // Fallback: simple file name + Accept/Undo
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                Expanded(
                  child: Text(filePath,
                      style: GoogleFonts.firaCode(fontSize: 12)),
                ),
                TextButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.acceptFile(filePath),
                  child: const Text('Accept'),
                ),
                TextButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.undoFile(filePath),
                  child: const Text('Undo'),
                ),
              ],
            ),
          );
        }
        // LCS diff display with Accept/Undo buttons
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DiffViewer(
                filePath: filePath,
                lines: diffLines,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: controller.running.value
                        ? null
                        : () => controller.acceptFile(filePath),
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    onPressed: controller.running.value
                        ? null
                        : () => controller.undoFile(filePath),
                    child: const Text('Undo'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<DiffLine>> _computeDiff(
      AgentRunnerController controller, String filePath) async {
    try {
      final ws = Get.find<AgentWorkspaceService>();
      final cpId = controller.checkpointId.value;
      final pid = controller.projectId.value;
      if (cpId == null || pid == null) return const [];
      // Read old content from checkpoint
      final oldBytes = await ws.readCheckpointFile(pid, cpId, filePath);
      final oldContent = oldBytes != null
          ? String.fromCharCodes(oldBytes)
          : '';
      // Read new content from live workspace
      final newContent = await ws.readFile(pid, filePath) ?? '';
      return buildDiffLines(oldContent, newContent);
    } catch (_) {
      return const [];
    }
  }
}
