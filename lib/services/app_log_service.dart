import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'crash_reporting_service.dart';

enum LogCategory {
  system('System'),
  model('Model'),
  cloud('Cloud'),
  chat('Chat'),
  server('Server'),
  image('Image'),
  // New-feature lanes (appended — persistence is name-based, so adding
  // values is safe for old stored rows).
  agent('Agent'),
  runtime('Runtime'),
  terminal('Terminal'),
  update('Update');

  final String label;
  const LogCategory(this.label);
}

/// Android ApplicationExitInfo reason codes → short names. Pure —
/// unit tested. Mirrors android.app.ApplicationExitInfo (API 30+).
String processExitReasonName(int reason) {
  switch (reason) {
    case 0:
      return 'UNKNOWN';
    case 1:
      return 'EXIT_SELF';
    case 2:
      return 'SIGNALED';
    case 3:
      return 'LOW_MEMORY';
    case 4:
      return 'CRASH_NATIVE';
    case 5:
      return 'CRASH';
    case 6:
      return 'ANR';
    case 7:
      return 'INIT_FAILURE';
    case 8:
      return 'PERMISSION_CHANGE';
    case 9:
      return 'EXCESSIVE_RESOURCE_USE';
    case 10:
      return 'OTHER';
    case 11:
      return 'USER_REQUESTED';
    case 12:
      return 'USER_STOPPED';
    case 13:
      return 'DEPENDENCY_DIED';
    case 14:
      return 'COMPLETED';
    case 15:
      return 'CANCELLED';
    default:
      return 'REASON_$reason';
  }
}

/// Reasons worth a System-Log row: abnormal deaths only. Clean exits
/// (self/user/completed/permission/other) would spam every upgrade.
bool isCrashExitReason(int reason) {
  switch (reason) {
    case 2: // SIGNALED (kill -9 incl. LMK-adjacent kills)
    case 3: // LOW_MEMORY (LMK kill)
    case 4: // CRASH_NATIVE (SIGSEGV/SIGABRT in llama.cpp)
    case 5: // CRASH (uncaught Java/Kotlin)
    case 6: // ANR (main-thread stall)
    case 7: // INIT_FAILURE
    case 9: // EXCESSIVE_RESOURCE_USE
    case 13: // DEPENDENCY_DIED
      return true;
    default:
      return false;
  }
}

class AppLogEntry {
  /// First occurrence time (kept as `timestamp` for compatibility).
  final DateTime timestamp;

  /// Last occurrence time (== timestamp until the first repeat).
  DateTime lastAt;

  /// How many identical occurrences collapsed into this row.
  int count;

  final String level;
  final String message;
  final String? details;
  final LogCategory category;

  /// Screen open when an ERROR/WARNING was logged ('' for info/debug or
  /// unknown). Excluded from dedup identity on purpose: the same failure
  /// on two screens is still one row, showing its first screen.
  final String screen;

  AppLogEntry({
    required this.level,
    required this.message,
    this.details,
    this.category = LogCategory.system,
    this.screen = '',
    DateTime? timestamp,
    DateTime? lastAt,
    this.count = 1,
  })  : timestamp = timestamp ?? DateTime.now(),
        lastAt = lastAt ?? timestamp ?? DateTime.now();

  bool get isImportant => level == 'ERROR' || level == 'WARNING';

  /// Exact-match key parts are compared field-wise (never concatenated)
  /// so multi-KB stack traces don't allocate on every log call.
  bool sameAs(String level, String message, String? details,
      LogCategory category) {
    if (this.level != level ||
        this.category != category ||
        this.message != message) {
      return false;
    }
    final a = this.details, b = details;
    if (a == null || a.isEmpty) return b == null || b.isEmpty;
    if (b == null || b.isEmpty) return false;
    if (a.length != b.length) return false;
    return a == b;
  }

  Map<String, dynamic> toJson() => {
        't': timestamp.toIso8601String(),
        'last': lastAt.toIso8601String(),
        'n': count,
        'l': level,
        'm': message,
        'd': details,
        'c': category.name,
        if (screen.isNotEmpty) 's': screen,
      };

  factory AppLogEntry.fromJson(Map<String, dynamic> j) {
    final first = DateTime.parse(j['t']);
    return AppLogEntry(
      timestamp: first,
      lastAt: j['last'] != null ? DateTime.tryParse(j['last']) ?? first : first,
      count: (j['n'] as num?)?.toInt() ?? 1,
      level: j['l'],
      message: j['m'],
      details: j['d'],
      category: LogCategory.values.firstWhere(
        (e) => e.name == j['c'],
        orElse: () => LogCategory.system,
      ),
      screen: j['s'] as String? ?? '',
    );
  }

  String format() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('$level [${category.label}]: $message');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n$details');
    }
    return buffer.toString();
  }

  /// Export rendering: one full body no matter how many repeats, with a
  /// `×N · first … · last …` header so pastes stay compact and readable.
  /// Secrets are scrubbed here (single choke point for every export,
  /// share and per-row copy) — the live in-app list keeps full fidelity
  /// for debugging, but nothing pasted to GitHub/chat can leak a key.
  String formatForExport() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('$level [${category.label}]');
    if (count > 1) {
      buffer
        ..write(' (×$count')
        ..write(', first ${timestamp.toIso8601String()}')
        ..write(', last ${lastAt.toIso8601String()}')
        ..write(')');
    }
    buffer.write(': ${scrubExportSecrets(message)}');
    if (screen.isNotEmpty) buffer.write('  [screen=$screen]');
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n${scrubExportSecrets(details!)}');
    }
    return buffer.toString();
  }
}

/// Scrubs secrets from log text before it leaves the device (exports,
/// shares, per-row copies, GitHub pastes). Pure and unit-tested.
/// Covers query-string keys (?key=), bearer tokens and known vendor
/// key prefixes. Deliberately NOT applied to the live list — local
/// debugging keeps full fidelity.
String scrubExportSecrets(String s) {
  var out = s.replaceAllMapped(
    RegExp(r'([?&]key=)[^&\s]+'),
    (m) => '${m.group(1)}***',
  );
  out = out.replaceAllMapped(
    RegExp(r'(Bearer )[^\s;,}"]+'),
    (m) => '${m.group(1)}***',
  );
  out = out.replaceAllMapped(
    RegExp(
        r'\b(sk-ant-[A-Za-z0-9_\-]+|sk-proj-[A-Za-z0-9_\-]+|AIza[A-Za-z0-9_\-]+|xai-[A-Za-z0-9_\-]+|gsk_[A-Za-z0-9_\-]+)'),
    (_) => '***',
  );
  return out;
}

class CrashPattern {
  final String id;
  final String title;
  final String description;
  final String fix;
  final bool Function(AppLogEntry) matcher;
  int occurrences = 0;
  DateTime? lastSeen;

  CrashPattern({
    required this.id,
    required this.title,
    required this.description,
    required this.fix,
    required this.matcher,
  });
}

class AppLogService extends GetxService with WidgetsBindingObserver {
  final entries = <AppLogEntry>[].obs;
  final searchQuery = ''.obs;
  final selectedCategory = Rxn<LogCategory>();
  final selectedLevel = 'ALL'.obs;

  /// Open-screen stack for diagnostics: tabs reset it, pushed editors
  /// push/pop in initState/dispose. Plain strings (no Rx, no widgets)
  /// so logging from anywhere — including build phase — stays safe.
  /// The top entry stamps every ERROR/WARNING row with its screen.
  final List<String> _screenStack = [];
  final List<String> _screenTrail = [];

  /// Screen considered open right now ('' when unknown).
  String get currentScreen =>
      _screenStack.isEmpty ? '' : _screenStack.last;

  /// Recent screens, newest first (max 8), for health exports.
  List<String> get screenTrail => List.unmodifiable(_screenTrail);

  /// Bottom-tab switch: tabs aren't pushed routes, so they reset the
  /// stack instead of pushing.
  void setTabScreen(String label) {
    _screenStack
      ..clear()
      ..add(label);
    _noteTrail(label);
  }

  /// Pushed editor/view opened.
  void pushScreen(String label) {
    if (label.isEmpty) return;
    _screenStack.add(label);
    if (_screenStack.length > 12) {
      _screenStack.removeRange(0, _screenStack.length - 12);
    }
    _noteTrail(label);
  }

  /// Pushed editor/view closed. Never throws; mismatched pops just
  /// remove the top entry when it matches.
  void popScreen([String? label]) {
    if (_screenStack.isEmpty) return;
    if (label == null || _screenStack.last == label) {
      _screenStack.removeLast();
    }
  }

  void _noteTrail(String label) {
    _screenTrail.remove(label);
    _screenTrail.insert(0, label);
    if (_screenTrail.length > 8) {
      _screenTrail.removeRange(8, _screenTrail.length);
    }
  }

  // ── User-action trail ──────────────────────────────────────────
  // What the user DID in new features (agent run, runtime install,
  // terminal command, export, key save) — newest first, max 30,
  // in-memory. Errors already carry the screen; the health export
  // carries this trail, so a pasted report shows actions + errors
  // together. Never throws. Keep entries short and secret-free
  // (callers must redact before passing).

  /// Max retained actions.
  static const maxTrailActions = 30;

  final List<String> _actionTrail = [];

  /// Recent user actions, newest first.
  List<String> get actionTrail => List.unmodifiable(_actionTrail);

  /// Record one user action (`'agent run finished'`). Safe anywhere.
  void trail(String action) {
    try {
      final a = action.trim();
      if (a.isEmpty) return;
      final now = DateTime.now();
      final t = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _actionTrail.insert(0, '$t $a');
      if (_actionTrail.length > maxTrailActions) {
        _actionTrail.removeRange(
            maxTrailActions, _actionTrail.length);
      }
    } catch (_) {}
  }

  /// Static shorthand (mirrors [trackScreen]). Safe before init.
  static void trailAction(String action) {
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().trail(action);
      }
    } catch (_) {}
  }

  // ── Route trail (auto) ─────────────────────────────────────────
  // Every Navigator push/pop — pages, dialogs, bottom sheets — lands
  // here via [LogRouteObserver] (wired once in GetMaterialApp). Sheets
  // never call trackScreen, so without this the trail goes blind the
  // moment a bottom sheet opens — exactly when layout rows fire.
  // Ring buffer, newest first, max 12. Never throws.

  /// Max retained route events.
  static const maxTrailRoutes = 12;

  final List<String> _routeTrail = [];

  /// Recent route pushes/pops, newest first.
  List<String> get routeTrail => List.unmodifiable(_routeTrail);

  /// Record one route event (`→ GetBottomSheet`). Safe anywhere.
  void trailRoute(String event) {
    try {
      final e = event.trim();
      if (e.isEmpty) return;
      final now = DateTime.now();
      final t = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _routeTrail.insert(0, '$t $e');
      if (_routeTrail.length > maxTrailRoutes) {
        _routeTrail.removeRange(
            maxTrailRoutes, _routeTrail.length);
      }
    } catch (_) {}
  }

  /// One-line screen tracking for views (no import needed beyond Get,
  /// which callers already have). Safe before init and after dispose.
  static void trackScreen(String label) {
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().pushScreen(label);
      }
    } catch (_) {}
  }

  /// Matches [trackScreen]; call from dispose().
  static void untrackScreen([String? label]) {
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().popScreen(label);
      }
    } catch (_) {}
  }
  File? _logFile;
  static const int _maxEntries = 500;
  static const int _persistBatch = 25;
  final List<AppLogEntry> _pendingEntries = [];
  bool _flushScheduled = false;
  // Deferred UI mutations, applied in the post-frame flush below. Writing
  // to Rx observables synchronously from _add caused a setState-during-
  // build infinite cascade: FlutterError.onError runs MID-BUILD, so every
  // logged framework error spawned another one (59x in one session).
  // File persistence stays immediate (kill-safe); only UI state waits.
  AppLogEntry? _pendingUnresolved;
  final List<AppLogEntry> _pendingCrashRows = [];

  // ── Crash-survivable diagnostics ──────────────────────────────
  /// Latest ERROR/WARNING that hasn't been cleared by the user ("unfixed").
  /// Persisted to its own file so it survives both process kills and the
  /// rolling [entries] buffer — it stays until [resolveCrashState] is called.
  final unresolvedError = Rxn<AppLogEntry>();

  /// Recent error/warning rows kept permanently (bounded) so even after the
  /// in-memory buffer is trimmed or the app was killed, we know what happened.
  final crashHistory = <AppLogEntry>[].obs;

  String _appVersion = 'unknown';
  String _deviceSummary = '';

  /// Human-readable context for the current unresolved error (version/device).
  String unresolvedErrorMeta = '';
  File? _cachedLastErrorFile;
  File? _cachedCrashHistoryFile;
  static const int _maxCrashHistory = 100;

  final crashPatterns = <CrashPattern>[
    CrashPattern(
      id: 'model_file_missing',
      title: 'Model file missing',
      description: 'Saved model path no longer exists on device.',
      fix: 'Re-download the model from the Models tab.',
      matcher: (e) =>
          e.message.contains('Model file missing') ||
          e.message.contains('not on this device'),
    ),
    CrashPattern(
      id: 'context_overflow',
      title: 'Context window overflow',
      description: 'Input tokens exceed the context window size.',
      fix: 'Increase Context Window Size in Settings or start a new chat.',
      matcher: (e) =>
          e.message.contains('context') &&
          (e.message.contains('overflow') ||
              e.message.contains('exceed') ||
              e.message.contains('too long')),
    ),
    CrashPattern(
      id: 'model_load_failed',
      title: 'Model load failed',
      description: 'The inference engine could not load the model file.',
      fix: 'Check available RAM. Try a smaller quantization (Q4_K_M).',
      matcher: (e) =>
          e.message.contains('load') &&
          (e.message.contains('failed') || e.message.contains('error')) &&
          e.message.contains('model'),
    ),
    CrashPattern(
      id: 'gpu_error',
      title: 'GPU / Neural Engine error',
      description: 'Hardware acceleration failed, falling back to CPU.',
      fix: 'Disable GPU in Settings → Compute Backend, or try CPU.',
      matcher: (e) =>
          (e.message.contains('GPU') || e.message.contains('Neural Engine') ||
              e.message.contains('Vulkan') || e.message.contains('OpenCL')) &&
          (e.message.contains('fail') || e.message.contains('error')),
    ),
    CrashPattern(
      id: 'cloud_api_error',
      title: 'Cloud API error',
      description: 'Network request to cloud provider failed.',
      fix: 'Check internet connection and API key validity.',
      matcher: (e) =>
          e.category == LogCategory.cloud &&
          e.level == 'ERROR' &&
          (e.message.contains('request failed') ||
              e.message.contains('API') ||
              e.message.contains('401') ||
              e.message.contains('429')),
    ),
    CrashPattern(
      id: 'oom',
      title: 'Out of memory',
      description: 'Device ran out of memory during inference.',
      fix: 'Use a smaller model or reduce context window size.',
      matcher: (e) =>
          e.message.contains('OOM') ||
          e.message.contains('out of memory') ||
          e.message.contains('OutOfMemory') ||
          (e.message.contains('memory') && e.level == 'ERROR'),
    ),
    CrashPattern(
      id: 'generation_hang',
      title: 'Generation hang detected',
      description: 'Token stream stopped without completion signal.',
      fix: 'Tap Stop, then retry. If persistent, reload the model.',
      matcher: (e) =>
          e.message.contains('generation') &&
          (e.message.contains('hang') ||
              e.message.contains('timeout') ||
              e.message.contains('no tokens')),
    ),
    CrashPattern(
      id: 'slot_stale',
      title: 'Multi-model slot stale',
      description: 'A model slot pointed to an invalid native state.',
      fix: 'App self-healed. If recurring, restart the app.',
      matcher: (e) =>
          e.message.contains('slot') &&
          (e.message.contains('stale') || e.message.contains('invalid')),
    ),
    CrashPattern(
      id: 'import_failed',
      title: 'Model import failed',
      description: 'Could not copy the GGUF file to app storage.',
      fix: 'Ensure enough free storage and try again.',
      matcher: (e) =>
          e.message.contains('import') &&
          (e.message.contains('failed') || e.message.contains('error')),
    ),
    CrashPattern(
      id: 'firebase_init',
      title: 'Firebase initialization failed',
      description: 'Crash reporting could not start.',
      fix: 'Non-critical. App works without crash reporting.',
      matcher: (e) =>
          e.message.contains('Firebase') && e.message.contains('failed'),
    ),
    CrashPattern(
      id: 'service_init',
      title: 'Deferred service failed to start',
      description:
          'A background service did not initialize in time or threw.',
      fix:
          'Usually transient — restart the app. If a service keeps failing, report it with the log row.',
      matcher: (e) =>
          e.message.contains('failed to init') ||
          e.message.contains('timed out / failed'),
    ),
    CrashPattern(
      id: 'renderflex_overflow',
      title: 'Layout overflow (pixels clipped)',
      description:
          'A row/column was wider/taller than the screen — content hidden behind the striped warning area.',
      fix:
          'The row carries the full widget path + screen size, so the exact widget is identifiable — copy the row and report it with what was open.',
      matcher: (e) =>
          e.message.contains('RenderFlex overflowed') ||
          e.message.contains('overflowed by'),
    ),
    CrashPattern(
      id: 'flutter_framework',
      title: 'Flutter framework assertion',
      description:
          'A framework invariant failed (layout, render object, focus or lifecycle).',
      fix:
          'Copy the row from System Logs and report it — the debugCreator chain pinpoints the widget.',
      matcher: (e) => _containsAny(e, const [
        'Failed assertion',
        '_dependents.isEmpty',
        'debugCreator',
        'RenderFlex overflowed',
        'was used after being disposed',
        '!_skipMarkNeedsLayout',
        'child.owner == owner',
        'RenderObject',
      ]),
    ),
    CrashPattern(
      id: 'getx_scope',
      title: 'GetX empty reactive scope',
      description:
          'A widget rebuilt without reading any observable (framework usage hint).',
      fix:
          'Usually benign. If part of the UI looks stale, report the screen and action.',
      matcher: (e) => _containsAny(e, const [
        'improper use of a GetX',
      ]),
    ),
    CrashPattern(
      id: 'native_crash',
      title: 'Previous-run native/system death',
      description:
          'The OS reported how the last process died (native crash signal, low-memory kill, ANR) — no adb needed.',
      fix:
          'Read the hint under the row: NATIVE CRASH during generation means free RAM / smaller quant / Large-model mode; LOW_MEMORY means close background apps.',
      matcher: (e) => _containsAny(e, const [
        'CRASH_NATIVE',
        'LOW_MEMORY',
        'NATIVE CRASH',
        '[Previous run]',
      ]),
    ),
    CrashPattern(
      id: 'overlay_issue',
      title: 'Overlay corruption',
      description:
          'Duplicate overlay keys or deferred layout children around routes, menus or text selection.',
      fix:
          'Note what was open (dialog, sheet, text selection) and report it.',
      matcher: (e) => _containsAny(e, const [
        'Duplicate GlobalKeys',
        '_OverlayEntryWidgetState',
        '_RenderTheater',
        '_Theater',
        'OverlayPortal',
      ]),
    ),
  ];

  /// True when [e]'s message or details contain any of [needles].
  static bool _containsAny(AppLogEntry e, List<String> needles) {
    final details = e.details;
    for (final n in needles) {
      if (e.message.contains(n)) return true;
      if (details != null && details.contains(n)) return true;
    }
    return false;
  }

  @override
  void onInit() {
    super.onInit();
    _captureDeviceContext();
    unawaited(_restorePersistedState());
    if (!kIsWeb) {
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}
    }
  }

  @override
  void onClose() {
    if (!kIsWeb) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    super.onClose();
  }

  /// Save everything the moment the app goes to the background so an OS kill
  /// while suspended can never lose the most recent diagnostics.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  // ── Crash-survivable persistence ─────────────────────────────

  Future<void> _captureDeviceContext() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        _deviceSummary =
            '${info.manufacturer} ${info.model} • Android ${info.version.release}';
      }
    } catch (_) {}
  }

  Future<File> get _lastErrorFile async {
    final cached = _cachedLastErrorFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_lasterror.json');
    _cachedLastErrorFile = f;
    return f;
  }

  Future<File> get _crashHistoryFile async {
    final cached = _cachedCrashHistoryFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_crash_history.json');
    _cachedCrashHistoryFile = f;
    return f;
  }

  File? _cachedBreadcrumbFile;

  Future<File> get _breadcrumbFile async {
    final cached = _cachedBreadcrumbFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/cubiclm_breadcrumb.json');
    _cachedBreadcrumbFile = f;
    return f;
  }

  /// Kill-proof breadcrumb: awaited flush:true write BEFORE a native call
  /// that can SIGKILL the process (model load). If the app dies, the next
  /// boot finds a `-start` step with no resolution and reports it — so a
  /// silent native death always leaves evidence.
  Future<void> setBreadcrumb(String step, [String detail = '']) async {
    try {
      final f = await _breadcrumbFile;
      await f.writeAsString(
          jsonEncode({
            'step': step,
            'detail': detail,
            'at': DateTime.now().toIso8601String(),
          }),
          flush: true);
    } catch (_) {}
  }

  /// Reads + clears the breadcrumb. Returns null when the previous
  /// session shut down cleanly (or never wrote one).
  Future<Map<String, String>?> takeBreadcrumb() async {
    try {
      final f = await _breadcrumbFile;
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      await f.delete();
      if (decoded is! Map) return null;
      return {
        'step': '${decoded['step'] ?? ''}',
        'detail': '${decoded['detail'] ?? ''}',
        'at': '${decoded['at'] ?? ''}',
      };
    } catch (_) {
      return null;
    }
  }

  /// Persists the "unfixed" error immediately with a *synchronous* write so
  /// even an instant process kill (OOM, force-stop, low-battery death) right
  /// after the error cannot lose it. Errors are rare, so this is cheap.
  Future<void> _persistUnresolved(AppLogEntry entry) async {
    try {
      final f = await _lastErrorFile;
      final payload = jsonEncode({
        ...entry.toJson(),
        'appVersion': _appVersion,
        'device': _deviceSummary,
      });
      unresolvedErrorMeta = '$_appVersion • $_deviceSummary';
      if (entry.screen.isNotEmpty) {
        unresolvedErrorMeta = "$unresolvedErrorMeta • ${entry.screen}";
      }
      // ignore: avoid_slow_async_io
      f.writeAsStringSync(payload, flush: true);
    } catch (_) {}
  }

  Future<void> _appendCrashHistory(AppLogEntry entry) async {
    _pendingCrashRows.insert(0, entry);
    if (_pendingCrashRows.length > _maxCrashHistory) {
      _pendingCrashRows.removeLast();
    }
    try {
      final f = await _crashHistoryFile;
      final list = crashHistory
          .map((e) => {
                ...e.toJson(),
                'appVersion': _appVersion,
                'device': _deviceSummary,
              })
          .toList();
      await f.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  Future<void> _loadPersistedUnresolved() async {
    try {
      final f = await _lastErrorFile;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final entry = AppLogEntry.fromJson(decoded);
      if (entry.level != 'ERROR' && entry.level != 'WARNING') return;

      unresolvedError.value = entry;
      unresolvedErrorMeta = [
        if (decoded['appVersion'] is String)
          decoded['appVersion'] as String,
        if (decoded['device'] is String) decoded['device'] as String,
        if (decoded['s'] is String) decoded['s'] as String,
      ].join(' • ');
      // Surface the previous session's unfixed issue at the very top of the
      // live list so it is visible immediately on the next launch.
      entries.insertAll(0, [
        AppLogEntry(
          level: entry.level,
          message: '[Previous session] ${entry.message}',
          details: entry.details,
          category: entry.category,
          screen: entry.screen,
          timestamp: entry.timestamp,
          lastAt: entry.lastAt,
          count: entry.count,
        ),
      ]);
    } catch (_) {}
  }

  Future<void> _loadPersistedCrashHistory() async {
    try {
      final f = await _crashHistoryFile;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) return;
      crashHistory.assignAll(decoded
          .map((j) => AppLogEntry.fromJson(Map<String, dynamic>.from(j))));
    } catch (_) {}
  }

  Future<void> _restorePersistedState() async {
    // Version/device MUST resolve before the old-death report below:
    // otherwise the persisted error is stamped "unknown" (PackageInfo
    // hadn't finished when onInit fired it unawaited).
    await _captureDeviceContext();
    await _loadPersistedLogs();
    await _loadPersistedUnresolved();
    await _loadPersistedCrashHistory();
    await _reportUnresolvedBreadcrumb();
    await _reportProcessExits();
    await _reportCrashFiles();
  }

  /// JVM crash files written by MainActivity's uncaught-exception handler
  /// (works on every API level — the answer for devices without the
  /// trace stream). One row per file, then deleted.
  Future<void> _reportCrashFiles() async {
    try {
      if (kIsWeb) return;
      final dir = await getApplicationDocumentsDirectory();
      final crashDir = Directory('${dir.path}/cubiclm_crashes');
      if (!await crashDir.exists()) return;
      final files = await crashDir
          .list()
          .where((e) => e is File && e.path.endsWith('.txt'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      var count = 0;
      for (final f in files) {
        String body = '';
        try {
          body = await f.readAsString();
        } catch (_) {}
        try {
          await f.delete();
        } catch (_) {}
        if (body.trim().isEmpty) continue;
        count++;
        if (count > 3) continue;
        if (body.length > 2800) body = '${body.substring(0, 2800)}…';
        error(
          '[Previous run] JAVA CRASH — uncaught exception killed the app',
          details: '$body\nCopy this row + the rows above it and report.',
          category: LogCategory.model,
        );
      }
    } catch (_) {}
  }

  static const _exitChannel =
      MethodChannel('com.cubiclm.app/process_exit');
  static const _exitSeenFileName = 'cubiclm_exit_seen_ms';

  /// Previous-process forensics via ApplicationExitInfo (Android 11+,
  /// no logcat permission needed — own deaths only). Logs one row per
  /// abnormal death newer than the last seen timestamp, newest first,
  /// so a native SIGSEGV/SIGABRT or LMK kill is reportable from inside
  /// the app instead of needing adb.
  Future<void> _reportProcessExits() async {
    try {
      if (kIsWeb) return;
      List<dynamic>? raw;
      try {
        raw = await _exitChannel.invokeListMethod<dynamic>(
            'getRecentExitReasons');
      } catch (_) {
        return; // Non-Android or old channel: nothing to report.
      }
      if (raw == null || raw.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      final seenFile = File('${dir.path}/$_exitSeenFileName');
      var seenMs = 0;
      try {
        if (await seenFile.exists()) {
          seenMs = int.tryParse(await seenFile.readAsString()) ?? 0;
        }
      } catch (_) {}
      var maxMs = seenMs;
      var fresh = 0;
      // Newest first: iterate reversed (channel returns newest first,
      // so keep order but skip seen).
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final reason = (m['reason'] as num?)?.toInt() ?? 0;
        final tsMs = (m['timestampMs'] as num?)?.toInt() ?? 0;
        if (tsMs > maxMs) maxMs = tsMs;
        if (tsMs <= seenMs) continue;
        if (!isCrashExitReason(reason)) continue;
        fresh++;
        if (fresh > 4) continue; // Cap rows; still advance maxMs above.
        final name = processExitReasonName(reason);
        final at = tsMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(tsMs).toIso8601String()
            : 'unknown time';
        final pssMb = ((m['pssKb'] as num?)?.toDouble() ?? 0) / 1024;
        final rssMb = ((m['rssKb'] as num?)?.toDouble() ?? 0) / 1024;
        var desc = '${m['description'] ?? ''}';
        final trace = '${m['trace'] ?? ''}';
        // Trace head (Java stack / tombstone excerpt, API 31+) is the
        // actual diagnosis — keep up to ~2.5KB of it after the one-line
        // description so the row stays copy-paste friendly.
        final combined = (desc + (trace.isEmpty ? '' : '\n--- trace ---\n$trace')).trim();
        final details = combined.isEmpty
            ? _exitHintFor(reason)
            : '${combined.length > 2800 ? '${combined.substring(0, 2800)}…' : combined}\n${_exitHintFor(reason)}';
        error(
          '[Previous run] $name @ $at'
          '${pssMb > 0 ? ' (pss ${pssMb.toStringAsFixed(0)}MB, rss ${rssMb.toStringAsFixed(0)}MB)' : ''}',
          details: details,
          category: (reason == 4 || reason == 5)
              ? LogCategory.model
              : LogCategory.system,
        );
      }
      try {
        await seenFile.writeAsString('$maxMs', flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  /// Actionable one-liner per death kind (shown under the raw signal).
  static String _exitHintFor(int reason) {
    switch (reason) {
      case 4:
        return 'Native crash inside on-device inference (often prompt-time OOM on 4-6GB phones): free RAM, use a smaller quant, enable Large-model mode, or Benchmark first.';
      case 3:
        return 'System killed the app for memory (LMK): free RAM, close background apps, use a smaller model.';
      case 2:
        return 'Process was signal-killed (system/unknown): check free RAM and whether a generation was running.';
      case 5:
        return 'Uncaught app exception: copy this row + the rows above it and report.';
      case 6:
        return 'Main thread stalled (ANR): note what was open and report.';
      default:
        return 'Copy this row and report it with what the app was doing.';
    }
  }

  /// A `-start` breadcrumb with no matching resolution means the previous
  /// process died mid-step (native abort, LMK kill, force-stop) with no
  /// chance to log. Report it as a persisted error so "no logs" deaths
  /// are visible + exportable on the next launch.
  Future<void> _reportUnresolvedBreadcrumb() async {
    try {
      final bc = await takeBreadcrumb();
      if (bc == null) return;
      final step = bc['step'] ?? '';
      if (!step.endsWith('-start')) return;
      final detail = bc['detail'] ?? '';
      error(
        'Previous session ended during: $step${detail.isNotEmpty ? ' ($detail)' : ''}',
        details:
            'The app died without shutting down (native abort or system kill — no Dart log possible). '
            'If this was a model load: re-download the file, free RAM, or try a smaller model. '
            'Breadcrumb from ${bc['at']}.',
        category: LogCategory.model,
      );
    } catch (_) {}
  }

  /// Force-write everything (main log + unresolved record) to disk.
  Future<void> flush() async {
    await _persistLogs();
    final un = unresolvedError.value;
    if (un != null) await _persistUnresolved(un);
  }

  /// Marks the stored crash state as fixed: clears the unfixed error banner,
  /// the previous-session marker row and the crash history, plus their files.
  Future<void> resolveCrashState() async {
    unresolvedError.value = null;
    entries.removeWhere((e) => e.message.startsWith('[Previous session]'));
    crashHistory.clear();
    try {
      final le = await _lastErrorFile;
      if (await le.exists()) await le.delete();
    } catch (_) {}
    try {
      final ch = await _crashHistoryFile;
      if (await ch.exists()) await ch.delete();
    } catch (_) {}
  }

  Future<void> _clearPersistentCrashState() async {
    try {
      final le = await _lastErrorFile;
      if (await le.exists()) await le.delete();
    } catch (_) {}
    try {
      final ch = await _crashHistoryFile;
      if (await ch.exists()) await ch.delete();
    } catch (_) {}
  }

  void warning(String message, {Object? details, LogCategory? category}) {
    _add('WARNING', message, details, category);
  }

  void error(String message, {Object? details, LogCategory? category}) {
    _add('ERROR', message, details, category);
  }

  void info(String message, {Object? details, LogCategory? category}) {
    _add('INFO', message, details, category);
  }

  void debug(String message, {Object? details, LogCategory? category}) {
    _add('DEBUG', message, details, category);
  }

  void _add(String level, String message, Object? details, LogCategory? cat) {
    // Demote GetX's empty-scope hint at every entry path (zone/platform
    // handlers bypass main's FlutterError filter). Same rationale: lint,
    // not failure — searchable, never an error/crash report.
    if ((level == 'ERROR' || level == 'WARNING') &&
        message.contains('improper use of a GetX')) {
      level = 'DEBUG';
    }
    final category = cat ?? LogCategory.system;
    final detailsStr = details?.toString();

    // Collapse exact repeats into one row (count + last-seen bump) instead
    // of appending N identical multi-KB bodies. Any single-symbol change
    // is a different key and stays its own row. Pending-only: touching the
    // shown RxList here would re-enter the build phase (see fields above).
    if (_bumpPendingDuplicate(level, message, detailsStr, category)) return;

    final entry = AppLogEntry(
      level: level,
      message: message,
      details: detailsStr,
      category: category,
      // Signal rows carry the open screen so a pasted log pinpoints
      // WHERE it happened (overflow reports without this are unfixable).
      // Info/debug stay blank to keep the buffer lean.
      screen: (level == 'ERROR' || level == 'WARNING') ? currentScreen : '',
    );
    _pendingEntries.insert(0, entry);

    // Write-through crash survival: every new ERROR/WARNING is persisted to
    // its own file immediately (synchronously for the unresolved record) so
    // a hard process kill right after the failure can't erase it.
    if (level == 'ERROR' || level == 'WARNING') {
      _pendingUnresolved = entry;
      unawaited(_persistUnresolved(entry));
      unawaited(_appendCrashHistory(entry));
    }

    if (!_flushScheduled) {
      _flushScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _flushScheduled = false;
        // Deferred UI state first (banner sees the latest error).
        final un = _pendingUnresolved;
        _pendingUnresolved = null;
        if (un != null) unresolvedError.value = un;
        if (_pendingCrashRows.isNotEmpty) {
          final rows = List<AppLogEntry>.from(_pendingCrashRows);
          _pendingCrashRows.clear();
          for (final r in rows.reversed) {
            crashHistory.insert(0, r);
          }
          while (crashHistory.length > _maxCrashHistory) {
            crashHistory.removeRange(_maxCrashHistory, crashHistory.length);
          }
        }
        final toAdd = List<AppLogEntry>.from(_pendingEntries);
        _pendingEntries.clear();
        // Fold into shown rows with the same dedup+move-to-top rule the
        // old synchronous path had — but safely outside the build phase.
        for (final e in toAdd.reversed) {
          final i = entries.indexWhere(
              (x) => x.sameAs(e.level, e.message, e.details, e.category));
          if (i >= 0) {
            final ex = entries[i];
            ex.count += e.count;
            ex.lastAt = e.lastAt;
            entries.removeAt(i);
            entries.insert(0, ex);
          } else {
            entries.insert(0, e);
          }
        }
        if (entries.length > _maxEntries) {
          entries.removeRange(_maxEntries, entries.length);
        }
        if (entries.length % _persistBatch == 0) {
          _persistLogs();
        }
      });
    }

    if ((level == 'ERROR' || level == 'WARNING') &&
        Get.isRegistered<CrashReportingService>()) {
      Get.find<CrashReportingService>().recordNonFatal(
        details ?? message,
        reason: message,
        extra: {'app_log_level': level, 'category': (cat ?? LogCategory.system).name},
      );
    }
  }

  /// Pending-only duplicate collapse (synchronous-safe: touches no Rx —
  /// see the fields above). Shown-row folding happens in the post-frame
  /// flush. Returns true when an identical pending row was bumped instead.
  bool _bumpPendingDuplicate(String level, String message, String? detailsStr,
      LogCategory category) {
    final now = DateTime.now();
    for (final e in _pendingEntries) {
      if (e.sameAs(level, message, detailsStr, category)) {
        e.count++;
        e.lastAt = now;
        return true;
      }
    }
    return false;
  }

  // --- Search & Filter ---

  List<AppLogEntry> get filteredEntries {
    var result = entries.toList();

    if (selectedLevel.value != 'ALL') {
      result = result.where((e) => e.level == selectedLevel.value).toList();
    }
    if (selectedCategory.value != null) {
      result =
          result.where((e) => e.category == selectedCategory.value).toList();
    }
    final q = searchQuery.value.toLowerCase().trim();
    if (q.isNotEmpty) {
      result = result
          .where((e) =>
              e.message.toLowerCase().contains(q) ||
              (e.details?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return result;
  }

  List<AppLogEntry> get importantEntries =>
      entries.where((entry) => entry.isImportant).toList();

  // --- Health Diagnostics ---

  /// Total occurrences (repeats counted), not just unique rows.
  int get errorCount =>
      entries.where((e) => e.level == 'ERROR').fold(0, (s, e) => s + e.count);
  int get warningCount => entries
      .where((e) => e.level == 'WARNING')
      .fold(0, (s, e) => s + e.count);

  /// Unique error rows (after dedup).
  int get uniqueErrorCount =>
      entries.where((e) => e.level == 'ERROR').length;

  DateTime? get lastError {
    DateTime? latest;
    for (final e in entries) {
      if (e.level != 'ERROR') continue;
      if (latest == null || e.lastAt.isAfter(latest)) latest = e.lastAt;
    }
    return latest;
  }

  List<CrashPattern> get detectedPatterns {
    final detected = <CrashPattern>[];
    for (final pattern in crashPatterns) {
      final matches = entries.where((e) => pattern.matcher(e)).toList();
      if (matches.isNotEmpty) {
        pattern.occurrences = matches.fold(0, (s, e) => s + e.count);
        DateTime? last;
        for (final m in matches) {
          if (last == null || m.lastAt.isAfter(last)) last = m.lastAt;
        }
        pattern.lastSeen = last ?? matches.first.timestamp;
        detected.add(pattern);
      }
    }
    detected.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    return detected;
  }

  Map<String, int> get categoryBreakdown {
    final map = <String, int>{};
    for (final cat in LogCategory.values) {
      final count = entries.where((e) => e.category == cat).length;
      if (count > 0) map[cat.label] = count;
    }
    return map;
  }

  /// ERROR/WARNING rows no pattern claims — so no red row ever goes
  /// untracked again. Sorted newest-first (entries order).
  List<AppLogEntry> get untrackedErrors {
    final out = <AppLogEntry>[];
    outer:
    for (final e in entries) {
      if (e.level != 'ERROR' && e.level != 'WARNING') continue;
      for (final p in crashPatterns) {
        try {
          if (p.matcher(e)) continue outer;
        } catch (_) {}
      }
      out.add(e);
    }
    return out;
  }

  String get healthSummary {
    final patterns = detectedPatterns;
    final buf = StringBuffer();
    buf.writeln('=== CubicLM System Health ===');
    buf.writeln('Total rows: ${entries.length}');
    buf.writeln('Errors: $errorCount  |  Warnings: $warningCount');
    if (currentScreen.isNotEmpty) {
      buf.writeln('Screen now: $currentScreen');
    }
    if (_screenTrail.length > 1) {
      buf.writeln('Recent screens: ${_screenTrail.take(5).join(' ← ')}');
    }
    if (_actionTrail.isNotEmpty) {
      buf.writeln('Recent actions:');
      for (final a in _actionTrail.take(8)) {
        buf.writeln('  • $a');
      }
    }
    if (_routeTrail.isNotEmpty) {
      buf.writeln('Recent routes:');
      for (final r in _routeTrail.take(6)) {
        buf.writeln('  • $r');
      }
    }
    if (uniqueErrorCount != errorCount) {
      buf.writeln('(unique error rows: $uniqueErrorCount)');
    }
    if (lastError != null) {
      buf.writeln('Last error: ${_fmtTime(lastError!)}');
    }
    final un = unresolvedError.value;
    if (un != null) {
      buf.writeln('Unresolved (unfixed) ${un.level}: ${un.message.split('\n').first}');
      buf.writeln('  persisted: ${_fmtTime(un.lastAt)}, app $_appVersion, $_deviceSummary');
    }
    buf.writeln('');
    if (patterns.isEmpty) {
      buf.writeln('✓ No crash patterns detected.');
    } else {
      buf.writeln('Crash patterns detected (${patterns.length}):');
      for (final p in patterns) {
        buf.writeln('  • ${p.title} (${p.occurrences}x)');
        buf.writeln('    Fix: ${p.fix}');
      }
    }
    final untracked = untrackedErrors;
    if (untracked.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Untracked errors/warnings (${untracked.length} rows):');
      for (final e in untracked.take(5)) {
        final firstLine = e.message.split('\n').first.trim();
        final short = firstLine.length > 120
            ? '${firstLine.substring(0, 120)}…'
            : firstLine;
        buf.writeln('  • [${e.level}] $short${e.count > 1 ? ' (×${e.count})' : ''}');
      }
      if (untracked.length > 5) {
        buf.writeln('  …and ${untracked.length - 5} more');
      }
    }
    buf.writeln('');
    buf.writeln('Category breakdown:');
    for (final entry in categoryBreakdown.entries) {
      buf.writeln('  ${entry.key}: ${entry.value}');
    }
    return buf.toString();
  }

  /// Compact AI-ready diagnosis block for one row (Copy-diagnosis button
  /// + Fix-with-Agent task). Everything a fixer needs, nothing more:
  /// first line, widget path, environment, screen, recent actions, top
  /// stack frames. Secrets scrubbed — safe to paste anywhere.
  /// Never throws.
  String diagnosisFor(AppLogEntry e, {bool forAgent = false}) {
    try {
      final buf = StringBuffer();
      if (forAgent) {
        buf.writeln(
            'You are working in the CubicLM Flutter codebase (Dart/Flutter, GetX). '
            'Diagnose the issue below and fix it with a minimal change. '
            'Reply with the file path, the exact edit, and how you verified it.');
        buf.writeln('');
      }
      buf.writeln('### CubicLM issue report');
      buf.writeln('- App: $_appVersion · $_deviceSummary');
      buf.writeln(
          '- When: ${e.lastAt.toIso8601String()}${e.count > 1 ? ' (×${e.count})' : ''}');
      if (e.screen.isNotEmpty) buf.writeln('- Screen: ${e.screen}');
      buf.writeln('- Level: ${e.level} [${e.category.label}]');
      final first = e.message.split('\n').first.trim();
      buf.writeln('- Error: $first');
      final path = _sectionOf(e.message, '--- full widget path');
      if (path.isNotEmpty) {
        buf.writeln('- Widget path:');
        buf.writeln('```');
        buf.writeln(path);
        buf.writeln('```');
      }
      final env = _sectionOf(e.message, '--- environment ---');
      if (env.isNotEmpty) buf.writeln('- Env: $env');
      if (_actionTrail.isNotEmpty) {
        buf.writeln('- Recent actions: ${_actionTrail.take(5).join(' | ')}');
      }
      final stackTop = _stackTop(e.details, 15);
      if (stackTop.isNotEmpty) {
        buf.writeln('- Stack (top):');
        buf.writeln('```');
        buf.writeln(stackTop);
        buf.writeln('```');
      }
      return scrubExportSecrets(buf.toString());
    } catch (_) {
      return 'CubicLM issue: ${e.message.split('\n').first}';
    }
  }

  /// Text under a `--- marker ---` header up to the next `---` header or
  /// end, trimmed to [maxChars].
  String _sectionOf(String message, String marker, {int maxChars = 2000}) {
    try {
      final lines = message.split('\n');
      final start = lines.indexWhere((l) => l.trim().startsWith(marker));
      if (start < 0) return '';
      final out = <String>[];
      for (var i = start + 1; i < lines.length; i++) {
        final t = lines[i].trimRight();
        if (t.trimLeft().startsWith('---') && out.isNotEmpty) break;
        out.add(t);
      }
      var text = out.join('\n').trim();
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars)}…';
      }
      return text;
    } catch (_) {
      return '';
    }
  }

  /// First [maxFrames] `#N` stack lines from details (details already
  /// trimmed at capture; this keeps the diagnosis block compact).
  String _stackTop(String? details, int maxFrames) {
    try {
      if (details == null || details.isEmpty) return '';
      final frames =
          details.split('\n').where((l) => l.startsWith('#')).toList();
      if (frames.isEmpty) return '';
      return frames.take(maxFrames).join('\n');
    } catch (_) {
      return '';
    }
  }

  // --- Persistence ---

  Future<File> get _file async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/cubiclm_logs.json');
    return _logFile!;
  }

  Future<void> _persistLogs() async {
    try {
      final f = await _file;
      // Include still-pending (not yet frame-flushed) rows so even a kill in
      // the same frame as the error keeps that row on disk.
      final combined = <AppLogEntry>[
        ..._pendingEntries,
        ...entries,
      ];
      final toSave = combined.take(200).map((e) => e.toJson()).toList();
      await f.writeAsString(jsonEncode(toSave), flush: true);
    } catch (_) {}
  }

  Future<void> _loadPersistedLogs() async {
    try {
      final f = await _file;
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as List;
        final loaded = json.map((j) => AppLogEntry.fromJson(j)).toList();
        entries.assignAll(loaded);
      }
    } catch (_) {}
  }

  // --- Export ---

  Future<void> copyImportantLogs() async {
    await Clipboard.setData(ClipboardData(text: shareText));
  }

  Future<String> exportFullLogs() async {
    final buf = StringBuffer();
    buf.writeln(healthSummary);
    buf.writeln('');
    buf.writeln('=== Full Log (${entries.length} rows) ===');
    for (final e in entries) {
      buf.writeln(e.formatForExport());
      buf.writeln('');
    }
    return buf.toString();
  }

  String get shareText {
    final selected = importantEntries.isEmpty ? entries : importantEntries;
    return selected.map((entry) => entry.formatForExport()).join('\n\n');
  }

  /// Suggested filename for the .txt export (app version + timestamp).
  String exportFileName(String appVersion) {
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    final ver = appVersion.trim().isEmpty
        ? 'unknown'
        : appVersion.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return 'cubiclm_logs_${ver}_$stamp.txt';
  }

  void clear() {
    entries.clear();
    crashHistory.clear();
    unresolvedError.value = null;
    _persistLogs();
    unawaited(_clearPersistentCrashState());
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// NavigatorObserver that records every route push/pop (pages, dialogs,
/// bottom sheets) into the log service's route trail. Sheets never call
/// trackScreen, so this is what names the open sheet when a layout row
/// fires. Zero log rows — only the bounded trail buffer. Never throws.
class LogRouteObserver extends NavigatorObserver {
  /// Friendly label: `_GetModalBottomSheet<dynamic>` → `BottomSheet`,
  /// `DialogRoute<T>` → `Dialog`, named pages keep their route name.
  static String labelOf(Route? route) {
    try {
      if (route == null) return 'null';
      final name = route.settings.name;
      var t = route.runtimeType.toString();
      // Strip generics: _GetModalBottomSheet<dynamic> → _GetModalBottomSheet
      final tick = t.indexOf('<');
      if (tick >= 0) t = t.substring(0, tick);
      String label;
      if (t.contains('ModalBottomSheet')) {
        label = 'BottomSheet';
      } else if (t.contains('Dialog')) {
        label = 'Dialog';
      } else if (t.contains('PopupMenu')) {
        label = 'PopupMenu';
      } else if (t.startsWith('_')) {
        label = t;
      } else {
        label = t
            .replaceAll('GetPageRoute', 'Page')
            .replaceAll('MaterialPageRoute', 'Page')
            .replaceAll('CupertinoPageRoute', 'Page');
      }
      if (name != null && name.isNotEmpty && name != '/') {
        label = '$label($name)';
      }
      return label;
    } catch (_) {
      return 'route';
    }
  }

  void _record(String arrow, Route? route) {
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().trailRoute('$arrow ${labelOf(route)}');
      }
    } catch (_) {}
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _record('→', route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _record('←', route);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _record('→', newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
