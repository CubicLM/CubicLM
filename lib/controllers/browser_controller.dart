import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// One session-only history entry. Never persisted (privacy by design).
class BrowserVisit {
  final String title;
  final String url;
  final DateTime at;

  BrowserVisit({required this.title, required this.url, DateTime? at})
      : at = at ?? DateTime.now();
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

  final List<String> backStack = [];
  final List<String> fwdStack = [];

  bool historyNav = false;
  bool historyBack = true;

  WebTab({required this.id, String? initialUrl}) {
    if (initialUrl != null) url.value = initialUrl;
  }

  /// Full reset back to a fresh tab (stacks, counters, error, UA flag).
  /// Callers reload `about:blank` through [webController] when present.
  void reset() {
    url.value = '';
    title.value = 'New Tab';
    progress.value = 0.0;
    loading.value = false;
    blockedCount.value = 0;
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

  final tabs = <WebTab>[].obs;
  final currentTabIndex = 0.obs;

  /// Session-only visits, newest first. Never persisted.
  final visits = <BrowserVisit>[].obs;

  WebTab? get currentTab =>
      tabs.isNotEmpty ? tabs[currentTabIndex.value] : null;

  @override
  void onInit() {
    super.onInit();
    // Start with one empty tab if none exist
    if (tabs.isEmpty) {
      addTab();
    }
  }

  /// Adds a tab. Returns false when the tab cap is reached.
  bool addTab({String? url}) {
    if (tabs.length >= maxTabs) return false;
    final newTab = WebTab(id: const Uuid().v4(), initialUrl: url);
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

    tabs.removeAt(index);
    if (currentTabIndex.value >= tabs.length) {
      currentTabIndex.value = tabs.length - 1;
    }
  }

  void switchTab(int index) {
    if (index >= 0 && index < tabs.length) {
      currentTabIndex.value = index;
    }
  }

  /// Record a completed main-frame load (session only, capped, consecutive
  /// duplicates collapsed).
  void recordVisit(String title, String url) {
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
}
