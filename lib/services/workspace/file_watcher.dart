/// CubicLM Agentic Workspace — directory watcher with debounce.
///
/// Wraps `Directory.watch()` so previews and the agent UI can auto-reload
/// on external file changes. Ignores hidden paths (`.checkpoints/`) and
/// coalesces bursts into a single callback.
///
/// Pure Dart (`dart:io`) — no Flutter dependencies.
library;

import 'dart:async';
import 'dart:io';

/// What changed on disk.
enum FileChangeKind { added, modified, removed }

/// One coalesced file-system change.
class FileChange {
  final String path;
  final FileChangeKind kind;

  const FileChange({required this.path, required this.kind});
}

/// Watches a directory tree, debounced. Call [dispose] when done.
class FileWatcher {
  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _debounce;
  final _pending = <String, FileChange>{};

  bool get isWatching => _sub != null;

  /// Start watching [dirPath] recursively. [onChanged] fires with the
  /// coalesced batch after [debounce] of quiet time.
  Future<void> watch(
    String dirPath,
    void Function(List<FileChange> changes) onChanged, {
    Duration debounce = const Duration(milliseconds: 800),
  }) async {
    await stop();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    _sub = dir
        .watch(recursive: true)
        .listen((event) {
          if (_isIgnored(event.path)) return;
          _pending[event.path] = FileChange(
            path: event.path,
            kind: _kindOf(event),
          );
          _debounce?.cancel();
          _debounce = Timer(debounce, () {
            final batch = _pending.values.toList();
            _pending.clear();
            if (batch.isNotEmpty) onChanged(batch);
          });
        }, onError: (_) {});
  }

  /// Stop watching (keeps the object reusable).
  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    _pending.clear();
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }

  /// Stop + release. After this the watcher must not be reused.
  Future<void> dispose() => stop();

  static bool _isIgnored(String path) {
    final p = path.replaceAll('\\', '/');
    return p.contains('/.') || p.endsWith('.tmp');
  }

  static FileChangeKind _kindOf(FileSystemEvent event) {
    if (event is FileSystemCreateEvent) return FileChangeKind.added;
    if (event is FileSystemDeleteEvent) return FileChangeKind.removed;
    return FileChangeKind.modified;
  }
}
