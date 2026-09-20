/// External downloads, pause/resume/cancel, and delete.
///
/// Split from `model_controller.dart` - behavior is unchanged.
/// Contains: refreshDownloaded(), isDownloaded(), _isAuxiliaryImageFile(), _isIncompleteCatalogFile()
///   isDownloadingAny, lastLoadedModelName, canLoadLastModel, getDownloadProgress()
///   isDownloadingModel(), setLocalFilter(), isVisionModel(), isUncensoredModel(), isImageModel()
///   isLiteRtModel(), isLlamaModel(), isGeneralModel(), modelSizeLabel(), _knownModelBytes()
///   _declaredModelBytes(), _formatModelSize(), filenameFromUrl(), detectUrlSize(), addModelFromUrl()
///   downloadModel(), downloadModelToDownloads(), _downloadToDownloadsAndroid()
///   _downloadToDownloadsDesktop(), _uniquePath(), cancelExternalDownload(), pauseDownload()
///   resumeDownload(), cancelDownload(), deleteModel()
part of 'model_controller.dart';

extension ModelControllerDownloads on ModelController {
  Future<void> refreshDownloaded() async {
    await _deletePartialImports();
    final files = (await _download.getDownloadedModels())
        .where((file) => !_isAuxiliaryImageFile(file))
        .toList();
    downloadedFiles.value = files;
    for (final file in files) {
      fileSizes[file] = await _download.getModelSize(file);
    }

    // Add any downloaded files that are not in availableModels
    final existingFilenames = availableModels.map((m) => m.filename).toSet();
    for (final file in files) {
      if (!existingFilenames.contains(file)) {
        final lower = file.toLowerCase();
        final runtime = AiModel.runtimeFromFilename(file);
        final isLiteRt = runtime == AiModel.runtimeLiteRt;
        final isVision = isLiteRt && AiModel.hasVisionMarker(lower);

        availableModels.add(AiModel(
          name: file,
          filename: file,
          url: '',
          size: _formatModelSize(file),
          description: 'Imported from local storage',
          template: isLiteRt ? 'litert' : 'chatml',
          runtime: runtime,
          isImported: true,
          isVision: isVision,
        ));
      }
    }

    // Remove any imported models that are no longer downloaded
    availableModels.removeWhere(
        (model) => model.isImported && !files.contains(model.filename));

    if (localFilter.value.isEmpty) {
      localFilter.value = defaultLocalFilter;
    }
  }

  bool isDownloaded(String filename) => downloadedFiles.contains(filename);

  bool _isAuxiliaryImageFile(String filename) {
    final lower = filename.toLowerCase();
    return lower == 'taesd.safetensors' ||
        lower.startsWith('taesd-') ||
        lower.startsWith('taesd_') ||
        lower == 'diffusion_pytorch_model.safetensors' ||
        lower.endsWith('.vae.safetensors') ||
        lower.startsWith('vae-') ||
        lower.startsWith('vae_');
  }

  Future<bool> _isIncompleteCatalogFile(AiModel model, int fileBytes) async {
    if (model.isImported) {
      // Don't bypass for imported models when fileBytes is invalid — check header magic instead.
      if (fileBytes <= 0) return true;
      try {
        final path = await _download.modelPath(model.filename);
        final lower = model.filename.toLowerCase();
        if (lower.endsWith('.safetensors')) {
          if (!await _hasValidSafetensorsHeader(path)) return true;
        } else if (lower.endsWith('.litertlm')) {
          if (!await _hasLikelyValidLiteRtFile(path, fileBytes)) return true;
        } else if (lower.endsWith('.gguf')) {
          final file = File(path);
          if (!await file.exists()) return true;
          RandomAccessFile? raf;
          try {
            raf = await file.open();
            final bytes = await raf.read(4);
            if (bytes.length < 4 ||
                bytes[0] != 0x47 ||
                bytes[1] != 0x47 ||
                bytes[2] != 0x55 ||
                bytes[3] != 0x46) {
              return true;
            }
          } finally {
            await raf?.close();
          }
        } else {
          if (fileBytes < 1024) return true;
        }
      } catch (_) {
        return true;
      }
      return false;
    }
    if (model.url.trim().isEmpty || fileBytes <= 0) {
      return false;
    }
    final expectedBytes = _declaredModelBytes(model);
    if (expectedBytes <= 0) return false;
    // Relax threshold to 85% to comfortably accommodate HuggingFace decimal-scaled catalog sizes 
    // and rounded metadata sizes (e.g. 770.3MB listed as 0.8GB) while still blocking failed downloads.
    return fileBytes < (expectedBytes * 0.85).round();
  }

  bool get isDownloading => _download.isDownloadingAny;

  String get lastLoadedModelName =>
      _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';

  bool get canLoadLastModel =>
      lastLoadedModelName.isNotEmpty && isDownloaded(lastLoadedModelName);

  DownloadProgress? getDownloadProgress(String filename) =>
      _download.activeDownloads[filename];

  bool isDownloadingModel(String filename) =>
      _download.activeDownloads.containsKey(filename);

  void setLocalFilter(String filter) {
    if (ModelController.localFilters.contains(filter)) {
      localFilter.value = filter;
    }
  }

  bool isVisionModel(AiModel model) {
    if (!isLiteRtModel(model)) return false;
    final lower =
        '${model.name} ${model.filename} ${model.description}'.toLowerCase();
    return model.isVision || AiModel.hasVisionMarker(lower);
  }

  bool isUncensoredModel(AiModel model) {
    return AppConstants.isUncensoredModelName(
      '${model.name} ${model.filename} ${model.description}',
    );
  }

  bool isImageModel(AiModel model) {
    final lower = model.filename.toLowerCase();
    return model.runtime == AiModel.runtimeSd ||
        lower.endsWith('.safetensors') ||
        model.template == 'sd';
  }

  bool isLiteRtModel(AiModel model) {
    return model.runtime == AiModel.runtimeLiteRt ||
        model.filename.toLowerCase().endsWith('.litertlm');
  }

  bool isLlamaModel(AiModel model) {
    return model.runtime == AiModel.runtimeLlama ||
        model.filename.toLowerCase().endsWith('.gguf');
  }

  bool isGeneralModel(AiModel model) =>
      !isVisionModel(model) &&
      !isUncensoredModel(model) &&
      !isImageModel(model);

  String modelSizeLabel(AiModel model) {
    final bytes = fileSizes[model.filename] ?? 0;
    if (bytes > 0) return DownloadService.formatBytes(bytes);
    return model.size;
  }

  int _knownModelBytes(AiModel model) {
    final detected = fileSizes[model.filename] ?? 0;
    if (detected > 0) return detected;
    return _declaredModelBytes(model);
  }

  int _declaredModelBytes(AiModel model) {
    final match = RegExp(r'([\d.]+)\s*(GB|MB)', caseSensitive: false)
        .firstMatch(model.size);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1) ?? '') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();
    if (unit == 'GB') return (value * 1024 * 1024 * 1024).round();
    if (unit == 'MB') return (value * 1024 * 1024).round();
    return 0;
  }

  String _formatModelSize(String filename) {
    final bytes = fileSizes[filename] ?? 0;
    if (bytes <= 0) return 'Local File';
    return DownloadService.formatBytes(bytes);
  }

  String filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'model.gguf';
    final decoded = Uri.decodeComponent(segment.split('?').first);
    if (decoded.toLowerCase().endsWith('.gguf') ||
        decoded.toLowerCase().endsWith('.litertlm') ||
        decoded.toLowerCase().endsWith('.safetensors')) {
      return decoded;
    }
    return '$decoded.gguf';
  }

  Future<String> detectUrlSize(String url) async {
    try {
      final bytes = await _download.getRemoteFileSize(url);
      if (bytes <= 0) return 'Unknown size';
      return DownloadService.formatBytes(bytes);
    } catch (_) {
      return 'Unknown size';
    }
  }

  Future<void> addModelFromUrl({
    required String name,
    required String url,
    String? filename,
    String? description,
    String template = 'chatml',
    String? size,
    bool isVision = false,
  }) async {
    final resolvedFilename = (filename == null || filename.trim().isEmpty)
        ? filenameFromUrl(url)
        : filename.trim();

    final model = AiModel(
      name: name.trim().isEmpty ? resolvedFilename : name.trim(),
      filename: resolvedFilename,
      url: url.trim(),
      size: size == null || size.trim().isEmpty ? 'Unknown size' : size.trim(),
      description: description == null || description.trim().isEmpty
          ? 'Added from custom URL'
          : description.trim(),
      template: template.trim().isEmpty ? 'chatml' : template.trim(),
      runtime: AiModel.runtimeFromFilename(
        resolvedFilename,
        template: template.trim().isEmpty ? 'chatml' : template.trim(),
      ),
      isVision: isVision &&
          AiModel.runtimeFromFilename(
                resolvedFilename,
                template: template.trim().isEmpty ? 'chatml' : template.trim(),
              ) ==
              AiModel.runtimeLiteRt,
      isCustom: true,
    );

    customModels.removeWhere((m) => m.filename == model.filename);
    customModels.add(model);
    availableModels.removeWhere((m) => m.filename == model.filename);
    availableModels.add(model);
    await _saveCustomModels();
  }

  Future<void> downloadModel(AiModel model) async {
    // Web has no on-device engine and no app-private model store worth
    // filling — stop gigabyte downloads before they start.
    if (kIsWeb) {
      Get.snackbar(
        'Downloads need the app',
        'On-device models run in the Android/Windows app — use Cloud mode here.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    try {
      await _download.downloadModel(
        url: model.url,
        filename: model.filename,
      );
      await refreshDownloaded();
    } catch (e) {
      Get.find<AppLogService>().error('Model download failed', details: e, category: LogCategory.model);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Saves [model] to the platform's public Downloads folder.
  ///
  /// - Android: delegates to the native DownloadManager bridge
  ///   (`downloadToDownloads`) so the file lands in the phone's public
  ///   Downloads folder and keeps downloading in the background.
  /// - Desktop (Windows/Linux/macOS): downloads with the in-app streaming
  ///   downloader (progress surfaces in the Models tab), then moves the
  ///   finished file into the user's Downloads folder.
  Future<void> downloadModelToDownloads(AiModel model) async {
    if (model.url.trim().isEmpty) {
      Get.snackbar('Download Unavailable', 'This model has no download URL.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (Platform.isAndroid) {
      await _downloadToDownloadsAndroid(model);
      return;
    }

    await _downloadToDownloadsDesktop(model);
  }

  Future<void> _downloadToDownloadsAndroid(AiModel model) async {
    try {
      isImporting.value = true;
      importFileName.value = model.filename;
      importStatus.value = 'Starting download...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await ModelController._androidImportChannel.invokeMapMethod<String, dynamic>(
        'downloadToDownloads',
        {'url': model.url, 'filename': model.filename},
      );
      externalDownloadId.value = result?['downloadId'] as int?;
      final filename = result?['filename'] as String? ?? model.filename;
      Get.snackbar(
        'Download Started',
        '$filename is downloading to your Downloads folder.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on PlatformException catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>().error(
        'Download to Downloads failed',
        details: '${e.code}: ${e.message}',
        category: LogCategory.model,
      );
      Get.snackbar('Download Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>()
          .error('Download to Downloads failed', details: e);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Desktop "Save to Downloads": stream into the app models dir first
  /// (reuses pause/resume + validation UI), then move the file out to the
  /// user's Downloads folder so no duplicate multi-GB copy is left behind.
  Future<void> _downloadToDownloadsDesktop(AiModel model) async {
    try {
      isImporting.value = true;
      importFileName.value = model.filename;
      importStatus.value = 'Downloading to Downloads folder...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final savedPath = await _download.downloadModel(
        url: model.url,
        filename: model.filename,
      );
      if (savedPath == 'PAUSED') {
        importStatus.value = 'Download paused — resume it from the Models tab.';
        Get.snackbar(
          'Download Paused',
          '${model.filename} will resume from the Models tab.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        // Downloader already placed the file in the app models dir —
        // keep it there as a graceful fallback.
        await refreshDownloaded();
        Get.snackbar(
          'Download Complete',
          '${model.filename} is in the app models folder (Downloads folder unavailable).',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
        );
        return;
      }

      final targetPath =
          await _uniquePath(downloadsDir.path, model.filename);
      try {
        await File(savedPath).rename(targetPath);
      } on FileSystemException {
        // Cross-volume move: fall back to copy + delete.
        await File(savedPath).copy(targetPath);
        await File(savedPath).delete();
      }
      await refreshDownloaded();
      Get.snackbar(
        'Saved to Downloads',
        '${targetPath.split(Platform.pathSeparator).last}\n$targetPath',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      Get.find<AppLogService>().info(
        'Model saved to Downloads',
        details: targetPath,
        category: LogCategory.model,
      );
    } catch (e) {
      Get.find<AppLogService>().error('Download to Downloads failed',
          details: e, category: LogCategory.model);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  /// Returns a non-colliding file path inside [dirPath] for [filename]
  /// by appending " (1)", " (2)", ... when needed.
  Future<String> _uniquePath(String dirPath, String filename) async {
    var candidate = '$dirPath${Platform.pathSeparator}$filename';
    if (!await File(candidate).exists()) return candidate;
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    var i = 1;
    while (await File(candidate).exists()) {
      candidate =
          '$dirPath${Platform.pathSeparator}$stem ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<void> cancelExternalDownload() async {
    if (!Platform.isAndroid) {
      // Desktop "Save to Downloads" runs through the in-app downloader.
      final filename = importFileName.value;
      if (filename.isNotEmpty) {
        try {
          await _download.cancelDownload(filename);
        } catch (e) {
          Get.find<AppLogService>().error('Cancel download failed',
              details: e, category: LogCategory.model);
        }
      }
      externalDownloadId.value = null;
      isImporting.value = false;
      importStatus.value = 'Download cancelled';
      return;
    }
    final id = externalDownloadId.value;
    if (id != null) {
      try {
        await ModelController._androidImportChannel.invokeMethod('cancelDownloadToDownloads', {'downloadId': id});
      } catch (e) {
        Get.find<AppLogService>().error('Cancel download failed', details: e, category: LogCategory.model);
      }
      externalDownloadId.value = null;
      isImporting.value = false;
      importStatus.value = 'Download cancelled';
    }
  }

  void pauseDownload(String filename) {
    _download.pauseDownload(filename);
  }

  void resumeDownload(String filename) {
    _download.resumeDownload(filename);
  }

  void cancelDownload(String filename) {
    _download.cancelDownload(filename);
  }

  Future<void> deleteModel(String filename) async {
    await _download.deleteModel(filename);
    await refreshDownloaded();
    // Unload if this was the active model
    if (_inference.loadedModelName.value == filename) {
      await _inference.unloadModel();
    }
  }
}
