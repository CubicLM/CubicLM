/// Load-safety confirmations, low-RAM warnings, and dialogs.
///
/// Split from `model_controller.dart` - behavior is unchanged.
/// Contains: _confirmRiskyLoad(), confirmLoadSafety(), _confirmLiteRtGpuWarning(), _isLowMemoryBytes()
///   _refreshAvailableRamGb(), _showImageModelLoadingDialog()
part of 'model_controller.dart';

extension ModelControllerSafety on ModelController {
  Future<bool> _confirmRiskyLoad({
    required String filename,
    required int availableBytes,
    required int estimatedNeed,
  }) async {
    final needLabel = DownloadService.formatWholeMb(estimatedNeed);
    final ramLabel = DownloadService.formatWholeMb(availableBytes);
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Load anyway? (risky)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename),
            const SizedBox(height: 12),
            Text('Needs ~$needLabel, free: $ramLabel.'),
            const SizedBox(height: 12),
            const Text(
              'Strict RAM guard is OFF. Android may close the app during '
              'this load. The loader will still free other models first '
              'and use minimal threads and context to maximize the odds.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Get.back(result: true),
            child: const Text('Load anyway'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<ModelLoadAction> confirmLoadSafety({
    required String filename,
    required int fileBytes,
    required bool isLiteRt,
  }) async {
    final availableRamGb = await _refreshAvailableRamGb();

    final availableBytes = (availableRamGb * 1024 * 1024 * 1024).round();
    final hasMeasuredMemory = availableBytes > 0 && fileBytes > 0;
    // Include KV cache estimate (contextSize * 2.5KB) for more accurate guard
    int estimatedNeed = fileBytes;
    try {
      if (Get.isRegistered<SettingsController>() && Get.isRegistered<DeviceInfoService>()) {
        final ctx = Get.find<SettingsController>().effectiveContextSize;
        final dev = Get.find<DeviceInfoService>();
        estimatedNeed = fileBytes + dev.estimatedKvBytes(ctx);
      }
    } catch (_) {}
    final isCriticallyLow = hasMeasuredMemory &&
        (availableBytes < estimatedNeed || _isLowMemoryBytes(availableBytes));

    // Hard block: not enough RAM for file (×1.25 mmap pressure) + KV
    // cache + scaled headroom. The native loader aborts (instant app
    // death, no catch possible) — offering "Load anyway" here is a crash
    // button, so refuse outright. With the strict guard OFF (power
    // users), degrade to an explicit risky confirmation instead: the
    // loader still evicts the pool and uses minimal threads/context.
    final kvBytes = (estimatedNeed - fileBytes).clamp(0, 1 << 62);
    final insufficient = hasMeasuredMemory &&
        ModelController.isRamInsufficient(
          availableBytes: availableBytes,
          fileBytes: fileBytes,
          kvBytes: kvBytes,
        );
    bool strict = true;
    try {
      if (Get.isRegistered<SettingsController>()) {
        strict = Get.find<SettingsController>().strictRamGuard.value;
      }
    } catch (_) {}
    final decision = ModelController.ramGateDecision(
      strict: strict,
      insufficient: insufficient,
      criticallyLow: isCriticallyLow,
    );
    if (decision == RamGateDecision.hardBlock) {
      final needLabel = DownloadService.formatWholeMb(estimatedNeed);
      final ramLabel = DownloadService.formatWholeMb(availableBytes);
      final headLabel = DownloadService.formatWholeMb(
          ModelController.loadHeadroomBytes(fileBytes));
      Get.snackbar(
        'Not enough free RAM',
        '$filename needs ~$needLabel + $headLabel reserve, but only $ramLabel is free. Close other apps, pick a smaller model — or allow risky loads in Settings (Strict RAM guard).',
        duration: const Duration(seconds: 6),
      );
      return ModelLoadAction.cancel;
    }
    if (decision == RamGateDecision.riskyConfirm) {
      final ok = await _confirmRiskyLoad(
        filename: filename,
        availableBytes: availableBytes,
        estimatedNeed: estimatedNeed,
      );
      return ok ? ModelLoadAction.continueLoad : ModelLoadAction.cancel;
    }

    // Enough headroom (or nothing measurable to warn about) — load straight
    // away. Any resident model is freed by InferenceService.loadModel.
    if (decision == RamGateDecision.allow) return ModelLoadAction.continueLoad;

    final modelLabel = fileBytes > 0
        ? DownloadService.formatWholeMb(fileBytes)
        : 'Unknown size';
    final ramLabel = availableBytes > 0
        ? DownloadService.formatWholeMb(availableBytes)
        : 'Unknown';
    final lower = filename.toLowerCase();
    final runtimeLabel = isLiteRt
        ? 'LiteRT-LM'
        : lower.endsWith('.gguf')
            ? 'GGUF'
            : lower.endsWith('.safetensors')
                ? 'Image model'
                : 'Local model';

    final result = await Get.dialog<ModelLoadAction>(
      AlertDialog(
        title: const Text('Restart recommended'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename),
            const SizedBox(height: 12),
            Text('Runtime: $runtimeLabel'),
            Text('Available RAM: $ramLabel'),
            Text('Model size: $modelLabel'),
            const SizedBox(height: 12),
            const Text(
              'Available RAM is lower than recommended. This can crash the app if Android cannot reserve enough memory.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: ModelLoadAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Get.back(result: ModelLoadAction.cancel);
              try {
                await ModelController._androidImportChannel.invokeMethod('restartApp');
              } catch (_) {
                SystemNavigator.pop();
              }
            },
            child: const Text('Restart app'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _refreshAvailableRamGb();
              Get.back(result: ModelLoadAction.continueLoad);
            },
            child: const Text('Load anyway'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return result ?? ModelLoadAction.cancel;
  }

  Future<bool> _confirmLiteRtGpuWarning() async {
    final mode = _settings.liteRtPerformanceMode.value;
    if (mode == 'cpu_safe') return true;

    final accepted = _hive.getSetting<bool>(
          AppConstants.keyLiteRtGpuWarningAccepted,
          defaultValue: false,
        ) ??
        false;
    if (accepted) return true;

    final modeLabel = mode == 'gpu_fast' ? 'GPU Fast' : 'Auto Fast';
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('$modeLabel LiteRT speed'),
        content: const Text(
          'GPU can make LiteRT models much faster, closer to Edge Gallery speed. '
          'On some phones GPU/OpenCL can crash the app while loading. '
          'If that happens, Auto Fast will use CPU on the next load.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Continue'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (confirmed == true) {
      await _hive.setSetting(AppConstants.keyLiteRtGpuWarningAccepted, true);
      return true;
    }
    return false;
  }

  /// Below this free RAM the low-memory warning always fires, even when
  /// the hard math passes (shared by the gate and the card verdict).

  bool _isLowMemoryBytes(int bytes) => bytes < ModelController.lowMemoryBytes;

  Future<double> _refreshAvailableRamGb() async {
    try {
      final device = Get.find<DeviceInfoService>();
      await device.refreshMemoryInfo();
      return device.availableRamGB.value;
    } catch (_) {
      return 0;
    }
  }

  void _showImageModelLoadingDialog(String filename) {
    final localImage = Get.find<LocalImageService>();
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Get.isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading $filename',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Obx(() {
                final log = localImage.latestLog.value;
                if (log.isEmpty) {
                  return const Text(
                    'Initializing model...',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  );
                }
                return Text(
                  log,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                );
              }),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }
}
