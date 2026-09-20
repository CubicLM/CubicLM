/// Project generation, planning, repair, and context building.
///
/// Split from `agent_controller.dart` - behavior is unchanged.
/// Contains: modifyProject(), generatePlan(), buildFromPlan(), _planSystemPrompt(), _extractPlan()
///   onConsoleError(), _shouldRewriteForError(), repairFromError(), runAutoTest(), _projectContext()
///   openProject(), updateSuggestions()
part of 'agent_controller.dart';

extension AgentControllerGeneration on AgentController {
  /// Follow-up change ("make navbar blue"): model returns ONLY
  /// changed/new files, merged over the workspace.
  Future<void> modifyProject() async {
    final p = project.value;
    final t = topic.value.trim();
    if (p == null || t.isEmpty || generating.value || fixing.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    currentTraceId = newTraceId();
    _say('user', t);
    _say('activity', '');
    buildStatus.value = 'Applying change…';
    term('> modify: "${t.length > 80 ? '${t.substring(0, 80)}…' : t}"');
    _beginSteps();
    step('thinking', 'Planning the change…');
    String? beforeCp;
    try {
      beforeCp = await _ws.saveCheckpoint(p.id, label: 'Before modify');
      // Snapshot pre-modify contents for the diff view. Live partial
      // writes land on disk mid-stream, so "old" must come from BEFORE
      // generation — never from post-stream disk reads.
      Map<String, String> before = {};
      try {
        before = await _projectContents(p.id);
        var total = 0;
        for (final v in before.values) {
          total += v.length;
        }
        if (total > 1000000) before = {};
      } catch (_) {}
      final projContext = await _projectContext(p.id, t);
      // One-shot visual context: user long-pressed an element in preview.
      final picked = pickedElement.value;
      pickedElement.value = null;
      final pickedCtx = (picked != null && picked.trim().isNotEmpty)
          ? 'SELECTED ELEMENT (user picked this in the live preview — focus the change here):\n$picked\n\n'
          : '';
      final raw = await _ask(
        prompt: 'Modify the "${p.name}" ${p.framework} project: $t\n\n'
            '${pickedCtx}CURRENT FILES:\n$projContext\n\n'
            '${_cwDiagnosticsForAi()}'
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
            'Return a files-JSON object with ONLY new or fully-rewritten changed files.',
        system:
            '${webSystemPrompt(
              framework: p.framework, 
              brandIdentity: brandIdentity,
              library: selectedLibrary.value,
              designSystem: selectedDesignSystem.value,
            )}\nSTRICT: output only files that change (plus any brand-new files).',
        onProgress: (n) => _streamStatus('Writing change', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );
      if (_cancelled) {
        // Live partial writes may already be on disk — restore the
        // pre-modify snapshot so cancel is lossless.
        try {
          await _ws.rollbackToCheckpoint(p.id, beforeCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        term('■ modify cancelled by user — rolled back');
        return;
      }
      lastInsertions.value = 0;
      lastDeletions.value = 0;
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      
      pendingChanges.clear();
      for (final f in parsed) {
        final old = before[f.path] ?? await _ws.readFile(p.id, f.path);
        _calculateDiffStats(old ?? '', f.content);
        pendingChanges[f.path] = {'old': old ?? '', 'new': f.content};
      }
      
      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ change ready for review');
        step('done', 'Change ready for review.');
      } else {
        term('! no changes generated');
        step('error', 'No changes generated.');
      }
      
      _snapshotActivity();
      _say('assistant', 'I\'ve generated the changes. Please review them in the diff view.');
      _markLastAssistantWithBuild();

    } catch (e) {
      if (_cancelled) {
        term('■ modify cancelled by user');
        return;
      }
      // Same guard as cancel: a mid-stream failure must not leave
      // live partial writes behind.
      final cp = beforeCp;
      if (cp != null) {
        try {
          await _ws.rollbackToCheckpoint(p.id, cp);
          await refreshFiles();
          _touch();
        } catch (_) {}
      }
      lastError.value = '$e';
      term('✗ modify failed: $e');
      step('error', 'Change failed — rolled back.');
      _snapshotActivity();
      _log('Project modify failed', e);
    } finally {
      _clearStreaming();
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  // ── Plan Mode ──

  /// Generate a structured plan (no code yet). User reviews, then approves.
  Future<void> generatePlan() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    transcript.clear();
    _say('user', t);
    buildStatus.value = 'Thinking through the plan…';
    term(
        '> plan: "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" (${framework.value})');
    try {
      final raw = await _ask(
        prompt: 'Plan this ${framework.value} project based on: $t\n\n'
            'Output a structured plan in this EXACT format inside a ```plan fenced block:\n\n'
            '```plan\n'
            'PROJECT: <short project name>\n'
            'FRAMEWORK: ${framework.value}\n'
            'DESCRIPTION: <1-2 sentence description>\n'
            'FILES:\n'
            '- index.html: <what this file does>\n'
            '- styles.css: <what this file does>\n'
            '- app.js: <what this file does>\n'
            'FEATURES:\n'
            '- <feature 1>\n'
            '- <feature 2>\n'
            'DESIGN:\n'
            '- <color scheme, layout style, typography>\n'
            '```\n\n'
            'Be specific about each file\'s purpose and the design decisions. '
            'Do NOT write any code yet — just the plan.',
        system: _planSystemPrompt(),
        onProgress: (n) => _streamStatus('Planning', n),
      );
      if (_cancelled) return;
      // Extract plan text from response
      final planText = _extractPlan(raw);
      pendingPlan.value = planText;
      _say('assistant', 'Here\'s my plan:\n\n$planText');
      term('✓ plan ready — review and tap Build to proceed');
      buildStatus.value = null;
    } catch (e) {
      if (_cancelled) {
        term('■ plan cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ plan failed: $e');
      _log('Plan generation failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  /// Build from an approved plan (plan must be in pendingPlan).
  Future<void> buildFromPlan() async {
    final plan = pendingPlan.value;
    final t = topic.value.trim();
    if (plan == null || t.isEmpty || generating.value) return;
    pendingPlan.value = null; // consume the plan
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    _say('user', '✓ Build it');
    _say('activity', '');
    buildStatus.value = 'Building from plan…';
    term('> build from plan (${framework.value})');
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, framework.value);
      project.value = p;
      final raw = await _ask(
        prompt:
            'Build this ${framework.value} project NOW based on this APPROVED plan:\n\n'
            '$plan\n\n'
            'ORIGINAL REQUEST: $t\n\n'
            'Output EXACTLY one ```files fenced block with ALL the code. '
            'Every file listed in the plan MUST be included with complete, '
            'working code. No placeholders.',
        system: webSystemPrompt(
          framework: framework.value, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        ),
        onProgress: (n) => _streamStatus('Writing project', n),
      );
      if (_cancelled) return;
      buildStatus.value = 'Saving files…';
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      final err = await _ws
          .importFiles(p.id, {for (final f in parsed) f.path: f.content});
      if (err != null) {
        lastError.value = 'Some files failed: $err';
      }
      await refreshFiles();
      await _serve();
      if (truncated.isNotEmpty) {
        term('⚠ truncated: ${truncated.join(', ')}');
        _say('assistant',
            'Heads-up — ${truncated.length} file(s) were cut to fit size limits (${truncated.take(3).join(', ')}). Ask me to regenerate them smaller if anything looks off.');
      }
      _touch();
      buildStatus.value = null;
      final summary =
          'Built ${parsed.length} files from plan — preview is live.';
      step('done', 'Built ${parsed.length} files from plan.');
      _snapshotActivity();
      _say('assistant', summary);
      _markLastAssistantWithBuild();
      term('✓ build done — ${files.length} files, preview live');
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ build from plan failed: $e');
      step('error', 'Build from plan failed.');
      _snapshotActivity();
      _log('Build from plan failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  String _planSystemPrompt() {
    return 'You are a senior web architect. When asked to plan a project, '
        'output a structured plan — NOT code. Use the exact format requested. '
        'Be specific about file purposes, features, and design decisions. '
        'Keep the plan concise but actionable.';
  }

  String _extractPlan(String raw) {
    final planFence = RegExp(r'```plan\n([\s\S]*?)```');
    final m = planFence.firstMatch(raw);
    if (m != null) return m.group(1)!.trim();
    // Fallback: return everything after "PLAN:" or the full response
    final planIdx = raw.indexOf('PLAN:');
    if (planIdx >= 0) return raw.substring(planIdx).trim();
    return raw.trim();
  }

  /// Called by the view's WebView console hook. Auto-repairs (bounded),
  /// otherwise surfaces with a manual Fix button.
  ///
  /// Page-load failures are classified first: a dead dev server is an
  /// environment problem (System Logs), never a rewrite trigger (§27).
  Future<void> onConsoleError(String message) async {
    final p = project.value;
    consoleError.value = message;
    term(
        '✗ console: ${message.length > 160 ? '${message.substring(0, 160)}…' : message}');
    if (message.startsWith('Page load failed') && p != null) {
      ClassificationResult? c;
      try {
        c = classifyFailure(
          stderr: message,
          platform: _cwPlatform(),
          localhostExpected: devServerUrl.value != null,
        );
      } catch (_) {}
      if (c != null && c.errorCode != null && !c.aiCanFix) {
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: c.category,
            component: 'WEBVIEW',
            errorCode: c.errorCode!,
            title: c.title,
            message: c.explanation,
            technicalDetails: message,
            operation: 'preview-load',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: c.fallbackAvailable,
          );
          term(
              '■ ${c.errorCode} — ${c.title} (see System Logs; no code rewrite)');
        } catch (_) {}
        return;
      }
    }
    if (p == null || fixing.value || generating.value) return;
    if (!autoFix.value || _autoRounds >= AgentController.maxRepairRounds) return;
    _autoRounds++;
    try {
      final short =
          message.length > 120 ? '${message.substring(0, 120)}…' : message;
      step('error', short);
      step('fix', 'Auto-fix round $_autoRounds/${AgentController.maxRepairRounds} — diagnosing…');
    } catch (_) {}
    await repairFromError();
  }

  /// True when the triggering error deserves a file rewrite. Separated
  /// so the auto-fix trigger, the manual button and tests share it.
  bool _shouldRewriteForError(String err) {
    ClassificationResult c;
    try {
      c = classifyFailure(stderr: err, platform: _cwPlatform());
    } catch (_) {
      return true;
    }
    if (c.errorCode != null && !c.aiCanFix) {
      term(
          '■ ${c.errorCode} — ${c.title}: environment problem, skipping code rewrite (see System Logs)');
      _say('assistant',
          '${c.title} (${c.errorCode}). ${c.explanation} I did not modify your files — open CubicWeb System Logs for details.');
      return false;
    }
    return true;
  }

  Future<void> repairFromError() async {
    final p = project.value;
    final err = consoleError.value;
    if (p == null || err == null || err.isEmpty || fixing.value) return;
    // No-loop guard (§5): environment failures must not trigger rewrites.
    if (!_shouldRewriteForError(err)) return;
    fixing.value = true;
    _cancelled = false;
    lastError.value = null;
    currentTraceId = newTraceId();
    _say('user', 'Auto-fix error: ${err.length > 200 ? '${err.substring(0, 200)}…' : err}');
    _say('activity', '');
    buildStatus.value = 'Fixing error…';
    term('⚙ auto-fix round $_autoRounds/${AgentController.maxRepairRounds}…');
    try {
      await _ws.saveCheckpoint(p.id, label: 'Before auto-fix');
      final projContext = await _projectContext(p.id, err);
      final raw = await _ask(
        prompt: 'Fix this runtime error in the "${p.name}" '
            '${p.framework} project:\n\nERROR:\n$err\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            '${_cwDiagnosticsForAi()}'
            'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n\n'
            'RECENT TERMINAL (what happened so far):\n'
            '${terminalTail()}\n\n'
            'Return a files-JSON object with ONLY the corrected files '
            '(complete new contents).',
        system:
            '${webSystemPrompt(
              framework: p.framework, 
              brandIdentity: brandIdentity,
              library: selectedLibrary.value,
              designSystem: selectedDesignSystem.value,
            )}\nSTRICT: output only files that change.',
        onProgress: (n) => _streamStatus('Writing fix', n),
      );
      final truncated = <String>[];
      final parsed = _parseChecked(raw, truncated);
      if (_cancelled) return;
      
      pendingChanges.clear();
      final currentFiles = await _projectContents(p.id);
      for (final f in parsed) {
        final old = currentFiles[f.path] ?? '';
        pendingChanges[f.path] = {'old': old, 'new': f.content};
      }

      if (pendingChanges.isNotEmpty) {
        reviewingChanges.value = true;
        term('✓ auto-fix ready for review');
        step('fix', 'Auto-fix ready for review.');
      } else {
        term('! auto-fix suggested no changes');
        step('fix', 'No changes suggested.');
      }

      _snapshotActivity();
      _say('assistant', 'I\'ve diagnosed the error and prepared a fix. Please review it in the diff view.');
      _markLastAssistantWithBuild();
      
      AppSnackbar.showTop(
        'Auto-fix ready',
        'Review the suggested fixes.',
        logHistory: false,
      );
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ fix cancelled by user');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-fix failed: $e');
      step('error', 'Auto-fix failed.');
      _snapshotActivity();
      _log('Auto-fix failed', e);
    } finally {
      fixing.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  // ── Browser Auto-Test ──

  /// Manual test button: checks console errors + asks AI to review code,
  /// then auto-fixes any issues found.
  Future<void> runAutoTest() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    _say('user', '🔍 Auto-test: review project for bugs and improvements');
    _say('activity', '');
    buildStatus.value = 'Running auto-test…';
    term('> auto-test: reviewing "${p.name}"…');
    try {
      // 1) Check existing console errors.
      final consoleErr = consoleError.value;
      if (consoleErr != null && consoleErr.isNotEmpty) {
        term('✗ console error detected: $consoleErr');
        await repairFromError();
        if (generating.value) return; // already fixing
      }
      // 2) Ask AI to review all files for issues.
      final projContext = await _projectContext(p.id, 'QA review');
      final raw = await _ask(
        prompt: 'Auto-test the "${p.name}" ${p.framework} project. '
            'Review all files for: broken links, missing images, '
            'accessibility issues (alt text, contrast), responsive bugs, '
            'SEO problems (missing title/meta), performance issues, '
            'and any other bugs.\n\n'
            'CURRENT FILES:\n$projContext\n\n'
            'If you find issues, return a files-JSON object with the '
            'corrected files (complete new contents). If everything looks '
            'good, respond with just: OK',
        system: '${webSystemPrompt(framework: p.framework, brandIdentity: brandIdentity)}\n'
            'You are a QA engineer. Be thorough but practical.',
        onProgress: (n) => _streamStatus('Testing', n),
      );
      if (_cancelled) return;
      if (raw.trim() == 'OK') {
        _say('assistant',
            'All checks passed! No issues found. The project looks good.');
        term('✓ auto-test: all checks passed');
        AppSnackbar.showTop('Auto-test passed', 'No issues found.',
            logHistory: false);
      } else {
        final truncated = <String>[];
        final parsed = _parseChecked(raw, truncated);
        await _ws.saveCheckpoint(p.id, label: 'Before auto-test fix');
        var applied = 0;
        for (final f in parsed) {
          final werr = await _ws.writeFile(p.id, f.path, f.content);
          if (werr == null) applied++;
        }
        await _ws.touch(p.id);
        await refreshFiles();
        _touch();
        if (truncated.isNotEmpty) {
          term('⚠ truncated: ${truncated.join(', ')}');
        }
        if (applied > 0) {
          step('done', 'Applied $applied fixes from auto-test.');
          _snapshotActivity();
          _say(
              'assistant',
              'Auto-test found and fixed $applied file${applied == 1 ? '' : 's'}. '
                  'Preview reloaded — check the result.');
          _markLastAssistantWithBuild();
          term('✓ auto-test: fixed $applied files');
          AppSnackbar.showTop('Auto-test fixed',
              '$applied file${applied == 1 ? '' : 's'} updated.',
              logHistory: false);
        } else {
          step('done', 'No issues found.');
          _snapshotActivity();
        }
      }
    } catch (e) {
      if (_cancelled) {
        term('■ auto-test cancelled');
        return;
      }
      lastError.value = '$e';
      term('✗ auto-test failed: $e');
      step('error', 'Auto-test failed.');
      _snapshotActivity();
      _log('Auto-test failed', e);
    } finally {
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }

  /// Context Management (Mini-RAG): Build a relevant context for the prompt.
  /// Prioritizes files mentioned in the prompt or symbol names.
  Future<String> _projectContext(String projectId, [String? userPrompt]) async {
    final buf = StringBuffer();
    final allFiles = await _ws.listFiles(projectId);
    final sortedFiles = List<String>.from(allFiles);

    // Prioritization logic
    if (userPrompt != null && userPrompt.isNotEmpty) {
      final promptLower = userPrompt.toLowerCase();
      
      // 1. Check for explicit file mentions
      final mentioned = sortedFiles.where((f) => promptLower.contains(f.toLowerCase())).toList();
      
      // 2. Check for symbol mentions (functions, components)
      final symbols = await scanProjectSymbols();
      final mentionedBySymbol = <String>{};
      for (final s in symbols) {
        final name = s['name']?.toString().toLowerCase();
        if (name != null && promptLower.contains(name)) {
          mentionedBySymbol.add(s['file']);
        }
      }

      // Re-sort: Mentioned files first, then by symbol, then others.
      sortedFiles.sort((a, b) {
        final aMentioned = mentioned.contains(a) || mentionedBySymbol.contains(a);
        final bMentioned = mentioned.contains(b) || mentionedBySymbol.contains(b);
        if (aMentioned && !bMentioned) return -1;
        if (!aMentioned && bMentioned) return 1;
        return a.compareTo(b);
      });
    }

    var used = 0;
    for (final path in sortedFiles) {
      final content = await _ws.readFile(projectId, path) ?? '';
      
      // If we're getting close to the limit, start truncating less relevant files
      int maxFileChars = 8000;
      if (used > AgentController.maxContextChars * 0.7) maxFileChars = 2000;

      if (content.length > maxFileChars) {
        buf.writeln('--- $path (first ${maxFileChars ~/ 1024}KB of ${content.length}) ---');
        final head = content.substring(0, maxFileChars);
        if (used + head.length > AgentController.maxContextChars) break;
        buf.writeln(head);
        used += head.length;
      } else {
        if (used + content.length > AgentController.maxContextChars) break;
        buf.writeln('--- $path ---');
        buf.writeln(content);
        used += content.length;
      }
    }
    return buf.toString();
  }

  Future<void> openProject(AgentProject p) async {
    project.value = p;
    consoleError.value = null;
    lastError.value = null;
    _autoRounds = 0;
    await refreshFiles();
    await _serve();
    _touch();
    updateSuggestions();
  }

  /// Update smart suggestions based on the project state.
  void updateSuggestions() {
    final p = project.value;
    if (p == null) {
      suggestions.assignAll([
        'Build a modern landing page',
        'Create a crypto dashboard',
        'Build a developer portfolio',
        'Create a minimalist blog',
      ]);
      return;
    }

    final list = <String>[];
    final f = p.framework.toLowerCase();

    if (files.length < 5) {
      list.add('Add a contact section');
      list.add('Add a dark mode toggle');
      list.add('Improve mobile responsiveness');
    }

    if (f.contains('react') || f.contains('next')) {
      list.add('Add a Framer Motion animation');
      list.add('Extract components to separate files');
      list.add('Add a Shadcn UI button');
    } else {
      list.add('Add a sticky navigation bar');
      list.add('Add a footer with social links');
    }

    list.add('Polish the typography');
    list.add('Add glassmorphism styles');
    
    suggestions.assignAll(list.take(5).toList());
  }
}
