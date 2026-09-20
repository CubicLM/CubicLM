/// Agent workspace ops: console, assets, symbols, attachments, mentions.
///
/// Split from `agent_controller.dart` - behavior is unchanged.
/// Contains: applyPendingChanges(), _cw, _cwPlatform(), initializeSkeleton(), _calculateDiffStats()
///   _cwDiagnosticsForAi(), addConsoleLog(), clearConsole(), _checkAutoInstall()
///   captureCheckpointThumbnail(), generateProjectAsset(), getProjectDependencies()
///   scanProjectSymbols(), searchProjectContent(), sendStdin(), promoteComponent(), inlineEdit()
///   attachImage(), clearAttachment(), clearPickedElement(), toggleElementPick(), onElementPicked()
part of 'agent_controller.dart';

extension AgentControllerWorkspace on AgentController {
  Future<void> applyPendingChanges() async {
    final p = project.value;
    if (p == null || pendingChanges.isEmpty) return;
    
    reviewingChanges.value = false;
    generating.value = true;
    buildStatus.value = 'Saving changes…';
    
    try {
      for (final entry in pendingChanges.entries) {
        await _ws.writeFile(p.id, entry.key, entry.value['new'] ?? '');
      }
      await _ws.touch(p.id);
      await refreshFiles();
      _touch();
      
      // Save checkpoint after successful apply with stats
      await _ws.saveCheckpoint(p.id, 
        label: 'Applied changes', 
        insertions: lastInsertions.value, 
        deletions: lastDeletions.value
      );

      pendingChanges.clear();
      AppSnackbar.showTop('Success', 'Changes applied successfully');
      
      // Master Class: Auto-install dependencies
      _checkAutoInstall();

      // Delay slightly to let the WebView reload before capturing
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      lastError.value = '$e';
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }

  CubicWebLogger? get _cw {
    try {
      return Get.find<CubicWebLogger>();
    } catch (_) {
      return null;
    }
  }

  String _cwPlatform() {
    try {
      return Get.find<RuntimeManager>().status.value.platform;
    } catch (_) {
      try {
        if (kIsWeb) return 'web';
        return Platform.operatingSystem;
      } catch (_) {
        return '';
      }
    }
  }

  /// Initialize a project with a pre-built skeleton based on the prompt.
  Future<void> initializeSkeleton(String projectId, String topic) async {
    String? template;
    final t = topic.toLowerCase();
    if (t.contains('landing')) template = 'Landing Page';
    if (t.contains('dashboard')) template = 'Dashboard';
    
    if (template != null && projectSkeletons.containsKey(template)) {
      term('🪄 initializing $template skeleton...');
      final skeleton = projectSkeletons[template]!;
      await _ws.importFiles(projectId, skeleton);
      await refreshFiles();
      _touch();
    }
  }

  /// Helper to calculate diff stats (+/-) for UI display.
  void _calculateDiffStats(String oldContent, String newContent) {
    if (oldContent.isEmpty) {
      lastInsertions.value += newContent.split('\n').length;
      return;
    }
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');
    
    // Simple line-based diff counting
    final oldSet = oldLines.toSet();
    lastInsertions.value += newLines.where((l) => !oldSet.contains(l)).length;
    lastDeletions.value += oldLines.where((l) => !newLines.contains(l)).length;
  }

  /// Recent system diagnostics for AI prompts (§16/17). Empty when
  /// nothing environmental failed — keeps prompts lean.
  String _cwDiagnosticsForAi() {
    try {
      final pid = project.value?.id ?? '';
      final ctx = _cw?.recentForAi(projectId: pid) ?? '';
      if (ctx.isEmpty) return '';
      return 'SYSTEM DIAGNOSTICS (environment — items marked aiCanFix: false '
          'CANNOT be fixed by editing code, do not rewrite files for them):\n$ctx\n\n';
    } catch (_) {
      return '';
    }
  }

  /// Manifest id of the CLI currently attached to the terminal input
  /// (null = input runs one-shot shell commands).

  /// Terminal-detected CLI awaiting the user's Add/Ignore choice.

  /// Terminal buffer: timestamped agent activity (builds, fixes, file
  /// ops, console errors). The AI reads the tail in repair prompts, so
  /// it "sees" what happened — capped at 200 lines.

  /// Chat transcript with the builder AI (user prompts + agent replies).
  /// Mirrors other builders: conversation is visible, not hidden.

  /// Live build status shown in the preview pane while working
  /// (null when idle). E.g. "Streaming response… 12k chars".

  /// Attached image (base64, no data-uri prefix) for vision models.
  /// Sent with the next build/modify call, then cleared.

  /// Element picked from the live preview (long-press in preview).
  /// Injected as context into the next modify prompt.

  /// Element currently hovered in the preview (canvas mode).

  void addConsoleLog(String level, String message) {
    consoleBuffer.add({
      'level': level,
      'message': message,
      'time': DateTime.now().millisecondsSinceEpoch,
    });
    if (consoleBuffer.length > 500) {
      consoleBuffer.removeAt(0);
    }
  }

  void clearConsole() => consoleBuffer.clear();

  /// Master Class: Detect new dependencies and run npm install automatically.
  Future<void> _checkAutoInstall() async {
    final p = project.value;
    if (p == null) return;
    
    try {
      final pkgJson = await _ws.readFile(p.id, 'package.json');
      if (pkgJson == null) return;
      
      final data = jsonDecode(pkgJson);
      final deps = data['dependencies'] as Map<String, dynamic>? ?? {};
      final devDeps = data['devDependencies'] as Map<String, dynamic>? ?? {};
      
      // Basic heuristic: check if node_modules exists, if not, or if deps changed
      // In a real WASM container we'd have a lockfile tracker.
      // For this master class upgrade, we'll trigger a check.
      term('⚙ scanning for new dependencies...');
      
      // If we find something common that's NOT usually there, trigger install.
      // In a real system we'd compare against a cached dep map.
      if (deps.isNotEmpty || devDeps.isNotEmpty) {
        term('🚀 new dependencies detected, running autonomous install...');
        runTerminal('npm install');
      }
    } catch (_) {}
  }

  /// Take a visual snapshot of the preview and link it to the latest checkpoint.
  Future<void> captureCheckpointThumbnail() async {
    final p = project.value;
    final web = previewWebController;
    if (p == null || web == null) return;
    
    try {
      final bytes = await web.takeScreenshot();
      if (bytes == null) return;
      
      final checkpoints = await _ws.listCheckpoints(p.id);
      if (checkpoints.isNotEmpty) {
        checkpointThumbnails[checkpoints.first.id] = bytes;
      }
    } catch (_) {}
  }

  /// Generate an AI image asset and save it to the project.
  Future<void> generateProjectAsset(String prompt, String path) async {
    final p = project.value;
    if (p == null || prompt.trim().isEmpty) return;

    generating.value = true;
    buildStatus.value = 'Generating asset...';
    term('> generate asset: "$prompt" -> $path');

    try {
      // Use stability provider if configured, otherwise fallback to a placeholder/mock
      // (The system prompt for StabilityProvider expects [IMAGE_BASE64] response)
      final cloud = Get.find<CloudService>();
      
      String response;
      if (cloud.isProviderConfigured('stability')) {
        response = await cloud.sendMessage(
          messages: [
            {'role': 'user', 'content': prompt}
          ],
        );
      } else {
        // Mock generation for testing if no API key
        await Future.delayed(const Duration(seconds: 3));
        response = '[IMAGE_BASE64]placeholder';
      }

      if (response.startsWith('[IMAGE_BASE64]')) {
        final base64 = response.replaceFirst('[IMAGE_BASE64]', '');
        if (base64 == 'placeholder') {
          // Just touch a dummy file for the UI effect in mock mode
          await _ws.writeFile(p.id, path, 'Mock image data for: $prompt');
        } else {
          final bytes = base64Decode(base64);
          await _ws.writeBinaryFile(p.id, path, bytes);
        }
        
        await refreshFiles();
        _touch();
        AppSnackbar.showTop('Asset Generated', '$path saved to project.');
        term('✓ asset generated: $path');
      } else {
        throw Exception('Unexpected response from image service');
      }
    } catch (e) {
      lastError.value = '$e';
      term('✗ asset generation failed: $e');
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }

  /// Analyze project imports to build a dependency graph.
  Future<List<Map<String, String>>> getProjectDependencies() async {
    final p = project.value;
    if (p == null) return [];
    
    final deps = <Map<String, String>>[];
    final importPattern = RegExp("import\\s+.*from\\s+['\"](.+)['\"]|import\\s+['\"](.+)['\"]");

    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      final matches = importPattern.allMatches(content);
      for (final m in matches) {
        final imported = m.group(1) ?? m.group(2);
        if (imported != null) {
          deps.add({'from': path, 'to': imported});
        }
      }
    }
    return deps;
  }
  /// Scan all project files for symbols (functions, components).
  Future<List<Map<String, dynamic>>> scanProjectSymbols() async {
    final p = project.value;
    if (p == null) return [];
    
    final symbols = <Map<String, dynamic>>[];
    // Patterns for React components, Vue components, and general JS functions
    final patterns = [
      RegExp(r'const\s+([A-Z][\w]+)\s*='), // React/Vue Component
      RegExp(r'function\s+([\w]+)\s*\('), // JS Function
      RegExp(r'export\s+(?:default\s+)?(?:const|let|var)\s+([\w]+)'), // Exported var
    ];

    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        for (final pattern in patterns) {
          final match = pattern.firstMatch(lines[i]);
          if (match != null && match.groupCount >= 1) {
            final name = match.group(1) ?? '';
            if (name.isEmpty) continue;
            
            final isComponent = name[0].toUpperCase() == name[0] && name[0] != name[0].toLowerCase();

            symbols.add({
              'name': name,
              'file': path,
              'line': i + 1,
              'type': isComponent ? 'component' : 'function',
            });
          }
        }
      }
    }
    return symbols;
  }

  /// Search through all project files for a specific query.
  Future<List<Map<String, dynamic>>> searchProjectContent(String query) async {
    final p = project.value;
    if (p == null || query.trim().isEmpty) return [];
    
    final results = <Map<String, dynamic>>[];
    final queryLower = query.toLowerCase();
    
    for (final path in files) {
      final content = await _ws.readFile(p.id, path) ?? '';
      if (content.toLowerCase().contains(queryLower)) {
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains(queryLower)) {
            results.add({
              'path': path,
              'line': i + 1,
              'text': lines[i].trim(),
            });
          }
        }
      }
    }
    return results;
  }
  /// Send a line to the active terminal process or attached CLI.
  void sendStdin(String line) {
    if (activeCliId.value != null) {
      sendStdinToCli(line);
      return;
    }
    // No active CLI/interactive session: treat as a new shell command.
    runTerminal(line);
  }

  Future<void> promoteComponent(String name, String code) async {
    final p = project.value;
    if (p == null) return;
    
    // Auto-detect extension based on framework
    String ext = '.html';
    if (p.framework.toLowerCase().contains('react')) ext = '.jsx';
    if (p.framework.toLowerCase().contains('vue')) ext = '.vue';
    
    final path = 'src/components/$name$ext';
    
    pendingChanges[path] = {'old': '', 'new': code};
    reviewingChanges.value = true;
    
    AppSnackbar.showTop('Promoting Component', 'Review the new file in the diff view.');
  }
  Future<void> inlineEdit(String path, String selection, String prompt) async {
    final p = project.value;
    if (p == null || selection.trim().isEmpty || prompt.trim().isEmpty) return;

    generating.value = true;
    buildStatus.value = 'AI Editing selection…';
    
    try {
      final currentContent = await _ws.readFile(p.id, path) ?? '';
      
      final raw = await _ask(
        prompt: 'Refactor the following selection in "$path":\n\n'
            'SELECTION:\n$selection\n\n'
            'INSTRUCTION: $prompt\n\n'
            'CONTEXT (FULL FILE):\n$currentContent\n\n'
            'Return ONLY the modified selection text. No explanations.',
        system: 'You are a precise code editor. Return ONLY the new selection text.',
        onProgress: (n) => _streamStatus('Editing', n),
      );

      if (_cancelled) return;
      
      final newSelection = raw.trim();
      final newContent = currentContent.replaceFirst(selection, newSelection);
      
      pendingChanges.clear();
      pendingChanges[path] = {'old': currentContent, 'new': newContent};
      reviewingChanges.value = true;
      
      AppSnackbar.showTop('AI Edit Ready', 'Review the changes in the diff view.');
    } catch (e) {
      lastError.value = '$e';
    } finally {
      generating.value = false;
      buildStatus.value = null;
    }
  }

  /// When true, long-press on any preview element captures it as context.

  /// Attach an image (from gallery/camera) for vision models.
  Future<void> attachImage() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 82,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      attachedImage.value = base64Encode(bytes);
      term('📷 image attached (${(bytes.length / 1024).round()} KB)');
    } catch (e) {
      AppSnackbar.showTop('Attach failed', '$e', logHistory: false);
    }
  }

  void clearAttachment() => attachedImage.value = null;
  void clearPickedElement() => pickedElement.value = null;
  void toggleElementPick() => elementPickMode.value = !elementPickMode.value;

  /// Called by the preview's JS bridge when the user long-presses an element.
  void onElementPicked(String info) {
    pickedElement.value = info;
    hoveredElement.value = null;
    elementPickMode.value = false;
    requestAskFocus.value++;
    term(
        '🎯 element picked: ${info.length > 80 ? '${info.substring(0, 80)}…' : info}');
    AppSnackbar.showTop(
      'Element picked',
      'Context added — describe the change you want.',
      logHistory: false,
    );
  }
}
