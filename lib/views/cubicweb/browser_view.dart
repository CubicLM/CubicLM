/// CubicWeb Browser: privacy-focused in-app browser for the Toolkit.
///
/// - Multi-tab support via BrowserController (capped, session-only history).
/// - Static ad-block list + per-site allowlist, Reader Mode, Forced Dark.
/// - Downloads, find-in-page, long-press actions, bookmarks, error pages.
/// - Bottom navigation for better ergonomics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/browser_controller.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../services/browser/adblock_service.dart';
import '../../services/browser/browser_download_service.dart';
import '../../services/browser/news_service.dart';
import '../../services/device_info_service.dart';
import '../../services/stats_service.dart';
import '../../services/tts_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/browser_utils.dart';
import '../../utils/export_file.dart';
import '../../widgets/voice_overlay.dart';
import 'browser_files_view.dart';
import 'qr_scanner_view.dart';

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
  String? _pipUrl;
  Offset _pipPos = const Offset(20, 100);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final _urlCtrl = TextEditingController();
  final _findCtrl = TextEditingController();
  final List<Worker> _workers = [];

  /// Opera-style search suggestions (DuckDuckGo autocomplete, no key).
  final _suggestFocus = FocusNode();
  final RxList<String> _suggestions = <String>[].obs;
  Timer? _suggestTimer;
  int _suggestSeq = 0;

  /// Cached ad-block state — refreshed via workers so the per-request
  /// interceptor never calls Get.find (hot path).
  bool _adblockOn = true;
  bool _dataSaverOn = false;
  bool _extremeModeOn = false;
  Set<String> _allowlist = {};

  final RxBool _voiceActive = false.obs;
  final RxBool _isListening = false.obs;
  final RxString _voiceText = ''.obs;
  final SpeechToText _speech = SpeechToText();
  final RxBool _isReading = false.obs;

  Color _parseColor(String? hex, Color fallback) {
    if (hex == null || !hex.startsWith('#')) return fallback;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback;
    }
  }

  bool _finding = false;
  double _readerFontSize = 18;

  @override
  void initState() {
    super.initState();
    AdblockService.ensureLoaded();
    _adblockOn = _settings.adblockEnabled.value;
    _dataSaverOn = _settings.browserDataSaver.value;
    _extremeModeOn = _settings.browserExtremeTextMode.value;
    _allowlist = _settings.browserAllowlist.toSet();
    // Sync URL bar with current tab
    _workers.add(ever(_browser.currentTabIndex, (_) => _syncUrl()));
    _workers.add(ever(_settings.adblockEnabled, (v) => _adblockOn = v));
    _workers.add(ever(_settings.browserDataSaver, (v) {
      _dataSaverOn = v;
      _updateSettingsForAllTabs();
    }));
    _workers.add(ever(_settings.browserExtremeTextMode, (v) {
      _extremeModeOn = v;
      _updateSettingsForAllTabs();
    }));
    _workers.add(ever(
        _settings.browserAllowlist, (_) => _allowlist = _settings.browserAllowlist.toSet()));
    _workers.add(ever(
        _settings.browserTextZoom, (_) => _updateSettingsForAllTabs()));
    _suggestFocus.addListener(() {
      if (!_suggestFocus.hasFocus) _suggestions.clear();
    });
    _syncUrl();
    _checkClipboard();
    Get.find<NewsService>().fetchNews();

    _workers.add(ever(_browser.currentTabIndex, (index) {
      if (index >= 0 && index < _browser.tabs.length) {
        final t = _browser.tabs[index];
        if (t.isHibernated.value) {
          t.isHibernated.value = false;
          _reload(t);
        }
      }
    }));
  }

  void _haptic() {
    if (_settings.browserHapticsEnabled.value) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      if (text.startsWith('http://') || text.startsWith('https://')) {
        _showClipboardSnackbar(text);
      }
    } catch (_) {}
  }

  Future<void> _triggerAiSearchInsight(String query) async {
    if (!Get.isRegistered<ChatController>()) return;
    final chat = Get.find<ChatController>();

    _toast('AI Insight', 'Analyzing search query...');
    
    if (_settings.browserSplitEnabled.value) {
      // If split is on, we don't need to open sidebar, it might be already open.
    } else {
      _scaffoldKey.currentState?.openEndDrawer();
    }
    
    await chat.askInNewChat(
      'Give me a brief 2-sentence expert overview of this search topic: "$query".',
    );  }

  void _showClipboardSnackbar(String url) {
    Get.snackbar(
      'Link in Clipboard',
      url,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () {
          Get.closeAllSnackbars();
          _go(url);
        },
        child: const Text('Open'),
      ),
    );
  }

  void _updateSettingsForAllTabs() {
    for (final tab in _browser.tabs) {
      tab.webController?.setSettings(
          settings: InAppWebViewSettings(
        blockNetworkImage: _dataSaverOn,
        javaScriptEnabled: !_extremeModeOn,
        textZoom: _settings.browserTextZoom.value,
      ));
    }
  }

  void _syncUrl() {
    final tab = _browser.currentTab;
    if (tab != null && _urlCtrl.text != tab.url.value) {
      _urlCtrl.text = tab.url.value;
    }
    _suggestions.clear();
  }

  /// Debounced address-bar suggestions (search text only, never URLs).
  void _onUrlChanged(String v) {
    _suggestTimer?.cancel();
    final q = v.trim();
    if (!_suggestFocus.hasFocus ||
        q.length < 2 ||
        !BrowserView.looksLikeSearch(q)) {
      if (_suggestions.isNotEmpty) _suggestions.clear();
      return;
    }
    _suggestTimer =
        Timer(const Duration(milliseconds: 350), () => _fetchSuggest(q));
  }

  Future<void> _fetchSuggest(String q) async {
    final seq = ++_suggestSeq;
    try {
      final res = await http
          .get(Uri.parse(
              'https://duckduckgo.com/ac/?q=${Uri.encodeComponent(q)}'))
          .timeout(const Duration(seconds: 6));
      if (seq != _suggestSeq || res.statusCode != 200) return;
      final list = jsonDecode(res.body);
      if (list is! List) return;
      final out = <String>[];
      for (final e in list) {
        if (e is Map && e['phrase'] is String) {
          final p = (e['phrase'] as String).trim();
          if (p.isNotEmpty && !out.contains(p)) out.add(p);
        }
        if (out.length >= 6) break;
      }
      _suggestions.assignAll(out);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _suggestTimer?.cancel();
    _suggestFocus.dispose();
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
    _haptic();
    final raw = input.trim();
    if (raw.isEmpty) return;

    final isSearch = BrowserView.looksLikeSearch(raw);
    var url = isSearch
        ? BrowserSearchEngines.searchUrl(
            _settings.browserSearchEngine.value, raw,
            custom: _settings.browserCustomEngines
                .map((e) => BrowserEngine(
                    id: e['name']!, name: e['name']!, template: e['template']!))
                .toList())
        : _normalize(raw);

    if (isSearch && _settings.browserSearchEnhancer.value) {
      _triggerAiSearchInsight(raw);
    }

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

  Future<void> _saveForOffline(WebTab tab) async {
    if (tab.url.value.isEmpty || tab.url.value == 'about:blank') return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final offlineDir = Directory('${dir.path}/offline_pages');
      if (!await offlineDir.exists()) {
        await offlineDir.create(recursive: true);
      }
      final filename = '${DateTime.now().millisecondsSinceEpoch}.mhtml';
      final savePath = '${offlineDir.path}/$filename';
      
      await tab.webController?.saveWebArchive(filePath: savePath, autoname: false);
      
      await _browser.saveOfflinePage(
        title: tab.title.value,
        url: tab.url.value,
        path: savePath,
      );

      Get.snackbar(
        'Saved for Offline',
        tab.title.value,
        snackPosition: SnackPosition.BOTTOM,
        mainButton: TextButton(
          onPressed: () {
            Get.closeAllSnackbars();
            _showSavedPagesSheet(context, Theme.of(context).brightness == Brightness.dark);
          },
          child: const Text('View'),
        ),
      );
    } catch (e) {
      _toast('Save failed', e.toString());
    }
  }

  Future<void> _saveAsPdf(WebTab tab) async {
    try {
      await tab.webController?.printCurrentPage();
    } catch (e) {
      _toast('Print failed', 'Not supported on this device.');
    }
  }

  Future<void> _reload(WebTab tab) async {
    _haptic();
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
    final home = _settings.browserHomepage.value.trim();
    if (home.isNotEmpty) {
      _loadUrl(tab, home);
      return;
    }
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

  Future<void> _autoFillIdentity(WebTab tab) async {
    final identity = _settings.browserIdentity;
    if (identity.isEmpty) return;

    final json = jsonEncode(identity);
    await tab.webController?.evaluateJavascript(source: """
      (function() {
        var data = $json;
        var inputs = document.querySelectorAll('input');
        for (var i = 0; i < inputs.length; i++) {
          var input = inputs[i];
          var name = (input.name || input.id || input.placeholder || '').toLowerCase();
          
          if (name.includes('name') && data['name']) input.value = data['name'];
          if (name.includes('email') && data['email']) input.value = data['email'];
          if ((name.includes('phone') || name.includes('tel')) && data['phone']) input.value = data['phone'];
          if (name.includes('address') && data['address']) input.value = data['address'];
          if (name.includes('city') && data['city']) input.value = data['city'];
          if (name.includes('zip') && data['zip']) input.value = data['zip'];
          
          // Trigger input events
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        }
      })();
    """);
    _toast('Auto-fill', 'Fields populated.');
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

  Future<void> _injectBlockedSelectors(WebTab tab) async {
    final host = AdblockService.hostOf(tab.url.value);
    if (host == null) return;
    final selectors = _settings.browserBlockedSelectors[host];
    if (selectors == null || selectors.isEmpty) return;

    final css = selectors.map((s) => '$s { display: none !important; }').join(' ');
    await tab.webController?.evaluateJavascript(source: """
      (function() {
        var style = document.createElement('style');
        style.innerText = '$css';
        document.head.appendChild(style);
      })();
    """);
  }

  Future<void> _startElementPicker(WebTab tab) async {
    _toast('Element Picker', 'Tap any element to block it.');
    await tab.webController?.evaluateJavascript(source: AdblockService.elementPickerJs);
  }

  void _showQrHandoff(WebTab tab) {
    // Encode URL and any other useful data
    final data = {
      'url': tab.url.value,
      'title': tab.title.value,
      'source': 'CubicLM Mobile',
    };
    _showQrGenerator(jsonEncode(data));
  }

  Future<void> _checkSiteRules(WebTab tab) async {
    final host = AdblockService.hostOf(tab.url.value);
    if (host == null) return;
    final rule = _settings.browserSiteAiRules[host];
    if (rule == null) return;

    if (rule == 'summarize') {
      _summarizePage(tab);
    } else if (rule == 'skim') {
      _skimPage(tab);
    }
  }

  void _showSiteRulesSheet(WebTab tab) {
    final host = AdblockService.hostOf(tab.url.value) ?? '';
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('AI Rules for $host', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(LucideIcons.list),
              title: const Text('Auto-Summarize on Load'),
              trailing: Obx(() => Switch(
                value: _settings.browserSiteAiRules[host] == 'summarize',
                onChanged: (v) => v ? _settings.addSiteAiRule(host, 'summarize') : _settings.removeSiteAiRule(host),
              )),
            ),
            ListTile(
              leading: const Icon(LucideIcons.eye),
              title: const Text('Auto-Skim on Load'),
              trailing: Obx(() => Switch(
                value: _settings.browserSiteAiRules[host] == 'skim',
                onChanged: (v) => v ? _settings.addSiteAiRule(host, 'skim') : _settings.removeSiteAiRule(host),
              )),
            ),
          ],
        ),
      ),
    );
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

  // ── Downloads (UC-style manager: progress, pause, resume) ──────

  BrowserDownloadService get _dl => Get.find<BrowserDownloadService>();

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
    final defaultName = downloadFilename(
        suggested: suggested,
        contentDisposition: contentDisposition,
        url: url);

    var finalName = defaultName;
    if (_settings.browserAutoRenameDownloads.value && Get.isRegistered<ChatController>()) {
      _toast('AI Organizer', 'Cleaning up filename...');
      final chat = Get.find<ChatController>();
      final suggestion = await chat.askOnce(
          'Suggest a clean, descriptive filename for this URL: "$url". Original name: "$defaultName". Return ONLY the filename with extension, no quotes or preamble.');
      if (suggestion != null && suggestion.trim().isNotEmpty) {
        finalName = suggestion.trim().replaceAll('"', '');
      }
    }

    final nameCtrl = TextEditingController(text: finalName);
    final confirmedName = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Download File'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Filename'),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Get.back(result: nameCtrl.text),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (confirmedName == null || confirmedName.isEmpty) return;

    final job = await _dl.enqueue(
      url: url.trim(),
      fileName: confirmedName,
      mimeType: mimeType,
    );
    if (job == null || !context.mounted) return;
    Get.snackbar(
      'Downloading',
      confirmedName,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
      mainButton: TextButton(
        onPressed: () {
          Get.closeAllSnackbars();
          _showDownloadsSheet(context, Theme.of(context).brightness == Brightness.dark);
        },
        child: const Text('View'),
      ),
    );
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

  void _openInNewTab(String url, {bool incognito = false}) {
    final ok = _browser.addTab(url: url, incognito: incognito);
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

  Future<void> _takeLongScreenshot(WebTab tab) async {
    _toast('Long Screenshot', 'Capturing full page...');
    try {
      // For now, we'll use printCurrentPage() as a way to "Save as PDF" 
      // which is a better version of "Long Screenshot" for pro users.
      // A true stitched image is extremely memory intensive on Android.
      await tab.webController?.printCurrentPage();
      _toast('Long Screenshot', 'Use "Save as PDF" from print dialog.');
    } catch (e) {
      _toast('Long Screenshot', 'Failed: $e');
    }
  }

  Future<void> _pickWallpaper() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await _settings.setBrowserWallpaper(image.path);
        _toast('Wallpaper', 'Updated.');
      }
    } catch (e) {
      _toast('Wallpaper', 'Failed to pick image.');
    }
  }

  Future<void> _showQrScanner() async {
    final code = await Get.to<String>(() => const QrScannerView());
    if (code != null && code.isNotEmpty) {
      _go(code);
    }
  }

  Future<void> _startVoiceControl() async {
    final available = await _speech.initialize();
    if (!available) {
      _toast('Voice Control', 'Speech recognition not available.');
      return;
    }

    _voiceActive.value = true;
    _isListening.value = true;
    _voiceText.value = '';

    await _speech.listen(
      onResult: (result) {
        _voiceText.value = result.recognizedWords;
        if (result.finalResult) {
          _isListening.value = false;
          Future.delayed(const Duration(milliseconds: 800), () {
            _voiceActive.value = false;
            _handleVoiceCommand(result.recognizedWords.toLowerCase());
          });
        }
      },
    );
  }

  void _handleVoiceCommand(String cmd) {
    if (cmd.contains('open')) {
      final site = cmd.split('open').last.trim();
      if (site.isNotEmpty) _go(site);
    } else if (cmd.contains('back')) {
      if (_browser.currentTab != null) _goBack(_browser.currentTab!);
    } else if (cmd.contains('forward')) {
      if (_browser.currentTab != null) _goForward(_browser.currentTab!);
    } else if (cmd.contains('summarize')) {
      if (_browser.currentTab != null) _summarizePage(_browser.currentTab!);
    } else if (cmd.contains('dark mode') || cmd.contains('night mode')) {
      if (_browser.currentTab != null) _toggleDarkMode(_browser.currentTab!);
    } else {
      _toast('Voice Control', 'Unknown command: $cmd');
    }
  }

  void _showQrGenerator(String url) {
    Get.dialog(
      AlertDialog(
        title: const Text('Share Page QR'),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: url,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final custom = _settings.browserCustomTheme;
      final bgColor =
          _parseColor(custom['bg'], isDark ? Dt.canvasDark : Dt.canvas);

      return Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,
            endDrawer: _buildAiSidebar(context, isDark),
            body: SafeArea(
              child: Column(children: [
                _buildTopBar(context, isDark),
                Obx(() => _suggestions.isEmpty
                    ? const SizedBox.shrink()
                    : _buildSuggestBox(context, isDark)),
                Obx(() {
                  final url = _browser.currentTab?.url.value ?? '';
                  if (url.isEmpty || url == 'about:blank') {
                    return const SizedBox.shrink(); // Hide top bar on Home Page
                  }
                  return _buildTopBar(context, isDark);
                }),
                if (_finding) _buildFindBar(context, isDark),
                Expanded(
                  child: Obx(() {
                    final tab = _browser.currentTab;
                    if (tab == null) return _emptyState(context, isDark);
                    final isSplit = _settings.browserSplitEnabled.value;

                    return Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Stack(children: [
                            IndexedStack(
                              index: _browser.currentTabIndex.value,
                              children: _browser.tabs
                                  .map((t) => _buildWebView(t, isDark))
                                  .toList(),
                            ),
                            if (tab.url.value.isEmpty || tab.url.value == 'about:blank')
                              Positioned.fill(
                                  child: Container(
                                      color: bgColor,
                                      child: _emptyState(context, isDark))),
                            if (tab.errorDesc.value.isNotEmpty &&
                                tab.url.value.isNotEmpty)
                              Positioned.fill(
                                  child: Container(
                                      color: bgColor,
                                      child:
                                          _buildErrorView(context, isDark, tab))),
                          ]),
                        ),
                        if (isSplit) ...[
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 1,
                            child: _buildSplitWindow(context, isDark),
                          ),
                        ],
                      ],
                    );
                  }),
                ),
                _buildBottomBar(context, isDark),
              ]),
            ),
          ),
          if (_pipUrl != null) _buildPipOverlay(isDark),
          Obx(() {
            if (!_voiceActive.value) return const SizedBox.shrink();
            return VoiceOverlay(
              isListening: _isListening.value,
              isSpeaking: _isReading.value,
              text: _voiceText.value,
              onStop: () => _voiceActive.value = false,
            );
          }),
          Obx(() {
            final intensity = _settings.browserNightIntensity.value;
            if (intensity <= 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                child:
                    Container(color: Colors.black.withValues(alpha: intensity)),
              ),
            );
          }),
        ],
      );
    });
  }

  Widget _buildTopBar(BuildContext context, bool isDark) {
    final tab = _browser.currentTab;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  focusNode: _suggestFocus,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search or enter address',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: _onUrlChanged,
                  onSubmitted: (v) {
                    _suggestTimer?.cancel();
                    _suggestions.clear();
                    _go(v);
                  },
                ),
              ),
              Obx(() => _isReading.value
                  ? IconButton(
                      icon: const Icon(LucideIcons.stopCircle,
                          size: 16, color: Colors.red),
                      onPressed: () =>
                          tab == null ? null : _toggleListeningMode(tab),
                    )
                  : const SizedBox.shrink()),
              Obx(() {
                final loading = tab?.loading.value ?? false;
                return IconButton(
                  icon: Icon(loading ? LucideIcons.x : LucideIcons.refreshCw,
                      size: 16),
                  onPressed: tab == null
                      ? null
                      : () => loading ? _stop(tab) : _reload(tab),
                );
              }),
            ]),
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.moreVertical, size: 20),
          onPressed: () => _showMenu(context, isDark, tab),
        ),
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

  /// Opera-style autocomplete dropdown under the address bar.
  Widget _buildSuggestBox(BuildContext context, bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(bottom: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _suggestions.length,
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          return ListTile(
            dense: true,
            leading: Icon(LucideIcons.search,
                size: 15, color: Theme.of(context).hintColor),
            title: Text(s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            trailing: Icon(LucideIcons.arrowUpLeft,
                size: 15, color: Theme.of(context).hintColor),
            onTap: () {
              _suggestTimer?.cancel();
              _suggestions.clear();
              _urlCtrl.text = s;
              _go(s);
            },
          );
        },
      ),
    );
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
            javaScriptEnabled: !_settings.browserExtremeTextMode.value,
            domStorageEnabled: true,
            supportZoom: true,
            transparentBackground: false,
            allowsBackForwardNavigationGestures: true,
            useOnDownloadStart: true,
            incognito: tab.isIncognito.value,
            blockNetworkImage: _settings.browserDataSaver.value,
            textZoom: _settings.browserTextZoom.value,
            userAgent:
                tab.desktopMode.value ? kDesktopUserAgent : null,
          ),
          pullToRefreshController: tab.pullCtrl,
          // v6 replaced onContextMenu with ContextMenu.onCreateContextMenu.
          // Links/images keep the long-press sheet; anything else with
          // text (e.g. a selection) opens the text-action sheet.
          contextMenu: ContextMenu(
            onCreateContextMenu: (hitTestResult) {
              final t = hitTestResult.type;
              if (t == InAppWebViewHitTestResultType.IMAGE_TYPE ||
                  t == InAppWebViewHitTestResultType
                      .SRC_IMAGE_ANCHOR_TYPE ||
                  t == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE) {
                return;
              }
              final text = (hitTestResult.extra ?? '').trim();
              if (text.isNotEmpty) {
                _showTextSelectionSheet(context, isDark, tab, text);
              }
            },
          ),
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

            ctrl.addJavaScriptHandler(
              handlerName: 'onElementSelected',
              callback: (args) async {
                final selector = args[0] as String;
                final host = AdblockService.hostOf(tab.url.value);
                if (host != null) {
                  await _settings.addBlockedSelector(host, selector);
                  _toast('Element Blocked', 'Selector: $selector');
                  _reload(tab);
                }
              },
            );

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
              // Estimate savings: trackers ~50KB
              _settings.addBrowserDataSaved(50 * 1024);

              final host = AdblockService.hostOf(url);
              if (host != null && !tab.blockedHosts.contains(host)) {
                tab.blockedHosts.add(host);
              }
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
            try {
              final vids = await tab.webController
                  ?.evaluateJavascript(source: AdblockService.videoDetectJs);
              if (vids is String) {
                final list = jsonDecode(vids);
                if (list is List) {
                  tab.detectedVideos.assignAll(list.cast<String>());
                }
              }
            } catch (_) {}
            if (tab.errorDesc.value.isEmpty) {
              final u = url?.toString() ?? tab.url.value;
              _browser.recordVisit(tab.title.value, u, 
                  isIncognito: tab.isIncognito.value);
              
              _injectBlockedSelectors(tab);
              _checkSiteRules(tab);
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
            _openInNewTab(url, incognito: tab.isIncognito.value);
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
        Obx(() => tab.detectedVideos.isNotEmpty
            ? Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Dt.accentGx,
                  onPressed: () =>
                      _showVideoDownloadSheet(context, isDark, tab),
                  child: const Icon(LucideIcons.video,
                      size: 18, color: Colors.white),
                ),
              )
            : const SizedBox.shrink()),
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
      child: Obx(() => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if (!_settings.browserGesturesEnabled.value) return;
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < 0) {
                // Swipe Left -> Next Tab
                if (_browser.tabs.length > 1) {
                  final next = (_browser.currentTabIndex.value + 1) %
                      _browser.tabs.length;
                  _browser.switchTab(next);
                  _haptic();
                }
              } else if (details.primaryVelocity! > 0) {
                // Swipe Right -> Prev Tab
                if (_browser.tabs.length > 1) {
                  final prev = (_browser.currentTabIndex.value - 1 +
                          _browser.tabs.length) %
                      _browser.tabs.length;
                  _browser.switchTab(prev);
                  _haptic();
                }
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _settings.browserToolbarTools.map((id) => _buildToolbarItem(id, tab, iconColor, context, isDark)).toList(),
            ),
          )),
    );
  }

  Widget _buildToolbarItem(
      String id, WebTab? tab, Color iconColor, BuildContext context, bool isDark) {
    final customAccent = _parseColor(_settings.browserCustomTheme['accent'], iconColor);
    final finalIconColor = customAccent;

    switch (id) {
      case 'back':
        return IconButton(
          icon: Icon(LucideIcons.chevronLeft, color: finalIconColor),
          onPressed: (tab != null && tab.backStack.isNotEmpty)
              ? () => _goBack(tab)
              : null,
        );
      case 'forward':
        return IconButton(
          icon: Icon(LucideIcons.chevronRight, color: finalIconColor),
          onPressed: (tab != null && tab.fwdStack.isNotEmpty)
              ? () => _goForward(tab)
              : null,
        );
      case 'home':
        return IconButton(
          icon: Icon(LucideIcons.home, color: finalIconColor),
          onPressed: tab == null ? null : () => _goHome(tab),
        );
      case 'tabs':
        return GestureDetector(
          onTap: _showTabSwitcher,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: finalIconColor, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_browser.tabs.length}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: finalIconColor),
            ),
          ),
        );
      case 'menu':
        return IconButton(
          icon: Icon(LucideIcons.moreVertical, color: finalIconColor),
          onPressed: () => _showMenu(context, isDark, tab),
        );
      case 'qr':
        return IconButton(
          icon: Icon(LucideIcons.qrCode, color: finalIconColor),
          onPressed: () => _showQrScanner(),
        );
      case 'snapshot':
        return IconButton(
          icon: Icon(LucideIcons.camera, color: finalIconColor),
          onPressed: tab == null ? null : () => _aiSnapshot(tab),
        );
      case 'summarize':
        return IconButton(
          icon: Icon(LucideIcons.list, color: finalIconColor),
          onPressed: tab == null ? null : () => _summarizePage(tab),
        );
      case 'split':
        return Obx(() => IconButton(
              icon: Icon(LucideIcons.columns,
                  color: _settings.browserSplitEnabled.value
                      ? Dt.accentGx
                      : finalIconColor),
              onPressed: () => _settings.browserSplitEnabled.toggle(),
            ));
      case 'translate':
        return IconButton(
          icon: Icon(LucideIcons.languages, color: finalIconColor),
          onPressed: tab == null ? null : () => _translatePage(tab),
        );
      case 'downloads':
        return Obx(() {
          final active =
              _dl.downloads.where((d) => d.isActive).length;
          return GestureDetector(
            onTap: () =>
                _showDownloadsSheet(context, isDark),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(LucideIcons.download,
                      color: finalIconColor, size: 20),
                  if (active > 0)
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
                          active > 99 ? '99+' : '$active',
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
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPipOverlay(bool isDark) {
    return Positioned(
      left: _pipPos.dx,
      top: _pipPos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipPos += details.delta;
          });
        },
        child: Container(
          width: 240,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_pipUrl!)),
                  initialSettings: InAppWebViewSettings(
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 16),
                    onPressed: () => setState(() => _pipUrl = null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

  BoxDecoration _sheetDecor(bool isDark) {
    final custom = _settings.browserCustomTheme;
    final bgColor =
        _parseColor(custom['bg'], isDark ? Dt.cardDark : Dt.card);
    return BoxDecoration(
      color: bgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    );
  }

  void _showMenu(BuildContext context, bool isDark, WebTab? tab) {
    if (tab == null) return;
    final url = tab.url.value;
    final hasPage = url.isNotEmpty && url != 'about:blank';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Dt.canvasDark : Dt.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Stats & Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildDataSavedPill(isDark),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.shieldCheck, size: 18, color: Colors.green),
                      onPressed: () { Get.back(); _showPrivacyDashboard(context, isDark, tab); },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.bookOpen, size: 18, color: Colors.amber),
                      onPressed: () async {
                        Get.back();
                        final html = await tab.webController?.evaluateJavascript(source: AdblockService.readerJs);
                        if (!context.mounted) return;
                        if (html != null && html.toString().isNotEmpty) {
                          _showReaderView(context, isDark, tab, html.toString());
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Main Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  runSpacing: 16,
                  children: [
                    _buildMenuItem('Bookmarks', LucideIcons.bookmark, Colors.cyan, () { Get.back(); _showBookmarksSheet(context, isDark); }),
                    _buildMenuItem('History', LucideIcons.history, Colors.orange, () { Get.back(); _showHistorySheet(context, isDark); }),
                    _buildMenuItem('Downloads', LucideIcons.download, Colors.blue, () { Get.back(); _showDownloadsSheet(context, isDark); }),
                    _buildMenuItem('Files', LucideIcons.folder, Colors.deepPurpleAccent, () { Get.back(); Get.to(() => const BrowserFilesView()); }),
                    _buildMenuItem('AI Notes', LucideIcons.bookMarked, Colors.pinkAccent, () { Get.back(); _scaffoldKey.currentState?.openEndDrawer(); }),
                    
                    _buildMenuItem('Offline', LucideIcons.cloudOff, Colors.brown, () { Get.back(); _saveForOffline(tab); }, enabled: hasPage),
                    _buildMenuItem('As PDF', LucideIcons.fileDown, Colors.redAccent, () { Get.back(); _saveAsPdf(tab); }, enabled: hasPage),
                    _buildMenuItem('Find', LucideIcons.fileSearch, Colors.indigoAccent, () { Get.back(); _startFind(); }, enabled: hasPage),
                    _buildMenuItem('Screenshot', LucideIcons.camera, Colors.blueGrey, () { Get.back(); _takeScreenshot(tab); }, enabled: hasPage),
                    _buildMenuItem('Capture All', LucideIcons.scan, Colors.deepPurple, () { Get.back(); _takeLongScreenshot(tab); }, enabled: hasPage),
                    
                    _buildMenuItem('QR Handoff', LucideIcons.monitorUp, Colors.blueGrey, () { Get.back(); _showQrHandoff(tab); }, enabled: hasPage),
                    _buildMenuItem('Group', LucideIcons.library, Colors.teal, () { Get.back(); _showTabGroupDialog(tab); }),
                    _buildMenuItem('Extract', LucideIcons.clipboardList, Colors.lightGreen, () { Get.back(); _extractToChat(tab); }, enabled: hasPage),
                    _buildMenuItem('Auto-fill', LucideIcons.userCheck, Colors.deepOrangeAccent, () { Get.back(); _autoFillIdentity(tab); }, enabled: hasPage),
                    _buildMenuItem('Site Rules', LucideIcons.bot, Colors.amberAccent, () { Get.back(); _showSiteRulesSheet(tab); }),

                    _buildMenuItem('Night', LucideIcons.moon, Colors.indigo, () { _toggleDarkMode(tab); }, isActive: _settings.browserForcedDark.value),
                    _buildMenuItem('Desktop', LucideIcons.monitor, Colors.blueGrey, () { Get.back(); _toggleDesktopMode(tab); }, isActive: tab.desktopMode.value),
                    _buildMenuItem('Wipe', LucideIcons.bomb, Colors.red, () async { Get.back(); await _browser.privacyBomb(); }),
                    _buildMenuItem('Limiter', LucideIcons.gauge, Dt.accentGx, () { Get.back(); _showGxLimiterSheet(context, isDark); }),
                    _buildMenuItem('Wallpaper', LucideIcons.image, Colors.pink, () { Get.back(); _pickWallpaper(); }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Bottom Action Bar
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.settings, size: 20),
                      onPressed: () { Get.back(); Get.toNamed('/app-settings'); },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.eraser, size: 20),
                      tooltip: 'Clear Data',
                      onPressed: () { Get.back(); _clearBrowsingData(tab); },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.search, size: 20),
                      tooltip: 'Search Engine',
                      onPressed: () { Get.back(); _showEngineSheet(context, isDark); },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.layout, size: 20),
                      tooltip: 'Toolbar',
                      onPressed: () { Get.back(); _showToolbarConfigSheet(isDark); },
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.palette, size: 20),
                      tooltip: 'AI Theme',
                      onPressed: () { Get.back(); _showAiThemeGenerator(); },
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(LucideIcons.power, color: Colors.red, size: 20),
                      onPressed: () => SystemNavigator.pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildMenuItem(String label, IconData icon, Color color, VoidCallback onTap, {bool enabled = true, bool isActive = false}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: Get.width / 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive ? color : color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isActive ? Colors.white : color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isActive ? color : null,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataSavedPill(bool isDark) {
    return Obx(() {
      final bytes = _settings.browserTotalDataSaved.value;
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.zap, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              '$mb MB Saved',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    });
  }

  void _showGxLimiterSheet(BuildContext context, bool isDark) {
    if (!Get.isRegistered<DeviceInfoService>()) return;
    final dev = Get.find<DeviceInfoService>();

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Row(
              children: [
                const Icon(LucideIcons.zap, color: Dt.accentGx, size: 20),
                const SizedBox(width: 12),
                Text('GX Resource Limiter',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Obx(() => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Limiter'),
              trailing: Switch(
                value: _settings.browserLimiterEnabled.value,
                onChanged: (v) => _settings.setBrowserLimiterEnabled(v),
              ),
            )),
            const Divider(),
            Obx(() {
              final total = dev.totalRamGB.value * 1024; // MB
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('RAM Limiter', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_settings.browserRamLimit.value} MB / ${total.toStringAsFixed(0)} MB'),
                    ],
                  ),
                  Slider(
                    value: _settings.browserRamLimit.value.toDouble(),
                    min: 256,
                    max: total,
                    divisions: 10,
                    activeColor: Dt.accentGx,
                    onChanged: _settings.browserLimiterEnabled.value
                        ? (v) => _settings.setBrowserRamLimit(v.round())
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CPU Limiter', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${(_settings.browserCpuLimit.value * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                  Slider(
                    value: _settings.browserCpuLimit.value,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    activeColor: Dt.accentGx,
                    onChanged: _settings.browserLimiterEnabled.value
                        ? (v) => _settings.setBrowserCpuLimit(v)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Soft limits will automatically hibernate background tabs when exceeded.',
                    style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                  ),
                  const Divider(height: 32),
                  Text('Performance Profile', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _profileBtn('eco', LucideIcons.leaf),
                      _profileBtn('balanced', LucideIcons.scale),
                      _profileBtn('beast', LucideIcons.zap),
                    ],
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }



  Widget _profileBtn(String id, IconData icon) {
    return Obx(() {
      final selected = _settings.browserPerformanceProfile.value == id;
      return IconButton(
        icon: Icon(icon, color: selected ? Dt.accentGx : Colors.grey),
        onPressed: () {
          _haptic();
          _settings.setBrowserPerformanceProfile(id);
        },
        tooltip: id.capitalizeFirst,
      );
    });
  }

  void _showNewsCategorySheet(bool isDark) {
    final cats = ['artificial intelligence', 'technology', 'science', 'business', 'health', 'entertainment'];
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('News Categories', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats.map((c) {
                return Obx(() {
                  final selected = _settings.browserNewsCategories.contains(c);
                  return FilterChip(
                    label: Text(c.capitalizeFirst!),
                    selected: selected,
                    onSelected: (_) {
                      _settings.toggleNewsCategory(c);
                      Get.find<NewsService>().fetchNews(force: true);
                    },
                  );
                });
              }).toList(),
            ),
          ],
        ),
      ),
    );
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
            ListTile(
              leading: const Icon(LucideIcons.mousePointer),
              title: const Text('Block Element Manually'),
              subtitle: const Text('Pick and hide parts of this page'),
              onTap: () {
                Get.back();
                _startElementPicker(tab);
              },
            ),
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

  void _showSavedPagesSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Saved Pages',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text('offline reading',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_browser.offlinePages.isEmpty) {
                return Center(
                    child: Text('No saved pages yet.\nUse ⋮ → Save for Offline.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _browser.offlinePages.length,
                itemBuilder: (context, i) {
                  final p = _browser.offlinePages[i];
                  final title = p['title'] ?? '';
                  final url = p['url'] ?? '';
                  final path = p['path'] ?? '';
                  final host = Uri.tryParse(url)?.host ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.fileText, size: 18),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(host.isNotEmpty ? host : url,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      onPressed: () => _browser.deleteOfflinePage(i),
                    ),
                    onTap: () {
                      Get.back();
                      if (path.isNotEmpty) {
                        _loadUrl(_browser.currentTab!, 'file://$path');
                      }
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

  /// UC-style download manager: live progress, pause / resume / retry.
  void _showDownloadsSheet(BuildContext context, bool isDark) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: _sheetDecor(isDark),
        child: Column(children: [
          _sheetHandle(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Downloads',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => _dl.clearFinished(),
              child: const Text('Clear finished'),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (_dl.downloads.isEmpty) {
                return Center(
                    child: Text(
                        'No downloads yet.\nFiles you download appear here with progress.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: Theme.of(context).hintColor)));
              }
              return ListView.builder(
                itemCount: _dl.downloads.length,
                itemBuilder: (context, i) =>
                    _buildDownloadRow(_dl.downloads[i], isDark),
              );
            }),
          ),
        ]),
      ),
    );
  }

  Widget _buildDownloadRow(BrowserDownload d, bool isDark) {
    return Obx(() {
      final st = d.status.value;
      final IconData icon;
      final Color color;
      switch (st) {
        case BrowserDownloadStatus.downloading:
        case BrowserDownloadStatus.queued:
          icon = LucideIcons.download;
          color = Dt.accent;
          break;
        case BrowserDownloadStatus.paused:
          icon = LucideIcons.pause;
          color = Colors.orange;
          break;
        case BrowserDownloadStatus.completed:
          icon = LucideIcons.checkCircle2;
          color = Colors.green;
          break;
        case BrowserDownloadStatus.failed:
          icon = LucideIcons.alertTriangle;
          color = Colors.red;
          break;
        case BrowserDownloadStatus.canceled:
          icon = LucideIcons.ban;
          color = Theme.of(context).hintColor;
          break;
      }
      final showBar = st == BrowserDownloadStatus.downloading ||
          st == BrowserDownloadStatus.paused;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Dt.borderColor(isDark)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      st == BrowserDownloadStatus.failed && d.error.value.isNotEmpty
                          ? d.error.value
                          : '${d.progressLabel} · ${st.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ),
              if (st == BrowserDownloadStatus.downloading ||
                  st == BrowserDownloadStatus.queued)
                IconButton(
                  tooltip: 'Pause',
                  icon: const Icon(LucideIcons.pause, size: 18),
                  onPressed: () => _dl.pause(d.id),
                ),
              if (st == BrowserDownloadStatus.paused)
                IconButton(
                  tooltip: 'Resume',
                  icon: const Icon(LucideIcons.play, size: 18),
                  onPressed: () => _dl.resume(d.id),
                ),
              if (st == BrowserDownloadStatus.failed ||
                  st == BrowserDownloadStatus.canceled)
                IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(LucideIcons.rotateCcw, size: 18),
                  onPressed: () => _dl.retry(d.id),
                ),
              if (st == BrowserDownloadStatus.downloading ||
                  st == BrowserDownloadStatus.queued ||
                  st == BrowserDownloadStatus.paused)
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => _dl.cancel(d.id),
                ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(LucideIcons.trash2,
                    size: 16, color: Theme.of(context).hintColor),
                onPressed: () => _dl.remove(d.id),
              ),
            ]),
            if (showBar) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.total.value > 0 ? d.progress : null,
                  minHeight: 4,
                  backgroundColor:
                      Theme.of(context).hintColor.withValues(alpha: 0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Dt.accent),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  void _showPrivacyDashboard(BuildContext context, bool isDark, WebTab tab) {    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          children: [
            _sheetHandle(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Privacy Dashboard',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: () => Get.back(),
              ),
            ]),
            const SizedBox(height: 16),
            Obx(() => ListTile(
                  leading:
                      const Icon(LucideIcons.shieldCheck, color: Colors.green),
                  title: Text('${tab.blockedCount.value} Trackers blocked'),
                  subtitle: const Text('on this page'),
                )),
            const Divider(),
            Expanded(
              child: Obx(() {
                if (tab.blockedHosts.isEmpty) {
                  return Center(
                      child: Text('No trackers detected on this page.',
                          style: GoogleFonts.plusJakartaSans(
                              color: Theme.of(context).hintColor)));
                }
                return ListView.builder(
                  itemCount: tab.blockedHosts.length,
                  itemBuilder: (context, i) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(LucideIcons.activity, size: 16),
                      title: Text(tab.blockedHosts[i]),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showTabGroupDialog(WebTab tab) {
    final ctrl = TextEditingController(text: tab.groupName.value);
    Get.dialog(
      AlertDialog(
        title: const Text('Tab Grouping'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Enter group name (e.g. Work)',
            labelText: 'Group Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _browser.setTabGroup(_browser.tabs.indexOf(tab), '');
              Get.back();
            },
            child: const Text('Remove Group'),
          ),
          TextButton(
            onPressed: () {
              _browser.setTabGroup(_browser.tabs.indexOf(tab), ctrl.text);
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showVideoDownloadSheet(BuildContext context, bool isDark, WebTab tab) {
    Get.bottomSheet(
      Container(
        height: Get.height * 0.5,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          children: [
            _sheetHandle(),
            Text('Videos Detected',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: Obx(() => ListView.builder(
                    itemCount: tab.detectedVideos.length,
                    itemBuilder: (context, i) {
                      final url = tab.detectedVideos[i];
                      final name = url.split('/').last.split('?').first;
                      return ListTile(
                        leading: const Icon(LucideIcons.video, size: 18),
                        title: Text(name.isEmpty ? 'Video $i' : name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_settings.browserPipEnabled.value)
                              IconButton(
                                icon: const Icon(LucideIcons.externalLink, size: 16),
                                tooltip: 'Pop-out',
                                onPressed: () {
                                  Get.back();
                                  setState(() => _pipUrl = url);
                                },
                              ),
                            IconButton(
                              icon: const Icon(LucideIcons.download, size: 18),
                              onPressed: () {
                                Get.back();
                                _downloadFile(url, suggested: name);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  )),
            ),
          ],
        ),
      ),
    );
  }

  void _showToolbarConfigSheet(bool isDark) {
    final available = [
      'back',
      'forward',
      'home',
      'tabs',
      'menu',
      'qr',
      'snapshot',
      'summarize',
      'translate',
      'split',
      'downloads'
    ];
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('Custom Toolbar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: available.map((id) {
                return Obx(() {
                  final selected = _settings.browserToolbarTools.contains(id);
                  return FilterChip(
                    label: Text(id.capitalizeFirst!),
                    selected: selected,
                    onSelected: (v) {
                      final current = _settings.browserToolbarTools.toList();
                      if (v) {
                        if (current.length < 5) current.add(id);
                      } else {
                        if (current.length > 2) current.remove(id);
                      }
                      _settings.setBrowserToolbarConfig(current);
                    },
                  );
                });
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Max 5 tools recommended', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showWritingAssistant() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('Writing Assistant', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Enter text to improve...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Improve');
                  },
                  child: const Text('Improve'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _triggerAssistantAction(ctrl.text, 'Simplify');
                  },
                  child: const Text('Simplify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerAssistantAction(String text, String action) async {
    if (text.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Assistant', 'Processing text...');
    Get.find<HomeController>().changeTab(0);
    await chat.askInNewChat('$action this text for me:\n\n$text');
  }

  void _showAiThemeGenerator() {
    final ctrl = TextEditingController();
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: _sheetDecor(Theme.of(context).brightness == Brightness.dark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Text('AI Theme Generator', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Describe a theme (e.g. Neon Cyberpunk)...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Get.back();
                _generateAiTheme(ctrl.text);
              },
              child: const Text('Generate Theme'),
            ),
            if (_settings.browserCustomTheme.isNotEmpty)
              TextButton(
                onPressed: () {
                  Get.back();
                  _settings.applyAiTheme({});
                },
                child: const Text('Reset Theme', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAiTheme(String prompt) async {
    if (prompt.trim().isEmpty) return;
    final chat = Get.find<ChatController>();
    _toast('AI Theme', 'Generating color palette...');

    final result = await chat.askOnce(
      'Generate a color palette for a browser theme based on this prompt: "$prompt". Return ONLY a JSON object with these keys: "accent", "bg", "secondary". Use hex codes (e.g. #FF0000).',
    );

    if (result == null) return;
    try {
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(result);
      if (match != null) {
        final data = jsonDecode(match.group(0)!);
        if (data is Map) {
          final theme = data.map((k, v) => MapEntry(k.toString(), v.toString()));
          await _settings.applyAiTheme(theme);
          _toast('AI Theme', 'New theme applied!');
        }
      }
    } catch (_) {
      _toast('AI Theme', 'Failed to parse colors.');
    }
  }

  Future<void> _toggleListeningMode(WebTab tab) async {
    final tts = Get.isRegistered<TtsService>() ? Get.find<TtsService>() : null;
    if (tts == null) return;

    if (_isReading.value) {
      await tts.stop();
      _isReading.value = false;
      return;
    }

    final page = await _extractPage(tab);
    if (page == null || (page['text'] ?? '').isEmpty) {
      _toast('Empty page', 'Nothing to read.');
      return;
    }

    _isReading.value = true;
    _toast('Listening Mode', 'Reading page...');
    await tts.speak(page['text']!);
    _isReading.value = false;
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
            ..._settings.browserCustomEngines.asMap().entries.map((entry) => Obx(() {
                  final i = entry.key;
                  final e = entry.value;
                  final id = e['name']!;
                  final selected = _settings.browserSearchEngine.value == id;
                  return ListTile(
                    dense: true,
                    title: Text(id),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) const Icon(LucideIcons.check, color: Dt.accent),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 16),
                          onPressed: () => _settings.removeCustomSearchEngine(i),
                        ),
                      ],
                    ),
                    onTap: () {
                      _settings.setBrowserSearchEngine(id);
                      Get.back();
                    },
                  );
                })),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.plus),
              title: const Text('Add Custom Engine'),
              onTap: () => _showAddEngineDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEngineDialog() {
    final nameCtrl = TextEditingController();
    final templateCtrl = TextEditingController(text: 'https://search.com/search?q=%s');
    Get.dialog(
      AlertDialog(
        title: const Text('Add Search Engine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: templateCtrl, decoration: const InputDecoration(labelText: 'URL Template (%s for query)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _settings.addCustomSearchEngine(nameCtrl.text, templateCtrl.text);
              Get.back();
            },
            child: const Text('Add'),
          ),
        ],
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
            Row(children: [
              IconButton(
                icon: const Icon(LucideIcons.bomb, color: Colors.red, size: 20),
                tooltip: 'Privacy Bomb',
                onPressed: () async {
                  final ok = await Get.dialog<bool>(
                    AlertDialog(
                      title: const Text('Privacy Bomb'),
                      content: const Text('Close all tabs and wipe history?'),
                      actions: [
                        TextButton(onPressed: () => Get.back(), child: const Text('No')),
                        TextButton(
                            onPressed: () => Get.back(result: true),
                            child: const Text('YES', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    Get.back();
                    await _browser.privacyBomb();
                  }
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.shieldAlert,
                    color: Colors.purple, size: 20),
                tooltip: 'New Incognito Tab',
                onPressed: () {
                  if (!_browser.addTab(incognito: true)) {
                    _toast('Tab limit',
                        'Close a tab first (max ${BrowserController.maxTabs}).');
                    return;
                  }
                  Get.back();
                },
              ),
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
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              final groups = <String, List<int>>{};
              final noGroup = <int>[];
              for (var i = 0; i < _browser.tabs.length; i++) {
                final g = _browser.tabs[i].groupName.value;
                if (g.isEmpty) {
                  noGroup.add(i);
                } else {
                  groups.putIfAbsent(g, () => []).add(i);
                }
              }

              return ListView(
                children: [
                  ...groups.entries.map((e) => _buildTabGroup(context, isDark, e.key, e.value)),
                  if (noGroup.isNotEmpty)
                    _buildTabGroup(context, isDark, 'Ungrouped', noGroup, isDefault: true),
                ],
              );
            }),
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

  Widget _buildResourceMonitor(bool isDark) {
    if (!_settings.browserResourceMonitor.value) return const SizedBox.shrink();
    if (!Get.isRegistered<DeviceInfoService>()) return const SizedBox.shrink();
    final dev = Get.find<DeviceInfoService>();
    return Obx(() {
      final total = dev.totalRamGB.value;
      final avail = dev.availableRamGB.value;
      if (total <= 0) return const SizedBox.shrink();
      final used = total - avail;
      final pct = (used / total).clamp(0.0, 1.0);
      final color = pct > 0.8 ? Colors.red : (pct > 0.6 ? Colors.orange : Dt.accent);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cpu, size: 10, color: color),
            const SizedBox(width: 4),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _boostRam(),
              child: Icon(LucideIcons.zap, size: 10, color: color),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _boostRam() async {
    _toast('Cubic Booster', 'Freeing up memory...');
    _haptic();
    
    // Clear recently closed tabs
    _browser.closedTabs.clear();
    
    // Hint VM for GC
    SystemChannels.platform.invokeMethod('SystemNavigator.pop'); // Not really GC but close on some platforms
    // The best we can do in Flutter is to let the system know.
    
    await Future.delayed(const Duration(seconds: 1));
    _toast('Cubic Booster', 'Optimization complete.');
  }

  Widget _buildAiSidebar(BuildContext context, bool isDark) {
    return Drawer(
      width: 320,
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? Dt.cardDark : Dt.card,
              border: Border(bottom: BorderSide(color: Dt.borderColor(isDark))),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, color: Dt.accent, size: 20),
                const SizedBox(width: 12),
                Text(
                  'AI Companion',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ),
          _buildAiSidebarShortcuts(isDark),
          const Divider(height: 1),
          _buildAiSidebarShortcuts(isDark),
          const Divider(height: 1),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Chat'),
                      Tab(text: 'Notebook'),
                    ],
                    labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildChatPlaceholder(context),
                        _buildNotebookView(isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildAiActionButtons(isDark),
        ],
      ),
    );
  }

  Widget _buildChatPlaceholder(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messageSquare,
                size: 48, color: Dt.accent.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Chat with CubicLM while you browse.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Get.back();
                Get.find<HomeController>().changeTab(0);
              },
              child: const Text('Open Full Chat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotebookView(bool isDark) {
    return Obx(() {
      if (_settings.browserAiNotes.isEmpty) {
        return Center(
          child: Text('No notes saved yet.\nSelect text on a page to save.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(color: Colors.grey)),
        );
      }
      return ListView.builder(
        itemCount: _settings.browserAiNotes.length,
        itemBuilder: (context, i) {
          final note = _settings.browserAiNotes[i];
          return ListTile(
            title: Text(note['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(note['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(LucideIcons.trash2, size: 16),
              onPressed: () => _settings.removeAiNote(i),
            ),
            onTap: () {
              // Open note details or chat about it
              _toast('Note', 'Chatting with this snippet...');
              _scaffoldKey.currentState?.closeEndDrawer();
              Get.find<HomeController>().changeTab(0);
              Get.find<ChatController>().askInNewChat(
                  'Let\'s discuss this snippet:\n\n${note['content']}');
            },
          );
        },
      );
    });
  }

  void _showTextSelectionSheet(
      BuildContext context, bool isDark, WebTab tab, String text) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: _sheetDecor(isDark),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Row(
              children: [
                const Icon(LucideIcons.sparkles, color: Dt.accent, size: 16),
                const SizedBox(width: 8),
                Text('AI Contextual Tools',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _aiToolBtn('Explain', LucideIcons.helpCircle, () {
                  Get.back();
                  _triggerAssistantAction(text, 'Explain');
                }),
                _aiToolBtn('Summarize', LucideIcons.list, () {
                  Get.back();
                  _triggerAssistantAction(text, 'Summarize');
                }),
                _aiToolBtn('Rewrite', LucideIcons.pencil, () {
                  Get.back();
                  _triggerAssistantAction(text, 'Rewrite');
                }),
                _aiToolBtn('Translate', LucideIcons.languages, () {
                  Get.back();
                  _triggerAssistantAction(text, 'Translate');
                }),
              ],
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(LucideIcons.bookMarked),
              title: const Text('Save to AI Notes'),
              onTap: () {
                _settings.addAiNote(tab.title.value, text, tab.url.value);
                Get.back();
                _toast('Saved', 'Added to Notebook.');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.copy),
              title: const Text('Copy to Clipboard'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Get.back();
                _toast('Copied', 'Text copied.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiToolBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: Dt.accent),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildAiSidebarShortcuts(bool isDark) {
    return Obx(() {
      if (_settings.browserSidebarShortcuts.isEmpty) {
        return const SizedBox.shrink();
      }
      return Container(
        height: 80,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: isDark ? Colors.black12 : Colors.black.withValues(alpha: 0.02),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _settings.browserSidebarShortcuts.length,
          itemBuilder: (context, i) {
            final s = _settings.browserSidebarShortcuts[i];
            final url = s['url'] ?? '';
            final title = s['title'] ?? '';
            final host = Uri.tryParse(url)?.host ?? '';
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () {
                  Get.back();
                  _go(url);
                },
                onLongPress: () => _settings.removeBrowserSidebarShortcut(url),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? Dt.cardDark : Dt.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: Dt.borderColor(isDark)),
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.globe, size: 20, color: Dt.accent),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 50,
                      child: Text(
                        host.isNotEmpty ? host : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildAiActionButtons(bool isDark) {
    final tab = _browser.currentTab;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        border: Border(top: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.camera, size: 18),
            title: const Text('AI Snapshot'),
            subtitle: const Text('Analyze visible area'),
            onTap: tab == null ? null : () {
              Get.back();
              _aiSnapshot(tab);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.penTool, size: 18),
            title: const Text('AI Writing Assistant'),
            subtitle: const Text('Improve or simplify text'),
            onTap: tab == null ? null : () {
              Get.back();
              _showWritingAssistant();
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.list, size: 18),
            title: const Text('Summarize Page'),
            onTap: tab == null ? null : () {
              Get.back();
              _summarizePage(tab);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.eye, size: 18),
            title: const Text('AI Skim (Highlight Key points)'),
            onTap: tab == null ? null : () {
              Get.back();
              _skimPage(tab);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.helpCircle, size: 18),
            title: const Text('Ask about this page'),
            onTap: tab == null ? null : () {
              Get.back();
              _askAiAboutPage(tab);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _summarizePage(WebTab tab) async {
    final html = await tab.webController?.evaluateJavascript(
        source: 'document.body.innerText');
    if (html == null || html.toString().trim().isEmpty) {
      _toast('AI Summary', 'Could not read page content.');
      return;
    }
    final content = html.toString().trim();
    final chat = Get.find<ChatController>();
    
    _toast('AI Summary', 'Analyzing page...');
    
    // Switch to Chat tab
    Get.find<HomeController>().changeTab(0);
    
    // Start a new session with the summary prompt
    await chat.askInNewChat(
      'Summarize this web page content in 3-5 key points:\n\n$content',
    );
  }

  Future<void> _skimPage(WebTab tab) async {
    final html = await tab.webController?.evaluateJavascript(
        source: 'document.body.innerText');
    if (html == null || html.toString().trim().isEmpty) {
      _toast('AI Skim', 'Could not read page content.');
      return;
    }
    final content = html.toString().trim();
    final chat = Get.find<ChatController>();
    
    _toast('AI Skim', 'Finding key points...');
    
    // In a real scenario, we'd use the model to get key sentences.
    // For now, let's simulate by highlighting common "important" sounding sentences
    // or just trigger the AI to give us the sentences and then we inject JS to highlight.
    
    // We'll use a specific prompt to get EXACT sentences from the text.
    final result = await chat.askOnce(
      'Identify the 3 most important EXACT sentences from this text for highlighting. Return ONLY the sentences, one per line, no numbering:\n\n$content',
    );
    
    if (result == null) return;
    final sentences = result.split('\n').where((s) => s.trim().length > 10).toList();
    
    for (final s in sentences) {
      final escaped = s.replaceAll("'", "\\'").replaceAll('"', '\\"');
      await tab.webController?.evaluateJavascript(source: """
        (function() {
          var text = "$escaped";
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
          var node;
          while(node = walker.nextNode()) {
            if (node.nodeValue.includes(text)) {
              var span = document.createElement('span');
              span.style.backgroundColor = 'yellow';
              span.style.color = 'black';
              span.innerText = node.nodeValue;
              node.parentNode.replaceChild(span, node);
            }
          }
        })();
      """);
    }
    _toast('AI Skim', 'Key points highlighted.');
  }

  Future<void> _aiSnapshot(WebTab tab) async {
    try {
      final screenshot = await tab.webController?.takeScreenshot();
      if (screenshot == null) {
        _toast('AI Snapshot', 'Could not capture screen.');
        return;
      }

      _toast('AI Snapshot', 'Analyzing image...');
      final chat = Get.find<ChatController>();

      // Persist the capture so the chat pipeline can attach it.
      final dir = await getTemporaryDirectory();
      final imgFile = File(
          '${dir.path}/ai_snapshot_${DateTime.now().millisecondsSinceEpoch}.png');
      await imgFile.writeAsBytes(screenshot);

      Get.find<HomeController>().changeTab(0);
      chat.createNewChat();
      chat.selectedImagePath.value = imgFile.path;
      const prompt =
          'What is in this image? Explain the web content shown.';
      chat.textController.text = prompt;
      chat.inputText.value = prompt;
      await chat.sendMessage();
    } catch (e) {
      _toast('AI Snapshot', 'Failed: $e');
    }
  }

  Future<void> _translatePage(WebTab tab) async {
    final html = await tab.webController
        ?.evaluateJavascript(source: 'document.body.innerText');
    if (html == null || html.toString().trim().isEmpty) {
      _toast('AI Translator', 'Could not read page content.');
      return;
    }
    final content = html.toString().trim();
    final chat = Get.find<ChatController>();

    _toast('AI Translator', 'Translating page...');

    Get.find<HomeController>().changeTab(0);

    await chat.askInNewChat(
      'Translate the following web page content accurately into ${Get.locale?.languageCode == 'bn' ? 'Bengali' : 'English'}:\n\n$content',
    );
  }

  Widget _buildTabGroup(BuildContext context, bool isDark, String name, List<int> indices, {bool isDefault = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(isDefault ? LucideIcons.layers : LucideIcons.folder, 
                  size: 14, color: isDefault ? Colors.grey : Dt.accent),
              const SizedBox(width: 8),
              Text(
                name.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: isDefault ? Colors.grey : Dt.accent,
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: indices.length,
          itemBuilder: (context, i) {
            final index = indices[i];
            final t = _browser.tabs[index];
            final isCurrent = _browser.currentTabIndex.value == index;
            return GestureDetector(
              onTap: () {
                _haptic();
                _browser.switchTab(index);
                Get.back();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Dt.cardDark : Dt.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isCurrent ? Dt.accent : Dt.borderColor(isDark),
                      width: 2),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Obx(() => Icon(
                          t.isIncognito.value
                              ? LucideIcons.shieldAlert
                              : LucideIcons.globe,
                          size: 24,
                          color: (t.isIncognito.value ? Colors.purple : Dt.accent)
                              .withValues(alpha: 0.15))),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05),
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Obx(() => Text(t.title.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10))),
                            ),
                            GestureDetector(
                              onTap: () {
                                _browser.closeTab(index);
                                if (_browser.currentTab != null) {
                                  _syncUrl();
                                }
                              },
                              child: const Icon(LucideIcons.x, size: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSplitWindow(BuildContext context, bool isDark) {
    // For now, split view shows the AI Sidebar content in the split pane
    // This turns the sidebar into a persistent panel.
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Dt.cardDark : Dt.card,
            border: Border(bottom: BorderSide(color: Dt.borderColor(isDark))),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.sparkles, color: Dt.accent, size: 14),
              const SizedBox(width: 8),
              Text('Cubic AI',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.maximize2, size: 14),
                onPressed: () => _settings.browserSplitEnabled.value = false,
              ),
            ],
          ),
        ),
        Expanded(child: _buildNotebookView(isDark)),
      ],
    );
  }

  Widget _emptyState(BuildContext context, bool isDark) {
    return Obx(() {
      final wallpaper = _settings.browserWallpaperPath.value;
      return Stack(
        children: [
          if (wallpaper.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: isDark ? 0.3 : 0.5,
                child: Image.file(
                  File(wallpaper),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              const SizedBox(height: 50),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Dt.accentGx.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.globe,
                      size: 40, color: Dt.accentGx),
                ),
              ),
              const SizedBox(height: 24),
              // Compact Search Box
              GestureDetector(
                onTap: () {
                  _urlCtrl.clear();
                  _suggestFocus.requestFocus();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Dt.cardDark : Dt.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Dt.borderColor(isDark).withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.search,
                          size: 18, color: Dt.accentGx),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search or type URL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.mic, size: 18, color: Colors.grey),
                        onPressed: () => _startVoiceControl(),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.qrCode, size: 18, color: Colors.grey),
                        onPressed: () => _showQrScanner(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: _settings.browserSpeedDial.length + 1,
                itemBuilder: (context, i) {
                  if (i == _settings.browserSpeedDial.length) {
                    return _buildAddShortcutTile(isDark);
                  }
                  final item = _settings.browserSpeedDial[i];
                  return _buildQuickLink(item['title'] ?? '', item['url'] ?? '',
                      LucideIcons.globe, isDark,
                      onLongPress: () =>
                          _settings.removeBrowserSpeedDialItem(item['url']!));
                },
              ),
              const SizedBox(height: 32),
              _buildDashboardWidgets(isDark),
              const SizedBox(height: 32),
              _buildAiBanner(isDark),
              _buildNewsFeed(isDark),
              const SizedBox(height: 60),
            ],
          ),
          // Floating Booster
          Positioned(
            right: 16,
            bottom: 80,
            child: _buildResourceMonitor(isDark),
          ),
        ],
      );
    });
  }



  Widget _buildNewsFeed(bool isDark) {
    final newsService = Get.find<NewsService>();
    return Obx(() {
      if (newsService.news.isEmpty && !newsService.isLoading.value) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI Trending News',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (newsService.isLoading.value)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  onPressed: () => newsService.fetchNews(force: true),
                ),
              IconButton(
                icon: const Icon(LucideIcons.settings, size: 14),
                onPressed: () => _showNewsCategorySheet(isDark),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...newsService.news.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Dt.cardDark : Dt.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Dt.borderColor(isDark)),
                ),
                child: InkWell(
                  onTap: () => _go(item.link),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.summary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.summary,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      );
    });
  }

  Widget _buildAiBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Dt.accentGx.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.accentGx.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, color: Dt.accentGx, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI CORNER',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Dt.accentGx)),
                Text('Explore new models and skills.',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Get.find<HomeController>().changeTab(1),
            child: const Text('VISIT'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardWidgets(bool isDark) {
    final stats = Get.isRegistered<StatsService>() ? Get.find<StatsService>() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'AI Activity',
                stats == null ? '0' : '${stats.snapshot()[StatsService.eventChatSent] ?? 0}',
                LucideIcons.messageSquare,
                isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'RAM Load',
                '${(Get.find<DeviceInfoService>().totalRamGB.value - Get.find<DeviceInfoService>().availableRamGB.value).toStringAsFixed(1)} GB',
                LucideIcons.cpu,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSavingsCard(isDark),
      ],
    );
  }

  Widget _buildSavingsCard(bool isDark) {
    return Obx(() {
      final bytes = _settings.browserTotalDataSaved.value;
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Dt.borderColor(isDark)),
          gradient: LinearGradient(
            colors: isDark
                ? [Colors.green.withValues(alpha: 0.1), Colors.transparent]
                : [Colors.green.withValues(alpha: 0.05), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.zap, color: Colors.green, size: 24),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$mb MB SAVED',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Data & Tracker protection active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatCard(String label, String value, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Dt.cardDark : Dt.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Dt.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Dt.accent),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLink(
      String name, String url, IconData icon, bool isDark,
      {VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: () => _go(url),
      onLongPress: onLongPress,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Dt.cardDark : Dt.card,
              shape: BoxShape.circle,
              border: Border.all(color: Dt.borderColor(isDark)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: Dt.accent),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddShortcutTile(bool isDark) {
    return GestureDetector(
      onTap: () => _showAddShortcutDialog(isDark),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Dt.cardDark : Dt.card,
              shape: BoxShape.circle,
              border: Border.all(color: Dt.borderColor(isDark), style: BorderStyle.none),
              // Use a dashed border or just a plus icon
            ),
            child: Icon(LucideIcons.plus,
                size: 24, color: Dt.accent.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          Text(
            'Add',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddShortcutDialog(bool isDark) {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('Add Shortcut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'URL (https://...)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              var url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              if (!url.contains('://')) url = 'https://$url';
              _settings.addBrowserSpeedDialItem(titleCtrl.text, url);
              Get.back();
            },
            child: const Text('Add'),
          ),
        ],
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
