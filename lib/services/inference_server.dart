/// Windows sidecar: server load + streaming generate paths.
///
/// Split from `inference_service.dart` - behavior is unchanged.
/// Contains: _generateViaServer(), _safeFileBytes(), _loadViaServer()
part of 'inference_service.dart';

extension InferenceServiceServer on InferenceService {
  Future<String> _generateViaServer({
    required String prompt,
    required String systemPrompt,
    required List<Map<String, String>>? conversationHistory,
    required double temperature,
    required double topP,
    required int maxTokens,
    required String source,
    required void Function(String token) onToken,
  }) async {
    final server = _server;
    if (server == null || !server.isRunning) {
      return 'ERROR: Local server is not running. Reload the model.';
    }
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      if (conversationHistory != null) ...conversationHistory,
      {'role': 'user', 'content': prompt},
    ];
    try {
      return await server.chat(
        messages: messages,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        onToken: onToken,
      );
    } catch (e) {
      if (source != 'benchmark') {
        Get.find<AppLogService>().error(
          'Local server generate failed',
          details: '$e',
          category: LogCategory.model,
        );
      }
      return 'ERROR: Local server generate failed — $e';
    }
  }

  /// File size for the engine's fit-aware offload math (0 = unknown,
  /// engine falls back to the tier heuristic). Never throws.
  int _safeFileBytes(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// Windows load path: start (or reuse) the llama-server sidecar and
  /// report it as a LoadResult so all state updates below stay shared.
  Future<LoadResult> _loadViaServer({
    required String modelPath,
    required String? modelName,
    required int contextSize,
    required String deviceTier,
  }) async {
    _server ??= Get.put(LocalServerService(), permanent: true);
    final settings = Get.find<SettingsController>();
    var threads = settings.autoAdjustThreads.value
        ? settings.recommendedThreads
        : 4;
    final largeMode = settings.largeModelMode.value;
    if (largeMode && threads > 2) threads = 2;
    final accelMode = largeMode ? 'cpu' : settings.ggufAccelMode.value;
    // Server asset choice mirrors the accel card. Auto probes the Vulkan
    // driver DLL: present → Vulkan build (ngl 99), absent → CPU build.
    // Explicit 'gpu' forces Vulkan (may fail without a driver), 'cpu'
    // always takes the CPU build.
    final wantGpu =
        accelMode == 'gpu' || (accelMode == 'auto' && vulkanPresent());
    final gpuLayers = wantGpu ? 99 : 0;
    isLoadingModel.value = true;
    loadingModelName.value = modelName ?? modelPath.split('/').last;
    try {
      final port = await _server!.start(
        modelPath: modelPath,
        contextSize: contextSize,
        threads: threads,
        gpuLayers: gpuLayers,
        wantGpu: wantGpu,
        onBinaryProgress: (p) => modelLoadProgress.value = p * 0.3,
      );
      _serverCtx = contextSize;
      Get.find<AppLogService>().info(
        'Local server ready: ${loadingModelName.value} (port $port, '
        'ctx=$contextSize, threads=$threads, gpu=$gpuLayers)',
        category: LogCategory.model,
      );
      return LoadResult(
        success: true,
        message: 'Loaded ${loadingModelName.value} via local server.',
        gpuName: wantGpu ? 'Vulkan' : 'CPU',
        gpuLayers: gpuLayers,
        runtime: 'llama',
        backend: gpuLayers > 0 ? 'gpu' : 'cpu',
      );
    } catch (e) {
      _serverCtx = 0;
      return LoadResult(
        success: false,
        message: 'ERROR: Local server failed — $e',
      );
    }
  }
}
