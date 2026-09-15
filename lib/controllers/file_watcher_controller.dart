/// CubicLM File Watcher integration — connects [FileWatcher] to UI state.
///
/// Provides an observable list of recent file changes that the agent
/// workspace and terminal views can bind to for live notifications.
library;

import 'dart:async';

import 'package:get/get.dart';

import '../services/workspace/file_watcher.dart';

/// GetxService that exposes live file change events as observable state.
class FileWatcherController extends GetxService {
  final recentChanges = <FileChange>[].obs;
  final isWatching = false.obs;
  Timer? _clearTimer;

  FileWatcher? _watcher;

  /// Start watching [dirPath]. Replaces any previous watch.
  void startWatching(String dirPath) {
    stopWatching();
    _watcher = FileWatcher();
    _watcher!.watch(dirPath, (changes) {
      recentChanges.addAll(changes);
      // Cap at 50 recent changes
      if (recentChanges.length > 50) {
        recentChanges.removeRange(0, recentChanges.length - 50);
      }
      // Auto-clear after 30 seconds of no changes
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(seconds: 30), () {
        recentChanges.clear();
      });
    });
    isWatching.value = true;
  }

  /// Stop watching.
  void stopWatching() {
    _watcher?.stop();
    _watcher = null;
    isWatching.value = false;
    _clearTimer?.cancel();
  }

  /// Clear the change list.
  void clearChanges() {
    recentChanges.clear();
    _clearTimer?.cancel();
  }

  @override
  void onClose() {
    stopWatching();
    super.onClose();
  }
}
