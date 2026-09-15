/// CubicLM Agentic Workspace — GetX controller for the general agent.
///
/// Owns the run lifecycle: prompt → [AgentRunner] event stream → trace UI,
/// plus disk-backed per-file undo/accept via [CheckpointManager] against
/// the run's checkpoint, and checkpoint rollback via [AgentWorkspaceService].
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../services/agent/agent_runner.dart';
import '../services/agent/agent_types.dart';
import '../services/agent_progress_service.dart';
import '../services/agent_workspace.dart';
import '../services/tools/tool_registry.dart';
import '../services/tools/todo_tools.dart';
import '../services/workspace/checkpoint_manager.dart';
import '../services/workspace/workspace_manager.dart';
import '../utils/app_snackbar.dart';

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

  FileDiff _diff = const FileDiff();
  FileDiff get diff => _diff;

  bool _cancelled = false;

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

    // Clear the previous plan so a stale checklist never shows.
    try {
      if (Get.isRegistered<ToolRegistry>()) {
        final tool = Get.find<ToolRegistry>().getTool('todo_write');
        if (tool is TodoWriteTool) tool.current.clear();
      }
    } catch (_) {}

    final pid = projectId.value;
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
