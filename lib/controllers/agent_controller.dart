import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/settings_controller.dart';
import '../services/agent_workspace.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/inference_service.dart';
import '../services/preview_server.dart';
import '../services/runtime/ansi.dart';
import '../services/cubicweb/cubicweb_event.dart';
import '../services/cubicweb/cubicweb_logger.dart';
import '../services/runtime/cli_manager.dart';
import '../services/runtime/cli_manifest.dart';
import '../services/runtime/cloud_runtime.dart';
import '../services/runtime/dev_server_manager.dart';
import '../services/runtime/preview_router.dart';
import '../services/runtime/process_runner.dart';
import '../services/runtime/project_detector.dart';
import '../services/runtime/project_validator.dart';
import '../services/runtime/runtime_manager.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import '../utils/web_project.dart';
import '../models/preview_step.dart';
part 'agent_controller_workspace.dart';
part 'agent_controller_chat.dart';
part 'agent_controller_streaming.dart';
part 'agent_controller_generation.dart';
part 'agent_controller_runtime.dart';

/// Agent-IDE orchestrator (MVP): prompt → files → local preview →
/// console-error repair loop (changed files only, max rounds).
class AgentController extends GetxController {
  static const maxRepairRounds = 3;
  static const maxContextChars = 60000;

  final topic = ''.obs;
  final framework = 'Single HTML'.obs;
  final project = Rxn<AgentProject>();
  final files = <String>[].obs;
  final generating = false.obs;
  final fixing = false.obs;
  final autoFix = true.obs;
  final planMode = false.obs;
  final extendedThinking = false.obs;
  final webSearch = false.obs;
  
  /// New Builder Settings
  final liveFlushThrottle = 1500.obs; // ms
  final enableLivePreview = true.obs;
  final selectedLibrary = 'Auto'.obs; // Auto | shadcn | Tailwind | Lucide
  final selectedDesignSystem = 'Modern'.obs; // Modern | Retro | Enterprise
  
  /// Stats for the current change
  final lastInsertions = 0.obs;
  final lastDeletions = 0.obs;

  /// Pending plan awaiting user approval (null when no plan pending).
  final pendingPlan = RxnString();

  /// Last modify diffs — file path → (old content, new content).
  final lastDiffs = <String, Map<String, String>>{}.obs;

  /// Live-streamed files mid-generation (path → partial content).
  /// Shown in the Files tab + streaming editor while the AI writes;
  /// cleared once final files land on disk.
  final streamingFiles = <String, String>{}.obs;

  /// True while partial output is being flushed (drives live UI).
  final streamingActive = false.obs;

  /// True once partial files hit disk at least once (live preview on).
  final livePreviewReady = false.obs;

  /// Set by Stop — in-flight awaits can't be aborted, but their results
  /// are discarded and flags reset.
  bool _cancelled = false;

  void cancelWork() {
    _cancelled = true;
  }

  final previewUrl = RxnString();
  final consoleError = RxnString();
  final lastError = RxnString();
  final revision = 0.obs;

  /// Runtime-aware preview routing (see services/runtime/).
  final previewKind = ProjectKind.staticSite.obs;
  final previewIssues = <ProjectIssue>[].obs;
  final previewSteps = <PreviewStep>[].obs;
  final previewDecision = Rxn<PreviewDecision>();

  /// Live dev-server URL when the pipeline runs one (null otherwise).
  final devServerUrl = RxnString();
  final devServerStarting = false.obs;

  /// True while `npm run build` validation runs.
  final validatingBuild = false.obs;

  /// Token tracking
  final totalTokensUsed = 0.obs;
  final lastRequestTokens = 0.obs;
  final projectSizeKb = 0.0.obs;

  /// Smart Suggestions
  final suggestions = <String>[].obs;

  /// Runtime Error Details
  final runtimeError = Rxn<Map<String, dynamic>>();

  /// Cloud fallback provider (unconfigured in this build — honest stub).
  final CloudRuntimeProvider cloudRuntime = UnconfiguredCloudRuntime();

  /// Map of path -> {old: string, new: string} for pending AI changes.
  final pendingChanges = <String, Map<String, String>>{}.obs;

  /// True while the user is reviewing pending changes in the diff view.
  final reviewingChanges = false.obs;

  /// Buffer for console logs from the preview WebView.
  final consoleBuffer = <Map<String, dynamic>>[].obs;

  /// Map of checkpoint ID -> screenshot bytes (visual history).
  final checkpointThumbnails = <String, Uint8List>{}.obs;

  /// Map of brand properties (primaryColor, secondaryColor, font, logo).
  final brandIdentity = <String, String>{}.obs;

  /// Correlation id for the current build/modify/fix operation (§23).
  /// Passed to every CubicWeb event so one operation's story rebuilds.
  String currentTraceId = '';

  /// Apply all pending changes from the diff view to the project files.

  final activeCliId = RxnString();
  final detectedCliId = RxnString();
  final detectedCliVersion = RxnString();
  final terminal = <String>[].obs;
  final transcript = <Map<String, dynamic>>[].obs;
  final buildStatus = RxnString();
  final attachedImage = RxnString();
  final pickedElement = RxnString();
  final hoveredElement = RxnString();
  final requestAskFocus = 0.obs;
  final elementPickMode = false.obs;
  final buildSteps = <Map<String, String>>[].obs;
  final _announcedPaths = <String>{};
  int _autoRounds = 0;

  AgentWorkspaceService get _ws => Get.find<AgentWorkspaceService>();
  PreviewServerService get _preview => Get.find<PreviewServerService>();

  /// Latest preview WebView controller (set by the view). Used for
  /// element picking arming + screenshot capture.
  InAppWebViewController? previewWebController;
  int _lastStatusMs = 0;
  int _lastLiveWriteMs = 0;

  Future<void> deleteProject(String id) async {
    try {
      await Get.find<DevServerManager>().stop(id);
    } catch (_) {}
    if (project.value?.id == id) {
      project.value = null;
      files.clear();
      previewUrl.value = null;
      devServerUrl.value = null;
      previewIssues.clear();
      previewSteps.clear();
      previewDecision.value = null;
      await _preview.stop();
    }
    await _ws.deleteProject(id);
  }

  Future<void> exportZip() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      final archive = Archive();
      for (final path in await _ws.listFiles(p.id)) {
        final bytes = await File('${dir.path}/$path').readAsBytes();
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
      final out = ZipEncoder().encode(archive);
      if (out.isEmpty) throw Exception('ZIP encoder returned nothing.');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = 'cubicagent_$stamp.zip';
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(out),
        fileName: name,
        mimeType: 'application/zip',
        category: 'agent',
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  // ── Engine (same rules as chat) ──

  Future<String> _ask(
      {required String prompt,
      required String system,
      void Function(int chars)? onProgress,
      void Function(String partial)? onPartial}) async {
    final settings = Get.find<SettingsController>();
    // Inject extended thinking instructions.
    var sys = system;
    if (extendedThinking.value) {
      sys += '\n\nTHINKING MODE: Before writing any code, think step-by-step. '
          'Analyze requirements, consider edge cases, plan the structure, '
          'then write clean, well-organized code.';
    }
    if (webSearch.value) {
      sys += '\n\nWEB SEARCH: If you need current library versions, CDN URLs, '
          'or best practices, include them. Use well-known, stable CDN '
          'links (unpkg, cdnjs, jsdelivr) for external libraries.';
    }
    final buf = StringBuffer();
    var count = 0;
    var lastPartialMs = 0;
    void bump(String chunk) {
      buf.write(chunk);
      count += chunk.length;
      try {
        onProgress?.call(count);
      } catch (_) {}
      // Throttled live-flush hook for streaming file preview (~2/sec).
      if (onPartial != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastPartialMs >= 500) {
          lastPartialMs = now;
          try {
            onPartial(buf.toString());
          } catch (_) {}
        }
      }
    }

    try {
      if (settings.inferenceMode.value == 'cloud') {
        final cloud = Get.find<CloudService>();
        await for (final chunk in cloud.streamMessage(
          [
            {'role': 'system', 'content': sys},
            {'role': 'user', 'content': prompt},
          ],
          temperature: settings.temperature.value,
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
          imageBase64: attachedImage.value,
        )) {
          bump(chunk);
        }
      } else {
        final inference = Get.find<InferenceService>();
        if (!inference.isModelLoaded.value) {
          throw Exception(
              'No local model loaded — load one in Explore → Local, or switch to Cloud mode.');
        }
        await inference.generate(
          prompt: prompt,
          systemPrompt: system,
          source: 'agent',
          onToken: bump,
        );
      }
      
      final out = buf.toString().trim();
      if (out.isEmpty) throw Exception('The model returned nothing.');
      
      // Update token tracking (heuristic: 4 chars = 1 token)
      final tokens = (out.length / 4).round();
      lastRequestTokens.value = tokens;
      totalTokensUsed.value += tokens;
      
      return out;
    } finally {
      // Any cleanup if needed
    }
  }

  /// Magic Wand: Auto-Polish the UI
  Future<void> autoPolish() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    currentTraceId = newTraceId();
    
    _say('user', '🪄 Auto-Polish: Refine UI styles and alignment');
    _say('activity', '');
    buildStatus.value = 'Polishing UI…';
    term('> auto-polish: refining "${p.name}"…');
    _beginSteps();
    step('thinking', 'Analyzing UI for refinements…');

    try {
      final beforeCp = await _ws.saveCheckpoint(p.id, label: 'Before auto-polish');
      final projContext = await _projectContext(p.id);
      
      final raw = await _ask(
        prompt: 'Refine and polish the UI of the "${p.name}" ${p.framework} project. '
            'Focus on: fixing inconsistent spacing/padding, improving color contrast, '
            'refining typography, adding subtle transitions/animations, and ensuring '
            'perfect alignment. Keep the core logic and features identical.\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'Return a files-JSON object with ONLY the polished files (complete new contents).',
        system: '${webSystemPrompt(
          framework: p.framework, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        )}\n'
            'You are a senior UI/UX engineer. Your goal is to make the design "lovable".',
        onProgress: (n) => _streamStatus('Polishing', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );

      if (_cancelled) {
        try {
          await _ws.rollbackToCheckpoint(p.id, beforeCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        return;
      }

      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      
      pendingChanges.clear();
      final currentFiles = await _projectContents(p.id);
      for (final f in parsed) {
        final old = currentFiles[f.path] ?? '';
        pendingChanges[f.path] = {'old': old, 'new': f.content};
      }
      
      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ UI polished — review the refinements');
        step('done', 'UI polished — ready for review.');
      } else {
        term('! no refinements needed');
        step('done', 'No refinements needed.');
      }
      
      _snapshotActivity();
      _say('assistant', 'I\'ve polished the UI. Review the refinements in the diff view.');
      _markLastAssistantWithBuild();

    } catch (e) {
      lastError.value = '$e';
      term('✗ polish failed: $e');
      step('error', 'Polish failed.');
    } finally {
      _clearStreaming();
      generating.value = false;
      buildStatus.value = null;
    }
  }

  void _log(String message, Object e) {
    try {
      Get.find<AppLogService>().warning(
        message,
        details: '$e',
        category: LogCategory.chat,
      );
    } catch (_) {}
  }

  List<AgentProject> projectsOf() => _ws.projects.toList();

  @override
  void onClose() {
    try {
      Get.find<PreviewServerService>().stop();
    } catch (_) {}
    try {
      Get.find<DevServerManager>().stopAll();
    } catch (_) {}
    try {
      Get.find<CliManagerService>().killAllLaunched();
    } catch (_) {}
    activeCliId.value = null;
    super.onClose();
  }
}
