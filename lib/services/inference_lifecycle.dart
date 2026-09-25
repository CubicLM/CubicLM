/// Unload, stop, idle wait, conversation reset, context refresh.
///
/// Split from `inference_service.dart` - behavior is unchanged.
/// Contains: unloadModel(), stopGeneration(), waitForIdle(), resetConversation(), refreshContextInfo()
part of 'inference_service.dart';

extension InferenceServiceLifecycle on InferenceService {
  Future<void> unloadModel() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await stopGeneration();
      await engine.dispose();
    }
    // Windows sidecar has no engine object — stop the child process.
    if (_server != null) {
      await stopGeneration();
      await _server!.stop();
      _serverCtx = 0;
    }
        isModelLoaded.value = false;
    isVisionLoaded.value = false;
    loadedModelName.value = '';
    // The freed RAM returns to the pool — drop the stale before/after.
    try {
      if (Get.isRegistered<DeviceInfoService>()) {
        Get.find<DeviceInfoService>().clearLoadSnapshot();
      }
    } catch (_) {}    loadingModelName.value = '';
    loadedModelRuntime.value = '';
    loadedBackend.value = '';
    gpuLayersUsed.value = 0;
    isGpuAccelerated.value = false;
    gpuName.value = '';
    contextTokensUsed.value = 0;
    contextTokensTotal.value = 0;
    residentTextModels.assignAll(<String>[]);
    // _sessionNativeRuntime is intentionally NOT cleared. Unloading frees the
    // model, but the runtime's .so files stay loaded in the process for its
    // lifetime, so the cross-runtime guard must keep firing after an unload.
  }
  Future<void> stopGeneration() async {
    isGenerating.value = false;
    tokenCount.value = 0;
    generationSource.value = '';
    streamingText.value = '';
    _server?.abortChat();
    final engine = _engine;
    if (engine != null) {
      unawaited(engine.stop().timeout(const Duration(seconds: 1)).catchError(
            (_) {},
          ));
    }
  }

  /// Waits until no generation is in flight. Returns true when idle,
  /// false on timeout. A fresh user turn waits on this after stopping
  /// stale background work — starting a new native generation while
  /// the old one still tears down can abort the process on low-RAM
  /// devices.
  Future<bool> waitForIdle(
      {Duration timeout = const Duration(seconds: 4)}) async {
    final deadline = DateTime.now().add(timeout);
    while (isGenerating.value) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  /// Reset the native conversation context. Call this whenever the user
  /// switches to a different chat session so old context doesn't leak.
  Future<void> resetConversation() async {
    final engine = _engine;
    if (engine != null) {
      await engine.resetConversation();
    }
  }

  Future<void> refreshContextInfo() async {
    if (supportsLocalServer && _serverActive) {
      // No native info channel on the sidecar: keep the load-time
      // window, usage is estimated per turn in generate().
      contextTokensTotal.value = _serverCtx;
      return;
    }
    if (!supportsLocalInference || _engine == null || !isModelLoaded.value) {
      return;
    }

    final info = await _engine!.getContextInfo();
    if (info == null) return;

    contextTokensUsed.value = info.tokensUsed;
    contextTokensTotal.value = info.contextSize;
  }
}
