/// Model loading and file validation (SafeTensors/LiteRT).
///
/// Split from `model_controller.dart` - behavior is unchanged.
/// Contains: loadModel(), _modelFileBytes(), _hasValidSafetensorsHeader(), _hasLikelyValidLiteRtFile()
part of 'model_controller.dart';

extension ModelControllerLoading on ModelController {
  Future<void> loadModel(String filename) async {
    // Desktop (Windows) and Web ship no on-device inference engine yet
    // (llama.cpp / LiteRT natives are Android/iOS only). Fail fast with a
    // clear message instead of letting the user download gigabytes first
    // and then hitting an opaque native error.
    if (!supportsLocalInference) {
      Get.snackbar(
        'Local Models Unavailable',
        'On-device models need the Android app. On this device, use Cloud mode instead.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (_inference.isLoadingModel.value) {
      Get.snackbar('Model Loading', 'Another model is already loading.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final path = await _download.modelPath(filename);
    final model =
        availableModels.firstWhereOrNull((m) => m.filename == filename);
    if (_isAuxiliaryImageFile(filename)) {
      Get.snackbar(
        'Helper File',
        '$filename is used internally by image generation and cannot be loaded as a model.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    // Guard: the file must actually exist on this device. Without this the
    // catalog size fallback in _modelFileBytes lets a never-downloaded or
    // deleted model reach the native loader, which fails with an opaque
    // "GGUF model file is missing or unreadable".
    if (!await File(path).exists()) {
      Get.snackbar(
        'Not Downloaded',
        '$filename is not on this device. Download it from the Models tab first.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final isLiteRt = filename.toLowerCase().endsWith('.litertlm') ||
        model?.runtime == AiModel.runtimeLiteRt;
    // Cross-runtime switches are allowed in-place now: the llama.cpp slot
    // pool and the LiteRT session live side by side, and generation picks
    // the engine matching the active model's runtime.
    final fileBytes = await _modelFileBytes(filename, path, model);
    if (model != null && await _isIncompleteCatalogFile(model, fileBytes)) {
      final actual = DownloadService.formatBytes(fileBytes);
      Get.find<AppLogService>().error(
        'Incomplete model file blocked',
        details: '$filename is $actual, expected about ${model.size}',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Incomplete Model File',
        '$filename is only $actual. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (filename.toLowerCase().endsWith('.safetensors') &&
        !await _hasValidSafetensorsHeader(path)) {
      Get.find<AppLogService>().error(
        'Corrupt safetensors file blocked',
        details: '$filename failed safetensors header validation',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename did not download correctly. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (isLiteRt && !await _hasLikelyValidLiteRtFile(path, fileBytes)) {
      Get.find<AppLogService>().error(
        'Corrupt LiteRT model file blocked',
        details: '$filename failed LiteRT file validation; size=$fileBytes',
        category: LogCategory.model,
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename is not a valid LiteRT-LM file. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    final loadAction = await confirmLoadSafety(
      filename: filename,
      fileBytes: fileBytes,
      isLiteRt: isLiteRt,
    );
    if (loadAction == ModelLoadAction.cancel) return;
    if (isLiteRt && !await _confirmLiteRtGpuWarning()) return;

    // Switching models mid-reply is allowed: stop the in-flight generation
    // first so the swap does not stall behind it.
    if (_inference.isGenerating.value) {
      await _inference.stopGeneration();
    }

    if (isImageModel(model ??
        AiModel(
          name: filename,
          filename: filename,
          url: '',
          size: '',
          description: '',
          template: '',
        ))) {
      // Auto-download TAESD for fast VAE decode if not present
      String? taesdPath;
      try {
        const taesdFilename = 'taesd.safetensors';
        const taesdUrl = 'https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors';
        final hasTaesd = await _download.isModelDownloaded(taesdFilename);
        if (!hasTaesd) {
          print('[ModelController] TAESD not found, downloading...');
          await _download.downloadModel(url: taesdUrl, filename: taesdFilename);
          print('[ModelController] TAESD downloaded successfully');
        } else {
          print('[ModelController] TAESD already present');
        }
        taesdPath = await _download.modelPath(taesdFilename);
      } catch (e) {
        print('[ModelController] TAESD download failed (will use standard VAE): $e');
      }

      // Show loading dialog with live logs
      _showImageModelLoadingDialog(filename);
      final result = await _localImage.loadModel(path, modelName: filename, taesdPath: taesdPath);
      // Close loading dialog
      if (Get.isDialogOpen ?? false) Get.back();

      final isError = !_localImage.isModelLoaded.value;
      if (isError) {
        Get.snackbar(
          'Model Not Loaded',
          result,
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.15),
          colorText: const Color(0xFFFF9500),
          duration: const Duration(seconds: 6),
          snackStyle: SnackStyle.FLOATING,
          margin: EdgeInsets.fromLTRB(
              16, (Get.overlayContext != null ? MediaQuery.of(Get.overlayContext!).padding.top : 24) + 8, 16, 0),
          borderRadius: 18,
          animationDuration: const Duration(milliseconds: 520),
          forwardAnimationCurve: Curves.easeOutBack,
          reverseAnimationCurve: Curves.easeInCubic,
        );
      } else {
        AppSnackbar.modelSwitched(filename);
        StatsService.tap(StatsService.eventModelLoaded);
      }
    } else {
      final result = await _inference.loadModel(
        path,
        modelName: filename,
        modelRuntime: model?.runtime,
        enableLiteRtVision: model == null ? false : isVisionModel(model),
        // Already gated above (confirmLoadSafety with dialogs) — the
        // service-level gate below is for ungated callers only.
        skipGate: true,
      );
      if (_inference.isModelLoaded.value) {
        final fallbackToText = result.toLowerCase().contains('text-only');
        _inference.isVisionLoaded.value =
            fallbackToText ? false : (model == null ? false : isVisionModel(model));
        await _settings.setInferenceMode('local');
        AppSnackbar.modelSwitched(filename);
        StatsService.tap(StatsService.eventModelLoaded);
      } else {
        bool showDetails = false;
        Get.dialog(
          StatefulBuilder(
            builder: (context, setState) {
              final friendlyMsg = _getFriendlyErrorMessage(result);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final detailBg = isDark ? Dt.cardDark : Dt.canvas;
              final detailBorder = isDark ? Dt.pillMutedDark : Dt.hairline;
              
              return AlertDialog(
                backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: isDark ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Model Load Failed',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friendlyMsg,
                        style: GoogleFonts.inter(
                          fontSize: 14, 
                          height: 1.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'TROUBLESHOOTING TIPS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTipRow(context, Icons.delete_outline_rounded, 'Delete the model and try redownloading it completely.'),
                      _buildTipRow(context, Icons.memory_rounded, 'Ensure your device has at least 2-3 GB of free RAM.'),
                      if (result.toLowerCase().contains('litert') || filename.toLowerCase().endsWith('.litertlm'))
                        _buildTipRow(context, Icons.settings_suggest_rounded, 'Double check if this LiteRT-LM file matches your architecture.'),
                      const SizedBox(height: 12),

                      // Technical Details Toggle Button
                      InkWell(
                        onTap: () => setState(() => showDetails = !showDetails),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                showDetails ? 'Hide Technical Details' : 'Show Technical Details',
                                style: GoogleFonts.inter(
                                  fontSize: 12, 
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Icon(
                                showDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: showDetails
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    width: double.maxFinite,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: detailBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: detailBorder, width: 1),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        result,
                                        style: GoogleFonts.firaCode(
                                          fontSize: 11,
                                          height: 1.4,
                                          color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFF9F1239),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }
  }

  Future<int> _modelFileBytes(
    String filename,
    String path,
    AiModel? model,
  ) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        fileSizes[filename] = bytes;
        return bytes;
      }
    } catch (_) {}
    final cached = fileSizes[filename] ?? 0;
    if (cached > 0) return cached;
    return model == null ? 0 : _knownModelBytes(model);
  }

  Future<bool> _hasValidSafetensorsHeader(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 16) return false;
      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 16) return false;

      var headerLength = 0;
      for (var i = 0; i < 8; i++) {
        headerLength += bytes[i] << (8 * i);
      }

      if (headerLength <= 2 || headerLength > length - 8) return false;
      if (headerLength > 64 * 1024 * 1024) return false;
      return bytes[8] == 0x7B;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> _hasLikelyValidLiteRtFile(String path, int fileBytes) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 10 * 1024 * 1024) return false;

      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 8) return false;

      // Verify LiteRT-LM magic identifier 'LITERTLM' at bytes 0-7
      final hasLmLiteRt = bytes[0] == 0x4C && // 'L'
          bytes[1] == 0x49 && // 'I'
          bytes[2] == 0x54 && // 'T'
          bytes[3] == 0x45 && // 'E'
          bytes[4] == 0x52 && // 'R'
          bytes[5] == 0x54 && // 'T'
          bytes[6] == 0x4C && // 'L'
          bytes[7] == 0x4D; // 'M'

      if (hasLmLiteRt) {
        return true;
      }

      // Note: We intentionally DO NOT allow standard TFLite models starting with 'TFL3' at offset 4
      // if they lack the 'LITERTLM' container header, because the native LiteRT-LM engine 
      // strictly expects the .litertlm conversational bundle structure and will crash with a
      // SIGABRT native assert check failure if it is not present.
      return false;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }
}
