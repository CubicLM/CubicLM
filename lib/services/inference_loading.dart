/// Model load: preflight, gates, context cap, engine/server dispatch.
///
/// Split from `inference_service.dart` - behavior is unchanged.
/// Contains: loadModel()
part of 'inference_service.dart';

extension InferenceServiceLoading on InferenceService {
  Future<String> loadModel(
    String modelPath, {
    String? modelName,
    String? modelRuntime,
    bool enableLiteRtVision = false,
    // ModelController pre-gates with dialogs and passes true; every
    // other caller (boot resume, context reload, cloud switch-back)
    // is gated here so no path can reach the native loader unchecked.
    bool skipGate = false,
  }) async {
    if (!supportsLocalInference && !supportsLocalServer) {
      return 'ERROR: Local inference is not available on this platform. Use Cloud mode.';
    }
    if (isLoadingModel.value) return 'ERROR: Model is already loading.';

    if (modelPath.toLowerCase().endsWith('.safetensors')) {
      return 'ERROR: Cannot load image generation models (.safetensors) into the local text engine. Native local image generation requires the upcoming stable-diffusion engine update. Use Cloud Stability AI for now.';
    }

    // Pre-flight: never hand a missing/empty file to the native layer — it
    // responds with an opaque "GGUF model file is missing or unreadable".
    final modelFile = File(modelPath);
    var fileOk = false;
    try {
      fileOk = modelFile.existsSync() && modelFile.lengthSync() > 0;
    } catch (_) {
      fileOk = false;
    }
    if (!fileOk) {
      final savedPath =
          _hive.getSetting<String>(AppConstants.keyLocalModelPath) ?? '';
      if (savedPath == modelPath) {
        // Stale pointer from a previous install/cleared storage — clear it so
        // the resume flow stops offering this model.
        await _hive.setSetting(AppConstants.keyLocalModelPath, '');
        await _hive.setSetting(AppConstants.keyLocalModelName, '');
        await _hive.setSetting(AppConstants.keyLocalModelRuntime, '');
        await _hive.setSetting(AppConstants.keyLocalModelBackend, '');
      }
      Get.find<AppLogService>().error(
        'Model file missing',
        details: 'path=$modelPath',
        category: LogCategory.model,
      );
      return
          'ERROR: "${modelName ?? modelPath.split('/').last}" is not on this device. Open the Models tab and download it first.';
    }

    // GGUF header sanity: a valid magic with garbage metadata segfaults
    // the native loader (no catch possible from Dart). Reject early.
    if (modelPath.toLowerCase().endsWith('.gguf')) {
      final headerError = InferenceService.validateGgufHeader(modelFile);
      if (headerError != null) {
        Get.find<AppLogService>().error(
          'Model file failed header check',
          details: 'path=$modelPath, reason=$headerError',
          category: LogCategory.model,
        );
        return 'ERROR: "${modelName ?? modelPath.split('/').last}" looks corrupted ($headerError). Re-download it from the Models tab.';
      }
    }

        try {
      // RAM snapshot for the Dashboard's before/after line: every load
      // path below records its own completion (or fails without one).
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          Get.find<DeviceInfoService>().snapshotBeforeLoad(
              modelName ?? modelPath.split('/').last);
        }
      } catch (_) {}
      final runtime = _runtimeFor(modelPath, modelRuntime);
      final isLiteRt = runtime == 'litert';      final liteRtMode = _hive.getSetting<String>(
            AppConstants.keyLiteRtPerformanceMode,
            defaultValue: AppConstants.defaultLiteRtPerformanceMode,
          ) ??
          AppConstants.defaultLiteRtPerformanceMode;
      final hadPendingGpuLoad = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuLoadPending,
                defaultValue: false,
              ) ??
              false);
      if (hadPendingGpuLoad) {
        await _hive.setSetting(AppConstants.keyLiteRtGpuLoadPending, false);
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, true);
      }
      final gpuCrashDetected = isLiteRt &&
          (_hive.getSetting<bool>(
                AppConstants.keyLiteRtGpuCrashDetected,
                defaultValue: false,
              ) ??
              false);
      final forceLiteRtCpu = isLiteRt &&
          (liteRtMode == 'cpu_safe' ||
              (liteRtMode == 'auto_fast' && gpuCrashDetected));
      final shouldTryLiteRtGpu =
          isLiteRt && !forceLiteRtCpu && liteRtMode != 'cpu_safe';

      final contextSizeSetting = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      // ── Instant switch: GGUF already resident in the native pool ────────
      // No unload, no reload — just make it the active slot. Only valid when
      // the requested context size matches what the resident slot was loaded
      // with; otherwise fall through to a real load so the new size applies.
      if (!isLiteRt) {
        _engine ??= platform.InferenceEngine();
        final lastLoadedCtx =
            _hive.getSetting<int>('last_loaded_context_size') ?? 0;
        final residentMatchesCtx =
            lastLoadedCtx == 0 || lastLoadedCtx == contextSizeSetting;
        if (residentMatchesCtx) {
          // Windows sidecar serves exactly one model: same path + same
          // ctx means the server is already serving it — no restart.
          if (_serverServes(modelPath)) {
            final requestedName = modelName ?? modelPath.split('/').last;
            isModelLoaded.value = true;
            isLoadingModel.value = false;
            loadingModelName.value = '';
            modelLoadProgress.value = 1.0;
            loadedModelName.value = requestedName;
            loadedModelRuntime.value = 'llama';
            _sessionNativeRuntime = 'llama';
            isVisionLoaded.value = false;
            contextTokensUsed.value = 0;
            contextTokensTotal.value = contextSizeSetting;
            await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
            await _hive.setSetting(
                AppConstants.keyLocalModelName, loadedModelName.value);
            await _hive.setSetting(
                AppConstants.keyLocalModelRuntime, 'llama');
            refreshResidency();
            try {
              if (Get.isRegistered<DeviceInfoService>()) {
                await Get.find<DeviceInfoService>().snapshotAfterLoad();
              }
            } catch (_) {}
            return 'Switched to $requestedName instantly (no reload).';
          }
          final switched = await _engine!.switchActiveModel(modelPath);
          if (switched) {
            final requestedName = modelName ?? modelPath.split('/').last;
            isModelLoaded.value = true;
            isLoadingModel.value = false;
            loadingModelName.value = '';
            modelLoadProgress.value = 1.0;
            loadedModelName.value = requestedName;
            loadedModelRuntime.value = 'llama';
            _sessionNativeRuntime = 'llama';
            isVisionLoaded.value = false;
            contextTokensUsed.value = 0;
            contextTokensTotal.value = contextSizeSetting;
            await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
            await _hive.setSetting(
                AppConstants.keyLocalModelName, loadedModelName.value);
            await _hive.setSetting(
                AppConstants.keyLocalModelRuntime, 'llama');
            Get.find<AppLogService>()
                .info('Instant switch to resident model: $requestedName', category: LogCategory.model);
            try {
              await Get.find<AppLogService>()
                  .setBreadcrumb('model-load-done', requestedName);
            } catch (_) {}
            try {
              if (Get.isRegistered<DeviceInfoService>()) {
                await Get.find<DeviceInfoService>().snapshotAfterLoad();
              }
            } catch (_) {}
            refreshResidency();
            return 'Switched to $requestedName instantly (no reload).';
          }
        }
      }

      // Pool-aware load for GGUF: the native layer frees only the target
      // slot, so other resident models stay loaded. LiteRT is single-session:
      // a litert→litert swap still needs the old one freed first, but a
      // llama→litert switch keeps the GGUF pool resident for instant return.
      // Service-level RAM gate: ModelController pre-gates its own loads
      // (skipGate), but boot-resume, context-size reload and cloud
      // switch-back call here directly — a file bigger than free RAM dies
      // natively with no catch, so every path is checked.
      if (!skipGate && Get.isRegistered<ModelController>()) {
        int fileBytes = 0;
        try {
          fileBytes = modelFile.lengthSync();
        } catch (_) {}
        final gateName = modelName ?? modelPath.split('/').last;
        final action =
            await Get.find<ModelController>().confirmLoadSafety(
          filename: gateName,
          fileBytes: fileBytes,
          isLiteRt: isLiteRt,
        );
        if (action != ModelLoadAction.continueLoad) {
          return 'ERROR: Not enough free RAM to load "$gateName". Close other apps or pick a smaller model.';
        }
      }
      final previousRuntime = loadedModelRuntime.value;
      if (isLiteRt && previousRuntime == 'litert') {
        await unloadModel();
      }
      isLoadingModel.value = true;
      loadingModelName.value = modelName ?? modelPath.split('/').last;
      modelLoadProgress.value = 0.0;

      _engine ??= platform.InferenceEngine();

      final contextSize = _hive.getSetting<int>(
            AppConstants.keyContextSize,
            defaultValue: AppConstants.defaultContextSize,
          ) ??
          AppConstants.defaultContextSize;

      final finalContextSize =
          isLiteRt ? contextSize.clamp(512, 4096) : contextSize;

      // Cap context by CURRENT free RAM (not tier): the KV cache scales
      // with ctx, and requesting 4096+ with <3GB free is a native OOM —
      // instant app death with no Dart log.
      var cappedCtx = finalContextSize;
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          final avail =
              Get.find<DeviceInfoService>().availableRamGB.value;
          if (avail > 0 && avail < 1.5) {
            cappedCtx = 512;
          } else if (avail > 0 && avail < 2.0) {
            cappedCtx = cappedCtx.clamp(512, 1024);
          } else if (avail > 0 && avail < 3.0) {
            cappedCtx = cappedCtx.clamp(512, 2048);
          }
          if (cappedCtx != finalContextSize) {
            Get.find<AppLogService>().info(
              'Context capped to $cappedCtx (free RAM ${avail.toStringAsFixed(1)}GB)',
              category: LogCategory.model,
            );
          }
        }
      } catch (_) {}

      final lastLoadedContext =
          _hive.getSetting<int>('last_loaded_context_size') ?? 0;
      final contextChanged = isLiteRt && lastLoadedContext != cappedCtx;

      final deviceTier = _getDeviceTier();
      final isTensorSoC = _getIsTensorSoC();

      final requestedModelName = modelName ?? modelPath.split('/').last;
      final activeModelName = requestedModelName;
      // Evidence row BEFORE the native call: a JNI-time abort kills the
      // process with no Dart exception, so without this the log shows
      // nothing and the next crash is undebuggable. Breadcrumb + flush
      // survive even SIGKILL (info rows alone would die in memory).
      try {
        final sizeMb = modelFile.lengthSync() ~/ (1024 * 1024);
        final logSvc = Get.find<AppLogService>();
        logSvc.info(
          'Loading local model: $requestedModelName (${sizeMb}MB, ctx=$cappedCtx, tier=$deviceTier)',
          category: LogCategory.model,
        );
        await logSvc.setBreadcrumb(
            'native-load-start', '$requestedModelName (${sizeMb}MB)');
        await logSvc.flush();
      } catch (_) {}
      // Windows sidecar serves GGUF only (.litertlm stays unsupported
      // there); the constructed LoadResult flows through the exact same
      // state updates below as a native load.
      final LoadResult result;
      if (supportsLocalServer && !isLiteRt) {
        result = await _loadViaServer(
          modelPath: modelPath,
          modelName: modelName,
          contextSize: cappedCtx,
          deviceTier: deviceTier,
        );
      } else {
        result = await _loadModelOnEngine(
          modelPath: modelPath,
          modelRuntime: modelRuntime,
          contextSize: cappedCtx,
          deviceTier: deviceTier,
          isTensorSoC: isTensorSoC,
          fileBytes: _safeFileBytes(modelFile),
          liteRtPerformanceMode: liteRtMode,
          forceLiteRtCpu: forceLiteRtCpu,
          clearLiteRtCache: hadPendingGpuLoad ||
              (isLiteRt && gpuCrashDetected) ||
              contextChanged,
          markLiteRtGpuPending: shouldTryLiteRtGpu,
          enableLiteRtVision: enableLiteRtVision,
        );
      }

      // Note: there is deliberately no "model already loaded" recovery path
      // here. The native layer now frees any resident model before loading
      // (LlamaController.loadModel), so that error should not occur — and
      // reporting success for a load that never happened would leave the UI
      // naming one model while inference ran another.

      if (!result.success) {
        isModelLoaded.value = false;
        isLoadingModel.value = false;
        loadingModelName.value = '';
        modelLoadProgress.value = 0.0;
        loadedModelName.value = '';
        loadedModelRuntime.value = '';
        loadedBackend.value = '';
        gpuName.value = '';
        gpuLayersUsed.value = 0;
        isGpuAccelerated.value = false;
        Get.find<AppLogService>().error(
          'Local model load failed',
          details:
              'model=$requestedModelName, runtime=$runtime, backend=${result.backend}, message=${result.message}',
          category: LogCategory.model,
        );
        try {
          await Get.find<AppLogService>()
              .setBreadcrumb('model-load-failed', requestedModelName);
        } catch (_) {}
        return result.message;
      }

      try {
        await Get.find<AppLogService>()
            .setBreadcrumb('model-load-done', requestedModelName);
      } catch (_) {}
      isModelLoaded.value = result.success;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 1.0;
      loadedModelName.value = activeModelName;
      loadedModelRuntime.value = result.runtime;
      if (result.runtime == 'llama' || result.runtime == 'litert') {
        _sessionNativeRuntime = result.runtime;
      }
      loadedBackend.value = result.backend;
      gpuName.value = result.gpuName;
      gpuLayersUsed.value = result.gpuLayers;
      isGpuAccelerated.value = result.backend == 'gpu' || result.gpuLayers > 0;
      if (isLiteRt && result.backend == 'gpu') {
        await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, false);
      }
      contextTokensUsed.value = 0;
      contextTokensTotal.value = cappedCtx;

      await _hive.setSetting(AppConstants.keyLocalModelPath, modelPath);
      await _hive.setSetting(
          AppConstants.keyLocalModelName, loadedModelName.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelRuntime, loadedModelRuntime.value);
      await _hive.setSetting(
          AppConstants.keyLocalModelBackend, loadedBackend.value);

      // Track loaded context size across ALL runtimes so the instant-switch
      // path can tell when a resident slot predates a context-size change.
      await _hive.setSetting('last_loaded_context_size', cappedCtx);

      refreshResidency();
      try {
        if (Get.isRegistered<DeviceInfoService>()) {
          await Get.find<DeviceInfoService>().snapshotAfterLoad();
        }
      } catch (_) {}

      return result.message;
    } catch (e) {
      isModelLoaded.value = false;
      isLoadingModel.value = false;
      loadingModelName.value = '';
      modelLoadProgress.value = 0.0;
      loadedBackend.value = '';
      Get.find<AppLogService>().error('Failed to load local model', details: e, category: LogCategory.model);
      return 'ERROR: Failed to load model — $e';
    }
  }
}
