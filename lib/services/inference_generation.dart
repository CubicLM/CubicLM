/// Streaming generation: budget, overflow guard, token plumbing.
///
/// Split from `inference_service.dart` - behavior is unchanged.
/// Contains: generate()
part of 'inference_service.dart';

extension InferenceServiceGeneration on InferenceService {
  Future<String> generate({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    String source = 'chat',
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    // Windows sidecar counts as a loaded local engine (_engine stays
    // null there by design).
    final useServer = supportsLocalServer && _serverActive;
    if ((!supportsLocalInference && !useServer) ||
        (!useServer && _engine == null) ||
        !isModelLoaded.value) {
      return 'ERROR: No model loaded. Go to Models tab to download and load one.';
    }

    if (isGenerating.value) {
      // A previous generation is still running: first give it a chance
      // to finish on its own, otherwise stop it and wait for TRUE idle
      // (not a fixed delay) before touching the native engine again.
      // Starting a new native generation while the old one still tears
      // down can abort the process on low-RAM devices.
      final settled = await waitForIdle(timeout: const Duration(seconds: 5));
      if (!settled) {
        await stopGeneration();
        await waitForIdle(timeout: const Duration(seconds: 4));
      }
    }

    isGenerating.value = true;
    tokenCount.value = 0;
    tokensPerSecond.value = 0.0;
    generationSource.value = source;
    streamingText.value = '';

    final startTime = DateTime.now();
    DateTime? firstVisibleTokenAt;
    Timer? tokenFlushTimer;
    final tokenFlushBuffer = StringBuffer();

    void flushTokenBuffer() {
      if (tokenFlushBuffer.isEmpty) return;
      final text = tokenFlushBuffer.toString();
      tokenFlushBuffer.clear();
      onToken?.call(text);
    }

    try {
      final temperature = _hive.getSetting<double>(
            AppConstants.keyTemperature,
            defaultValue: AppConstants.defaultTemperature,
          ) ??
          AppConstants.defaultTemperature;

      final maxTokens = _hive.getSetting<int>(
            AppConstants.keyMaxTokens,
            defaultValue: AppConstants.defaultMaxTokens,
          ) ??
          AppConstants.defaultMaxTokens;

      // Local sampling params (GGUF + LiteRT; cloud uses provider defaults).
      final topP = _hive.getSetting<double>(
            AppConstants.keyTopP,
            defaultValue: AppConstants.defaultTopP,
          ) ??
          AppConstants.defaultTopP;
      final topK = _hive.getSetting<int>(
            AppConstants.keyTopK,
            defaultValue: AppConstants.defaultTopK,
          ) ??
          AppConstants.defaultTopK;
      final repeatPenalty = _hive.getSetting<double>(
            AppConstants.keyRepeatPenalty,
            defaultValue: AppConstants.defaultRepeatPenalty,
          ) ??
          AppConstants.defaultRepeatPenalty;

      // ── Context-overflow guard ──────────────────────────────
      // Filling KV past n_ctx aborts the process natively (no Dart
      // exception possible) — this is the "dies right after answering"
      // crash on small-context devices. Estimate room up front, cap
      // this call's budget to fit, refuse when nothing fits, and stop
      // early if the estimate says we're about to hit the wall.
      var effMaxTokens = maxTokens;
      var ctxTotal = 0;
      var promptEst = 0;
      try {
        final info = await _engine!.getContextInfo();
        if (info != null && info.contextSize > 0) {
          ctxTotal = info.contextSize;
          contextTokensTotal.value = ctxTotal;
          var histChars = 0;
          final hist = conversationHistory;
          if (hist != null) {
            for (final m in hist) {
              histChars += (m['content'] ?? '').length;
            }
          }
          promptEst = (prompt.length +
                  (systemPrompt ?? AppConstants.systemPrompt).length +
                  histChars) ~/
              4;
          // GGUF path resets the native session to 0 BEFORE every prefill
          // (_resetNativeSession in _generateInner), so the pre-existing
          // n_past is stale by design and must NOT count against this
          // turn — counting it refused every turn after the first with
          // "Context is full" (room = ctx − stale − promptEst < 0).
          // Only LiteRT/server accumulate across turns.
          final isGgufResetPath =
              !useServer && loadedModelRuntime.value != 'litert';
          final used = isGgufResetPath ? 0 : info.tokensUsed;
          final room = ctxTotal - used - promptEst;
          if (room <= 64) {
            // Log the inputs, not just the refusal: a wrongly-firing
            // guard is otherwise indistinguishable from a genuinely full
            // context in post-mortem logs (this exact blind spot hid the
            // stale-n_past refusal for weeks).
            try {
              Get.find<AppLogService>().warning(
                '[Inference] Context guard refused turn: ctx=$ctxTotal used=$used promptEst=$promptEst room=$room source=$source',
                category: LogCategory.model,
              );
            } catch (_) {}
            return '⚠️ Context is full ($used/$ctxTotal tokens used) — '
                'this turn cannot fit. Start a new chat, or raise Context size '
                'in Settings → Parameters (if RAM allows).';
          }
          final capped = room - 64;
          if (capped < effMaxTokens) effMaxTokens = capped < 64 ? 64 : capped;
        }
      } catch (_) {}
      var overflowCut = false;

      // Shared per-token handler for both engines: counters, live
      // tok/s, overflow trip-wire, LiteRT flush batching.
      void handleToken(String token) {
        firstVisibleTokenAt ??= DateTime.now();
        tokenCount.value++;
        streamingText.value += token;
        // Live overflow trip-wire: estimated KV use passed 95% of the
        // window — stop now (partial answer survives) instead of
        // letting the native layer abort the process a few tokens
        // later. Sync callback: fire-and-forget the async stop.
        if (!overflowCut &&
            ctxTotal > 0 &&
            promptEst + tokenCount.value >= (ctxTotal * 0.95).floor()) {
          overflowCut = true;
          unawaited(stopGeneration());
        }
        final speedStart = firstVisibleTokenAt ?? startTime;
        final elapsedSeconds =
            DateTime.now().difference(speedStart).inMilliseconds / 1000.0;
        if (elapsedSeconds > 0) {
          tokensPerSecond.value = tokenCount.value / elapsedSeconds;
        }
        if (loadedModelRuntime.value == 'litert') {
          tokenFlushBuffer.write(token);
          tokenFlushTimer ??= Timer(const Duration(milliseconds: 60), () {
            tokenFlushTimer = null;
            flushTokenBuffer();
          });
        } else {
          onToken?.call(token);
        }
      }

      // Server-side context accounting: no native info channel, so
      // track our own window (load-time ctx, usage ≈ prompt + tokens).
      if (useServer) {
        ctxTotal = _serverCtx;
        var histChars = 0;
        final hist = conversationHistory;
        if (hist != null) {
          for (final m in hist) {
            histChars += (m['content'] ?? '').length;
          }
        }
        promptEst = (prompt.length +
                (systemPrompt ?? AppConstants.systemPrompt).length +
                histChars) ~/
            4;
        contextTokensTotal.value = ctxTotal;
      }

      // Kill-proof breadcrumb for user-visible turns only (background
      // jobs churn the file too much): written right before the native
      // call with a RAM/backend snapshot, so a mid-generation death
      // reports actionable context on next boot without adb.
      if (source == 'chat') {
        try {
          var detail = loadedModelName.value;
          try {
            final dev = Get.find<DeviceInfoService>();
            detail = '$detail | free=${dev.availableRamGB.value.toStringAsFixed(1)}GB'
                ' ctx=$ctxTotal backend=${loadedBackend.value}';
          } catch (_) {}
          await Get.find<AppLogService>()
              .setBreadcrumb('generation-start', detail);
        } catch (_) {}
      }

      // Last-resort pre-generate gate (native GGUF path only): below
      // ~350MB free even the smallest prefill spike is a proven killer
      // (turn-2 deaths on 2GB phones). Refuse with a clear, chat-visible
      // message instead of letting the OS kill the process mid-prefill —
      // the chat stays alive and the user can free RAM and retry.
      if (!useServer && loadedModelRuntime.value != 'litert') {
        final refusal = _refuseWhenStarved();
        if (refusal != null) return refusal;
      }

      final result = useServer
          ? await _generateViaServer(
              prompt: prompt,
              systemPrompt: systemPrompt ?? AppConstants.systemPrompt,
              conversationHistory: conversationHistory,
              temperature: temperature,
              topP: topP,
              maxTokens: effMaxTokens,
              source: source,
              onToken: handleToken,
            )
          : await _engine!.generate(
              prompt: prompt,
              conversationHistory: conversationHistory,
              systemPrompt: systemPrompt ?? AppConstants.systemPrompt,
              modelName: loadedModelName.value,
              maxTokens: effMaxTokens,
              temperature: temperature,
              topP: topP,
              topK: topK,
              repeatPenalty: repeatPenalty,
              imagePath: imagePath,
              audioPath: audioPath,
              onToken: handleToken,
            );
      tokenFlushTimer?.cancel();
      flushTokenBuffer();

      await refreshContextInfo();
      isGenerating.value = false;
      generationSource.value = '';

      // Detect Tensor SoC + Gemma Q4_K_M corruption: model outputs only
      // special tokens and terminates immediately with empty result.
      if (result.trim().isEmpty &&
          tokenCount.value < 5 &&
          loadedModelName.value.toLowerCase().contains('gemma')) {
        final isTensor = _getIsTensorSoC();
        if (isTensor) {
          if (source == 'chat') {
            try {
              await Get.find<AppLogService>().setBreadcrumb(
                  'generation-failed', 'gemma-tensor-empty');
            } catch (_) {}
          }
          return '⚠️ This Gemma model is incompatible with your Pixel\'s Google Tensor chip. '
              'The Q4_K_M quantization format has a known bug on Tensor SoC that produces empty responses.\n\n'
              'Try one of these fixes:\n'
              '1. Download a Q4_0 or Q5_K_M version of the same model\n'
              '2. Use a different model (Qwen, Phi, or Llama-3)\n'
              '3. Switch to Cloud mode in Settings';
        }
      }

      // Context guard trip: keep the partial answer and say why it
      // stopped, instead of letting the next tokens kill the process.
      if (overflowCut && result.trim().isNotEmpty) {
        return '$result\n\n> ⚠️ Stopped early: the context window was about to fill up '
            '(~$ctxTotal tokens). Start a new chat or raise Context size in '
            'Settings → Parameters to continue.';
      }

      if (source == 'chat') {
        try {
          await Get.find<AppLogService>()
              .setBreadcrumb('generation-done', loadedModelName.value);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      isGenerating.value = false;
      generationSource.value = '';
      streamingText.value = '';
      tokenFlushTimer?.cancel();
      flushTokenBuffer();
      if (source == 'chat') {
        try {
          await Get.find<AppLogService>().setBreadcrumb(
              'generation-failed', '${e.toString().length > 120 ? e.toString().substring(0, 120) : e}');
        } catch (_) {}
      }
      Get.find<AppLogService>().error('Local generation failed', details: e, category: LogCategory.model);
      return 'ERROR: $e';
    }
  }

  /// Near-certain-death line for prefill (~350MB free): returns a
  /// chat-visible refusal, else null. Never throws — a broken reading
  /// must not block generation.
  String? _refuseWhenStarved() {
    try {
      final availGb = Get.find<DeviceInfoService>().availableRamGB.value;
      if (availGb > 0 && availGb * 1024 < 350) {
        return 'ERROR: Only ${(availGb * 1024).round()}MB RAM free — too low to run even a small prompt safely. Close background apps (or restart the app to free memory), then send again.';
      }
    } catch (_) {}
    return null;
  }

}
