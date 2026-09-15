/// CubicLM Agentic Workspace — per-file undo/accept for agent runs.
///
/// Full-project checkpoints live in [AgentWorkspaceService] as on-disk
/// file copies (like the reference app). This manager adds the per-file
/// layer on top of that same on-disk baseline:
/// - SHA-256 change detection (binary-safe, streamed — projects are never
///   loaded wholesale into memory),
/// - per-file undo (restore baseline bytes) and accept (baseline follows
///   the accepted file, so later undo-all skips it).
///
/// Map diffs stay pure for unit tests; disk IO delegates to the workspace.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';

import '../agent_workspace.dart';

/// Content snapshot: path → content (null = file did not exist).
/// Kept for the in-memory fallback path + unit tests.
typedef FileSnapshot = Map<String, String?>;

/// Per-file change set between two snapshots.
class FileDiff {
  final List<String> added;
  final List<String> modified;
  final List<String> deleted;

  const FileDiff({
    this.added = const [],
    this.modified = const [],
    this.deleted = const [],
  });

  bool get isEmpty => added.isEmpty && modified.isEmpty && deleted.isEmpty;

  /// Every changed path, sorted.
  List<String> get allChanged =>
      [...added, ...modified, ...deleted]..sort();
}

/// Pure snapshot diff (text snapshots). Public for unit tests.
FileDiff diffSnapshots(FileSnapshot before, FileSnapshot after) {
  final added = <String>[];
  final modified = <String>[];
  final deleted = <String>[];
  final keys = {...before.keys, ...after.keys};
  for (final k in keys) {
    final b = before[k];
    final a = after[k];
    if (b == null && a != null) {
      added.add(k);
    } else if (b != null && a == null) {
      deleted.add(k);
    } else if (b != a) {
      modified.add(k);
    }
  }
  added.sort();
  modified.sort();
  deleted.sort();
  return FileDiff(added: added, modified: modified, deleted: deleted);
}

/// Pure hash-map diff: path → sha256 hex, null = absent.
/// Public for unit tests.
FileDiff diffHashes(Map<String, String?> before, Map<String, String?> after) {
  final added = <String>[];
  final modified = <String>[];
  final deleted = <String>[];
  final keys = {...before.keys, ...after.keys};
  for (final k in keys) {
    final b = before[k];
    final a = after[k];
    if (b == null && a != null) {
      added.add(k);
    } else if (b != null && a == null) {
      deleted.add(k);
    } else if (b != a) {
      modified.add(k);
    }
  }
  added.sort();
  modified.sort();
  deleted.sort();
  return FileDiff(added: added, modified: modified, deleted: deleted);
}

/// SHA-256 hex of bytes. Public for unit tests.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// SHA-256 hex of a file, read in full (binary-safe).
/// Throws when the file cannot be read.
Future<String> sha256File(File file) async {
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
}

/// Service wrapper around [AgentWorkspaceService] for snapshot IO.
class CheckpointManager extends GetxService {
  Future<CheckpointManager> init() async => this;

  AgentWorkspaceService? get _ws =>
      Get.isRegistered<AgentWorkspaceService>() ? Get.find<AgentWorkspaceService>() : null;

  // ── Hash snapshots (disk, binary-safe) ───────────────────────────

  /// SHA-256 per project file: path → hex digest.
  Future<Map<String, String>> hashCurrent(String projectId) async {
    final ws = _ws;
    if (ws == null) return {};
    final out = <String, String>{};
    try {
      final dir = await ws.dirFor(projectId);
      for (final path in await ws.listFiles(projectId)) {
        try {
          out[path] = await sha256File(File('${dir.path}/$path'));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// SHA-256 per checkpoint file. Null when the checkpoint is gone.
  Future<Map<String, String>?> hashSnapshot(
      String projectId, String checkpointId) async {
    final ws = _ws;
    if (ws == null) return null;
    final dir = await ws.checkpointDirFor(projectId, checkpointId);
    if (dir == null) return null;
    final out = <String, String>{};
    try {
      for (final path
          in await ws.listCheckpointFiles(projectId, checkpointId)) {
        try {
          out[path] = await sha256File(File('${dir.path}/$path'));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// Diff live files against a checkpoint baseline (binary-safe).
  Future<FileDiff> diffAgainstCheckpoint(
      String projectId, String checkpointId) async {
    final base = await hashSnapshot(projectId, checkpointId);
    if (base == null) return const FileDiff();
    final current = await hashCurrent(projectId);
    return diffHashes(base, current);
  }

  // ── Undo (restore baseline bytes) ────────────────────────────────

  /// Undo one file: restore checkpoint bytes (delete when it was added).
  /// Returns an error string or null on success.
  Future<String?> undoFile(
    String projectId,
    String checkpointId,
    String path,
  ) async {
    final ws = _ws;
    if (ws == null) return 'Workspace unavailable.';
    try {
      final original =
          await ws.readCheckpointFile(projectId, checkpointId, path);
      if (original == null) {
        await ws.deleteFile(projectId, path);
      } else {
        final err = await ws.writeBinaryFile(projectId, path, original);
        if (err != null) return err;
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Undo every changed file. Returns the number restored.
  Future<int> undoAll(
    String projectId,
    String checkpointId,
    FileDiff diff,
  ) async {
    var restored = 0;
    for (final path in diff.allChanged) {
      final err = await undoFile(projectId, checkpointId, path);
      if (err == null) restored++;
    }
    return restored;
  }

  // ── Accept (baseline follows accepted files) ─────────────────────
  //
  // Mirrors the reference app: accepting a file copies the CURRENT content
  // into the baseline, so a later undo-all leaves accepted files alone.

  /// Accept one file into the baseline. Returns error string or null.
  Future<String?> acceptFile(
    String projectId,
    String checkpointId,
    String path,
  ) async {
    final ws = _ws;
    if (ws == null) return 'Workspace unavailable.';
    try {
      final dir = await ws.dirFor(projectId);
      final current = File('${dir.path}/$path');
      if (await current.exists()) {
        final bytes = await current.readAsBytes();
        final err = await ws.writeCheckpointFile(
            projectId, checkpointId, path, bytes);
        if (err != null) return err;
      } else {
        await ws.deleteCheckpointFile(projectId, checkpointId, path);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Accept every changed file into the baseline. Returns the count.
  Future<int> acceptAll(
    String projectId,
    String checkpointId,
    FileDiff diff,
  ) async {
    var accepted = 0;
    for (final path in diff.allChanged) {
      final err = await acceptFile(projectId, checkpointId, path);
      if (err == null) accepted++;
    }
    return accepted;
  }

  // ── Legacy in-memory API (kept for back-compat) ──────────────────

  /// Read every project file into a snapshot map.
  Future<FileSnapshot> takeSnapshot(String projectId) async {
    final ws = _ws;
    if (ws == null) return {};
    final snap = <String, String?>{};
    try {
      for (final path in await ws.listFiles(projectId)) {
        snap[path] = await ws.readFile(projectId, path);
      }
    } catch (_) {}
    return snap;
  }

  /// Diff two snapshots.
  FileDiff diff(FileSnapshot before, FileSnapshot after) =>
      diffSnapshots(before, after);
}
