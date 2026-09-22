/// Deck generation: outline, direct, import, URL, templates.
///
/// Split from `slide_deck_controller.dart` - behavior is unchanged.
/// Contains: generateOutline(), generateFromOutline(), generateDirectly(), generate(), importPptxFile()
///   generateFromUrl(), generateFromTemplate()
part of 'slide_deck_controller.dart';

extension SlideDeckControllerGenerate on SlideDeckController {
  Future<void> generateOutline() async {
    // .pptx sources skip the AI outline flow: structural import is instant
    // and exact, then Restyle/regen can redesign from real content.
    if (sourceFile.value != null &&
        sourceFile.value!.path.toLowerCase().endsWith('.pptx')) {
      await importPptxFile();
      return;
    }
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      String context = '';
      if (sourceFile.value != null) {
        final ext = sourceFile.value!.path.split('.').last;
        context = await DocumentExtractorService.extractText(
            sourceFile.value!.path, ext);
      }
      if (selectedDataSheetId.value != null) {
        final ds = Get.find<CubicDataController>().byId(selectedDataSheetId.value!);
        if (ds != null) {
          context += '\n--- DataSheet: ${ds.name} ---\n${_extractDataSheetText(ds)}';
        }
      }
      if (useResearch.value) {
        final result = await WebFetchService.augmentWithSources(t);
        context += result.augmentedText;
      }

      final raw = await _ask(
        prompt: 'Create an outline for a ${slideCount.value}-slide presentation about: $t\n\n'
            '${context.isNotEmpty ? "Use this context:\n$context" : ""}',
        system: outlineSystemPrompt(count: slideCount.value, topic: t),
        imagePath: inputImage.value?.path,
        onProgress: (fullText) {
          final parsed = parseOutline(fullText);
          if (parsed.isNotEmpty) {
            outline.assignAll(parsed);
            showingOutline.value = true;
          }
        },
      );
      final parsed = parseOutline(raw);
      if (parsed.isNotEmpty) {
        outline.assignAll(parsed);
        showingOutline.value = true;
      } else if (raw.trim().isNotEmpty) {
        lastError.value = 'Failed to parse outline JSON.';
      }
    } catch (e) {
      lastError.value = '$e';
      _log('Outline generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generateFromOutline() async {
    if (outline.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      final t = topic.value.trim();
      final outlineJson = jsonEncode(outline.map((e) => e.toMap()).toList());

      final raw = await _ask(
        prompt: 'Create a ${outline.length}-slide presentation about: $t\n\n'
            'Follow this outline strictly:\n$outlineJson',
        system: slideSystemPrompt(
            count: outline.length,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
        imagePath: inputImage.value?.path,
        onProgress: (fullText) {
          final parsed = parseSlides(fullText);
          if (parsed.isNotEmpty) {
            slides.assignAll(parsed);
          }
        },
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
      showingOutline.value = false;
    } catch (e) {
      lastError.value = '$e';
      _log('Deck generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generateDirectly() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    regenIndex.value = -1;
    lastError.value = null;
    try {
      String context = '';
      if (sourceFile.value != null) {
        final ext = sourceFile.value!.path.split('.').last;
        context = await DocumentExtractorService.extractText(
            sourceFile.value!.path, ext);
      }

      final raw = await _ask(
        prompt: 'Create a ${slideCount.value}-slide presentation about: $t\n\n'
            '${context.isNotEmpty ? "Use this context:\n$context" : ""}',
        system: slideSystemPrompt(
            count: slideCount.value,
            style: style.value,
            visualStyle: visualStyle.value,
            audience: audience.value),
        imagePath: inputImage.value?.path,
        onProgress: (fullText) {
          final parsed = parseSlides(fullText);
          if (parsed.isNotEmpty) {
            slides.assignAll(parsed);
          }
        },
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
    } catch (e) {
      lastError.value = '$e';
      _log('Deck generation failed', e);
    } finally {
      generating.value = false;
    }
  }

  Future<void> generate() async {
    // Default to outline workflow for Gemma level
    await generateOutline();
  }

  /// Structural .pptx import: real slides in, editable deck out. No AI
  Future<void> importPptxFile() async {
    final f = sourceFile.value;
    if (f == null || generating.value) return;
    generating.value = true;
    lastError.value = null;
    try {
      final bytes = await f.readAsBytes();
      final parsed = parsePptx(bytes);
      if (parsed.isEmpty) {
        lastError.value =
            'No readable slides found in ${f.path.split('/').last}.';
        return;
      }
      slides.assignAll(parsed);
      outline.clear();
      showingOutline.value = false;
      final base = f.path.split('/').last.replaceAll(
          RegExp(r'\.pptx$', caseSensitive: false), '');
      topic.value = base.isEmpty ? 'Imported deck' : base;
      AppSnackbar.showTop('Imported ${parsed.length} slides',
          'Restyle or regenerate any slide to redesign.',
          logHistory: true);
    } catch (e) {
      lastError.value = '$e';
      _log('PPTX import failed', e);
    } finally {
      generating.value = false;
    }
  }

  /// Generate a deck from a website URL.
  Future<void> generateFromUrl(String url) async {
    if (generating.value || url.trim().isEmpty) return;
    generating.value = true;
    lastError.value = null;
    try {
      final content = await WebFetchService.fetchAsText(url);
      if (content == null || content.isEmpty) {
        throw Exception('Could not extract content from the provided URL.');
      }

      topic.value = 'Presentation based on $url';
      final raw = await _ask(
        prompt: 'Create a ${slideCount.value}-slide presentation outline based on this web content:\n\n$content',
        system: outlineSystemPrompt(count: slideCount.value, topic: topic.value),
      );
      final parsed = parseOutline(raw);
      if (parsed.isNotEmpty) {
        outline.assignAll(parsed);
        showingOutline.value = true;
      }
    } catch (e) {
      lastError.value = '$e';
      _log('URL-to-Deck failed', e);
    } finally {
      generating.value = false;
    }
  }
  Future<void> generateFromTemplate(String templateName) async {
    final skeleton = SlideDeckController.templates[templateName];
    if (skeleton == null) return;
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    lastError.value = null;
    slideCount.value = skeleton.length;
    try {
      final structureHint = skeleton
          .asMap()
          .entries
          .map((e) =>
              'Slide ${e.key + 1}: "${e.value['title']}" (layout: ${e.value['layout']})')
          .join('\n');
      final raw = await _ask(
        prompt: 'Create a ${skeleton.length}-slide presentation about: $t\n\n'
            'Follow this exact slide structure:\n$structureHint',
        system: slideSystemPrompt(
            count: skeleton.length,
            style: style.value,
            audience: audience.value),
        onProgress: (fullText) {
          final parsed = parseSlides(fullText);
          if (parsed.isNotEmpty) {
            slides.assignAll(parsed);
          }
        },
      );
      final parsed = parseSlides(raw);
      slides.assignAll(parsed);
    } catch (e) {
      lastError.value = '$e';
      _log('Template generation failed', e);
    } finally {
      generating.value = false;
    }
  }

}
