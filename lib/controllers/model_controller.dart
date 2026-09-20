import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/hive_service.dart';
import '../services/stats_service.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../models/ai_model.dart';
import '../core/constants.dart';
import 'settings_controller.dart';

part 'model_catalog.dart';
part 'model_downloads.dart';
part 'model_loading.dart';
part 'model_safety.dart';

enum ModelLoadAction { cancel, continueLoad }

/// RAM-gate outcome: allow silently, show the low-memory warning, refuse
/// outright, or ask for an explicit risky override (strict guard off).
enum RamGateDecision { allow, warnDialog, hardBlock, riskyConfirm }

/// Proactive fit verdict shown on model cards (strict-guard view):
/// fits = loads straight away, tight = warning dialog first,
/// blocked = refused without the guard override.
enum RamFit { fits, tight, blocked }

class ModelController extends GetxController {
  final DownloadService _download = Get.find<DownloadService>();
  final LocalImageService _localImage = Get.find<LocalImageService>();
  final InferenceService _inference = Get.find<InferenceService>();
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _customModelsKey = 'custom_url_models';
  static const _catalogCacheKey = 'model_catalog_cache_json';
  static const _catalogFetchMsKey = 'model_catalog_last_fetch_ms';

  /// Over-the-air model catalog. Served from the repo so new GGUF/LiteRT
  /// drops don't need an app release. Regenerate with
  /// `dart run tool/gen_catalog.dart` after editing AppConstants.
  static const _catalogUrl =
      'https://raw.githubusercontent.com/abir2afridi/CubicLM/main/assets/catalog/models.json';
  static const _catalogCooldown = Duration(hours: 24);
  static const _androidImportChannel =
      MethodChannel('com.cubiclm.app/model_import');

  Map<String, DownloadProgress> get activeDownloads =>
      _download.activeDownloads;

  final availableModels = <AiModel>[].obs;
  final downloadedFiles = <String>[].obs;
  final isImporting = false.obs;
  final customModels = <AiModel>[].obs;
  final fileSizes = <String, int>{}.obs;
  final modelScope = 'local'.obs;
  final localFilter = ''.obs;
  final importFileName = ''.obs;
  final importStatus = ''.obs;
  final importCopiedBytes = 0.obs;
  final importTotalBytes = 0.obs;
  final importBytesPerSecond = 0.0.obs;
  final sortSmallestFirst = true.obs;
  /// Filenames currently running a speed benchmark (one at a time enforced).
  final benchmarking = <String, bool>{}.obs;
  final externalDownloadId = Rx<int?>(null);

  void toggleSort() {
    sortSmallestFirst.value = !sortSmallestFirst.value;
  }

  /// Whether the current platform can load local models into an on-device
  /// inference engine. Desktop (Windows) and Web are Cloud-only for now —
  /// the llama.cpp / LiteRT engines ship Android (and iOS) natives only.
  bool get supportsLocalInference => _inference.supportsLocalInference;

  /// Human-readable label for the public Downloads folder on this platform.
  String get saveToDownloadsLabel => Platform.isAndroid
      ? "your phone's public Downloads folder"
      : 'your Downloads folder';

  static const localFilters = [
    'downloaded',
    'general',
    'image',
    'uncensored',
    'vision'
  ];

  List<AiModel> get displayedModels {
    final active = _inference.loadedModelName.value;
    final models = [...availableModels];
    models.sort((a, b) {
      if (a.filename == active) return -1;
      if (b.filename == active) return 1;
      final aDownloaded = isDownloaded(a.filename);
      final bDownloaded = isDownloaded(b.filename);
      if (aDownloaded != bDownloaded) return aDownloaded ? -1 : 1;

      if (sortSmallestFirst.value) {
        final aBytes = _knownModelBytes(a);
        final bBytes = _knownModelBytes(b);
        if (aBytes > 0 && bBytes > 0 && aBytes != bBytes) {
          return aBytes.compareTo(bBytes);
        }
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return models;
  }

  List<AiModel> get filteredDisplayedModels {    final filter =
        localFilter.value.isEmpty ? defaultLocalFilter : localFilter.value;
    return displayedModels.where((model) {
      switch (filter) {
        case 'downloaded':
          return isDownloaded(model.filename);
        case 'uncensored':
          return isUncensoredModel(model);
        case 'vision':
          return isVisionModel(model);
        case 'image':
          return isImageModel(model);
        case 'general':
        default:
          return isGeneralModel(model);
      }
    }).toList();
  }

  String get defaultLocalFilter =>
      downloadedFiles.isNotEmpty ? 'downloaded' : 'general';

  /// Chosen quant per catalog entry (base filename → variant filename).
  /// Absent = default entry. Reactive so quant chips rebuild.
  final selectedVariant = <String, String>{}.obs;

  /// Resolve the downloadable entry honoring the user's quant pick.
  /// Everything downstream stays filename-keyed, so download / load /
  /// delete / progress all work unchanged for the chosen file.
  AiModel resolveForDownload(AiModel model) {
    if (model.variants.isEmpty) return model;
    final picked = selectedVariant[model.filename];
    if (picked == null || picked.isEmpty) return model;
    for (final opt in model.variantOptions()) {
      if (opt.filename == picked) return opt;
    }
    return model;
  }

  void selectVariant(AiModel model, String filename) {
    if (filename == model.filename) {
      selectedVariant.remove(model.filename);
    } else {
      selectedVariant[model.filename] = filename;
    }
  }

  double get importProgress => importTotalBytes.value <= 0
      ? 0.0
      : (importCopiedBytes.value / importTotalBytes.value)
          .clamp(0.0, 1.0)
          .toDouble();

  int get downloadedCount => downloadedFiles.length;

  String get activeLocalModelName => _inference.loadedModelName.value;

  @override
  void onInit() {
    super.onInit();
    _loadCustomModels();
    _applyCatalog(_bundledCatalog());
    refreshDownloaded();
    // OTA catalog refresh (fire-and-forget, throttled, cached).
    unawaited(_refreshCatalog());
  }


  /// Gate a local model load on available memory.
  ///
  /// Switching models is a one-tap action: the previously loaded model is freed
  /// automatically, so no dialog is shown for an ordinary swap. A prompt only
  /// appears when memory is genuinely too tight to load safely.
  ///
  /// Pure RAM gate ([isRamInsufficient]): true when loading would almost
  /// Pure RAM gate: true when loading would almost surely die natively
  /// (mmap page pressure + transient dequant buffers + KV). The 1.25x file
  /// factor covers mmap page-cache pressure on low-RAM devices. Public
  /// for unit tests.
  /// Safety reserve kept free for Android itself (LMK kills first when
  /// the system runs dry). Scales with file size: a fixed 1GB reserve
  /// needlessly blocks tiny models on small phones, while big models
  /// still get the full gigabyte. Public for unit tests.
  static int loadHeadroomBytes(int fileBytes) {
    const gb = 1024 * 1024 * 1024;
    const minHead = 256 * 1024 * 1024;
    if (fileBytes <= 0) return gb;
    if (fileBytes <= minHead) return minHead;
    if (fileBytes >= gb) return gb;
    return fileBytes;
  }

  static bool isRamInsufficient({
    required int availableBytes,
    required int fileBytes,
    required int kvBytes,
  }) {
    if (availableBytes <= 0 || fileBytes <= 0) return false;
    final headroomBytes = loadHeadroomBytes(fileBytes);
    return availableBytes <
        (fileBytes * 1.25).round() + kvBytes + headroomBytes;
  }

  /// Pure gate decision so the strict/override matrix stays unit-tested:
  /// a would-be hard block degrades to an explicit risky confirmation
  /// when the user switched the strict guard off. Pure for unit tests.
  static RamGateDecision ramGateDecision({
    required bool strict,
    required bool insufficient,
    required bool criticallyLow,
  }) {
    if (insufficient) {
      return strict ? RamGateDecision.hardBlock : RamGateDecision.riskyConfirm;
    }
    if (criticallyLow) return RamGateDecision.warnDialog;
    return RamGateDecision.allow;
  }

  /// Card-level fit verdict from the same math as the load gate, so the
  /// dot on a model card never disagrees with what tapping Load does.
  /// Pure for unit tests.
  static RamFit ramFitFor({
    required int fileBytes,
    required int kvBytes,
    required int availableBytes,
  }) {
    if (availableBytes <= 0 || fileBytes <= 0) return RamFit.fits;
    switch (ramGateDecision(
      strict: true,
      insufficient: isRamInsufficient(
        availableBytes: availableBytes,
        fileBytes: fileBytes,
        kvBytes: kvBytes,
      ),
      // Same two clauses as the gate's isCriticallyLow.
      criticallyLow: availableBytes < fileBytes + kvBytes ||
          availableBytes < lowMemoryBytes,
    )) {
      case RamGateDecision.allow:
        return RamFit.fits;
      case RamGateDecision.warnDialog:
        return RamFit.tight;
      case RamGateDecision.hardBlock:
      case RamGateDecision.riskyConfirm:
        return RamFit.blocked;
    }
  }
  static const int lowMemoryBytes = 768 * 1024 * 1024;

  Future<void> unloadModel() async {
    await _inference.unloadModel();
    await _localImage.unloadModel();
  }

  Future<void> importModelFromStorage() async {
    if (isImporting.value) {
      Get.snackbar(
          'Import in Progress', 'Wait for the current import to finish.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (Platform.isAndroid) {
      await _importModelWithAndroidPicker();
      return;
    }

    String? partialImportPath;
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
      );

      if (result != null) {
        final picked = result.files.single;
        final filename = picked.name;
        final lower = filename.toLowerCase();

        if (!lower.endsWith('.gguf') &&
            !lower.endsWith('.litertlm') &&
            !lower.endsWith('.safetensors')) {
          Get.snackbar('Unsupported Model',
              'Only .gguf, .litertlm, and .safetensors files can be imported.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final file = picked.path == null ? null : File(picked.path!);
        final totalBytes = picked.size > 0
            ? picked.size
            : file == null
                ? 0
                : await file.length();
        if (totalBytes <= 0) {
          Get.snackbar('Import Failed', 'The selected file is empty.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final sourceStream = picked.readStream ?? file?.openRead();
        if (sourceStream == null) {
          Get.snackbar(
            'Import Failed',
            'Unable to read the selected file. Try selecting it from local storage.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        final modelsDir = await _download.modelsDir;
        final destPath = '$modelsDir/$filename';
        final partPath = '$destPath.part';
        partialImportPath = partPath;
        final destFile = File(destPath);
        final partFile = File(partPath);
        var shouldReplace = false;

        if (await destFile.exists()) {
          final replace = await _confirmReplace(filename);
          if (!replace) return;
          shouldReplace = true;
        }

        isImporting.value = true;
        importFileName.value = filename;
        importStatus.value = 'Copying to app storage...';
        importCopiedBytes.value = 0;
        importTotalBytes.value = totalBytes;
        importBytesPerSecond.value = 0;

        if (await partFile.exists()) {
          await partFile.delete();
        }

        await _copyWithProgress(sourceStream, partFile);
        if (shouldReplace && await destFile.exists()) {
          await destFile.delete();
        }
        await partFile.rename(destPath);
        fileSizes[filename] = await File(destPath).length();

        await refreshDownloaded();
        localFilter.value = 'downloaded';
        importStatus.value = 'Import complete';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (partialImportPath != null) {
        final partialFile = File(partialImportPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      Get.find<AppLogService>().error('Model import failed', details: e, category: LogCategory.model);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _importModelWithAndroidPicker() async {
    try {
      isImporting.value = true;
      importFileName.value = '';
      importStatus.value = 'Select a model file...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await _androidImportChannel.invokeMapMethod<String, dynamic>(
        'pickAndImportModel',
        {'modelsDir': await _download.modelsDir},
      );

      if (result?['cancelled'] == true) return;

      final filename = result?['filename'] as String?;
      if (filename != null && filename.isNotEmpty) {
        fileSizes[filename] = (result?['bytes'] as num?)?.toInt() ??
            await _download.getModelSize(filename);
        await refreshDownloaded();
        localFilter.value = 'downloaded';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } on PlatformException catch (e) {
        Get.find<AppLogService>().error(
          'Android model import failed',
          details: '${e.code}: ${e.message}',
          category: LogCategory.model,
        );
      Get.snackbar('Import Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.find<AppLogService>()
          .error('Android model import failed', details: e, category: LogCategory.model);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _copyWithProgress(
    Stream<List<int>> source,
    File destination,
  ) async {
    final startedAt = DateTime.now();
    final sink = destination.openWrite();
    try {
      await for (final chunk in source) {
        sink.add(chunk);
        importCopiedBytes.value += chunk.length;
        final elapsed =
            DateTime.now().difference(startedAt).inMilliseconds / 1000;
        if (elapsed > 0) {
          importBytesPerSecond.value = importCopiedBytes.value / elapsed;
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  Future<bool> _confirmReplace(String filename) async {
    final result = await Get.dialog<bool>(
      Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.copy_all_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Model Already Exists',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'A model file named "$filename" is already imported in your local app storage. Would you like to replace it?',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Get.back(result: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: Text(
                  'Replace File',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _deletePartialImports() async {
    try {
      final dir = Directory(await _download.modelsDir);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  String _getFriendlyErrorMessage(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('unknown model architecture') ||
        lower.contains('unsupported model architecture')) {
      return 'This GGUF uses a model architecture that is not supported by the bundled llama.cpp runtime. Update the app runtime or try a GGUF exported for a supported architecture.';
    }
    if (lower.contains('missing key') ||
        lower.contains('failed to load gguf split')) {
      return 'This appears to be a split GGUF model, but one or more required model files are missing. Import every split into the same folder before loading it.';
    }
    if (lower.contains('failed to load model from buffer') ||
        lower.contains('invalid_argument') ||
        lower.contains('invalid gguf') ||
        lower.contains('missing or unreadable') ||
        lower.contains('incomplete') ||
        lower.contains('corrupt')) {
      return 'The model file appears to be incomplete or corrupted. This usually happens when the download is interrupted or the file is invalid.';
    }
    if (lower.contains('out of memory') ||
        lower.contains('allocate') ||
        lower.contains('oom') ||
        lower.contains('cannot allocate')) {
      return 'Your device ran out of memory (RAM) trying to load this model. Mobile devices have strict memory limits; try using a smaller or more highly quantized model (e.g., 1B or 3B parameters, q4_k_m quantized).';
    }
    if (lower.contains('opencl') ||
        lower.contains('vulkan') ||
        lower.contains('opengl') ||
        lower.contains('gpu') ||
        lower.contains('cl_') ||
        lower.contains('driver')) {
      return 'A hardware or GPU driver error occurred while initializing the model. Try disabling GPU acceleration or switching to CPU-only inference in Settings.';
    }
    return 'The native AI engine encountered an unexpected error while loading the model. Please check the technical details below for more information.';
  }

  Widget _buildTipRow(BuildContext context, IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
