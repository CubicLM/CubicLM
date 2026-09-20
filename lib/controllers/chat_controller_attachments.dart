/// Attachments for [ChatController]: image/photo/file picking, text
/// extraction, vision-support checks and composer attachment state.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: _messageKey(), pickImage(), _pickImageDesktop(), takePhoto(), clearImage()
///   _checkVisionSupport(), _checkLocalVisionSupport(), pickFile(), handleFile()
///   _generateProjectStructure(), clearFile()
part of 'chat_controller.dart';

extension ChatControllerAttachments on ChatController {
  String _messageKey(String chatId, String id) =>
      chatId.isNotEmpty ? '$chatId/$id' : id;

  // ─── Image Handling ─────────────────────────────

  Future<void> pickImage() async {
    try {
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await _pickImageDesktop();
        return;
      }
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _visionImageMaxSide.toDouble(),
        maxHeight: _visionImageMaxSide.toDouble(),
        imageQuality: _visionImageJpegQuality,
      );
      if (file != null) {
        selectedImagePath.value = file.path;
        selectedImageBase64.value = null;
        selectedFileName.value = file.name;
        selectedFilePath.value = file.path;
        selectedFileType.value = 'image';
        selectedFileSize.value = await file.length();
        selectedFileContent.value = null;
        _checkVisionSupport();
      }
    } catch (e) {
      Get.find<AppLogService>()
          .error('Image pick failed', details: e, category: LogCategory.chat);
      Get.snackbar(
          'Image Pick Failed', 'Could not pick an image on this device.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _pickImageDesktop() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final files = picked?.files;
    if (files == null || files.isEmpty) return;
    final path = files.first.path;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    selectedImagePath.value = path;
    selectedImageBase64.value = null;
    selectedFileName.value = path.split(Platform.pathSeparator).last;
    selectedFilePath.value = path;
    selectedFileType.value = 'image';
    selectedFileSize.value = await file.length();
    selectedFileContent.value = null;
    _checkVisionSupport();
  }

  Future<void> takePhoto() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      Get.snackbar('Camera Unavailable',
          'Photo capture needs the Android app — pick an image instead.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _visionImageMaxSide.toDouble(),
        maxHeight: _visionImageMaxSide.toDouble(),
        imageQuality: _visionImageJpegQuality,
      );
      if (file != null) {
        selectedImagePath.value = file.path;
        selectedImageBase64.value = null;
        selectedFileName.value = file.name;
        selectedFilePath.value = file.path;
        selectedFileType.value = 'image';
        selectedFileSize.value = await file.length();
        selectedFileContent.value = null;
        _checkVisionSupport();
      }
    } catch (e) {
      Get.find<AppLogService>().error('Photo capture failed',
          details: e, category: LogCategory.chat);
      Get.snackbar('Camera Failed', 'Could not capture a photo.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  void clearImage({bool deleteFile = true}) {
    final path = selectedImagePath.value;
    selectedImagePath.value = null;
    selectedImageBase64.value = null;
    if (deleteFile && path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    if (selectedFileType.value == 'image') {
      clearFile();
    }
  }

  void _checkVisionSupport() {
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value != 'cloud') {
      _checkLocalVisionSupport();
      return;
    }

    final provider = s.cloudProvider.value;
    String modelName = '';
    switch (provider) {
      case 'anthropic':
        modelName = s.anthropicModel.value;
        break;
      case 'google':
        modelName = s.googleModel.value;
        break;
      case 'kimi':
        modelName = s.kimiModel.value;
        break;
      case 'stability':
        modelName = s.stabilityModel.value;
        break;
      case 'nvidia':
        modelName = s.nvidiaModel.value;
        break;
      case 'openrouter':
        modelName = s.openRouterModel.value;
        break;
      case 'deepseek':
        modelName = s.deepSeekModel.value;
        break;
      case 'custom':
        modelName = s.customCloudModel.value;
        break;
      default:
        modelName = s.openaiModel.value;
        break;
    }

    final model = modelName.toLowerCase();

    final isVision = model.contains('vision') ||
        model.contains('-vl') ||
        model.contains('gpt-4o') ||
        model.contains('claude-3') ||
        model.contains('gemini') ||
        model.contains('pixtral') ||
        model.contains('llava') ||
        model.contains('omni');

    if (!isVision) {
      Get.snackbar(
        'Warning: Text-Only Model',
        'The selected model ($modelName) might not support images. If you get an error, switch to a vision model (like Gemini, GPT-4o, or Claude 3).',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 6),
        backgroundColor:
            const Color(0xFFFF9500).withValues(alpha: 0.95),
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
      );
    }
  }

  void _checkLocalVisionSupport() {
    var ok = false;
    try {
      final inference = Get.find<InferenceService>();
      final runtime = inference.loadedModelRuntime.value.toLowerCase();
      ok = inference.isModelLoaded.value &&
          runtime.contains('litert') &&
          inference.isVisionLoaded.value;
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    Get.snackbar(
      'Warning: Text-Only Engine',
      'On-device vision needs a LiteRT vision model — GGUF models are text-only here. Switch to Cloud for vision.',
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 6),
      backgroundColor: const Color(0xFFFF9500).withValues(alpha: 0.95),
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
    );
  }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic',
          'pdf', 'docx',
          'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac',
          'mp4', 'mov', 'avi', 'mkv',
          'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', 'xml',
          'dart', 'kt', 'java', 'js', 'ts', 'py',
          'zip', 'c', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb', 'php'
        ],
        withData: kIsWeb,
      );
      if (result == null) return;
      final file = result.files.single;
      await handleFile(file.path!, file.name,
          size: file.size, bytes: file.bytes);
    } catch (e) {
      Get.find<AppLogService>().error('File pick failed',
          details: e, category: LogCategory.chat);
    }
  }

  Future<void> handleFile(String path, String name,
      {int? size, Uint8List? bytes}) async {
    try {
      final extension = name.split('.').last.toLowerCase();
      final fileType = _attachmentTypeForExtension(extension);

      if (extension.isEmpty || (fileType == 'file' && extension != 'zip')) {
        Get.snackbar(
          'Unsupported file',
          'Only images, audio, PDF, DOCX, ZIP and text/code files are supported.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      if (fileType == 'image') {
        selectedImagePath.value = path;
        selectedImageBase64.value =
            (kIsWeb && bytes != null) ? base64Encode(bytes) : null;
        selectedFileName.value = name;
        selectedFilePath.value = path;
        selectedFileType.value = 'image';
        selectedFileSize.value = size ?? await File(path).length();
        selectedFileContent.value = null;
        _checkVisionSupport();
        return;
      }

      selectedFileName.value = name;
      selectedFileType.value = extension;
      selectedFileSize.value = size ?? await File(path).length();
      selectedFilePath.value = path;
      selectedFileContent.value = 'chat_extracting_text'.tr;

      if (extension == 'zip') {
        final chunks = await DocumentExtractorService.extractZip(path);
        final structure = _generateProjectStructure(chunks);
        final content =
            chunks.map((c) => '--- ${c.source} ---\n${c.text}').join('\n\n');
        selectedFileContent.value = '$structure\n\n$content';
      } else {
        final text = await DocumentExtractorService.extractText(path, extension);
        selectedFileContent.value = text;
      }

      if (selectedFileContent.value != null && selectedFileContent.value!.length > 2000) {
        final vs = Get.find<VectorService>();
        selectedFileChunks.assignAll(vs.chunkText(selectedFileContent.value!));
      } else {
        selectedFileChunks.clear();
      }
    } catch (e) {
      Get.find<AppLogService>().error('File handle failed',
          details: e, category: LogCategory.chat);
    }
  }

  String _generateProjectStructure(List<DocumentChunk> chunks) {
    final buffer = StringBuffer();
    buffer.writeln('Project Structure Overview:');
    
    final tree = <String, Set<String>>{};
    for (final c in chunks) {
      final parts = c.source.split('/');
      if (parts.length > 1) {
        final root = parts[0];
        tree.putIfAbsent(root, () => {}).add(parts.sublist(0, parts.length - 1).join('/'));
      }
    }

    if (tree.isNotEmpty) {
      buffer.writeln('Root Folders: ${tree.keys.join(', ')}');
      if (tree.values.fold(0, (sum, set) => sum + set.length) < 20) {
        buffer.writeln('Subfolders: ${tree.values.expand((e) => e).join(', ')}');
      }
    }
    
    buffer.writeln('Total files: ${chunks.length}');
    buffer.writeln('---');
    return buffer.toString();
  }

  void clearFile() {
    selectedFileName.value = null;
    selectedFileContent.value = null;
    selectedFilePath.value = null;
    selectedFileType.value = null;
    selectedFileSize.value = 0;
    selectedFileChunks.clear();
  }
}
