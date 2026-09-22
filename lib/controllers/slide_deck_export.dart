/// Export: markdown, PDF, HTML, PPTX, browser preview, slide images.
///
/// Split from `slide_deck_controller.dart` - behavior is unchanged.
/// Contains: canGenerateImages, generateSlideImage(), _hintNoImageEngine(), _deckTitle, exportMarkdown()
///   exportPdf(), exportHtml(), previewInBrowser(), exportPptx(), templates
part of 'slide_deck_controller.dart';

extension SlideDeckControllerExport on SlideDeckController {
  bool get canGenerateImages {
    try {
      return Get.find<LocalImageService>().isModelLoaded.value;
    } catch (_) {
      return false;
    }
  }

  Future<void> generateSlideImage(int index) async {
    if (index < 0 || index >= slides.length) return;
    LocalImageService svc;
    try {
      svc = Get.find<LocalImageService>();
    } catch (_) {
      _hintNoImageEngine();
      return;
    }
    if (!svc.isModelLoaded.value) {
      _hintNoImageEngine();
      return;
    }
    final s = slides[index];
    final prompt = s.imagePrompt.trim().isEmpty
        ? '${topic.value.trim()}: ${s.title}'.trim()
        : s.imagePrompt.trim();
    imageBusyIndex.value = index;
    try {
      final bytes = await svc.generateImage(prompt: prompt);
      if (bytes != null && bytes.isNotEmpty) {
        s.imageBytes = bytes;
        slides.refresh();
      } else {
        AppSnackbar.showTop('Image failed', 'The image engine returned nothing.');
      }
    } catch (e) {
      AppSnackbar.showTop('Image failed', '$e');
      _log('Slide image failed', e);
    } finally {
      imageBusyIndex.value = -1;
    }
  }

  void _hintNoImageEngine() {
    AppSnackbar.showTop(
      'No image engine',
      'Load a Stable Diffusion model to render slide images.',
    );
  }

  String get _deckTitle =>
      topic.value.trim().isEmpty ? 'Untitled deck' : topic.value.trim();

  Future<void> exportMarkdown() async {
    if (slides.isEmpty) return;
    await PromptExport.shareAsMarkdown(
      deckToMarkdown(_deckTitle, slides.toList()),
      baseName: 'slides',
    );
  }

  Future<void> exportPdf() async {
    if (slides.isEmpty) return;
    await PromptExport.shareAsPdf(
      deckToMarkdown(_deckTitle, slides.toList()),
      baseName: 'slides',
    );
  }

  Future<void> exportHtml() async {
    if (slides.isEmpty) return;
    try {
      final html = deckToHtml(_deckTitle, slides.toList(), theme: theme.value);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await ExportFile.quickExport(
        text: html,
        fileName: 'cubiclm_slides_$stamp.html',
        mimeType: 'text/html',
        shareText: html,
        category: 'slides',
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  Future<void> previewInBrowser() async {
    if (slides.isEmpty) return;
    try {
      final html = deckToHtml(_deckTitle, slides.toList(), theme: theme.value);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/cubiclm_slides_$stamp.html');
      await file.writeAsString(html, flush: true);
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        AppSnackbar.showTop('Cannot open', 'No browser found.');
      }
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  Future<void> exportPptx() async {
    if (slides.isEmpty) return;
    try {
      final bytes = await deckToPptx(_deckTitle, slides.toList(), theme: theme.value);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await ExportFile.quickExport(
        bytes: Uint8List.fromList(bytes),
        fileName: 'cubiclm_slides_$stamp.pptx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        category: 'slides',
      );
    } catch (e) {
      AppSnackbar.showTop('prompt_export_failed'.tr, '$e');
    }
  }

  static const templates = SlideDeckControllerTemplates.templates;

}
