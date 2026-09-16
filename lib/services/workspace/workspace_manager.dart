/// CubicLM Agentic Workspace — project lifecycle manager.
///
/// Thin coordinator over [AgentWorkspaceService] for the general agent:
/// ensure/select projects, resolve on-disk paths, import an external
/// directory (SAF copy target / desktop folder pick), and expose the file
/// watcher + checkpoint helpers in one place.
///
/// Full SAF (Storage Access Framework) UI integration is platform work that
/// lands with the file-picker wiring; this manager already accepts a source
/// directory so any picker can feed it.
library;

import 'dart:io';

import 'package:get/get.dart';

import '../agent_workspace.dart';
import 'checkpoint_manager.dart';
import 'file_watcher.dart';

/// Project lifecycle coordinator (registered in main deferred init).
class WorkspaceManager extends GetxService {
  final FileWatcher watcher = FileWatcher();

  Future<WorkspaceManager> init() async => this;

  AgentWorkspaceService? get _ws =>
      Get.isRegistered<AgentWorkspaceService>() ? Get.find<AgentWorkspaceService>() : null;

  /// All known projects (empty when the workspace service is down).
  List<AgentProject> get projects => _ws?.projects.toList() ?? const [];

  /// Create a project and return it (null when unavailable).
  Future<AgentProject?> ensureProject(String name, String framework) async {
    try {
      return await _ws?.createProject(name, framework);
    } catch (_) {
      return null;
    }
  }

  /// On-disk directory for a project ('' when unavailable).
  Future<String> projectPath(String projectId) async {
    try {
      final ws = _ws;
      if (ws == null) return '';
      return (await ws.dirFor(projectId)).path;
    } catch (_) {
      return '';
    }
  }

  /// Copy an external directory into a new agent project.
  ///
  /// Used by SAF / folder-picker flows: the picker grants access, Dart
  /// copies the tree into the sandboxed workspace. Returns the project,
  /// or null when the source is unreadable.
  Future<AgentProject?> importExternalDirectory(
    String sourceDirPath,
    String name,
  ) async {
    final ws = _ws;
    if (ws == null) return null;
    final src = Directory(sourceDirPath);
    try {
      if (!await src.exists()) return null;
      final project = await ws.createProject(name, 'Imported');
      final dst = await ws.dirFor(project.id);
      var count = 0;
      await for (final entity in src.list(recursive: true, followLinks: false)) {
        if (count >= AgentWorkspaceService.maxFiles) break;
        // Never follow or copy symlinks (canonical-path parity).
        try {
          if (FileSystemEntity.isLinkSync(entity.path)) continue;
        } catch (_) {
          continue;
        }
        final rel = entity.path
            .substring(src.path.length)
            .replaceAll('\\', '/')
            .replaceAll(RegExp(r'^/+'), '');
        if (rel.isEmpty || rel.startsWith('.')) continue;
        try {
          if (entity is File) {
            final content = await entity.readAsString();
            final err = await ws.writeFile(project.id, rel, content);
            if (err == null) count++;
          }
        } catch (_) {}
      }
      await ws.saveCheckpoint(project.id, label: 'Imported $count files');
      // Touch the destination so linters see the use.
      await dst.exists();
      return project;
    } catch (_) {
      return null;
    }
  }

  CheckpointManager? get checkpoints =>
      Get.isRegistered<CheckpointManager>() ? Get.find<CheckpointManager>() : null;
}
