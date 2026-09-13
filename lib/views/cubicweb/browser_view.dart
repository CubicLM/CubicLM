/// CubicWeb Browser: privacy-focused in-app browser for the Toolkit.
///
/// - Multi-tab support via BrowserController (capped, session-only history).
/// - Static ad-block list + per-site allowlist, Reader Mode, Forced Dark.
/// - Downloads, find-in-page, long-press actions, bookmarks, error pages.
/// - Bottom navigation for better ergonomics.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../controllers/browser_controller.dart';
import '../../services/browser/adblock_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/browser_utils.dart';
import '../../utils/export_file.dart';

class BrowserView extends StatefulWidget {
  const BrowserView({super.key});

  static bool looksLikeSearch(String s) {
    if (s.contains(' ')) return true;
    if (s.contains('://')) return false;
    if (s.contains(':')) return false;
    return !s.contains('.');
  }

  /// Default-engine (DuckDuckGo) search URL. Kept for compatibility;
  /// the view routes through the user's chosen engine instead.
  static String searchUrl(String query) =>
      BrowserSearchEngines.searchUrl(BrowserSearchEngines.defaultId, query);

  static void pushCapped(List<String> stack, String url, [int cap = 50]) {
    stack.add(url);
    while (stack.length > cap) {
      stack.removeAt(0);
    }
  }

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  final BrowserController _browser = Get.find<BrowserController>();
  SettingsController get _settings => Get.find<SettingsController>();

  final _urlCtrl = TextEditingController();
  final _findCtrl = TextEditingController();
  final List<Worker> _workers = [];

  /// Cached ad-block state — refreshed via workers so the per-request
  /// interceptor never calls Get.find (hot path).
  bool _adblockOn = true;
  Set<String> _allowlist = {};

  bool _finding = false;
  double _readerFontSize = 18;

  @override
  void initState() {
    super.initState();
    AdblockService.ensureLoaded();
    _adblockOn = _settings.adblockEnabled.value;
    _allowlist = _settings.browserAllowlist.toSet();
    // Sync URL bar with current tab
    _workers.add(ever(_browser.currentTabIndex, (_) => _syncUrl()));
    _workers.add(ever(_settings.adblockEnabled, (v) => _adblockOn = v));
    _workers.add(ever(
        _settings.browserAllowlist, (_) => _allowlist = _settings.browserAllowlist.toSet()));
    _syncUrl();
  }

  void _syncUrl() {
    final tab = _browser.currentTab;
    if (tab != null && _urlCtrl.text != tab.url.value) {
      _urlCtrl.text = tab.url.value;
    }
  }

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _urlCtrl.dispose();
    _findCtrl.dispose();
    super.dispose();
  }

  void _toast(String title, String message) {
    Get.snackbar(title, message, snackPosition: SnackPosition.BOTTOM);
  }

  String _normalize(String input) {
    var u = input.trim();
    if (u.isEmpty) return u;
    if (!u.contains('://')) u = 'https://$u';
    return u;
  }

  Future<void> _go(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return;
    var url = BrowserView.looksLikeSearch(raw)
        ? BrowserSearchEngines.searchUrl(
            _settings.browserSearchEngine.value, raw)
        : _normalize(raw);

    // HTTPS-only mode: upgrade HTTP to HTTPS
    if (_settings.browserHttpsOnly.value && url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }

    final tab = _browser.currentTab;
    if (tab == null) return;

    // HTTPS-only mode: block plain HTTP navigation
    if (_settings.browserHttpsOnly.value && url.startsWith('http://')) {
      _toast('HTTPS-only', 'This site does not support HTTPS.');
      return;
    }

    Get.focusScope?.unfocus();
    tab.blockedCount.value = 0;
    tab.errorDesc.value = '';
    if (_finding) _stopFind(tab);
    _loadUrl(tab, url);
  }

  Future<void> _loadUrl(WebTab tab, String url) async {
    tab.url.value = url;
    if (_browser.currentTab == tab) _urlCtrl.text = url;
    try {
      final headers = <String, String>{};
      if (_settings.browserDntEnabled.value) {
        headers['DNT'] = '1';
        headers['Sec-GPC'] = '1';
      }
      final req = URLRequest(
        url: WebUri(url),
        headers: headers.isNotEmpty ? headers : null,
      );
      await tab.webController?.loadUrl(urlRequest: req);
    } catch (_) {}
  }

  /// Shared history bookkeeping for onLoadStart + onUpdateVisitedHistory.
  /// The equality guard means the second of the two callbacks is a no-op.
  void _noteNavigation(WebTab tab, String u) {
    if (u.isEmpty || u == 'about:blank' || u == tab.url.value) return;
    if (tab.url.value.isNotEmpty) {
      if (tab.historyNav) {
        if (tab.historyBack) {
          tab.fwdStack.add(tab.url.value);
        } else {
          BrowserView.pushCapped(tab.backStack, tab.url.value);
        }
      } else if (shouldPushHistory(
        current: tab.url.value,
        next: u,
        lastInStack:
            tab.backStack.isEmpty ? null : tab.backStack.last,
      )) {
        BrowserView.pushCapped(tab.backStack, tab.url.value);
        tab.fwdStack.clear();
      }
    }
    tab.url.value = u;
    if (_browser.currentTab == tab) _urlCtrl.text = u;
    tab.historyNav = false;
  }

  Future<void> _goBack(WebTab tab) async {
    if (tab.backStack.isEmpty) return;
    final url = tab.backStack.removeLast();
    tab.historyNav = true;
    tab.historyBack = true;
    tab.blockedCount.value = 0;
    tab.errorDesc.value = '';
    await _loadUrl(tab, url);
  }

  Future<void> _goForward(WebTab tab) async {
    if (tab.fwdStack.isEmpty) return;
    final url = tab.fwdStack.removeLast();
    tab.historyNav = true;
    tab.historyBack = false;
    tab.blockedCount.value = 0;
    tab.errorDesc.value = '';
    await _loadUrl(tab, url);
  }

  Future<void> _reload(WebTab tab) async {
    tab.errorDesc.value = '';
    try {
      await tab.webController?.reload();
    } catch (_) {}
  }

  Future<void> _stop(WebTab tab) async {
    try {
      await tab.webController?.stopLoading();
    } catch (_) {}
    tab.loading.value = false;
    tab.progress.value = 0;
    try {
      await tab.pullCtrl?.endRefreshing();
    } catch (_) {}
  }

  void _goHome(WebTab tab) {
    _browser.resetTab(tab);
    _urlCtrl.clear();
    if (_finding) setState(() => _finding = false);
  }

  bool _adBlocked(String url) {
    if (!_adblockOn) return false;
    if (_allowlist.isNotEmpty &&
        AdblockService.matchesRules(url, _allowlist)) {
      return false;
    }
    return true;
  }

  // ── Extract / Ask AI ──────────────────────────────────────────────

  Future<Map<String, String>?> _extractPage(WebTab tab) async {
    if (tab.url.value.isEmpty) return null;
    try {
      final raw = await tab.webController
          ?.evaluateJavascript(source: AdblockService.extractJs);
      String title = '';
      String text = '';
      if (raw is Map) {
        title = '${raw['title'] ?? ''}';
        text = '${raw['text'] ?? ''}';
      } else if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            title = '${decoded['title'] ?? ''}';
            text = '${decoded['text'] ?? ''}';
          }
        } catch (_) {}
      }
      text = text.trim();
      if (text.isEmpty) return null;
      return {'title': title, 'text': text};
    } catch (_) {
      return null;
    }
  }

  Future<void> _extractToChat(WebTab tab) async {
    final page = await _extractPage(tab);
    if (page == null) {
      _toast('Empty page', 'No readable text found.');
      return;
    }
    if (!Get.isRegistered<ChatController>()) return;
    Get.find<ChatController>()
        .insertBrowserExtract(page['title']!, tab.url.value, page['text']!);
    _toast('Added to chat', 'Page text is in the composer.');
  }

  Future<void> _askAiAboutPage(WebTab tab) async {
    final page = await _extractPage(tab);
    if (page == null) {
      _toast('Empty page', 'No readable text found.');
      return;
    }
    if (!Get.isRegistered<ChatController>()) return;
    Get.find<ChatController>().insertBrowserExtract(
        page['title']!, tab.url.value, '${page['text']!}\n\nMy question: ');
    _toast('Added to chat', 'Page added — type your question.');
  }

  Future<void> _toggleDarkMode(WebTab tab) async {
    final next = !_settings.browserForcedDark.value;
    await _settings.setBrowserForcedDark(next);
    try {
      await tab.webController?.evaluateJavascript(
          source: next ? AdblockService.darkModeJs : AdblockService.lightModeJs);
    } catch (_) {}
  }

  Future<void> _toggleDesktopMode(WebTab tab) async {
    tab.desktopMode.toggle();
    try {
      final ua = tab.desktopMode.value
          ? kDesktopUserAgent
          : (tab.defaultUa ?? '');
      await tab.webController
          ?.setSettings(settings: InAppWebViewSettings(userAgent: ua));
      await tab.webController?.reload();
    } catch (_) {}
    _toast(tab.desktopMode.value ? 'Desktop mode' : 'Mobile mode',
        tab.desktopMode.value ? 'Reloading as desktop…' : 'Reloading…');
  }

  // ── Find in page ──────────────────────────────────────────────────

  void _startFind() => setState(() => _finding = true);

  void _stopFind(WebTab tab) {
    setState(() {
      _finding = false;
      _findCtrl.clear();
    });
    tab.findActive.value = 0;
    tab.findTotal.value = 0;
    try {
      tab.findCtrl?.clearMatches();
    } catch (_) {}
  }

  Future<void> _runFind(WebTab tab, {bool forward = true}) async {
    final q = _findCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      await tab.findCtrl?.findAll(find: q);
      await tab.findCtrl?.findNext(forward: forward);
    } catch (_) {
      _toast('Find in page', 'Not supported on this platform.');
    }
  }

  // ── Downloads ─────────────────────────────────────────────────────

  Future<void> _downloadFile(
    String url, {
    String? suggested,
    String? contentDisposition,
    String? mimeType,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _toast('Download', 'Only http(s) downloads are supported.');
      return;
    }
    final name = downloadFilename(
        suggested: suggested,
        contentDisposition: contentDisposition,
        url: url);
    _toast('Downloading', name);
    try {
      final res =
          await http.get(uri).timeout(const Duration(seconds: 90));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw 'HTTP ${res.statusCode}';
      }
      await ExportFile.quickExport(
        bytes: res.bodyBytes,
        fileName: name,
        mimeType: mimeType,
        shareText: name,
      );
    } catch (e) {
      _toast('Download failed', '$e');
    }
  }

  // ── Share / copy / external ───────────────────────────────────────

  Future<void> _shareLink(String url, {String? title}) async {
    try {
      await Share.share(url.trim(),
          subject: (title ?? '').trim().isEmpty ? null : title!.trim());
    } catch (_) {
      _toast('Share', 'Could not open the share sheet.');
    }
  }

  Future<void> _copyLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url.trim()));
      _toast('Copied', 'Link copied to clipboard.');
    } catch (_) {}
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast('Open externally', 'No app can open this link.');
    } catch (_) {
      _toast('Open externally', 'Could not open this link.');
    }
  }

  void _openInNewTab(String url) {
    final ok = _browser.addTab(url: url);
    if (!ok) {
      _toast('Tab limit', 'Close a tab first (max ${BrowserController.maxTabs}).');
    }
  }

  Future<void> _clearBrowsingData(WebTab? tab) async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    _toast('Browsing data', 'Cookies and cache cleared.');
  }

  // ── Screenshot ──────────────────────────────────────────────────────

  Future<void> _takeScreenshot(WebTab tab) async {
    try {
      final controller = tab.webController;
      if (controller == null) return;
      final screenshot = await controller.takeScreenshot();
      if (screenshot == null || screenshot.isEmpty) {
        _toast('Screenshot', 'Could not capture the page.');
        return;
      }
      await ExportFile.quickExport(
        bytes: screenshot,
        fileName: 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
        mimeType: 'image/png',
        shareText: 'Screenshot',
      );
      _toast('Screenshot', 'Saved.');
    } catch (e) {
      _toast('Screenshot', 'Failed: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(context, isDark),
          if (_finding) _buildFindBar(context, isDark),
          Expanded(
            child: Obx(() {
              final tab = _browser.currentTab;
              if (tab == null) return _emptyState(context, isDark);
              return Stack(children: [
                IndexedStack(
                  index: _browser.currentTabIndex.value,
                  children: _browser.tabs
                      .map((t) => _buildWebView(t, isDark))
                      .toList(),
                ),
                if (tab.url.value.isEmpty)
                  Positioned.fill(
                      child: Container(
                          color: isDark ? Dt.canvasDark : Dt.canvas,
                          child: _emptyState(context, isDark))),
                if (tab.errorDesc.value.isNotEmpty &&
                    tab.url.value.isNotEmpty)
                  Positioned.fill(
                      child: Container(
                          color: isDark ? Dt.canvasDark : Dt.canvas,
                          child: _buildErrorView(context, isDark, tab))),
              ]);
            }),
          ),
          _buildBottomBar(context, isDark),
        ]),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark) {
    final tab = _browser.currentTab;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(bottom: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: Row(children: [
        _buildShieldButton(isDark, tab),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search or enter address',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: _go,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: () => _urlCtrl.clear(),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        Obx(() {
          final loading = tab?.loading.value ?? false;
          return IconButton(
            icon: Icon(loading ? LucideIcons.x : LucideIcons.refreshCw,
                size: 18),
            tooltip: loading ? 'Stop' : 'Reload',
            onPressed: tab == null
                ? null
                : () => loading ? _stop(tab) : _reload(tab),
          );
        }),
      ]),
    );
  }

  /// Scheme indicator + blocked-trackers badge. Taps open the shield sheet.
  Widget _buildShieldButton(bool isDark, WebTab? tab) {
    return Obx(() {
      final url = tab?.url.value ?? '';
      final blocked = tab?.blockedCount.value ?? 0;
      final kind = classifyUrl(url);
      final IconData icon;
      final Color color;
      switch (kind) {
        case BrowserUrlKind.https:
          icon = LucideIcons.lock;
          color = Dt.accent;
          break;
        case BrowserUrlKind.http:
          icon = LucideIcons.alertTriangle;
          color = Colors.orange;
          break;
        case BrowserUrlKind.blank:
        case BrowserUrlKind.other:
          icon = LucideIcons.globe;
          color = Theme.of(context).hintColor;
          break;
      }
      return GestureDetector(
        onTap: tab == null ? null : () => _showShieldSheet(context, isDark, tab),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              if (blocked > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Dt.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      blocked > 99 ? '99+' : '$blocked',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildFindBar(BuildContext context, bool isDark) {
    final tab = _browser.currentTab;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(bottom: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: Row(children: [
        const Icon(LucideIcons.fileSearch, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _findCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Find in page',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => tab == null ? null : _runFind(tab),
          ),
        ),
        if (tab != null)
          Obx(() => tab.findTotal.value > 0
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${tab.findActive.value}/${tab.findTotal.value}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                )
              : const SizedBox.shrink()),
        IconButton(
          icon: const Icon(LucideIcons.arrowUp, size: 18),
          onPressed: tab == null ? null : () => _runFind(tab, forward: false),
        ),
        IconButton(
          icon: const Icon(LucideIcons.arrowDown, size: 18),
          onPressed: tab == null ? null : () => _runFind(tab),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 18),
          onPressed: tab == null ? null : () => _stopFind(tab),
        ),
      ]),
    );
  }

  Widget _buildWebView(WebTab tab, bool isDark) {
    tab.pullCtrl ??= defaultTargetPlatform == TargetPlatform.windows
        ? null
        : PullToRefreshController(
            settings: PullToRefreshSettings(color: Dt.accent),
            onRefresh: () async {
              try {
                await tab.webController?.reload();
              } catch (_) {
                try {
                  await tab.pullCtrl?.endRefreshing();
                } catch (_) {}
              }
            },
          );
    return Stack(
      key: ValueKey(tab.id),
      children: [
        InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            supportZoom: true,
            transparentBackground: false,
            allowsBackForwardNavigationGestures: true,
            useOnDownloadStart: true,
            userAgent:
                tab.desktopMode.value ? kDesktopUserAgent : null,
          ),
          pullToRefreshController: tab.pullCtrl,
          findInteractionController: tab.findCtrl ??=
              FindInteractionController(
            onFindResultReceived:
                (_, activeMatchOrdinal, numberOfMatches, __) {
              tab.findActive.value = activeMatchOrdinal + 1;
              tab.findTotal.value = numberOfMatches;
            },
          ),
          onWebViewCreated: (ctrl) async {
            tab.webController = ctrl;
            try {
              final ua = await ctrl.evaluateJavascript(
                  source: 'navigator.userAgent');
              if (ua is String && ua.isNotEmpty) tab.defaultUa = ua;
            } catch (_) {}
            // Tabs opened with a URL (popups, long-press, deep links)
            // start blank — kick off the pending navigation here.
            final pending = tab.url.value.trim();
            if (pending.isNotEmpty && pending != 'about:blank') {
              try {
                await ctrl.loadUrl(
                    urlRequest: URLRequest(url: WebUri(pending)));
              } catch (_) {}
            }
          },
          shouldInterceptRequest: (controller, request) async {
            if (!_adBlocked(request.url.toString())) return null;
            final url = request.url.toString();
            if (AdblockService.isBlockedUrl(url,
                isMainFrame: request.isForMainFrame ?? false)) {
              tab.blockedCount.value++;
              return WebResourceResponse(
                  contentType: 'text/plain',
                  statusCode: 404,
                  reasonPhrase: 'Blocked');
            }
            return null;
          },
          onLoadStart: (controller, url) {
            tab.errorDesc.value = '';
            final u = url?.toString() ?? '';
            if (u.isNotEmpty && u != 'about:blank') {
              _noteNavigation(tab, u);
            }
            tab.loading.value = true;
          },
          onUpdateVisitedHistory: (controller, url, isReload) {
            final u = url?.toString() ?? '';
            if (u.isNotEmpty && u != 'about:blank') {
              _noteNavigation(tab, u);
            }
          },
          onProgressChanged: (_, progress) =>
              tab.progress.value = progress / 100,
          onTitleChanged: (_, title) {
            if (title != null) tab.title.value = title;
          },
          onLoadStop: (controller, url) async {
            tab.loading.value = false;
            tab.progress.value = 0;
            try {
              await tab.pullCtrl?.endRefreshing();
            } catch (_) {}
            if (_settings.adblockEnabled.value) {
              try {
                await tab.webController?.evaluateJavascript(
                    source: AdblockService.cosmeticJs);
              } catch (_) {}
            }
            if (_settings.browserForcedDark.value) {
              try {
                await tab.webController?.evaluateJavascript(
                    source: AdblockService.darkModeJs);
              } catch (_) {}
            }
            if (tab.errorDesc.value.isEmpty) {
              final u = url?.toString() ?? tab.url.value;
              _browser.recordVisit(tab.title.value, u);
            }
          },
          onReceivedError: (controller, request, error) async {
            try {
              await tab.pullCtrl?.endRefreshing();
            } catch (_) {}
            if (request.isForMainFrame ?? true) {
              tab.loading.value = false;
              tab.progress.value = 0;
              tab.errorDesc.value = error.description.isEmpty
                  ? 'Page could not be loaded.'
                  : error.description;
            }
          },
          onReceivedHttpError: (controller, request, errorResponse) async {
            try {
              await tab.pullCtrl?.endRefreshing();
            } catch (_) {}
            if (request.isForMainFrame ?? true) {
              tab.loading.value = false;
              tab.progress.value = 0;
              tab.errorDesc.value =
                  'HTTP ${errorResponse.statusCode ?? '?'} — page could not be loaded.';
            }
          },
          onCreateWindow: (controller, action) async {
            final url = action.request.url?.toString() ?? '';
            if (url.isEmpty || url == 'about:blank') return false;
            _openInNewTab(url);
            return true;
          },
          onDownloadStartRequest: (controller, request) {
            _downloadFile(
              request.url.toString(),
              suggested: request.suggestedFilename,
              contentDisposition: request.contentDisposition,
              mimeType: request.mimeType,
            );
          },
          onLongPressHitTestResult: (controller, hitTestResult) {
            final extra = (hitTestResult.extra ?? '').trim();
            if (extra.isEmpty) return;
            final isImage =
                hitTestResult.type == InAppWebViewHitTestResultType.IMAGE_TYPE ||
                    hitTestResult.type ==
                        InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
            _showLinkSheet(context, isDark, tab, extra, isImage: isImage);
          },
        ),
        Obx(() => tab.loading.value
            ? LinearProgressIndicator(
                value: tab.progress.value <= 0 || tab.progress.value >= 1
                    ? null
                    : tab.progress.value,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Dt.accent),
              )
            : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildErrorView(BuildContext context, bool isDark, WebTab tab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff,
                size: 56, color: Dt.accent.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('Could not load page',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Obx(() => Text(tab.errorDesc.value,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: Theme.of(context).hintColor))),
            const SizedBox(height: 8),
            Text(tab.url.value,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _reload(tab),
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _openExternal(tab.url.value),
                  icon: const Icon(LucideIcons.externalLink, size: 16),
                  label: const Text('Open externally'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isDark) {
    final tab = _browser.currentTab;
    final iconColor = Theme.of(context).iconTheme.color ?? Dt.accent;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(top: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: Obx(() => Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.chevronLeft),
                onPressed: (tab != null && tab.backStack.isNotEmpty)
                    ? () => _goBack(tab)
                    : null,
              ),
              IconButton(
                icon: const Icon(LucideIcons.chevronRight),
                onPressed: (tab != null && tab.fwdStack.isNotEmpty)
                    ? () => _goForward(tab)
                    : null,
              ),
              IconButton(
                icon: const Icon(LucideIcons.home),
                onPressed: tab == null ? null : () => _goHome(tab),
              ),
              GestureDetector(
                onTap: _showTabSwitcher,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: iconColor, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_browser.tabs.length}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.moreVertical),
                onPressed: () => _showMenu(context, isDark, tab),
              ),
            ],
          )),
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────

  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  BoxDecoration _sheetDecor(bool isDark) => BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      );

  void _showMenu(BuildContext context, bool isDark, WebTab? tab) {
    if (tab == null) return;
    final url = tab.url.value;
    final hasPage = url.isNotEmpty && url != 'about:blank';
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: const Text('Reload'),
                onTap: () {
                  Get.back();
                  _reload(tab);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileSearch),
                title: const Text('Find in page'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _startFind();
                },
              ),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.monitor),
                    title: const Text('Desktop mode'),
                    trailing: Switch(
                      value: tab.desktopMode.value,
                      onChanged: (_) {
                        Get.back();
                        _toggleDesktopMode(tab);
                      },
                    ),
                  )),
              ListTile(
                leading: const Icon(LucideIcons.bookOpen),
                title: const Text('Reader Mode'),
                enabled: hasPage,
                onTap: () async {
                  Get.back();
                  final html = await tab.webController
                      ?.evaluateJavascript(
                          source: AdblockService.readerJs);
                  if (!context.mounted) return;
                  if (html != null && html.toString().isNotEmpty) {
                    _showReaderView(context, isDark, tab, html.toString());
                  } else {
                    _toast('Reader Mode', 'Could not extract article.');
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.clipboardList),
                title: const Text('Extract to Chat'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _extractToChat(tab);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.sparkles),
                title: const Text('Ask AI about page'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _askAiAboutPage(tab);
                },
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.share),
                title: const Text('Share page'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _shareLink(url, title: tab.title.value);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copy link'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _copyLink(url);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.externalLink),
                title: const Text('Open externally'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _openExternal(url);
                },
              ),
              Obx(() {
                final saved = _settings.isBookmarked(url);
                return ListTile(
                  leading: Icon(saved
                      ? LucideIcons.bookmarkMinus
                      : LucideIcons.bookmarkPlus),
                  title:
                      Text(saved ? 'Remove bookmark' : 'Bookmark this page'),
                  enabled: hasPage,
                  onTap: () async {
                    Get.back();
                    if (saved) {
                      await _settings.removeBookmark(url);
                    } else {
                      await _settings.addBookmark(tab.title.value, url);
                      _toast('Bookmarked', 'Saved to bookmarks.');
                    }
                  },
                );
              }),
              ListTile(
                leading: const Icon(LucideIcons.bookMarked),
                title: const Text('Bookmarks'),
                onTap: () {
                  Get.back();
                  _showBookmarksSheet(context, isDark);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.history),
                title: const Text('History (this session)'),
                onTap: () {
                  Get.back();
                  _showHistorySheet(context, isDark);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.search),
                title: const Text('Search engine'),
                subtitle: Obx(() => Text(_engineName(
                    _settings.browserSearchEngine.value))),
                onTap: () {
                  Get.back();
                  _showEngineSheet(context, isDark);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.eraser),
                title: const Text('Clear browsing data'),
                subtitle: const Text('Cookies and cache'),
                onTap: () {
                  Get.back();
                  _clearBrowsingData(tab);
                },
              ),
              const Divider(height: 8),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.shield),
                    title: const Text('Ad-block'),
                    trailing: Switch(
                      value: _settings.adblockEnabled.value,
                      onChanged: (v) =>
                          _settings.setAdblockEnabled(v),
                    ),
                  )),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.moon),
                    title: const Text('Forced Dark Mode'),
                    trailing: Switch(
                      value: _settings.browserForcedDark.value,
                      onChanged: (_) => _toggleDarkMode(tab),
                    ),
                  )),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.camera),
                title: const Text('Screenshot'),
                enabled: hasPage,
                onTap: () {
                  Get.back();
                  _takeScreenshot(tab);
                },
              ),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.lock),
                    title: const Text('HTTPS-only mode'),
                    subtitle: const Text('Block plain HTTP sites'),
                    trailing: Switch(
                      value: _settings.browserHttpsOnly.value,
                      onChanged: (v) => _settings.setBrowserHttpsOnly(v),
                    ),
                  )),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.eyeOff),
                    title: const Text('Do Not Track'),
                    subtitle: const Text('Send DNT + GPC headers'),
                    trailing: Switch(
                      value: _settings.browserDntEnabled.value,
                      onChanged: (v) => _settings.setBrowserDntEnabled(v),
                    ),
                  )),
              Obx(() => ListTile(
                    leading: const Icon(LucideIcons.cookie),
                    title: const Text('Block 3rd-party cookies'),
                    trailing: Switch(
                      value: _settings.browserBlockThirdPartyCookies.value,
                      onChanged: (v) =>
                          _settings.setBrowserBlockThirdPartyCookies(v),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String _engineName(String id) {
    try {
      return BrowserSearchEngines.engines
          .firstWhere((e) => e.id == id)
          .name;
    } catch (_) {
      return 'DuckDuckGo';
    }
  }

  void _showShieldSheet(BuildContext context, bool isDark, WebTab tab) {
    final host = AdblockService.hostOf(tab.url.value) ?? '';
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.shieldCheck),
                  title: const Text('Trackers blocked'),
                  subtitle: host.isEmpty
                      ? null
                      : Text('on $host · this page load'),
                  trailing: Text(
                    '${tab.blockedCount.value}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                )),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.eyeOff),
                  title: const Text('Allow ads on this site'),
                  subtitle: host.isEmpty ? null : Text(host),
                  trailing: Switch(
                    value: host.isNotEmpty &&
                        _settings.isAllowlisted('https://$host/'),
                    onChanged: host.isEmpty
                        ? null
                        : (_) async {
                            final nowOn = await _settings
                                .toggleAllowlist(host);
                            _toast(
                                nowOn ? 'Allowlisted' : 'Blocklisted',
                                nowOn
                                    ? 'Ads allowed on $host.'
                                    : 'Ad-block restored on $host.');
                            _reload(tab);
                          },
                  ),
                )),
            Obx(() => ListTile(
                  leading: const Icon(LucideIcons.shield),
                  title: const Text('Ad-block everywhere'),
                  trailing: Switch(
                    value: _settings.adblockEnabled.value,
                    onChanged: (v) =>
                        _settings.setAdblockEnabled(v),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _showLinkSheet(
      BuildContext context, bool isDark, WebTab tab, String link,
      {bool isImage = false}) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(link,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            ),
            ListTile(
              leading: const Icon(LucideIcons.plus),
              title: const Text('Open in new tab'),
              onTap: () {
                Get.back();
                _openInNewTab(link);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.copy),
              title: const Text('Copy link'),
              onTap: () {
                Get.back();
                _copyLink(link);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.share),
              title: const Text('Share link'),
              onTap: () {
                Get.back();
                _shareLink(link);
              },
            ),
            if (isImage)
              ListTile(
                leading: const Icon(LucideIcons.download),
                title: const Text('Download image'),
                onTap: () {
                  Get.back();
                  _downloadFile(link);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showHistorySheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('History',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Row(children: [
              Text('session only',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Theme.of(context).hintColor)),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                tooltip: 'Clear history',
                onPressed: () => _browser.clearVisits(),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_browser.visits.isEmpty) {
                return Center(
                    child: Text('No pages visited yet this session.',
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _browser.visits.length,
                itemBuilder: (context, i) {
                  final v = _browser.visits[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.globe, size: 18),
                    title: Text(v.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(v.url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(_ago(v.at),
                        style:
                            GoogleFonts.plusJakartaSans(fontSize: 11)),
                    onTap: () {
                      Get.back();
                      _go(v.url);
                    },
                  );
                },
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _showBookmarksSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Bookmarks',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text('saved on this device',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_settings.browserBookmarks.isEmpty) {
                return Center(
                    child: Text(
                        'No bookmarks yet.\nUse ⋮ → Bookmark this page.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _settings.browserBookmarks.length,
                itemBuilder: (context, i) {
                  final b = _settings.browserBookmarks[i];
                  final title = b['title'] ?? '';
                  final url = b['url'] ?? '';
                  return ListTile(
                    dense: true,
                    leading:
                        const Icon(LucideIcons.bookmark, size: 18),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      onPressed: () =>
                          _settings.removeBookmark(url),
                    ),
                    onTap: () {
                      Get.back();
                      _go(url);
                    },
                  );
                },
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _showEngineSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Search engine',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            ...BrowserSearchEngines.engines.map(
              (e) => Obx(() {
                final selected =
                    _settings.browserSearchEngine.value == e.id;
                return ListTile(
                  dense: true,
                  title: Text(e.name),
                  trailing: selected
                      ? const Icon(LucideIcons.check,
                          color: Dt.accent)
                      : null,
                  onTap: () {
                    _settings.setBrowserSearchEngine(e.id);
                    Get.back();
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  void _showReaderView(
      BuildContext context, bool isDark, WebTab tab, String html) {
    Get.to(() => _ReaderPage(
          pageUrl: tab.url.value,
          title: tab.title.value,
          bodyHtml: html,
          isDark: isDark,
          initialFontSize: _readerFontSize,
          onFontSize: (v) => _readerFontSize = v,
        ));
  }

  void _showTabSwitcher() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Dt.canvasDark : Dt.canvas,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Tabs (${_browser.tabs.length}/${BrowserController.maxTabs})',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(LucideIcons.plus),
                onPressed: () {
                  if (!_browser.addTab()) {
                    _toast('Tab limit',
                        'Close a tab first (max ${BrowserController.maxTabs}).');
                    return;
                  }
                  Get.back();
                }),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() => GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _browser.tabs.length,
                  itemBuilder: (context, index) {
                    final t = _browser.tabs[index];
                    final isCurrent =
                        _browser.currentTabIndex.value == index;
                    return GestureDetector(
                      onTap: () {
                        _browser.switchTab(index);
                        Get.back();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Dt.cardDark : Dt.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isCurrent
                                  ? Dt.accent
                                  : Dt.borderColor(isDark),
                              width: 2),
                        ),
                        child: Column(children: [
                          Expanded(
                            child: Center(
                              child: Icon(LucideIcons.globe,
                                  size: 32,
                                  color: Dt.accent.withValues(alpha: 0.3)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black26
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(10)),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Obx(() => Text(t.title.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 10))),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _browser.closeTab(index);
                                  if (_browser.currentTab != null) {
                                    _syncUrl();
                                  }
                                },
                                child:
                                    const Icon(LucideIcons.x, size: 14),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                )),
          ),
          // Recently closed tabs
          Obx(() {
            if (_browser.closedTabs.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recently closed',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    TextButton(
                      onPressed: () {
                        _browser.closedTabs.clear();
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _browser.closedTabs.length.clamp(0, 8),
                    itemBuilder: (context, i) {
                      final closed = _browser.closedTabs[i];
                      return GestureDetector(
                        onTap: () {
                          _browser.reopenClosedTab();
                          Get.back();
                        },
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? Dt.cardDark : Dt.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Dt.borderColor(isDark)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.globe,
                                  size: 18,
                                  color: Dt.accent.withValues(alpha: 0.4)),
                              const SizedBox(height: 4),
                              Text(closed.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }),
        ]),
      ),
    );
  }

  Widget _emptyState(BuildContext context, bool isDark) {
    final quick = [
      ('Wikipedia', 'wikipedia.org', LucideIcons.book),
      ('DuckDuckGo', 'duckduckgo.com', LucideIcons.search),
      ('arXiv', 'arxiv.org', LucideIcons.fileText),
      ('MDN Docs', 'developer.mozilla.org', LucideIcons.code),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Center(
            child: Icon(LucideIcons.globe,
                size: 64, color: Dt.accent.withValues(alpha: 0.2))),
        const SizedBox(height: 24),
        Text('CubicWeb Browser',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            'Privacy-focused browsing with ad-block and local AI extraction.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: Theme.of(context).hintColor)),
        const SizedBox(height: 32),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.2,
          children: quick
              .map((q) => _buildQuickLink(q.$1, q.$2, q.$3, isDark))
              .toList(),
        ),
        Obx(() {
          final tops = _browser.topSites(6);
          if (tops.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              Text('Continue browsing',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('this session only — never saved',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tops
                    .map((e) => ActionChip(
                          label: Text(e.key,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12)),
                          avatar: const Icon(LucideIcons.history,
                              size: 14),
                          onPressed: () => _go('https://${e.key}'),
                        ))
                    .toList(),
              ),
            ],
          );
        }),
        Obx(() {
          final marks = _settings.browserBookmarks.take(5).toList();
          if (marks.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              Text('Bookmarks',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: marks
                    .map((b) => ActionChip(
                          label: Text(b['title'] ?? b['url'] ?? '',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12)),
                          avatar: const Icon(LucideIcons.bookmark,
                              size: 14),
                          onPressed: () => _go(b['url'] ?? ''),
                        ))
                    .toList(),
              ),
            ],
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildQuickLink(
      String name, String url, IconData icon, bool isDark) {
    return GestureDetector(
      onTap: () => _go(url),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Dt.borderColor(isDark)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 28, color: Dt.accent),
          const SizedBox(height: 8),
          Text(name,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Reader-mode page with adjustable font size. Images resolve against the
/// source page via `<base>` (see [readerDocument]).
class _ReaderPage extends StatefulWidget {
  final String pageUrl;
  final String title;
  final String bodyHtml;
  final bool isDark;
  final double initialFontSize;
  final ValueChanged<double> onFontSize;

  const _ReaderPage({
    required this.pageUrl,
    required this.title,
    required this.bodyHtml,
    required this.isDark,
    required this.initialFontSize,
    required this.onFontSize,
  });

  @override
  State<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<_ReaderPage> {
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize.clamp(14, 26);
  }

  void _bump(double delta) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(14, 26);
    });
    widget.onFontSize(_fontSize);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          widget.isDark ? const Color(0xFF262624) : const Color(0xFFF8F4ED),
      appBar: AppBar(
        title: const Text('Reader Mode'),
        actions: [
          IconButton(
            icon: const Text('A-',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            tooltip: 'Smaller text',
            onPressed: () => _bump(-2),
          ),
          IconButton(
            icon: const Text('A+',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            tooltip: 'Larger text',
            onPressed: () => _bump(2),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(widget.title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          Expanded(
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: readerDocument(
                  pageUrl: widget.pageUrl,
                  bodyHtml: widget.bodyHtml,
                  fontSize: _fontSize,
                  isDark: widget.isDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
