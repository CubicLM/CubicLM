/// Media pipeline: SD/WebGPU, cameras, TTS/STT, Whisper, vision, audio.
///
/// Split from `settings_controller.dart` - behavior is unchanged.
/// Contains: _scheduleContextReload(), _reloadTextModelForContextSize(), setLiteRtPerformanceMode()
///   setImageSteps(), setImageGenForceCpu(), setImageGenGpuGuardMb(), setImageGenSize()
///   setImageGenNegative(), setImageGenSeed(), randomizeImageSeed(), setImageGenCfg()
///   _detectImageGpu(), recommendedImageGpuBackend(), imageGpuLabel(), setImageBackendMode()
///   _reloadImageModelForBackend()
part of 'settings_controller.dart';

extension SettingsControllerMedia on SettingsController {

  /// Context size is baked into the model at load time, so a live reload is
  /// required for the change to take effect. Debounced because the slider
  /// fires onChanged continuously while dragging.
  void _scheduleContextReload() {
    if (_isReloadingForContext) return;
    _contextReloadTimer?.cancel();
    _contextReloadTimer = Timer(const Duration(milliseconds: 900), () {
      _reloadTextModelForContextSize();
    });
  }

  Future<void> _reloadTextModelForContextSize() async {
    try {
      if (!Get.isRegistered<InferenceService>()) return;
      final inference = Get.find<InferenceService>();
      if (!inference.isModelLoaded.value ||
          inference.isLoadingModel.value ||
          inference.isGenerating.value ||
          _isReloadingForContext) {
        // No model resident (or busy): the saved value applies on next load.
        return;
      }
      final path =
          _hive.getSetting<String>(AppConstants.keyLocalModelPath) ?? '';
      if (path.isEmpty) return;
      final name =
          _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
      final runtime =
          _hive.getSetting<String>(AppConstants.keyLocalModelRuntime) ?? '';
      final wasVision = inference.isVisionLoaded.value;

      _isReloadingForContext = true;
      Get.snackbar(
        'Context Size',
        'Reloading ${name.isNotEmpty ? name : 'model'} to apply the new context window…',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      await inference.loadModel(
        path,
        modelName: name.isEmpty ? null : name,
        modelRuntime: runtime.isEmpty ? null : runtime,
        enableLiteRtVision: wasVision,
      );
      _isReloadingForContext = false;
    } catch (e) {
      _isReloadingForContext = false;
      Get.find<AppLogService>().error(
        'Context-size reload failed',
        details: e.toString(),
        category: LogCategory.model,
      );
    }
  }

  Future<void> setLiteRtPerformanceMode(String mode) async {
    final normalized = switch (mode) {
      'gpu_fast' => 'gpu_fast',
      'cpu_safe' => 'cpu_safe',
      _ => AppConstants.defaultLiteRtPerformanceMode,
    };
    liteRtPerformanceMode.value = normalized;
    await _hive.setSetting(AppConstants.keyLiteRtPerformanceMode, normalized);
    if (normalized == 'gpu_fast') {
      await _hive.setSetting(AppConstants.keyLiteRtGpuCrashDetected, false);
    }
  }

  Future<void> setImageSteps(int value) async {
    imageSteps.value = value;
    await _hive.setSetting(AppConstants.keyImageSteps, value);
  }

  Future<void> setImageGenForceCpu(bool value) async {
    imageGenForceCpu.value = value;
    await _hive.setSetting(AppConstants.keyImageGenForceCpu, value);
  }

  Future<void> setImageGenGpuGuardMb(int value) async {
    imageGenGpuGuardMb.value = value;
    await _hive.setSetting(AppConstants.keyImageGenGpuGuardMb, value);
  }

  Future<void> setImageGenSize(int value) async {
    final allowed = value == 0 ||
        value == 256 ||
        value == 320 ||
        value == 384 ||
        value == 512;
    final normalized = allowed ? value : AppConstants.defaultImageGenSize;
    imageGenSize.value = normalized;
    await _hive.setSetting(AppConstants.keyImageGenSize, normalized);
  }

  Future<void> setImageGenNegative(String value) async {
    imageGenNegative.value = value.trim();
    imageGenNegativeController.text = imageGenNegative.value;
    await _hive.setSetting(
        AppConstants.keyImageGenNegative, imageGenNegative.value);
  }

  Future<void> setImageGenSeed(int value) async {
    imageGenSeed.value = value;
    await _hive.setSetting(AppConstants.keyImageGenSeed, value);
  }

  /// Fixes a random seed (reproducible generations).
  Future<void> randomizeImageSeed() async {
    await setImageGenSeed(Random().nextInt(1 << 31));
  }

  Future<void> setImageGenCfg(double value) async {
    final normalized = value.clamp(1.0, 15.0);
    imageGenCfg.value = normalized;
    await _hive.setSetting(AppConstants.keyImageGenCfg, normalized);
  }

  Future<void> _detectImageGpu() async {
    try {
      imageGpuVendor.value = await SdFlutterAndroid.detectGpuVendor();
    } catch (_) {
      imageGpuVendor.value = 'unknown';
    }
  }

  Backend recommendedImageGpuBackend() {
    final vendor = imageGpuVendor.value;
    final preferred = switch (vendor) {
      'adreno' => Backend.opencl,
      'mali' || 'xclipse' || 'powervr' || 'imagination' => Backend.vulkan,
      _ => Backend.vulkan,
    };
    if (preferred.isAvailable) return preferred;
    if (Backend.opencl.isAvailable) return Backend.opencl;
    if (Backend.vulkan.isAvailable) return Backend.vulkan;
    return Backend.cpu;
  }

  String imageGpuLabel() {
    final vendor = imageGpuVendor.value;
    final backend = recommendedImageGpuBackend();
    final vendorLabel = vendor == 'detecting'
        ? 'Detecting'
        : vendor == 'unknown'
            ? 'Unknown GPU'
            : vendor.toUpperCase();
    return backend == Backend.cpu
        ? '$vendorLabel - GPU unavailable'
        : '$vendorLabel - ${backend.displayName}';
  }

  Future<void> setImageBackendMode(bool useGpu) async {
    final backend = useGpu ? recommendedImageGpuBackend() : Backend.cpu;
    imageGenBackend.value = backend;
    imageGenForceCpu.value = !useGpu || backend == Backend.cpu;
    await _hive.setSetting(AppConstants.keyImageGenBackend, backend.index);
    await _hive.setSetting(
        AppConstants.keyImageGenForceCpu, imageGenForceCpu.value);
    if (!Get.isRegistered<LocalImageService>()) return;
    final image = Get.find<LocalImageService>();
    final previous = image.currentBackend.value;
    image.setBackend(backend);
    // The backend only takes effect at load time — reload a resident image
    // model immediately so the toggle is not silently ignored.
    if (image.isModelLoaded.value &&
        !image.isLoadingModel.value &&
        !image.isGenerating.value &&
        previous != backend) {
      await _reloadImageModelForBackend();
    }
  }

  Future<void> _reloadImageModelForBackend() async {
    try {
      final image = Get.find<LocalImageService>();
      final path =
          _hive.getSetting<String>(AppConstants.keyImageModelPath) ?? '';
      final name =
          _hive.getSetting<String>(AppConstants.keyImageModelName) ?? '';
      if (path.isEmpty) return;
      Get.snackbar(
        'Compute Backend',
        'Reloading ${name.isNotEmpty ? name : 'image model'} on ${imageGenBackend.value == Backend.cpu ? 'CPU' : 'GPU'}…',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      String? taesdPath;
      try {
        if (Get.isRegistered<DownloadService>() &&
            await Get.find<DownloadService>()
                .isModelDownloaded('taesd.safetensors')) {
          taesdPath =
              await Get.find<DownloadService>().modelPath('taesd.safetensors');
        }
      } catch (_) {}
      await image.unloadModel();
      final result = await image.loadModel(path,
          modelName: name.isEmpty ? null : name, taesdPath: taesdPath);
      final ok = image.isModelLoaded.value;
      Get.snackbar(
        ok ? 'Compute Backend' : 'Reload Failed',
        result,
        snackPosition: SnackPosition.BOTTOM,
        duration: Duration(seconds: ok ? 2 : 6),
      );
    } catch (e) {
      Get.find<AppLogService>().error(
        'Backend reload failed',
        details: e.toString(),
        category: LogCategory.model,
      );
    }
  }
}
