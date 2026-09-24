import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../controllers/settings_controller.dart';
import 'app_log_service.dart';
import 'device_info_service.dart';
import 'inference_text.dart';
import 'inference_types.dart';
import 'package:get/get.dart';

/// GGUF inference engine (llama.cpp) - owns the llama.cpp session
/// lifecycle: load, generate, KV guard, hard reset. LiteRT lives in
/// inference_litert.dart; the two engines share no mutable state,
/// so a GGUF edit can never break LiteRT and vice versa.

class GgufEngine {
  LlamaController? _controller;
  StreamSubscription? _subscription;
  StreamSubscription? _loadProgressSub;
  Timer? _idleTimer;
  void Function()? _onStop;
  bool _disposed = false;
  // Last successful GGUF load - used for hard-reset recovery.
  String? _lastModelPath;
  int _lastContextSize = 2048;
  String _lastDeviceTier = 'mid';
  bool _lastIsTensor = false;
  // Consecutive native decode failures across calls. Reset on success.
  int _decodeFailStreak = 0;

  /// ONE shared LlamaController per process.
  ///
  /// Every LlamaController constructor registers itself as the global
  /// Flutter-side token/error handler. Constructing throwaway instances
  /// (e.g. for utility queries) silently steals that handler from the
  /// controller a live generation is streaming on, so tokens vanish and
  /// generation hangs until timeout. Always reuse this instance.
  static final LlamaController _sharedLlama = LlamaController();

  /// Instantly activate an already-resident GGUF model in the native pool.
  /// Returns false when [modelPath] is not resident (caller falls back to a
  /// full load).
  Future<bool> switchActiveModel(String modelPath) async {
    try {
      // Assign the persistent controller so subsequent generate() calls run
      // on the llama path. Skipping this left _controller null after an
      // instant switch and generation failed with "No model loaded".
      final ctl = _controller ??= _sharedLlama;
      final ok = await ctl.switchTo(modelPath);
      if (ok) {        _idleTimer?.cancel();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Paths of GGUF models currently resident in the native pool.
  Future<List<String>> residentModels() async {
    try {
      return await _sharedLlama.residentModels();
    } catch (_) {
      return const [];
    }
  }

  /// Free one specific resident GGUF model (all slots stay otherwise).
  Future<void> freeResidentModel(String modelPath) async {
    try {
      await _sharedLlama.freeByPath(modelPath);
    } catch (_) {}
  }

  /// Pure overflow predicate: true when the upcoming call would push
  /// native KV past 90% of capacity. Retained as a tested utility
  /// (sessions now reset every call via [_resetNativeSession]).
  /// Public for unit tests.
  static bool needsContextClear({
    required int tokensUsed,
    required int contextSize,
    required int promptChars,
    required int maxTokens,
  }) {
    if (contextSize <= 0) return false;
    final estimate = promptChars ~/ 4 + 32;
    return tokensUsed + estimate + maxTokens > contextSize * 0.9;
  }

  /// Drops oldest history turns until the prompt fits [maxPromptChars]
  /// (keeps at least the 2 most recent). A prompt that alone exceeds the
  /// context can never decode — no sliding window saves it. Pure logic,
  /// public for unit tests.
  static List<Map<String, String>>? trimHistoryToFit({
    required List<Map<String, String>>? history,
    required int fixedChars,
    required int maxPromptChars,
  }) {
    if (history == null || history.isEmpty) return history;
    var total = (fixedChars * 1.1).toInt() +
        history.fold<int>(0, (a, m) => a + (m['content']?.length ?? 0));
    if (total <= maxPromptChars) return history;
    final trimmed = List<Map<String, String>>.of(history);
    while (trimmed.length > 2 && total > maxPromptChars) {
      total -= (trimmed.removeAt(0)['content']?.length ?? 0);
    }
    return trimmed;
  }

  /// Low-RAM load profile (pure logic, public for unit tests).
  ///
  /// Phones with <3GB free die when two GGUF models sit resident at once
  /// (mmap page-in spike + compute buffers + KV while the old model's
  /// pages are hot), so those loads evict every other resident first.
  /// Thread counts are clamped down for the same reason: each extra
  /// thread grows the native compute buffer.
  static bool shouldEvictPoolForRam(double availGb) =>
      availGb > 0 && availGb < 3.0;

  static int clampThreadsForRam({
    required int threads,
    required double availGb,
  }) {
    if (availGb <= 0 || availGb >= 3.0) return threads;
    // Below 1.5GB every thread's compute buffer matters: single thread.
    if (availGb < 1.5) return threads <= 1 ? threads : 1;
    // Below 2.5GB a second/third thread's buffers + a hot phone after
    // turn 1 push prefill over the edge (observed turn-2 death at
    // 2.1GB/3 threads): cap at 2.
    final cap = availGb < 2.5 ? 2 : 3;
    return threads <= cap ? threads : cap;
  }

  /// Prompt-processing batch by free RAM (pure logic, unit tested).
  /// The parallel prompt pass is the biggest transient spike after
  /// mmap page-in. Observed turn-2 prefill death at 2.1GB free with
  /// batch 256 — so the 128 tier now extends to 2.5GB. Unknown RAM
  /// (≤0) keeps the historic 512.
  static int resolveBatchSize(double availGb) {
    if (availGb > 0 && availGb < 2.5) return 128;
    if (availGb > 0 && availGb < 3.0) return 256;
    return 512;
  }

  /// Batch thread count by free RAM (pure logic, unit tested).
  /// Prompt-parallel work scales with threads. 1 thread halves the
  /// transient spike but makes prefill ~4x slower than release-era
  /// defaults — on 1.5–2.5GB phones that pushed a 300-token prefill
  /// past every first-token timeout (healthy prefill murdered as
  /// "Model did not respond"). 2 threads halves prefill time back
  /// (~35s) while keeping batch=128's small spike; <1.5GB stays at
  /// 1 thread. -1 keeps the native default (= generation threads).
  static int resolveBatchThreads(double availGb) {
    if (availGb > 0 && availGb < 1.5) return 1;
    if (availGb > 0 && availGb < 2.5) return 2;
    return -1;
  }
  /// Returns [contextSize] unchanged when already minimal.
  static int reducedContextForRetry(int contextSize) {
    if (contextSize <= 512) return contextSize;
    final halved = contextSize ~/ 2;
    return halved < 512 ? 512 : halved;
  }

  /// Acceleration override (pure logic, public for unit tests).
  ///
  /// 'cpu' always disables offload; 'gpu' forces full offload when Vulkan
  /// is present (else CPU fallback); anything else keeps [autoLayers].
  static int resolveGpuLayers({
    required String mode,
    required int autoLayers,
    required bool vulkanSupported,
  }) {
    if (mode == 'cpu') return 0;
    if (mode == 'gpu') return vulkanSupported ? 99 : 0;
    return autoLayers;
  }

  /// Fit-aware auto offload (pure logic, public for unit tests).
  ///
  /// Phone GPUs share unified memory with the CPU, so "flagship GPU"
  /// alone must not force full offload when RAM is tight (instant
  /// OOM, no catch possible). When the model file + KV cache + 20%
  /// headroom fits in free RAM → full offload (99) on any Vulkan GPU.
  /// Otherwise fall back to the tier heuristic ([gpuNum] ≥ 650 keeps
  /// the plugin's [recommendedLayers]); unknown RAM ([availBytes] ≤ 0)
  /// also falls back to the heuristic.
  static int resolveAutoGpuLayers({
    required bool vulkanSupported,
    required int gpuNum,
    required int recommendedLayers,
    required int fileBytes,
    required int kvBytes,
    required int availBytes,
  }) {
    if (!vulkanSupported) return 0;
    if (availBytes > 0 && fileBytes > 0) {
      final fullNeed = ((fileBytes + kvBytes) * 1.2).round();
      if (fullNeed <= availBytes) return 99;
    }
    if (gpuNum >= 650 && recommendedLayers > 0) return recommendedLayers;
    return 0;
  }

  double _availableRamGb() {
    try {
      if (Get.isRegistered<DeviceInfoService>()) {
        return Get.find<DeviceInfoService>().availableRamGB.value;
      }
    } catch (_) {}
    return 0;
  }

  /// Frees every resident GGUF model except [keepPath] so a low-RAM load
  /// never coexists with another model's pages. Best effort only.
  /// Returns the number of evicted residents (for the flushed load log).
  Future<int> _evictOtherResidents(String keepPath) async {
    var evicted = 0;
    try {
      final ctl = _controller ?? _sharedLlama;
      final residents = await ctl.residentModels();
      for (final p in residents) {
        if (p != keepPath) {
          try {
            await ctl.freeByPath(p);
            evicted++;
            print('[Inference] Low-RAM load: evicted resident $p');
          } catch (_) {}
        }
      }
    } catch (_) {}
    return evicted;
  }

  /// Frees the native slot and reloads the last GGUF model from scratch —
  /// guaranteed-clean KV. Used once per call after repeated decode
  /// failures (soft clearContext wasn't enough).
  Future<bool> _hardReloadGguf() async {
    final path = _lastModelPath;
    final ctl = _controller;
    if (path == null || ctl == null) return false;
    try {
      print(
          '[Inference] Hard reset: freeing + reloading model after repeated decode failures.');
      try {
        await ctl.freeByPath(path);
      } catch (_) {}
      final r = await loadModel(
        modelPath: path,
        contextSize: _lastContextSize,
        deviceTier: _lastDeviceTier,
        isTensorSoC: _lastIsTensor,
      );
      return r.success;
    } catch (e) {
      print('[Inference] Hard reset failed: $e');
      return false;
    }
  }

  /// Resets the native KV session before EVERY call (not just when full).
  ///
  /// The native layer never clears between calls: it decodes each new
  /// prompt appended after the previous KV, while Dart re-sends the FULL
  /// history every turn. Without this reset the model sees everything
  /// twice (history + answer + history + answer + new message) and small
  /// models collapse into regurgitating their previous reply verbatim.
  /// Dart re-sends full history by design (edit/regenerate/branch rewrite
  /// it arbitrarily), so dropping native state loses nothing — the
  /// prefill recomputes exactly what was sent. Best effort: a failed
  /// reset must never block generation.
  Future<void> _resetNativeSession() async {
    try {
      // Fully stop any in-flight native run first: clearContext under an
      // active decode is the observed SIGSEGV path (gate may have been
      // released by a timeout while native was still mid-batch).
      await _controller?.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await _controller?.clearContext();
    } catch (_) {
      // Best effort only — a failed reset must never block generation.
    }
  }

  double _normalizeProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) return 0.0;
    final normalized = progress > 1 ? progress / 100 : progress;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  int _extractGpuModel(String gpuName) {
    final match = RegExp(r'(\d{3})').firstMatch(gpuName.toLowerCase());
    return match != null ? (int.tryParse(match.group(1)!) ?? 0) : 0;
  }

  List<ChatMessage> _buildChatMessages(
    String prompt,
    List<Map<String, String>>? history,
    String systemPrompt, {
    String? imagePath,
  }) {
    final messages = <ChatMessage>[];
    messages.add(ChatMessage(role: 'system', content: systemPrompt));

    if (history != null && history.isNotEmpty) {
      var recent = history.length > 16
          ? history.sublist(history.length - 16)
          : List.of(history);
      if (recent.isNotEmpty &&
          recent.last['role'] == 'user' &&
          recent.last['content'] == prompt) {
        recent = recent.sublist(0, recent.length - 1);
      }
      for (final msg in recent) {
        final content = msg['content'] ?? '';
        messages
            .add(ChatMessage(role: msg['role'] ?? 'user', content: content));
      }
    }

    messages
        .add(ChatMessage(role: 'user', content: prompt, imagePath: imagePath));
    return messages;
  }

  String _buildPrompt(
    String userMessage,
    List<Map<String, String>>? history,
    String systemPrompt,
    String modelName,
  ) {
    // Auto-detect template from model name
    final name = modelName.toLowerCase();
    if (name.contains('gemma')) {
      return _buildGemma(userMessage, history, systemPrompt);
    }
    if (name.contains('llama-3') || name.contains('llama3')) {
      return _buildLlama3(userMessage, history, systemPrompt);
    }
    return _buildChatML(userMessage, history, systemPrompt);
  }

  String _buildChatML(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write('<|im_start|>system\n$sys<|im_end|>\n');
    if (history != null) {
      final recent =
          history.length > 8 ? history.sublist(history.length - 8) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write('<|im_start|>${m['role'] ?? 'user'}\n$trunc<|im_end|>\n');
      }
    }
    buf.write('<|im_start|>user\n$msg<|im_end|>\n<|im_start|>assistant\n');
    return buf.toString();
  }

  String _buildGemma(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<start_of_turn>user\n$sys<end_of_turn>\n<start_of_turn>model\nUnderstood.<end_of_turn>\n');
    if (history != null) {
      final recent =
          history.length > 4 ? history.sublist(history.length - 4) : history;
      for (final m in recent) {
        final role = m['role'] == 'assistant' ? 'model' : 'user';
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write('<start_of_turn>$role\n$trunc<end_of_turn>\n');
      }
    }
    buf.write('<start_of_turn>user\n$msg<end_of_turn>\n<start_of_turn>model\n');
    return buf.toString();
  }

  String _buildLlama3(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$sys<|eot_id|>');
    if (history != null) {
      final recent =
          history.length > 4 ? history.sublist(history.length - 4) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write(
            '<|start_header_id|>${m['role'] ?? 'user'}<|end_header_id|>\n\n$trunc<|eot_id|>');
      }
    }
    buf.write(
        '<|start_header_id|>user<|end_header_id|>\n\n$msg<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n');
    return buf.toString();
  }

  /// Load a GGUF model into the native pool (GPU detect, thread tuning,
  /// progress reporting included).
  Future<LoadResult> loadModel({
    required String modelPath,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    int fileBytes = 0,
    void Function(double)? onProgress,
  }) async {
    _disposed = false;
    _controller ??= _sharedLlama;

    // ── GPU Detection ──
    int gpuLayers = 0;
    String gpuNameStr = '';
    var vulkanSupported = false;

    try {
      final gpu = await _controller!.detectGpu();
      gpuNameStr = gpu.gpuName;
      vulkanSupported = gpu.vulkanSupported;

      print('[Inference] GPU: ${gpu.gpuName}');
      print('[Inference]   Vulkan: ${gpu.vulkanSupported}');
      print('[Inference]   Free RAM: ${gpu.freeRamBytes ~/ 1024 ~/ 1024}MB');
      print('[Inference]   Recommended layers: ${gpu.recommendedGpuLayers}');

      // Fit-aware auto offload: file + KV + headroom vs free RAM beats
      // the fixed tier table (a tight flagship falls back instead of
      // OOM-ing; a roomy upper-mid chip gets full offload). [fileBytes]
      // arrives from the facade (0 = unknown → tier heuristic).
      var kvBytes = 0;
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          kvBytes = Get.find<DeviceInfoService>()
              .estimatedKvBytes(contextSize);
        }
      } catch (_) {}
      final gpuNum = _extractGpuModel(gpu.gpuName);
      gpuLayers = GgufEngine.resolveAutoGpuLayers(
        vulkanSupported: gpu.vulkanSupported,
        gpuNum: gpuNum,
        recommendedLayers: gpu.recommendedGpuLayers,
        fileBytes: fileBytes,
        kvBytes: kvBytes,
        availBytes: gpu.freeRamBytes,
      );
      print('[Inference] Auto offload → $gpuLayers layers '
          '(file=${fileBytes ~/ 1024 ~/ 1024}MB, '
          'kv=${kvBytes ~/ 1024 ~/ 1024}MB, free=${gpu.freeRamBytes ~/ 1024 ~/ 1024}MB)');
    } catch (e) {
      print('[Inference] GPU detection failed: $e — CPU fallback');
    }

    // ── User acceleration override (Settings › Parameters) ──
    // 'cpu' forces CPU (stability / diagnosing GPU crashes), 'gpu' forces
    // full offload when Vulkan is present, 'auto' keeps the tier heuristic.
    // Large-model mode forces CPU regardless. Takes effect on load — a
    // resident model is NOT reloaded automatically.
    final settings = Get.find<SettingsController>();
    final largeMode = settings.largeModelMode.value;
    try {
      final accelMode =
          largeMode ? 'cpu' : settings.ggufAccelMode.value;
      final resolved = GgufEngine.resolveGpuLayers(
        mode: accelMode,
        autoLayers: gpuLayers,
        vulkanSupported: vulkanSupported,
      );
      if (resolved != gpuLayers) {
        print('[Inference] Accel mode $accelMode — GPU layers $gpuLayers → $resolved');
        gpuLayers = resolved;
      }
    } catch (e) {
      print('[Inference] Accel override unread: $e — keeping auto result');
    }

    // ── Thread Tuning ──
    int threads;

    if (settings.autoAdjustThreads.value) {
      threads = settings.recommendedThreads;
    } else if (gpuLayers > 0) {
      threads = deviceTier == 'ultra'
          ? 4
          : deviceTier == 'high'
              ? 4
              : 4;
    } else {
      threads = deviceTier == 'ultra'
          ? 6
          : deviceTier == 'high'
              ? 5
              : deviceTier == 'mid'
                  ? 4
                  : 3;
    }

    // Google Tensor SoC (Pixel 6/7/8) has known Q4_K_M dequant bugs
    // that corrupt logits at >1 thread on Gemma models. Force single-threaded
    // to eliminate KV cache races in the quantization dot-product path.
    final modelName = modelPath.toLowerCase();
    if (isTensorSoC && modelName.contains('gemma')) {
      threads = 1;
      print(
          '[Inference] Tensor SoC + Gemma detected — forcing single-threaded inference');
    }

    // ── Low-RAM profile: evict pool + clamp threads ──
    // <3GB free: a second resident model plus this load's page-in spike
    // is what kills the process on 4–6GB phones (instant death, no
    // catch possible) — free the others BEFORE touching native memory.
    // Large-model mode forces the same treatment unconditionally.
    final availGb = _availableRamGb();
    final lowRam = shouldEvictPoolForRam(availGb) || largeMode;
    var evicted = 0;
    if (lowRam) {
      evicted = await _evictOtherResidents(modelPath);
    }
    // Below 2GB free, also drop decoded-image caches: they can hold
    // tens of MB of app RSS that the native load needs more urgently.
    if (availGb > 0 && availGb < 2.0) {
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
    }
    final clampedThreads =
        clampThreadsForRam(threads: threads, availGb: availGb);
    if (clampedThreads != threads) {
      print(
          '[Inference] Low-RAM load (${availGb.toStringAsFixed(1)}GB free) — threads $threads → $clampedThreads');
    }
    threads = clampedThreads;
    // Large-model mode: cap at 2 threads on top — each extra thread
    // grows the native compute buffer that big models can't spare.
    if (largeMode && threads > 2) {
      print('[Inference] Large-model mode — threads $threads → 2');
      threads = 2;
    }
    // Flush the load profile to disk BEFORE the native call: if the
    // process dies inside it, this is the post-mortem evidence of what
    // the low-RAM path actually did (in-memory prints die with it).
    try {
      final log = Get.find<AppLogService>();
      log.info(
        '[Inference] Native load profile: ${availGb.toStringAsFixed(1)}GB free, '
        'evicted=$evicted, threads=$threads, ctx=$contextSize, gpu=$gpuLayers',
        category: LogCategory.model,
      );
      await log.flush();
    } catch (_) {}

    // ── Prompt batch by free RAM ──
    // Set before the native load: the parallel prompt pass is the
    // biggest transient spike, and small batches keep 4-6GB phones
    // alive through it. No-op where the native side is absent.
    final batchSize = GgufEngine.resolveBatchSize(availGb);
    final batchThreads = GgufEngine.resolveBatchThreads(availGb);
    try {
      await _controller!
          .setBatchSize(batchSize, nBatchThreads: batchThreads);
    } catch (_) {}
    print('[Inference] Batch size → $batchSize (threads $batchThreads, '
        'free RAM ${availGb.toStringAsFixed(1)}GB)');

    // ── Load Progress ──
    await _loadProgressSub?.cancel();
    _loadProgressSub = null;
    try {
      _loadProgressSub = _controller!.loadProgress.listen((progress) {
        onProgress?.call(_normalizeProgress(progress));
      });
    } catch (_) {}

    // ── Load ──
    // No "did the load succeed?" flag is tracked here on purpose. The Kotlin
    // side flips its own isModelLoaded during this call, so a load that throws
    // partway (OOM, corrupt file, GPU fallback) leaves a model resident that
    // Dart never saw succeed. dispose() therefore always frees natively, and
    // LlamaController.loadModel frees any resident model before loading.
    var effCtx = contextSize;
    var effThreads = threads;
    try {
      await _controller!.loadModel(
        modelPath: modelPath,
        threads: effThreads,
        contextSize: effCtx,
        gpuLayers: gpuLayers,
      );
    } catch (e) {
      // One reduced-footprint retry before surfacing the error: evict the
      // pool, halve the context, drop to 2 threads. A load that throws
      // (e.g. "Failed to create context") is usually transient memory
      // pressure, not a bad file — the RAM gate already blocked hopeless
      // ones outright.
      final retryCtx = reducedContextForRetry(effCtx);
      final retryThreads = effThreads > 2 ? 2 : effThreads;
      if (retryCtx >= effCtx && retryThreads >= effThreads) rethrow;
      print(
          '[Inference] Load failed ($e) — retrying once with ctx=$retryCtx, threads=$retryThreads after pool eviction.');
      await _evictOtherResidents(modelPath);
      try {
        await _controller!.setBatchSize(
            batchSize ~/ 2 < 64 ? 64 : batchSize ~/ 2,
            nBatchThreads: 1);
      } catch (_) {}
      try {
        final log = Get.find<AppLogService>();
        log.info(
          '[Inference] Retrying native load once: ctx=$retryCtx, threads=$retryThreads.',
          category: LogCategory.model,
        );
        await log.flush();
      } catch (_) {}
      await _controller!.loadModel(
        modelPath: modelPath,
        threads: retryThreads,
        contextSize: retryCtx,
        gpuLayers: gpuLayers,
      );
      effCtx = retryCtx;
      effThreads = retryThreads;
    }
    // Remember for hard-reset recovery (repeated native decode failures).
    _lastModelPath = modelPath;
    _lastContextSize = effCtx;
    _lastDeviceTier = deviceTier;
    _lastIsTensor = isTensorSoC;
    _decodeFailStreak = 0;

    final accel = gpuLayers > 0
        ? 'GPU ($gpuLayers layers, $gpuNameStr)'
        : 'CPU ($effThreads threads)';
    print('[Inference] ✓ Model loaded: $accel, ctx=$effCtx');

    return LoadResult(
      success: true,
      message: 'Model loaded ($accel).',
      gpuName: gpuNameStr,
      gpuLayers: gpuLayers,
      runtime: 'llama',
      backend: gpuLayers > 0 ? 'gpu' : 'cpu',
    );
  }

  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {

    if (_controller == null) throw Exception('No model loaded');
    if (imagePath != null && imagePath.isNotEmpty) {
      return 'GGUF image input is not available in this build yet. This llama runtime is text-only right now: it does not load a matching mmproj vision projector or send image pixels into llama.cpp. Use a LiteRT vision model for image understanding.';
    }
    if (audioPath != null && audioPath.isNotEmpty) {
      return 'GGUF audio input is not available in this build yet. Text files can be read when their content is attached, but audio needs a model/runtime path that supports audio input.';
    }

    // Serialize native generations: llama.cpp contexts die with SIGSEGV
    // on overlapping decodes (observed turn-2 death). A newcomer waits
    // for the in-flight call (bounded); only a stuck holder (>45s past
    // every timeout) yields a clean busy-error instead of overlapping.
    if (!_nestedNativeCall) {
      var waited = 0;
      while (_nativeGate != null) {
        if (waited >= 45) {
          return 'ERROR: Engine is busy finishing the previous reply — wait a moment and send again.';
        }
        try {
          await _nativeGate!.future.timeout(const Duration(seconds: 2));
        } catch (_) {}
        waited += 2;
      }
      if (waited > 0) {
        print('[Inference] Native gate waited ${waited}s for in-flight call.');
      }
      _nativeGate = Completer<void>();
    }
    try {
      return await _generateInner(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt,
        modelName: modelName,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        repeatPenalty: repeatPenalty,
        imagePath: imagePath,
        audioPath: audioPath,
        onToken: onToken,
      );
    } finally {
      if (!_nestedNativeCall) {
        final gate = _nativeGate;
        _nativeGate = null;
        if (gate != null && !gate.isCompleted) gate.complete();
      }
    }
  }

  /// Set while [generate] runs its post-failure self-retry so the nested
  /// call skips the gate (the outer call still holds it).
  bool _nestedNativeCall = false;

  /// Chain of in-flight native calls (completers, never errors).
  Completer<void>? _nativeGate;

  Future<String> _generateInner({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    final p = topP ?? 0.9;
    final k = topK ?? 40;
    final r = repeatPenalty ?? 1.1;
    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;
    bool retried = false;
    // Lifecycle timestamps for the post-mortem outcome line: prefill vs
    // total time is what separates "slow phone" from "hung engine".
    // (tokenCount lives up here too so finish() can report it — it is
    // only mutated in the stream callbacks below.)
    final genStart = DateTime.now();
    DateTime? firstTokenAt;
    var tokenCount = 0;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        if (!result.startsWith('ERROR')) _decodeFailStreak = 0;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        // One structured outcome row per generation: tokens, wall time,
        // first-token latency (prefill cost), and ok vs which error.
        // Post-mortem, this single row answers "did prefill fit the
        // timeout?" without correlating native batch logs by hand.
        try {
          final totalS =
              DateTime.now().difference(genStart).inMilliseconds / 1000.0;
          final firstS = firstTokenAt == null
              ? 'NO-TOKEN'
              : '${(firstTokenAt!.difference(genStart).inMilliseconds / 1000.0).toStringAsFixed(1)}s';
          final outcome = result.startsWith('ERROR')
              ? result.split('\n').first
              : 'ok';
          Get.find<AppLogService>().info(
            '[Inference] generate finished: tokens=$tokenCount total=${totalS.toStringAsFixed(1)}s firstToken=$firstS result=$outcome',
            category: LogCategory.model,
          );
        } catch (_) {}
        // Hold the completer until native has actually left nativeGenerate.
        // The generate() gate releases only after completer completes —
        // completing while llama_decode still runs lets the next call
        // clearContext under the live graph (SIGSEGV in mul_mat).
        () async {
          try {
            await _controller?.stop().timeout(const Duration(seconds: 5));
          } catch (_) {}
          if (!completer.isCompleted) completer.complete(result);
        }();
      }
    }

    _onStop = () {
      finish(buffer.toString());
    };

    // ── Use generateChat() for native template handling ──
    Stream<String>? stream;
    try {
      // Cap the prompt: a single prompt bigger than the context can NEVER
      // fit (no sliding window saves it) — trim oldest history first.
      var history = conversationHistory;
      try {
        final probe = await _controller?.getContextInfo();
        final ctx = probe?.contextSize ?? 0;
        if (ctx > 0) {
          final trimmed = trimHistoryToFit(
            history: history,
            fixedChars: systemPrompt.length + prompt.length,
            maxPromptChars: (ctx * 0.75 * 4).toInt(),
          );
          if (!identical(trimmed, history)) {
            print(
                '[Inference] Prompt too big for ctx=$ctx — trimmed history ${(history?.length ?? 0)} → ${trimmed?.length ?? 0} turns.');
          }
          history = trimmed;
        }
      } catch (_) {}
      final messages = _buildChatMessages(
          prompt, history, systemPrompt,
          imagePath: imagePath);
      // Fresh native session for every call (see _resetNativeSession):
      // the prefill below decodes exactly these messages from position 0.
      await _resetNativeSession();
      // Small on-device models tend to rehash their own previous answer
      // on weak follow-ups ("then", "and?"). A gentle presence/frequency
      // penalty plus a wider penalty window pushes novel phrasing without
      // stiffening output; the user's repeat-penalty slider still applies
      // on top via [r].
      stream = _controller!.generateChat(
        messages: messages,
        template: null,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: p,
        topK: k,
        minP: 0.05,
        repeatPenalty: r,
        frequencyPenalty: 0.1,
        presencePenalty: 0.2,
        repeatLastN: 128,
      );
      print('[Inference] generateChat() started (${messages.length} messages)');
    } catch (e) {
      print('[Inference] generateChat() failed: $e — fallback to generate()');
      try {
        await _controller?.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
      // The fallback path decodes the full prompt itself: reset the
      // native session first, otherwise it prefills onto stale KV
      // (duplicate context at best, out-of-range cells at worst).
      try {
        await _resetNativeSession();
      } catch (_) {}
      final fullPrompt =
          _buildPrompt(prompt, conversationHistory, systemPrompt, modelName);
      stream = _controller!.generate(
        prompt: fullPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: p,
        topK: k,
        minP: 0.05,
        repeatPenalty: r,
        frequencyPenalty: 0.1,
        presencePenalty: 0.2,
        repeatLastN: 128,
      );
    }

    _subscription = stream.listen(
      (token) {
        if (tokenCount == 0) {
          firstTokenAt = DateTime.now();
          print('[Inference] ✓ FIRST TOKEN received! Prefill done.');
        }
        final clean = sanitizeGemmaGarbage(token);
        if (clean.isEmpty) return;
        buffer.write(clean);
        tokenCount++;
        onToken?.call(clean);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          print('[Inference] Idle timeout — $tokenCount tokens');
          finish(buffer.toString());
        });
      },
      onDone: () {
        print('[Inference] Stream onDone — $tokenCount tokens total');
        finish(buffer.toString());
      },
      onError: (error) async {
        print('[Inference] Stream error: $error');
        final msg = error.toString();
        final isDecode = msg.contains('decode prompt') || msg.contains('decode');
        if (isDecode) {
          _decodeFailStreak++;
          // Native KV overflowed despite the pre-check (race between
          // calls). Self-heal so the NEXT call works.
          try {
            await _controller?.clearContext();
          } catch (_) {}
          // Twice in a row = native state is corrupt beyond a soft
          // clear (bad shift, partial-write). Nuke it: free + reload
          // the model, then retry this exact call once.
          if (!retried && _decodeFailStreak >= 2 && _lastModelPath != null) {
            retried = true;
            _decodeFailStreak = 0;
            if (await _hardReloadGguf()) {
              // Nested retry: bypass the native gate (outer call holds
              // it until its own finish()).
              _nestedNativeCall = true;
              try {
                finish(await generate(
                prompt: prompt,
                conversationHistory: conversationHistory,
                systemPrompt: systemPrompt,
                modelName: modelName,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: p,
                topK: k,
                repeatPenalty: r,
                imagePath: imagePath,
                audioPath: audioPath,
                onToken: onToken,
              ));
              } finally {
                _nestedNativeCall = false;
              }
              return;
            }
          }
          finish(
              'ERROR: Conversation grew past the model\'s context. I cleared it — send again (older turns may be trimmed).');
        } else {
          finish('ERROR: Generation failed — $error');
        }
      },
    );

    // Prefill timeout, scaled to FULL prompt size: the native prompt is
    // dominated by the system prompt + tools (~250-300 tokens even for a
    // one-word user message). Estimating from the user message alone kept
    // the timeout at ~61s while 1-thread prefill needs ~70s+ — the timer
    // fired mid-prefill, finish() stopped native, and every prompt died
    // with "Model did not respond" (healthy prefill murdered, no crash).
    var histChars = 0;
    try {
      final hist = conversationHistory;
      if (hist != null) {
        for (final m in hist) {
          histChars += (m['content'] ?? '').length;
        }
      }
    } catch (_) {}
    final estTokens =
        (systemPrompt.length + prompt.length + histChars) ~/ 4;
    var prefillSecs = 60 + estTokens ~/ 2;
    if (prefillSecs < 90) prefillSecs = 90;
    if (prefillSecs > 300) prefillSecs = 300;
    _idleTimer = Timer(Duration(seconds: prefillSecs), () {
      if (tokenCount == 0) {
        // Log the fire with its inputs: silent timeouts look exactly
        // like a dead engine in post-mortem logs.
        try {
          Get.find<AppLogService>().warning(
            '[Inference] Prefill timeout fired after ${prefillSecs}s with 0 tokens (promptEst=$estTokens) — stopping native.',
            category: LogCategory.model,
          );
        } catch (_) {}
        finish(
            'ERROR: Model did not respond. Try a smaller model or shorter conversation.');
      }
    });

    // Hard timeout (bounds a truly-hung native; slow-but-healthy runs
    // must fit: 512 reply tokens at ~2 tok/s on 1 thread ≈ 250s).
    Future.delayed(const Duration(seconds: 300), () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty ? 'ERROR: Generation timed out.' : partial);
      }
    });

    return await completer.future;
  }

  /// Stop the current generation, if any.
  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCallback = _onStop;
    _onStop = null;
    stopCallback?.call();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    try {
      await _controller?.stop().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  Future<ContextInfo?> getContextInfo() async {
    try {
      return await _controller?.getContextInfo();
    } catch (_) {
      return null;
    }
  }

  /// Unload the model and free native resources.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    // Always attempt the native free: the Kotlin/C++ side can hold a model this
    // object never saw succeed (a load that threw partway still leaves g_model
    // resident), and skipping the free is what blocks all later loads until the
    // process restarts.
    try {
      await _controller?.dispose();
    } catch (_) {}
    unawaited(_loadProgressSub?.cancel() ?? Future<void>.value());
    _loadProgressSub = null;
    _controller = null;
  }
}
