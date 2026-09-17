import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'settings_controller.dart';
import '../services/device_info_service.dart';
import '../services/hive_service.dart';

/// One session-only history entry. Never persisted (privacy by design).
class BrowserVisit {
  final String title;
  final String url;
  final DateTime at;

  BrowserVisit({required this.title, required this.url, DateTime? at})
      : at = at ?? DateTime.now();
}

/// A recently-closed tab snapshot for "reopen closed tab".
class ClosedTab {
  final String url;
  final String title;

  ClosedTab({required this.url, required this.title});
}

class WebTab {
  final String id;
  final RxString url = ''.obs;
  final RxString title = 'New Tab'.obs;
  final RxDouble progress = 0.0.obs;
  final RxBool loading = false.obs;
  final RxInt blockedCount = 0.obs;

  /// Last main-frame load failure, or '' when healthy.
  final RxString errorDesc = ''.obs;

  /// Desktop user-agent override for this tab.
  final RxBool desktopMode = false.obs;

  /// Default UA captured on creation (for reverting desktop mode).
  String? defaultUa;

  InAppWebViewController? webController;

  /// Created lazily by the view (one per tab — never shared).
  PullToRefreshController? pullCtrl;

  /// Find-in-page controller (one per tab) + live match counters.
  FindInteractionController? findCtrl;
  final RxInt findActive = 0.obs;
  final RxInt findTotal = 0.obs;

  final RxBool isIncognito = false.obs;
  final RxList<String> blockedHosts = <String>[].obs;
  final RxList<String> detectedVideos = <String>[].obs;
  final RxString groupName = ''.obs;
  final RxBool isHibernated = false.obs;
  DateTime lastAccessedAt = DateTime.now();

  final List<String> backStack = [];
  final List<String> fwdStack = [];

  bool historyNav = false;
  bool historyBack = true;

  WebTab({required this.id, String? initialUrl, bool incognito = false}) {
    if (initialUrl != null) url.value = initialUrl;
    isIncognito.value = incognito;
  }

  /// Full reset back to a fresh tab (stacks, counters, error, UA flag).
  /// Callers reload `about:blank` through [webController] when present.
  void reset() {
    url.value = '';
    title.value = 'New Tab';
    progress.value = 0.0;
    loading.value = false;
    blockedCount.value = 0;
    blockedHosts.clear();
    detectedVideos.clear();
    groupName.value = '';
    isHibernated.value = false;
    lastAccessedAt = DateTime.now();
    errorDesc.value = '';
    desktopMode.value = false;
    findActive.value = 0;
    findTotal.value = 0;
    backStack.clear();
    fwdStack.clear();
    historyNav = false;
    historyBack = true;
  }
}

class BrowserController extends GetxController {
  /// Hard cap: every tab keeps a live native WebView (IndexedStack), so
  /// unbounded tabs OOM low-RAM devices.
  static const int maxTabs = 10;

  /// Session history cap (in-memory only, never persisted).
  static const int maxVisits = 100;

  /// Recently closed tabs cap.
  static const int maxClosedTabs = 15;

  final tabs = <WebTab>[].obs;
  final currentTabIndex = 0.obs;

  /// Session-only visits, newest first. Never persisted.
  final visits = <BrowserVisit>[].obs;

  /// Recently closed tabs (newest first). Session-only.
  final closedTabs = <ClosedTab>[].obs;

  /// Persisted offline pages metadata.
  final offlinePages = <Map<String, dynamic>>[].obs;

  WebTab? get currentTab =>
      tabs.isNotEmpty ? tabs[currentTabIndex.value] : null;

  @override
  void onInit() {
    super.onInit();
    _loadOfflinePages();
    // Start with one empty tab if none exist
    if (tabs.isEmpty) {
      addTab();
    }
    _startHibernationTimer();
  }

  Timer? _hibernationTimer;
  void _startHibernationTimer() {
    _hibernationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkHibernation();
    });
  }

  void _checkHibernation() {
    final settings = Get.find<SettingsController>();
    if (!settings.browserHibernationEnabled.value &&
        !settings.browserLimiterEnabled.value) {
      return;
    }

    final now = DateTime.now();

    // GX Limiter Enforcement
    if (settings.browserLimiterEnabled.value &&
        Get.isRegistered<DeviceInfoService>()) {
      final dev = Get.find<DeviceInfoService>();
      final usedMb = (dev.totalRamGB.value - dev.availableRamGB.value) * 1024;
      if (usedMb > settings.browserRamLimit.value) {
        // If we exceed limit, find the oldest background tab to hibernate
        WebTab? oldest;
        for (var i = 0; i < tabs.length; i++) {
          if (i == currentTabIndex.value) {
            continue;
          }
          final t = tabs[i];
          if (t.isHibernated.value) {
            continue;
          }
          if (oldest == null ||
              t.lastAccessedAt.isBefore(oldest.lastAccessedAt)) {
            oldest = t;
          }
        }
        if (oldest != null) {
          oldest.isHibernated.value = true;
        }
      }
    }

    if (settings.browserHibernationEnabled.value) {
      for (var i = 0; i < tabs.length; i++) {
        if (i == currentTabIndex.value) {
          continue;
        }
        final tab = tabs[i];
        if (tab.isHibernated.value) {
          continue;
        }
        if (tab.url.value.isEmpty || tab.url.value == 'about:blank') {
          continue;
        }

        if (now.difference(tab.lastAccessedAt).inMinutes >= 10) {
          tab.isHibernated.value = true;
        }
      }
    }
  }

  @override
  void onClose() {
    _hibernationTimer?.cancel();
    super.onClose();
  }

  void _loadOfflinePages() {
    final hive = Get.find<HiveService>();
    offlinePages.assignAll(hive.getAllOfflinePages().cast<Map<String, dynamic>>());
  }

  Future<void> saveOfflinePage({
    required String title,
    required String url,
    required String path,
  }) async {
    final id = const Uuid().v4();
    final data = {
      'id': id,
      'title': title.trim().isEmpty ? url : title.trim(),
      'url': url,
      'path': path,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await Get.find<HiveService>().saveOfflinePage(id, data);
    offlinePages.insert(0, data);
  }

  Future<void> deleteOfflinePage(int index) async {
    if (index < 0 || index >= offlinePages.length) return;
    final item = offlinePages[index];
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Get.find<HiveService>().deleteOfflinePage(id);
    offlinePages.removeAt(index);
  }

  /// Adds a tab. Returns false when the tab cap is reached.
  bool addTab({String? url, bool incognito = false}) {
    if (tabs.length >= maxTabs) return false;
    final newTab = WebTab(id: const Uuid().v4(), initialUrl: url, incognito: incognito);
    tabs.add(newTab);
    currentTabIndex.value = tabs.length - 1;
    return true;
  }

  /// Reset [tab] to a fresh state and blank its WebView.
  void resetTab(WebTab tab) {
    tab.reset();
    try {
      tab.webController
          ?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {}
  }

  void closeTab(int index) {
    if (tabs.length <= 1) {
      // Don't close the last tab, just reset it
      resetTab(tabs[0]);
      return;
    }

    // Save to recently closed before removing
    final tab = tabs[index];
    final url = tab.url.value;
    if (url.isNotEmpty && url != 'about:blank') {
      closedTabs.insert(0, ClosedTab(url: url, title: tab.title.value));
      while (closedTabs.length > maxClosedTabs) {
        closedTabs.removeLast();
      }
    }

    tabs.removeAt(index);
    if (currentTabIndex.value >= tabs.length) {
      currentTabIndex.value = tabs.length - 1;
    }
  }

  /// Reopen the most recently closed tab. Returns false if none available.
  bool reopenClosedTab() {
    if (closedTabs.isEmpty) return false;
    final closed = closedTabs.removeAt(0);
    return addTab(url: closed.url);
  }

  void switchTab(int index) {
    if (index >= 0 && index < tabs.length) {
      currentTabIndex.value = index;
      tabs[index].lastAccessedAt = DateTime.now();
      if (tabs[index].isHibernated.value) {
        tabs[index].isHibernated.value = false;
        // Re-load will be handled by the view when it sees isHibernated changing
      }
    }
  }

  void setTabGroup(int index, String group) {
    if (index >= 0 && index < tabs.length) {
      tabs[index].groupName.value = group.trim();
    }
  }

  void moveTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= tabs.length) return;
    if (newIndex < 0 || newIndex >= tabs.length) return;
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    if (currentTabIndex.value == oldIndex) {
      currentTabIndex.value = newIndex;
    } else if (currentTabIndex.value > oldIndex && currentTabIndex.value <= newIndex) {
      currentTabIndex.value--;
    } else if (currentTabIndex.value < oldIndex && currentTabIndex.value >= newIndex) {
      currentTabIndex.value++;
    }
  }

  /// Record a completed main-frame load (session only, capped, consecutive
  /// duplicates collapsed).
  void recordVisit(String title, String url, {bool isIncognito = false}) {
    if (isIncognito) return;
    final u = url.trim();
    if (u.isEmpty || u == 'about:blank') return;
    if (visits.isNotEmpty && visits.first.url == u) {
      if (title.trim().isNotEmpty) {
        visits.first = BrowserVisit(title: title.trim(), url: u);
        visits.refresh();
      }
      return;
    }
    visits.insert(
        0,
        BrowserVisit(
            title: title.trim().isEmpty ? u : title.trim(), url: u));
    while (visits.length > maxVisits) {
      visits.removeLast();
    }
  }

  /// Ranked host → visit-count pairs for the empty-state "continue" strip.
  List<MapEntry<String, int>> topSites(int limit) {
    final counts = <String, int>{};
    for (final v in visits) {
      try {
        final host = Uri.parse(v.url).host.toLowerCase();
        if (host.isEmpty) continue;
        counts[host] = (counts[host] ?? 0) + 1;
      } catch (_) {}
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  void clearVisits() => visits.clear();

  Future<void> privacyBomb() async {
    // 1. Close all tabs
    for (var i = tabs.length - 1; i >= 0; i--) {
      closeTab(i);
    }
    // ensure at least one fresh tab
    if (tabs.isEmpty) addTab();

    // 2. Clear history
    clearVisits();
    closedTabs.clear();

    // 3. Clear cookies & storage (handled via WebView but we can trigger it)
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
  }
}
