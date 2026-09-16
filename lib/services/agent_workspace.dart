import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'hive_service.dart';

/// Agent-IDE project workspace (MVP: local-first).
///
/// - Metadata lives in Hive settings JSON (`agent_projects`): no new box.
/// - Files live under app documents `agent_projects/<id>/` (OS-sandboxed).
/// - Every path is jailed: absolute, `..`, and oversized writes rejected.
/// - Caps mirror the web-builder parser (30 files / 200KB / 5MB).
class AgentProject {
  final String id;
  String name;
  String framework;
  int updatedMs;

  /// True when the name was auto-generated (quick project): empty ones
  /// are pruned automatically (Mobile-Harness parity).
  bool quick;

  AgentProject({
    required this.id,
    required this.name,
    required this.framework,
    required this.updatedMs,
    this.quick = false,
  });

  factory AgentProject.fromMap(Map m) => AgentProject(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? 'Untitled').toString(),
        framework: (m['framework'] ?? 'Single HTML').toString(),
        updatedMs: (m['updatedMs'] is int)
            ? m['updatedMs'] as int
            : int.tryParse(m['updatedMs'].toString()) ?? 0,
        quick: m['quick'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'framework': framework,
        'updatedMs': updatedMs,
        'quick': quick,
      };
}

/// One saved conversation in a project's chat switcher
/// (Mobile-Harness `ProjectChat` parity: auto-titled, index-persisted).
class AgentChat {
  /// Max chats kept per project.
  static const maxPerProject = 20;

  /// Stored prompt/answer truncation (display + re-run, not full trace).
  static const maxPromptChars = 5000;
  static const maxAnswerChars = 20000;

  final String id;
  String title;
  String prompt;
  String answer;
  int updatedMs;

  AgentChat({
    required this.id,
    required this.title,
    required this.prompt,
    required this.answer,
    required this.updatedMs,
  });

  /// Auto-title from the first user message (42 chars, MH parity).
  static String autoTitle(String prompt) {
    final first = prompt.trim().split('\n').first.trim();
    if (first.isEmpty) return 'New chat';
    return first.length <= 42 ? first : '${first.substring(0, 42)}…';
  }

  factory AgentChat.fromMap(Map m) => AgentChat(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? 'New chat').toString(),
        prompt: (m['prompt'] ?? '').toString(),
        answer: (m['answer'] ?? '').toString(),
        updatedMs: (m['updatedMs'] is int)
            ? m['updatedMs'] as int
            : int.tryParse(m['updatedMs'].toString()) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'prompt': prompt.length > maxPromptChars
            ? prompt.substring(0, maxPromptChars)
            : prompt,
        'answer': answer.length > maxAnswerChars
            ? answer.substring(0, maxAnswerChars)
            : answer,
        'updatedMs': updatedMs,
      };
}
/// A snapshot of project files at a point in time.
class ProjectCheckpoint {
  final String id;
  final String label;
  final int timestampMs;
  final int fileCount;
  final int insertions;
  final int deletions;

  ProjectCheckpoint({
    required this.id,
    required this.label,
    required this.timestampMs,
    required this.fileCount,
    this.insertions = 0,
    this.deletions = 0,
  });

  factory ProjectCheckpoint.fromMap(Map m) => ProjectCheckpoint(
        id: (m['id'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        timestampMs: m['timestampMs'] is int
            ? m['timestampMs'] as int
            : int.tryParse(m['timestampMs'].toString()) ?? 0,
        fileCount: m['fileCount'] is int
            ? m['fileCount'] as int
            : int.tryParse(m['fileCount'].toString()) ?? 0,
        insertions: m['insertions'] ?? 0,
        deletions: m['deletions'] ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'timestampMs': timestampMs,
        'fileCount': fileCount,
        'insertions': insertions,
        'deletions': deletions,
      };
}

/// Quick-project display names (Mobile-Harness parity): a readable
/// `Adjective Pioneer` pair, e.g. "Curious Lovelace".
const _quickAdjectives = [
  'bright',
  'calm',
  'clever',
  'curious',
  'gentle',
  'nimble',
  'quiet',
  'swift',
  'wise',
  'bold',
];

/// Historical computing/science pioneers (no living celebrities).
const _quickPioneers = [
  'turing',
  'lovelace',
  'hopper',
  'tesla',
  'curie',
  'ramanujan',
  'bose',
  'kalam',
  'faraday',
  'darwin',
];

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Generate a unique quick-project name not in [existing] (up to 20
/// tries, then a numeric suffix — same guarantee as the reference app).
/// Pure for unit tests.
String generateQuickProjectName(Set<String> existing, {int? seed}) {
  var nonce = seed ?? DateTime.now().microsecondsSinceEpoch;
  String candidate() {
    final adj = _quickAdjectives[nonce % _quickAdjectives.length];
    nonce ~/= _quickAdjectives.length;
    final pio = _quickPioneers[nonce % _quickPioneers.length];
    nonce = nonce ~/ _quickPioneers.length + 1;
    return '${_titleCase(adj)} ${_titleCase(pio)}';
  }

  var name = candidate();
  for (var i = 0; i < 20 && existing.contains(name); i++) {
    name = candidate();
  }
  if (existing.contains(name)) {
    var n = 2;
    while (existing.contains('$name $n')) {
      n++;
    }
    return '$name $n';
  }
  return name;
}

class AgentWorkspaceService extends GetxService {
  static const _kProjects = 'agent_projects';
  static const maxFiles = 30;
  static const maxFileChars = 200000;
  static const maxTotalChars = 5000000;

  /// File-tree cap (Mobile-Harness parity: 2000 entries).
  static const maxListEntries = 2000;

  /// Viewer truncation (Mobile-Harness parity: 512 KB). Tools, checkpoints,
  /// fork, and export keep using full [readFile]; only UI display goes
  /// through [readFilePreview].
  static const maxPreviewChars = 512 * 1024;

  final projects = <AgentProject>[].obs;

  Future<Directory> get _root async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/agent_projects');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<AgentWorkspaceService> init() async {
    loadProjects();
    return this;
  }

  void loadProjects() {
    try {
      final raw = Get.find<HiveService>().getSetting<List>(_kProjects);
      final list = (raw ?? [])
          .whereType<Map>()
          .map(AgentProject.fromMap)
          .where((p) => p.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      projects.assignAll(list);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await Get.find<HiveService>().setSetting(
          _kProjects, projects.map((p) => p.toMap()).toList());
    } catch (_) {}
  }

  /// Jail + normalize a project-relative path. '' = reject.
  static String sanitize(String raw) {
    var p = raw.trim().replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    final parts = <String>[];
    for (final seg in p.split('/')) {
      final s = seg.trim();
      if (s.isEmpty || s == '.' || s == '..') continue;
      parts.add(s);
    }
    if (parts.isEmpty) return '';
    final joined = parts.join('/');
    if (joined.length > 160) return '';
    return joined;
  }

  Future<Directory> dirFor(String projectId) async {
    final root = await _root;
    return Directory('${root.path}/$projectId');
  }

  Future<AgentProject> createProject(String name, String framework) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final trimmed = name.trim();
    // Empty name → friendly auto-generated identity (quick-project parity).
    final quick = trimmed.isEmpty;
    final display = quick
        ? generateQuickProjectName(projects.map((p) => p.name).toSet())
        : trimmed;
    final p = AgentProject(
      id: id,
      name: display,
      framework: framework,
      updatedMs: DateTime.now().millisecondsSinceEpoch,
      quick: quick,
    );
    await (await dirFor(id)).create(recursive: true);
    projects.insert(0, p);
    await _save();
    return p;
  }

  Future<void> touch(String projectId) async {
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0) return;
    projects[i].updatedMs = DateTime.now().millisecondsSinceEpoch;
    projects.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    await _save();
  }

  Future<void> deleteProject(String projectId) async {
    projects.removeWhere((p) => p.id == projectId);
    await _save();
    try {
      final dir = await dirFor(projectId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> renameProject(String projectId, String name) async {
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0 || name.trim().isEmpty) return;
    projects[i].name = name.trim();
    await _save();
  }

  // ── Chats (switcher parity) ────────────────────────────────────

  static String _chatsKey(String projectId) => 'agent_chats_$projectId';

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  /// Load saved chats for a project, newest first. Never throws.
  Future<List<AgentChat>> loadChats(String projectId) async {
    try {
      final raw = _hive?.getSetting<List>(_chatsKey(projectId));
      final list = (raw ?? [])
          .whereType<Map>()
          .map(AgentChat.fromMap)
          .where((c) => c.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Persist chats (capped at [AgentChat.maxPerProject]). Never throws.
  Future<void> saveChats(String projectId, List<AgentChat> chats) async {
    try {
      final sorted = chats.toList()
        ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      final capped = sorted.take(AgentChat.maxPerProject).toList();
      await _hive?.setSetting(
          _chatsKey(projectId), capped.map((c) => c.toMap()).toList());
    } catch (_) {}
  }

  /// Delete auto-named (quick) projects that have no files and no chats.
  /// Returns the number pruned. Never throws.
  Future<int> pruneEmptyProjects() async {
    var pruned = 0;
    try {
      for (final p in projects.where((p) => p.quick).toList()) {
        final files = await listFiles(p.id);
        if (files.isNotEmpty) continue;
        final chats = await loadChats(p.id);
        if (chats.isNotEmpty) continue;
        projects.removeWhere((q) => q.id == p.id);
        try {
          final dir = await dirFor(p.id);
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
        pruned++;
      }
      if (pruned > 0) await _save();
    } catch (_) {}
    return pruned;
  }

  /// Fork: copy all files (except checkpoints) into a brand-new project.
  /// Returns the fork, or null when the source is gone.
  Future<AgentProject?> forkProject(String projectId) async {
    final i = projects.indexWhere((p) => p.id == projectId);
    if (i < 0) return null;
    final src = projects[i];
    final np = await createProject('${src.name} (fork)', src.framework);
    try {
      for (final f in await listFiles(projectId)) {
        if (f.startsWith('.checkpoints/')) continue;
        final content = await readFile(projectId, f);
        if (content != null) await writeFile(np.id, f, content);
      }
      await saveCheckpoint(np.id, label: 'Forked from ${src.name}');
    } catch (_) {}
    return np;
  }

  Future<String?> writeBinaryFile(
      String projectId, String path, Uint8List bytes) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return 'Rejected path.';
    if (bytes.length > maxFileChars) return 'File too large.';
    try {
      final dir = await dirFor(projectId);
      final files = await listFiles(projectId);
      var total = 0;
      for (final f in files) {
        if (f == clean) continue;
        total += await _fileLength(dir, f);
      }
      if (total + bytes.length > maxTotalChars) {
        return 'Project too large.';
      }
      final out = await _resolveInside(dir, clean);
      if (out == null) return 'Rejected path.';
      await out.parent.create(recursive: true);
      final tmp = File('${out.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await out.exists()) await out.delete();
      await tmp.rename(out.path);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Write (create/overwrite) one file. Returns error string or null.
  Future<String?> writeFile(
      String projectId, String path, String content) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return 'Rejected path.';
    if (content.length > maxFileChars) return 'File too large.';
    try {
      final dir = await dirFor(projectId);
      final files = await listFiles(projectId);
      var total = 0;
      for (final f in files) {
        if (f == clean) continue;
        total += await _fileLength(dir, f);
      }
      if (total + content.length > maxTotalChars) {
        return 'Project too large.';
      }
      final out = await _resolveInside(dir, clean);
      if (out == null) return 'Rejected path.';
      await out.parent.create(recursive: true);
      // Atomic write: crash mid-write must never leave a truncated
      // file behind (same-dir rename is atomic on POSIX, near-atomic
      // on Windows with the delete fallback below).
      final tmp = File(
          '${out.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
      try {
        await tmp.writeAsString(content, flush: true);
        try {
          await tmp.rename(out.path);
        } catch (_) {
          try {
            if (await out.exists()) await out.delete();
          } catch (_) {}
          await tmp.rename(out.path);
        }
      } finally {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
      await touch(projectId);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Resolve [clean] (already [sanitize]d) to a [File] guaranteed inside
  /// [dir]. Returns null when any existing path prefix is a symlink or
  /// the final target resolves outside the project (Mobile-Harness
  /// canonical-path parity). Works for not-yet-existing files too.
  Future<File?> _resolveInside(Directory dir, String clean) async {
    try {
      final base = await dir.resolveSymbolicLinks();
      // Walk segments: every existing prefix must be a real directory —
      // never a symlink (sanitize already removed `..`, so the join
      // cannot escape as long as no prefix is a link).
      var cur = base;
      final segs = clean.split('/');
      for (var i = 0; i < segs.length - 1; i++) {
        cur = '$cur/${segs[i]}';
        final t = await FileSystemEntity.type(cur, followLinks: false);
        if (t == FileSystemEntityType.notFound) break;
        if (t != FileSystemEntityType.directory) return null;
      }
      final f = File('$base/$clean');
      final t = await FileSystemEntity.type(f.path, followLinks: false);
      if (t == FileSystemEntityType.link) return null;
      if (t == FileSystemEntityType.notFound) return f;
      final resolved = await f.resolveSymbolicLinks();
      // Normalize separators (Windows resolves with `\`) and case
      // (Windows + macOS resolve case-insensitively) before comparing.
      String norm(String p) => p.replaceAll('\\', '/');
      var r = norm(resolved);
      var b = norm(base);
      if (Platform.isWindows || Platform.isMacOS) {
        r = r.toLowerCase();
        b = b.toLowerCase();
      }
      if (r != b && !r.startsWith('$b/')) return null;
      return f;
    } catch (_) {
      return null;
    }
  }

  Future<int> _fileLength(Directory dir, String path) async {
    try {
      return await File('${dir.path}/$path').length();
    } catch (_) {
      return 0;
    }
  }

  Future<String?> readFile(String projectId, String path) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return null;
    try {
      final dir = await dirFor(projectId);
      final f = await _resolveInside(dir, clean);
      if (f == null || !await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Truncated read for UI display (Mobile-Harness 512 KB parity).
  ///
  /// Returns a (text, truncated) record; tools/checkpoints keep full
  /// [readFile]. Never throws.
  Future<({String text, bool truncated})> readFilePreview(
    String projectId,
    String path, {
    int maxChars = maxPreviewChars,
  }) async {
    try {
      final full = await readFile(projectId, path) ?? '';
      if (full.length <= maxChars) return (text: full, truncated: false);
      return (
        text: '${full.substring(0, maxChars)}\n… [truncated, showing '
            'first ${maxChars ~/ 1024}KB of ${full.length}]',
        truncated: true,
      );
    } catch (_) {
      return (text: '', truncated: false);
    }
  }

  Future<void> deleteFile(String projectId, String path) async {
    final clean = sanitize(path);
    if (clean.isEmpty) return;
    try {
      final dir = await dirFor(projectId);
      final f = await _resolveInside(dir, clean);
      if (f == null || !await f.exists()) return;
      await f.delete();
      await touch(projectId);
    } catch (_) {}
  }

  Future<void> renameFile(
      String projectId, String oldPath, String newPath) async {
    final o = sanitize(oldPath);
    final n = sanitize(newPath);
    if (o.isEmpty || n.isEmpty || o == n) return;
    try {
      final dir = await dirFor(projectId);
      final src = await _resolveInside(dir, o);
      final dst = await _resolveInside(dir, n);
      if (src == null || dst == null || !await src.exists()) return;
      await dst.parent.create(recursive: true);
      await src.rename(dst.path);
      await touch(projectId);
    } catch (_) {}
  }

  /// Relative file paths, sorted, deepest last. Capped at
  /// [maxListEntries] (Mobile-Harness 2000-entry parity); symlinks are
  /// never listed.
  Future<List<String>> listFiles(String projectId) async {
    try {
      final dir = await dirFor(projectId);
      if (!await dir.exists()) return [];
      final out = <String>[];
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (out.length >= maxListEntries) break;
        try {
          if (FileSystemEntity.isLinkSync(e.path)) continue;
        } catch (_) {
          continue;
        }
        final rel = e.path.substring(dir.path.length + 1).replaceAll('\\', '/');
        if (rel.startsWith('.') || rel.contains('/.')) continue;
        if (e is File) {
          out.add(rel);
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Grep file contents (case-insensitive). Returns path → line numbers.
  Future<Map<String, List<int>>> searchCode(
      String projectId, String query) async {
    final out = <String, List<int>>{};
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return {};
    try {
      final dir = await dirFor(projectId);
      for (final path in await listFiles(projectId)) {
        try {
          final text = await File('${dir.path}/$path').readAsString();
          final hits = <int>[];
          final lines = text.split('\n');
          for (var i = 0; i < lines.length && hits.length < 50; i++) {
            if (lines[i].toLowerCase().contains(q)) hits.add(i + 1);
          }
          if (hits.isNotEmpty) out[path] = hits;
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  /// Import generated files wholesale (bulk write, returns first error).
  Future<String?> importFiles(
      String projectId, Map<String, String> files) async {
    for (final e in files.entries.take(maxFiles)) {
      final err = await writeFile(projectId, e.key, e.value);
      if (err != null) return '${e.key}: $err';
    }
    return null;
  }

  // ── Checkpoints ──

  static const int maxCheckpoints = 20;
  static const _kCheckpoints = 'agent_checkpoints';

  Future<Directory> _checkpointDir(String projectId) async {
    final projectDir = await dirFor(projectId);
    final cpDir = Directory('${projectDir.path}/.checkpoints');
    if (!await cpDir.exists()) await cpDir.create(recursive: true);
    return cpDir;
  }

  Map<String, List<Map>> _allCheckpointMeta() {
    try {
      final raw = Get.find<HiveService>().getSetting<Map>(_kCheckpoints);
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), List<Map>.from(v as List)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCheckpointMeta(
      String projectId, List<Map> list) async {
    try {
      final all = _allCheckpointMeta();
      all[projectId] = list;
      await Get.find<HiveService>().setSetting(_kCheckpoints, all);
    } catch (_) {}
  }

  /// Save a snapshot of all project files. Returns the checkpoint ID.
  Future<String> saveCheckpoint(String projectId,
      {String? label, int insertions = 0, int deletions = 0}) async {
    final cpId = DateTime.now().millisecondsSinceEpoch.toString();
    final cpDir = await _checkpointDir(projectId);
    final targetDir = Directory('${cpDir.path}/$cpId');
    await targetDir.create(recursive: true);

    // Copy all project files into the checkpoint directory.
    final projectDir = await dirFor(projectId);
    var fileCount = 0;
    for (final path in await listFiles(projectId)) {
      try {
        final src = File('${projectDir.path}/$path');
        final dst = File('${targetDir.path}/$path');
        await dst.parent.create(recursive: true);
        await src.copy(dst.path);
        fileCount++;
      } catch (_) {}
    }

    // Save metadata.
    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    list.insert(
        0,
        ProjectCheckpoint(
          id: cpId,
          label: label ?? 'Auto-save',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          fileCount: fileCount,
          insertions: insertions,
          deletions: deletions,
        ).toMap());
    // Prune old checkpoints (keep maxCheckpoints).
    while (list.length > maxCheckpoints) {
      final oldest = list.removeLast();
      try {
        final oldDir = Directory('${cpDir.path}/${oldest['id']}');
        if (await oldDir.exists()) await oldDir.delete(recursive: true);
      } catch (_) {}
    }
    await _saveCheckpointMeta(projectId, list);
    return cpId;
  }

  /// List checkpoints for a project (newest first).
  Future<List<ProjectCheckpoint>> listCheckpoints(String projectId) async {
    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    return list.map(ProjectCheckpoint.fromMap).toList();
  }

  /// Rollback project files to a checkpoint. Returns the number of files restored.
  Future<int> rollbackToCheckpoint(String projectId, String checkpointId) async {
    final cpDir = await _checkpointDir(projectId);
    final srcDir = Directory('${cpDir.path}/$checkpointId');
    if (!await srcDir.exists()) return 0;

    // Clear current project files (except .checkpoints).
    final projectDir = await dirFor(projectId);
    await for (final e in projectDir.list(recursive: false)) {
      if (e is Directory && e.path.endsWith('.checkpoints')) continue;
      try {
        if (e is File) await e.delete();
        if (e is Directory) await e.delete(recursive: true);
      } catch (_) {}
    }

    // Copy checkpoint files back.
    var restored = 0;
    await for (final e in srcDir.list(recursive: true)) {
      if (e is File) {
        final rel = e.path.substring(srcDir.path.length + 1).replaceAll('\\', '/');
        final dst = File('${projectDir.path}/$rel');
        await dst.parent.create(recursive: true);
        await e.copy(dst.path);
        restored++;
      }
    }
    await touch(projectId);
    return restored;
  }

  /// Delete a specific checkpoint.
  Future<void> deleteCheckpoint(String projectId, String checkpointId) async {
    final cpDir = await _checkpointDir(projectId);
    final targetDir = Directory('${cpDir.path}/$checkpointId');
    if (await targetDir.exists()) await targetDir.delete(recursive: true);

    final meta = _allCheckpointMeta();
    final list = meta[projectId] ?? [];
    list.removeWhere((m) => m['id'] == checkpointId);
    await _saveCheckpointMeta(projectId, list);
  }

  // ── Per-file checkpoint access (binary-safe, for CheckpointManager) ──
  //
  // The full-project backup above is the baseline; these helpers read and
  // update single files inside it so the agent UI can undo/accept per file
  // without loading whole projects into memory.

  /// Directory of one checkpoint, or null when it does not exist.
  Future<Directory?> checkpointDirFor(
      String projectId, String checkpointId) async {
    try {
      final cpDir = await _checkpointDir(projectId);
      final clean = sanitize(checkpointId);
      if (clean.isEmpty || clean.contains('/')) return null;
      final dir = Directory('${cpDir.path}/$clean');
      if (!await dir.exists()) return null;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Relative file paths inside one checkpoint (sorted).
  Future<List<String>> listCheckpointFiles(
      String projectId, String checkpointId) async {
    final dir = await checkpointDirFor(projectId, checkpointId);
    if (dir == null) return [];
    try {
      final out = <String>[];
      await for (final e
          in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          out.add(e.path
              .substring(dir.path.length + 1)
              .replaceAll('\\', '/'));
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Read one checkpoint file as bytes (binary-safe). Null when absent.
  Future<Uint8List?> readCheckpointFile(
      String projectId, String checkpointId, String path) async {
    final dir = await checkpointDirFor(projectId, checkpointId);
    if (dir == null) return null;
    final clean = sanitize(path);
    if (clean.isEmpty) return null;
    try {
      final f = File('${dir.path}/$clean');
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Write/overwrite one file inside a checkpoint (accept semantics:
  /// the baseline follows accepted files). Returns error string or null.
  Future<String?> writeCheckpointFile(String projectId, String checkpointId,
      String path, Uint8List bytes) async {
    final dir = await checkpointDirFor(projectId, checkpointId);
    if (dir == null) return 'Checkpoint not found.';
    final clean = sanitize(path);
    if (clean.isEmpty) return 'Rejected path.';
    try {
      final out = File('${dir.path}/$clean');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes, flush: true);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Delete one file inside a checkpoint (accept-of-deletion).
  Future<void> deleteCheckpointFile(
      String projectId, String checkpointId, String path) async {
    final dir = await checkpointDirFor(projectId, checkpointId);
    if (dir == null) return;
    final clean = sanitize(path);
    if (clean.isEmpty) return;
    try {
      final f = File('${dir.path}/$clean');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
