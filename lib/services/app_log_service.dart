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
part 'app_log_persistence.dart';
part 'app_log_writer.dart';
part 'app_log_health.dart';
part 'app_log_export.dart';

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
  File? _cachedBreadcrumbFile;
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


  static const _exitChannel =
      MethodChannel('com.cubiclm.app/process_exit');
  static const _exitSeenFileName = 'cubiclm_exit_seen_ms';
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

}
