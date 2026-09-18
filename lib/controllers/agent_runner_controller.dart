/// CubicLM Agentic Workspace — GetX controller for the general agent.
///
/// Owns the run lifecycle: prompt → [AgentRunner] event stream → trace UI,
/// plus disk-backed per-file undo/accept via [CheckpointManager] against
/// the run's checkpoint, and checkpoint rollback via [AgentWorkspaceService].
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../services/agent/agent_runner.dart';
import '../services/agent/agent_types.dart';
import '../services/agent_progress_service.dart';
import '../services/agent_workspace.dart';
import '../services/app_log_service.dart';
import '../services/tools/tool_registry.dart';
import '../services/tools/todo_tools.dart';
import '../services/workspace/checkpoint_manager.dart';
import '../services/workspace/workspace_manager.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';

/// Directories never included in a project ZIP (Mobile-Harness parity,
/// plus CubicLM-internal state): VCS metadata, dependency installs,
/// build output, agent checkpoints.
const exportZipExcludedPrefixes = {
  '.git/',
  '.claude/',
  '.gradle/',
  'node_modules/',
  'build/',
  '.dart_tool/',
  '.checkpoints/',
};

/// Controller for AgentWorkspaceView (lazy-put by the view).
class AgentRunnerController extends GetxController {
  final prompt = ''.obs;
  final projectId = RxnString();
  final useLocal = false.obs;
  final planMode = false.obs;
  final running = false.obs;
  final importing = false.obs;

  final events = <AgentEvent>[].obs;
  final answer = ''.obs;
  final changedFiles = <String>[].obs;
  final checkpointId = RxnString();
  final error = RxnString();

  /// Chat switcher state (Mobile-Harness multi-chat parity). The null
  /// project (Q&A mode) uses the pseudo-id 'qa'.
  final chats = <AgentChat>[].obs;
  final activeChatId = RxnString();

  static String chatScope(String? pid) =>
      (pid == null || pid.isEmpty) ? 'qa' : pid;

  @override
  void onInit() {
    super.onInit();
    loadChatsFor(projectId.value);
  }

  /// Switch project (loads its chats + prunes abandoned quick ones).
  Future<void> selectProject(String? id) async {
    if (running.value) return;
    projectId.value = id;
    await loadChatsFor(id);
  }

  /// Load chats for a scope; guarantees at least one (fresh) chat.
  Future<void> loadChatsFor(String? pid) async {
    final ws = _ws;
    final scope = chatScope(pid);
    List<AgentChat> loaded = [];
    try {
      if (ws != null) {
        loaded = await ws.loadChats(scope);
        await ws.pruneEmptyProjects();
      }
    } catch (_) {}
    chats.assignAll(loaded);
    if (loaded.isEmpty) {
      await newChat(silent: true);
    } else {
      activeChatId.value = loaded.first.id;
    }
  }

  /// Start a fresh chat (keeps the composer; clears trace display).
  Future<void> newChat({bool silent = false}) async {
    if (running.value) return;
    await _persistCurrentChat();
    final chat = AgentChat(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: 'New chat',
      prompt: '',
      answer: '',
      updatedMs: DateTime.now().millisecondsSinceEpoch,
    );
    chats.insert(0, chat);
    activeChatId.value = chat.id;
    events.clear();
    answer.value = '';
    checkpointId.value = null;
    error.value = null;
    changedFiles.clear();
    _diff = const FileDiff();
    await _saveChats();
    if (!silent) {
      AppSnackbar.showTop('New chat', 'Previous chats stay in the switcher.');
    }
  }

  /// Load a saved chat into the composer + trace display.
  void selectChat(String id) {
    if (running.value) return;
    final i = chats.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final chat = chats[i];
    activeChatId.value = id;
    prompt.value = chat.prompt;
    answer.value = chat.answer;
    events.clear();
    if (chat.answer.isNotEmpty) {
      events.add(AgentEvent.text(chat.answer));
    }
    changedFiles.clear();
    _diff = const FileDiff();
    checkpointId.value = null;
    error.value = null;
  }

  /// Delete a chat (keeps at least one fresh chat around).
  Future<void> deleteChat(String id) async {
    if (running.value) return;
    chats.removeWhere((c) => c.id == id);
    if (activeChatId.value == id) activeChatId.value = null;
    if (chats.isEmpty) {
      await newChat(silent: true);
    } else if (activeChatId.value == null) {
      activeChatId.value = chats.first.id;
    }
    await _saveChats();
  }

  /// Persist the active chat's prompt + answer (called when a run ends
  /// and when leaving a chat). No-op for empty composers.
  Future<void> _persistCurrentChat() async {
    try {
      final text = prompt.value.trim();
      if (text.isEmpty) return;
      final ws = _ws;
      if (ws == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final i = chats.indexWhere((c) => c.id == activeChatId.value);
      if (i < 0) return;
      final chat = chats[i];
      chat.prompt = text;
      chat.answer = answer.value;
      chat.updatedMs = now;
      if (chat.title == 'New chat') {
        chat.title = AgentChat.autoTitle(text);
      }
      chats[i] = chat;
      chats.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      await _saveChats();
    } catch (_) {}
  }

  Future<void> _saveChats() async {
    try {
      await _ws?.saveChats(chatScope(projectId.value), chats.toList());
    } catch (_) {}
  }

  FileDiff _diff = const FileDiff();
  FileDiff get diff => _diff;

  bool _cancelled = false;

  /// Agent-lane logging: trail every run, warning row only on failure
  /// (prompts never enter logs). Never throws.
  void _agentLog(String message, {bool warn = false, Object? details}) {
    try {
      AppLogService.trailAction(message);
      if (warn && Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().warning(
          message,
          details: details,
          category: LogCategory.agent,
        );
      }
    } catch (_) {}
  }

  /// Live elapsed-time counter for the running agent (Mobile-Harness
  /// parity: "Working… 1:23"). Ticks while [running], frozen otherwise.
  final elapsed = ''.obs;
  int? _runStartedMs;
  Timer? _elapsedTimer;

  /// m:ss / h:mm:ss for [ms]. Pure for unit tests.
  static String formatElapsed(int ms) {
    final total = ms < 0 ? 0 : ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
  }

  void _startElapsed() {
    _stopElapsed();
    _runStartedMs = DateTime.now().millisecondsSinceEpoch;
    elapsed.value = formatElapsed(0);
    _elapsedTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _runStartedMs;
      if (start == null) return;
      elapsed.value = formatElapsed(
          DateTime.now().millisecondsSinceEpoch - start);
    });
  }

  void _stopElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  @override
  void onClose() {
    _stopElapsed();
    super.onClose();
  }

  AgentRunner? get _runner =>
      Get.isRegistered<AgentRunner>() ? Get.find<AgentRunner>() : null;

  CheckpointManager? get _checkpoints => Get.isRegistered<CheckpointManager>()
      ? Get.find<CheckpointManager>()
      : null;

  AgentWorkspaceService? get _ws => Get.isRegistered<AgentWorkspaceService>()
      ? Get.find<AgentWorkspaceService>()
      : null;

  AgentProgressService? get _progress =>
      Get.isRegistered<AgentProgressService>()
          ? Get.find<AgentProgressService>()
          : null;

  /// Live task plan (from the agent's todo_write tool, if it ran one).
  List<TodoItem> get todos {
    try {
      if (!Get.isRegistered<ToolRegistry>()) return const [];
      final tool = Get.find<ToolRegistry>().getTool('todo_write');
      if (tool is TodoWriteTool) return tool.current.toList();
    } catch (_) {}
    return const [];
  }

  /// Start a run with the current prompt/project/source.
  Future<void> run() async {
    final runner = _runner;
    if (runner == null) {
      error.value = 'AgentRunner is not running yet. Restart the app.';
      return;
    }
    final text = prompt.value.trim();
    if (text.isEmpty || running.value) return;

    _cancelled = false;
    running.value = true;
    events.clear();
    answer.value = '';
    changedFiles.clear();
    checkpointId.value = null;
    error.value = null;
    _diff = const FileDiff();
    _startElapsed();

    final pid = projectId.value;
    _agentLog('agent run started '
        '(${useLocal.value ? 'local' : 'cloud'}'
        '${pid == null || pid.isEmpty ? ', Q&A' : ', project'})');

    // Clear the previous plan so a stale checklist never shows.
    try {
      if (Get.isRegistered<ToolRegistry>()) {
        final tool = Get.find<ToolRegistry>().getTool('todo_write');
        if (tool is TodoWriteTool) tool.current.clear();
      }
    } catch (_) {}

    await _progress?.showStarted(useLocal.value ? 'Local agent' : 'Agent');

    try {
      final stream = runner.run(
        text,
        config: AgentConfig(
          useLocal: useLocal.value,
          projectId: pid,
          planMode: planMode.value,
        ),
      );
      await for (final event in stream) {
        if (_cancelled) break;
        events.add(event);
        switch (event.kind) {
          case AgentEventKind.text:
            answer.value +=
                (answer.value.isEmpty ? '' : '\n\n') + event.text;
            break;
          case AgentEventKind.reasoning:
            break;
          case AgentEventKind.toolCompleted:
            for (final f in event.modifiedFiles) {
              if (!changedFiles.contains(f)) changedFiles.add(f);
            }
            await _progress?.showProgress(event.toolName);
            break;
          case AgentEventKind.checkpoint:
            checkpointId.value = event.checkpointId;
            break;
          case AgentEventKind.error:
            error.value = event.text;
            break;
          case AgentEventKind.cancelled:
            break;
          case AgentEventKind.toolStarted:
          case AgentEventKind.complete:
            break;
        }
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      running.value = false;
      _stopElapsed();
      if (error.value != null) {
        _agentLog('agent run failed',
            warn: true, details: error.value);
      } else if (_cancelled) {
        AppLogService.trailAction('agent run cancelled');
      } else {
        AppLogService.trailAction('agent run finished');
      }
      await _persistCurrentChat();
      await refreshDiff();
      if (_cancelled) {
        await _progress?.cancel();
      } else if (error.value != null) {
        await _progress?.showFinished('Agent failed');
      } else {
        await _progress?.showFinished('Agent finished');
      }
    }
  }

  /// Request cancellation (checked between loop steps).
  void cancel() {
    _cancelled = true;
    _runner?.cancel();
  }

  /// Re-diff the project against the run's checkpoint baseline.
  Future<void> refreshDiff() async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final cp = _checkpoints;
    if (pid == null || pid.isEmpty || cpId == null || cp == null) return;
    try {
      _diff = await cp.diffAgainstCheckpoint(pid, cpId);
      changedFiles.assignAll(_diff.allChanged);
    } catch (_) {}
  }

  /// Undo one file to its baseline content.
  Future<void> undoFile(String path) async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final cp = _checkpoints;
    if (pid == null || pid.isEmpty || cpId == null || cp == null) return;
    final err = await cp.undoFile(pid, cpId, path);
    if (err == null) {
      await refreshDiff();
    } else {
      error.value = err;
    }
  }

  /// Undo every changed file.
  Future<void> undoAll() async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final cp = _checkpoints;
    if (pid == null || pid.isEmpty || cpId == null || cp == null) return;
    await cp.undoAll(pid, cpId, _diff);
    await refreshDiff();
  }

  /// Accept one file: the baseline follows it, so later undo-all skips it.
  Future<void> acceptFile(String path) async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final cp = _checkpoints;
    if (pid == null || pid.isEmpty || cpId == null || cp == null) return;
    final err = await cp.acceptFile(pid, cpId, path);
    if (err == null) {
      await refreshDiff();
    } else {
      error.value = err;
    }
  }

  /// Accept the current state (baseline follows every changed file).
  Future<void> acceptAll() async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final cp = _checkpoints;
    if (pid == null || pid.isEmpty || cpId == null || cp == null) {
      _diff = const FileDiff();
      changedFiles.clear();
      return;
    }
    await cp.acceptAll(pid, cpId, _diff);
    await refreshDiff();
  }

  /// Roll back the whole project to the pre-run checkpoint.
  Future<void> rollbackCheckpoint() async {
    final pid = projectId.value;
    final cpId = checkpointId.value;
    final ws = _ws;
    if (pid == null || pid.isEmpty || cpId == null || ws == null) return;
    try {
      await ws.rollbackToCheckpoint(pid, cpId);
      await refreshDiff();
    } catch (_) {}
  }

  /// Export the selected project as a ZIP (auto-saved + Share sheet).
  ///
  /// Excludes VCS/dependency/build/checkpoint dirs ([exportZipExcludedPrefixes])
  /// and skips files over 10 MB so one huge asset can't OOM the encoder.
  Future<void> exportProjectZip() async {
    final pid = projectId.value;
    final ws = _ws;
    if (pid == null || pid.isEmpty || ws == null) {
      AppSnackbar.showTop('No project', 'Select a project first.');
      return;
    }
    try {
      final dir = await ws.dirFor(pid);
      final archive = Archive();
      var skipped = 0;
      for (final path in await ws.listFiles(pid)) {
        if (exportZipExcludedPrefixes.any((p) => path.startsWith(p))) {
          continue;
        }
        try {
          final bytes = await File('${dir.path}/$path').readAsBytes();
          if (bytes.length > 10 * 1024 * 1024) {
            skipped++;
            continue;
          }
          archive.addFile(ArchiveFile(path, bytes.length, bytes));
        } catch (_) {
          skipped++;
        }
      }
      if (archive.isEmpty) {
        AppSnackbar.showTop('Nothing to export', 'The project is empty.');
        return;
      }
      final out = ZipEncoder().encode(archive);
      if (out.isEmpty) throw Exception('ZIP encoder returned nothing.');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = pid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(out),
        fileName: 'cubiclm_project_${safeName}_$stamp.zip',
        mimeType: 'application/zip',
        category: 'agent',
      );
      if (skipped > 0) {
        AppSnackbar.showTop(
            'Export done', '$skipped file(s) skipped (too large).');
      }
      AppLogService.trailAction(
          'project exported (ZIP${skipped > 0 ? ', $skipped skipped' : ''})');
    } catch (e) {
      AppSnackbar.showTop('Export failed', '$e');
      _agentLog('project export failed', warn: true, details: '$e');
    }
  }

  /// Import an external folder (SAF picker on Android) as a new project.
  Future<void> importFolder() async {
    if (importing.value || running.value) return;
    if (!Get.isRegistered<WorkspaceManager>()) {
      AppSnackbar.showTop(
          'Unavailable', 'Workspace manager is not running.');
      return;
    }
    importing.value = true;
    try {
      String? dir;
      try {
        dir = await FilePicker.getDirectoryPath(
          dialogTitle: 'Pick a project folder to import',
        );
      } catch (e) {
        AppSnackbar.showTop('Picker failed', '$e');
        return;
      }
      if (dir == null || dir.isEmpty) return; // user cancelled
      final name = dir.split(Platform.pathSeparator).last;
      final project = await Get.find<WorkspaceManager>()
          .importExternalDirectory(dir, name.isEmpty ? 'Imported' : name);
      if (project == null) {
        AppSnackbar.showTop(
            'Import failed', 'Could not read that folder.');
        return;
      }
      projectId.value = project.id;
      AppSnackbar.showTop('Imported', '${project.name} is ready.');
    } finally {
      importing.value = false;
    }
  }
}
