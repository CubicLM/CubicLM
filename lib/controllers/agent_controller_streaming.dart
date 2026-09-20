/// Streaming merge, fidelity checks, and project file management.
///
/// Split from `agent_controller.dart` - behavior is unchanged.
/// Contains: _touch(), _streamStatus(), _flushPartial(), _mergeIssues(), _verifyWriteFidelity()
///   _parseChecked(), _mergeTruncation(), validateBuild(), _clearStreaming(), refreshFiles()
///   notifyFilesChanged(), renameProject(), forkProject(), capturePreviewShot(), readFile()
///   newProject()
part of 'agent_controller.dart';

extension AgentControllerStreaming on AgentController {
  void _touch() => revision.value++;


  void _streamStatus(String prefix, int chars) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastStatusMs < 300) return;
    _lastStatusMs = now;
    buildStatus.value = '$prefix… ${(chars / 1024).toStringAsFixed(1)}k chars';
  }


  /// Merge one streamed buffer into live file state.
  ///
  /// - Updates [streamingFiles] so the Files tab + streaming editor
  ///   show code AS the AI writes it (v0/Replit-style).
  /// - For previewable output (no package.json in the partial set) the
  ///   partial files are ALSO written to disk (throttled) so the
  ///   preview WebView reloads live. npm/framework output skips disk
  ///   writes — it cannot execute until installed/built anyway.
  /// - Never throws; streaming must not break generation.
  Future<void> _flushPartial(String buf, String projectId) async {
    List<PartialWebFile> partial;
    try {
      partial = parsePartialFiles(buf);
    } catch (_) {
      return;
    }
    if (partial.isEmpty || _cancelled) return;
    streamingActive.value = true;
    var changed = false;
    for (final f in partial) {
      if (streamingFiles[f.path] != f.content) {
        streamingFiles[f.path] = f.content;
        changed = true;
        if (_announcedPaths.add(f.path)) step('file', 'Writing ${f.path}…');
      }
    }
    if (!changed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasPackageJson = partial.any((f) {
      final p = f.path.toLowerCase();
      return p == 'package.json' || p.endsWith('/package.json');
    });
    if (!hasPackageJson && enableLivePreview.value && now - _lastLiveWriteMs >= liveFlushThrottle.value) {
      _lastLiveWriteMs = now;
      try {
        var wrote = false;
        for (final f in partial) {
          final err = await _ws.writeFile(projectId, f.path, f.content);
          if (err == null) wrote = true;
        }
        if (wrote && !_cancelled) {
          await refreshFiles();
          livePreviewReady.value = true;
          _touch(); // reload the preview WebView
        }
      } catch (_) {}
    }
  }

  /// Merge issue lists without code+path duplicates (disk validation
  /// and write-fidelity often flag the same file twice).
  void _mergeIssues(List<ProjectIssue> base, List<ProjectIssue> extra) {
    final have = base.map((i) => '${i.code}:${i.path}').toSet();
    for (final i in extra) {
      if (have.add('${i.code}:${i.path}')) base.add(i);
    }
  }

  /// Generation integrity (§8): read back what was just written and
  /// compare byte-for-byte, plus hygiene-scan the generated source.
  /// Catches truncation/corruption between model output and disk —
  /// surfaced as blockers, never silently previewed.
  Future<List<ProjectIssue>> _verifyWriteFidelity(
      String projectId, Map<String, String> expected) async {
    final issues = <ProjectIssue>[];
    for (final e in expected.entries) {
      String? actual;
      try {
        actual = await _ws.readFile(projectId, e.key);
      } catch (_) {}
      if (actual == null) {
        issues.add(ProjectIssue('write-missing',
            '"${e.key}" is missing on disk after writing — the write failed.',
            path: e.key));
      } else if (actual.length != e.value.length) {
        issues.add(ProjectIssue('write-truncated',
            '"${e.key}" on disk (${actual.length} chars) differs from generated source (${e.value.length} chars) — truncated or corrupted in transit.',
            path: e.key));
      } else if (actual != e.value) {
        issues.add(ProjectIssue('write-corrupted',
            '"${e.key}" on disk differs from generated source — serialization corrupted it.',
            path: e.key));
      }
      issues.addAll(sourceHygieneIssues(e.key, e.value));
    }
    return issues;
  }

  /// Parse + collect silent truncations (file/total caps) so callers can
  /// surface them as blocking issues instead of serving partial source.
  List<WebFile> _parseChecked(String raw, List<String> truncatedOut) =>
      parseFiles(raw, onTruncated: truncatedOut.add);

  /// Turn collected truncations into blocking preview issues (§13).
  void _mergeTruncation(List<ProjectIssue> issues, List<String> truncated) {
    for (final t in truncated) {
      issues.add(ProjectIssue(
        'truncated-source',
        '"$t" was cut to fit size limits — ask the AI to regenerate it smaller or split it.',
        path: t.startsWith('(') ? null : t,
      ));
    }
    if (truncated.isNotEmpty) {
      step('error', 'Truncated ${truncated.length} file(s) — see issues.');
    }
  }

  /// Production build validation (`npm run build`) for Node projects.
  /// Streams real compiler output to the terminal; failures flow into
  /// the existing Ask-AI loop via the terminal wand button.
  Future<void> validateBuild() async {
    final p = project.value;
    if (p == null ||
        validatingBuild.value ||
        generating.value ||
        fixing.value) {
      return;
    }
    if (!projectNeedsNode(previewKind.value)) {
      AppSnackbar.showTop('Build check',
          'Only Node projects need `npm run build` — this one previews statically.',
          logHistory: false);
      return;
    }
    validatingBuild.value = true;
    buildStatus.value = 'Running npm run build…';
    term('> npm run build  (production validation)');
    try {
      String? npm;
      try {
        npm = (await Get.find<RuntimeManager>().refresh()).npmPath;
      } catch (_) {}
      if (npm == null || npm.isEmpty) {
        term(
            '✗ NEXT_BUILD_FAILED — npm unavailable (NPM_MISSING): Node.js runtime missing.');
        lastError.value = 'npm is unavailable — Node.js runtime missing.';
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: CwCategory.runtime,
            component: 'TERMINAL',
            errorCode: CwCodes.executableUnavailable,
            title: 'npm unavailable for build check',
            message:
                'The project needs Node.js for `npm run build`, but npm is unavailable in this environment.',
            operation: 'npm run build',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: 'USE_CLOUD_RUNTIME',
          );
        } catch (_) {}
        return;
      }
      final dir = await _ws.dirFor(p.id);
      final session = await ProcessRunner.startSession(
        npm,
        const ['run', 'build'],
        workingDirectory: dir.path,
        commandLabel: 'npm run build',
      );
      final sub1 = session.stdoutLines.listen(term);
      final sub2 = session.stderrLines.listen(term);
      int code;
      try {
        code = await session.exitCode.timeout(const Duration(minutes: 10));
      } on TimeoutException {
        code = -1;
        try {
          await session.kill(true);
        } catch (_) {}
      }
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      if (code == 0) {
        term('✓ npm run build passed');
        _say('assistant',
            'Production build passed (`npm run build` ✅). Preview keeps running the dev server.');
        AppSnackbar.showTop('Build passed', '`npm run build` succeeded.',
            logHistory: false);
      } else {
        term(
            '✗ NEXT_BUILD_FAILED (exit $code) — compiler output above; tap the terminal wand (Ask AI) and I’ll fix it');
        lastError.value =
            '`npm run build` failed (exit $code) — see Terminal, then Ask AI to Fix.';
        _say('assistant',
            'The production build failed (exit $code) — full compiler output is in the Terminal. Tap the wand button there (Ask AI to Fix) and I’ll repair the source.');
      }
    } catch (e) {
      term('✗ build check failed: $e');
      lastError.value = '$e';
    } finally {
      validatingBuild.value = false;
      buildStatus.value = null;
    }
  }

  /// Clear all live-streaming state (call when generation settles).
  void _clearStreaming() {
    try {
      streamingFiles.clear();
    } catch (_) {}
    streamingActive.value = false;
    livePreviewReady.value = false;
    _lastLiveWriteMs = 0;
  }

  Future<void> refreshFiles() async {
    final p = project.value;
    if (p == null) {
      files.clear();
      projectSizeKb.value = 0.0;
      return;
    }
    final list = await _ws.listFiles(p.id);
    files.assignAll(list);
    
    // Calculate project size
    double totalBytes = 0;
    final dir = await _ws.dirFor(p.id);
    for (final f in list) {
      try {
        final file = File('${dir.path}/$f');
        if (await file.exists()) {
          totalBytes += await file.length();
        }
      } catch (_) {}
    }
    projectSizeKb.value = totalBytes / 1024;
  }

  /// Call after manual file ops (save/rename/add/delete) so the explorer
  /// list AND the preview both refresh. Clears a stale console error —
  /// a hand fix likely resolved it.
  Future<void> notifyFilesChanged() async {
    await refreshFiles();
    consoleError.value = null;
    _touch();
  }

  Future<void> renameProject(String name) async {
    final p = project.value;
    if (p == null || name.trim().isEmpty) return;
    await _ws.renameProject(p.id, name);
    p.name = name.trim();
    project.refresh();
  }

  /// Fork the current project into a copy and open it.
  Future<void> forkProject() async {
    final p = project.value;
    if (p == null || generating.value || fixing.value) return;
    try {
      buildStatus.value = 'Forking project…';
      final np = await _ws.forkProject(p.id);
      if (np == null) return;
      await openProject(np);
      AppSnackbar.showTop('Project forked', np.name, logHistory: false);
    } catch (e) {
      AppSnackbar.showTop('Fork failed', '$e', logHistory: false);
    } finally {
      if (buildStatus.value == 'Forking project…') buildStatus.value = null;
    }
  }

  /// Capture the live preview as PNG and attach it as vision context.
  Future<void> capturePreviewShot() async {
    final w = previewWebController;
    if (w == null || project.value == null) return;
    try {
      final bytes = await w.takeScreenshot();
      if (bytes == null || bytes.isEmpty) return;
      attachedImage.value = base64Encode(bytes);
      term('preview screenshot attached (${(bytes.length / 1024).round()} KB)');
      AppSnackbar.showTop(
        'Screenshot attached',
        'Describe what to change in the screenshot.',
        logHistory: false,
      );
    } catch (e) {
      AppSnackbar.showTop('Capture failed', '$e', logHistory: false);
    }
  }

  Future<String?> readFile(String path) async {
    final p = project.value;
    if (p == null) return null;
    return _ws.readFile(p.id, path);
  }

  Future<void> newProject() async {
    final t = topic.value.trim();
    if (t.isEmpty || generating.value) return;
    // If plan mode is on, generate plan first instead of building directly.
    if (planMode.value) {
      await generatePlan();
      return;
    }
    // Framework guard (CW-PREVIEW-003): a Node framework with no Node
    // runtime produces an unpreviewable project. Offer static instead.
    var buildFramework = framework.value;
    if (frameworkNeedsNode(buildFramework)) {
      var nodeOk = false;
      try {
        nodeOk = (await Get.find<RuntimeManager>().refresh()).nodeAvailable;
      } catch (_) {}
      if (!nodeOk) {
        final choice = await Get.dialog<String>(
          AlertDialog(
            title: const Text('No Node.js on this device'),
            content: Text(
                '"$buildFramework" needs Node.js (`npm run dev`), which is not available here. Build as static single-file HTML instead so preview works?'),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Get.back(result: 'node'),
                child: Text('Build $buildFramework anyway'),
              ),
              FilledButton(
                onPressed: () => Get.back(result: 'static'),
                child: const Text('Build static HTML'),
              ),
            ],
          ),
          barrierDismissible: false,
        );
        if (choice == null) return;
        if (choice == 'static') buildFramework = 'Single HTML';
      }
    }
    generating.value = true;
    _cancelled = false;
    lastError.value = null;
    consoleError.value = null;
    _autoRounds = 0;
    currentTraceId = newTraceId();
    transcript.clear();
    _say('user', t);
    _say('activity', '');
    buildStatus.value = 'Designing project…';
    term(
        '> build "${t.length > 60 ? '${t.substring(0, 60)}…' : t}" ($buildFramework)');
    _beginSteps();
    step('thinking', 'Planning $buildFramework project…');
    String? createdCp;
    try {
      final name = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      final p = await _ws.createProject(name, buildFramework);
      project.value = p;
      createdCp = await _ws.saveCheckpoint(p.id, label: 'Project created');
      
      // Smart Skeleton Initialization
      await initializeSkeleton(p.id, t);

      final raw = await _ask(
        prompt: 'Build this website with $buildFramework: $t',
        system: webSystemPrompt(
          framework: buildFramework, 
          brandIdentity: brandIdentity,
          library: selectedLibrary.value,
          designSystem: selectedDesignSystem.value,
        ),
        onProgress: (n) => _streamStatus('Writing project', n),
        onPartial: (buf) => unawaited(_flushPartial(buf, p.id)),
      );
      if (_cancelled) {
        // Live partial writes may already be on disk — roll back to the
        // empty just-created state so cancel means "never happened".
        // (createdCp is definitely assigned here; the catch block below
        // keeps the null-safe variant.)
        try {
          await _ws.rollbackToCheckpoint(p.id, createdCp);
          await refreshFiles();
          _touch();
        } catch (_) {}
        term('■ build cancelled by user — rolled back');
        return;
      }
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
      // Integrity gate (§8): what landed on disk must equal what the
      // model emitted — byte-for-byte — plus hygiene scan.
      final fidelity = await _verifyWriteFidelity(
          p.id, {for (final f in parsed) f.path: f.content});
      _mergeTruncation(fidelity, truncated);
      if (fidelity.isNotEmpty) {
        _mergeIssues(previewIssues, fidelity);
        final blocking = previewIssues.where((i) => i.blocksPreview).toList();
        if (blocking.isNotEmpty) {
          previewDecision.value = routePreview(
              kind: previewKind.value,
              issues: previewIssues.toList(),
              nodeAvailable: true,
              cloudConfigured: cloudRuntime.isConfigured);
          term(
              '✗ source validation failed: ${blocking.map((i) => i.code).join(', ')}');
          _say('assistant',
              'Generated source validation failed — ${blocking.length} problem(s), not previewing blindly:\n${blocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” and I’ll regenerate the broken files.');
        }
      }
      _touch();
      buildStatus.value = null;
      final builtPaths = [for (final f in parsed) f.path];
      step('done', 'Built ${builtPaths.length} files — preview live.');
      _snapshotActivity();
      final summary =
          '${_doneSummary('Built', builtPaths)}\nTap a file to edit, or ask for changes below.';
      _say('assistant', summary);
      _markLastAssistantWithBuild();
      term('✓ build done — ${files.length} files, preview live');
      Future.delayed(const Duration(seconds: 1), () => captureCheckpointThumbnail());
    } catch (e) {
      if (_cancelled) {
        term('■ build cancelled by user');
        return;
      }
      // Generation failed mid-stream: live partials may be on disk —
      // restore the empty just-created state (§7: never keep half files).
      final cp = createdCp;
      final p0 = project.value;
      if (cp != null && p0 != null) {
        try {
          await _ws.rollbackToCheckpoint(p0.id, cp);
          await refreshFiles();
          _touch();
        } catch (_) {}
      }
      lastError.value = '$e';
      term('✗ build failed: $e');
      step('error', 'Build failed — rolled back.');
      _snapshotActivity();
      _log('Project build failed', e);
    } finally {
      _clearStreaming();
      generating.value = false;
      buildStatus.value = null;
      _cancelled = false;
    }
  }
}
