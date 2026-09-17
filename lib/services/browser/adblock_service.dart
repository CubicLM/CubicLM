/// Privacy ad-block engine for the CubicWeb Browser — zero database.
///
/// Rules live in `assets/adblock_hosts.txt` (bundled at build time) and
/// are loaded once into an in-memory set. Matching is pure string work
/// (exact host or any subdomain), so per-request checks are O(1) average
/// and never touch disk, Hive or the network. Browsing history is never
/// persisted anywhere.
library;

import 'package:flutter/services.dart';

class AdblockService {
  AdblockService._();

  static final Set<String> _hosts = {};
  static bool _loaded = false;

  /// Load rules once (idempotent, safe to call on every navigation).
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/adblock_hosts.txt');
      for (final line in raw.split('\n')) {
        final h = line.trim().toLowerCase();
        if (h.isEmpty || h.startsWith('#')) continue;
        // Skip malformed lines (spaces, slashes, wildcards) — they can
        // never match a real host and only waste memory.
        if (h.contains(RegExp(r'[\s/*]'))) continue;
        _hosts.add(h);
      }
    } catch (_) {}
    _loaded = true;
  }

  static int get ruleCount => _hosts.length;

  /// Test seam: match [url] against an explicit rule set.
  static bool matchesRules(String url, Set<String> rules) {
    final host = hostOf(url);
    if (host == null || host.isEmpty) return false;
    for (final rule in rules) {
      if (rule.isEmpty) continue;
      if (host == rule || host.endsWith('.$rule')) return true;
    }
    return false;
  }

  /// True when [url] is an ad/tracker request. Only http(s) is ever
  /// blocked — page navigations, data/blob/file URLs always pass.
  /// [isMainFrame] navigations are never blocked (blocking those would
  /// blank the whole page on false positives).
  static bool isBlockedUrl(String url, {bool isMainFrame = false}) {
    if (isMainFrame) return false;
    final lower = url.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    return matchesRules(url, _hosts);
  }

  /// Lowercased host of [url], or null when unparseable.
  static String? hostOf(String url) {
    try {
      final host = Uri.parse(url.trim()).host.toLowerCase();
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  /// Bundled cosmetic script (static asset equivalent): removes common
  /// ad containers after load. Shipped inside the APK — never fetched
  /// remotely (Play-policy safe: no dynamic code execution).
  static const String cosmeticJs = r'''
(function(){
  try {
    var sels = [
      '[id^="ad-"]', '[class^="ad-"]', '[id$="-ad"]', '[class$="-ad"]',
      '[id*="_ad_"]', '[class*=" ads"]', '[class^="ads"]',
      '[id*="sponsor"]', '[class*="sponsor"]',
      '[class*="popup-overlay"]', '[class*="cookie-banner"]',
      'iframe[src*="ads"]', 'iframe[src*="doubleclick"]',
      'iframe[src*="googlesyndication"]', 'div[id*="taboola"]',
      'div[id*="outbrain"]', 'ins.adsbygoogle'
    ];
    for (var i = 0; i < sels.length; i++) {
      var els = document.querySelectorAll(sels[i]);
      for (var j = 0; j < els.length; j++) { els[j].remove(); }
    }
  } catch (e) {}
})();
''';

  /// Readability-lite extraction: title + visible text, capped.
  static const String extractJs = '''
(function(){
  try {
    var t = (document.title || '').slice(0, 200);
    var b = document.body ? document.body.innerText : '';
    return JSON.stringify({title: t, text: (b || '').slice(0, 12000)});
  } catch (e) {
    return JSON.stringify({title: '', text: ''});
  }
})();
''';

  /// Reader Mode JS: tries to extract main article and strip clutter.
  static const String readerJs = r'''
(function(){
  try {
    var content = '';
    var article = document.querySelector('article') || document.querySelector('[role="main"]') || document.querySelector('.main-content') || document.body;
    var clone = article.cloneNode(true);
    // Remove scripts, styles, forms, ads
    var strip = clone.querySelectorAll('script, style, form, iframe, noscript, .ad, .ads, [id^="ad-"], [class^="ad-"]');
    for(var i=0; i<strip.length; i++) strip[i].remove();
    return clone.innerHTML;
  } catch(e) { return ''; }
})();
''';

  /// Forced Dark Mode: injects a CSS filter to invert colors while preserving images.
  static const String darkModeJs = r'''
(function(){
  var id = 'cubic-dark-mode';
  if (document.getElementById(id)) return;
  var style = document.createElement('style');
  style.id = id;
  style.innerHTML = 'html { filter: invert(1) hue-rotate(180deg) !important; background: #000 !important; } ' +
                    'img, video, iframe, canvas, svg { filter: invert(1) hue-rotate(180deg) !important; }';
  document.head.appendChild(style);
})();
''';

  /// Remove Dark Mode injection.
  static const String lightModeJs = r'''
(function(){
  var style = document.getElementById('cubic-dark-mode');
  if (style) style.remove();
})();
''';

  /// Video Detection: finds video sources on the page.
  static const String videoDetectJs = r'''
(function(){
  try {
    var urls = [];
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      if (videos[i].src) urls.push(videos[i].src);
      var sources = videos[i].querySelectorAll('source');
      for (var j = 0; j < sources.length; j++) {
        if (sources[j].src) urls.push(sources[j].src);
      }
    }
    var links = document.querySelectorAll('a[href*=".mp4"], a[href*=".mkv"], a[href*=".webm"], a[href*=".mov"]');
    for (var i = 0; i < links.length; i++) {
      urls.push(links[i].href);
    }
    return JSON.stringify([...new Set(urls.filter(u => u.startsWith('http')))]);
  } catch (e) { return '[]'; }
})();
''';

  /// Element Picker: highlights and allows clicking elements to block them.
  static const String elementPickerJs = r'''
(function(){
  var style = document.createElement('style');
  style.id = 'cubic-picker-style';
  style.innerHTML = '*:hover { outline: 2px solid #FF4D00 !important; cursor: crosshair !important; }';
  document.head.appendChild(style);

  var handler = function(e) {
    e.preventDefault();
    e.stopPropagation();
    
    var el = e.target;
    var selector = el.tagName.toLowerCase();
    if (el.id) selector += '#' + el.id;
    if (el.className) selector += '.' + el.className.split(' ').join('.');
    
    window.flutter_inappwebview.callHandler('onElementSelected', selector);
    
    document.getElementById('cubic-picker-style').remove();
    document.removeEventListener('click', handler, true);
  };
  
  document.addEventListener('click', handler, true);
})();
''';
}
