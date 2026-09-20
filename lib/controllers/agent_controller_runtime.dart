/// Preview/shell/CLI runtime: serve, dev server, terminal, cloud fallback.
///
/// Split from `agent_controller.dart` - behavior is unchanged.
/// Contains: _projectContents(), _serve(), startDevServer(), _onDevServerCrashed(), _fallbackToStatic()
///   restartDevServer(), stopDevServer(), recheckRuntimeAndServe(), fixPreviewIssues(), runTerminal()
///   runShellCommand(), openCli(), sendStdinToCli(), stopActiveCli(), askAiToFixTerminalError()
///   useCloudFallback(), ensureTerminalWelcome(), _cliContextLine(), _splitCommand()
part of 'agent_controller.dart';

extension AgentControllerRuntime on AgentController {
  /// Read every project file into a path → content map (shared
  /// workspace: the SAME files the AI wrote, the terminal sees, and
  /// the preview serves — never a separate copy).
  Future<Map<String, String>> _projectContents(String projectId) async {
    final out = <String, String>{};
    for (final path in await _ws.listFiles(projectId)) {
      out[path] = await _ws.readFile(projectId, path) ?? '';
    }
    return out;
  }

  /// Route the project to its preview strategy, then serve.
  ///
  /// Static sites keep the exact previous behavior. Framework projects
  /// get a diagnosis + dev-server pipeline instead of being silently
  /// mis-served as static HTML (JSX never executes statically — that
  /// was the "unstyled HTML" preview bug).
  Future<void> _serve() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      final contents = await _projectContents(p.id);
      final kind = detectProject(contents);
      previewKind.value = kind;
      final issues = validateProject(kind, contents);
      previewIssues.assignAll(issues);

      if (!projectNeedsNode(kind)) {
        previewSteps.assignAll([
          PreviewStep('Detect project', 'ok', projectKindLabel(kind)),
          const PreviewStep('Validate', 'ok', 'entry present'),
          const PreviewStep('Preview', 'ok', 'static server'),
        ]);
        previewDecision.value = routePreview(
            kind: kind,
            issues: issues,
            nodeAvailable: true,
            cloudConfigured: cloudRuntime.isConfigured);
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }

      // Framework path: validate first, then runtime.
      final steps = <PreviewStep>[
        PreviewStep('Detect project', 'ok', projectKindLabel(kind)),
      ];
      final blocking = issues.where((i) => i.blocksPreview).toList();
      if (blocking.isNotEmpty) {
        steps.add(
            PreviewStep('Validate', 'fail', '${blocking.length} blocker(s)'));
        steps.add(const PreviewStep('Preview', 'fail', 'blocked'));
        previewSteps.assignAll(steps);
        previewDecision.value = routePreview(
            kind: kind,
            issues: issues,
            nodeAvailable: false,
            cloudConfigured: cloudRuntime.isConfigured);
        term('✗ preview blocked: ${blocking.map((i) => i.code).join(', ')}');
        _say('assistant',
            'I generated a ${projectKindLabel(kind)} project, but ${blocking.length} structural problem(s) block preview:\n${blocking.map((i) => '• ${i.message}').join('\n')}\nTap “Ask AI to Fix” in the preview pane and I’ll repair them.');
        // Keep the static fallback servable for file inspection, but the
        // UI flags it as non-running (see previewDecision).
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }
      steps.add(const PreviewStep('Validate', 'ok', 'structure clean'));

      final rt = Get.find<RuntimeManager>();
      final st = await rt.refresh();
      if (!st.nodeAvailable) {
        steps.add(const PreviewStep('Runtime', 'fail', 'Node.js missing'));
        steps.add(const PreviewStep('Preview', 'fail', 'needs runtime'));
        previewSteps.assignAll(steps);
        previewDecision.value = routePreview(
            kind: kind,
            issues: issues,
            nodeAvailable: false,
            cloudConfigured: cloudRuntime.isConfigured);
        term('✗ preview needs Node.js — runtime unavailable (${st.platform})');
        try {
          _cw?.log(
            severity: CwSeverity.error,
            category: CwCategory.preview,
            component: 'PREVIEW',
            errorCode: CwCodes.frameworkNeedsRuntime,
            title:
                '${CwCodes.titles[CwCodes.frameworkNeedsRuntime]} (${projectKindLabel(kind)})',
            message:
                'The project is a ${projectKindLabel(kind)} project and needs Node.js (`npm run dev`), which is unavailable on ${st.platform}. The source may be valid — AI code changes cannot fix this.',
            operation: 'preview-serve',
            projectId: p.id,
            traceId: currentTraceId,
            platform: st.platform,
            runtime: st.deviceAbi,
            aiCanFix: false,
            fallbackAvailable: 'USE_CLOUD_RUNTIME',
          );
        } catch (_) {}
        _say(
            'assistant',
            'This is a ${projectKindLabel(kind)} project — it needs Node.js (`npm run dev`), which is not available on this device. '
                'Static serving cannot execute JSX, so the preview would only show unstyled HTML. '
                'Use “Recheck” after installing a runtime, “Cloud” if configured, or export the ZIP and run it where Node exists.');
        previewUrl.value = await _preview.start(p.id, dir.path);
        devServerUrl.value = null;
        return;
      }
      steps.add(PreviewStep('Runtime', 'ok', 'node ${st.nodeVersion}'.trim()));
      previewSteps.assignAll(steps);
      previewDecision.value = routePreview(
          kind: kind,
          issues: issues,
          nodeAvailable: true,
          cloudConfigured: cloudRuntime.isConfigured);
      // Auto-start the dev server and point preview at the REAL url.
      await startDevServer();
    } catch (_) {
      previewUrl.value = null;
    }
  }

  /// Start (or reuse) the dev server and point the preview at it.
  /// Surfaces specific errors — never a generic dead preview.
  Future<void> startDevServer() async {
    final p = project.value;
    if (p == null || devServerStarting.value) return;
    devServerStarting.value = true;
    buildStatus.value = 'Starting dev server…';
    try {
      final dir = await _ws.dirFor(p.id);
      final mgr = Get.find<DevServerManager>();
      final session = await mgr.start(
        projectId: p.id,
        workDir: dir.path,
        kind: previewKind.value,
        onLog: term,
        onUnexpectedExit: (pid, code) => _onDevServerCrashed(pid, code),
      );
      devServerUrl.value = session.url;
      previewUrl.value = session.url;
      _touch();
      // Recovery story (§41): a live server after a blocking runtime
      // issue is worth one INFO event, not silence.
      try {
        _cw?.log(
          severity: CwSeverity.info,
          category: CwCategory.preview,
          component: 'DEV_SERVER',
          title: 'Development server started',
          message:
              '${session.runtime.label} dev server live at ${session.url} (port ${session.port ?? '?'}).',
          operation: 'npm run dev',
          projectId: p.id,
          traceId: currentTraceId,
          platform: _cwPlatform(),
          aiCanFix: true,
          fallbackUsed: 'LOCAL_RUNTIME',
        );
      } catch (_) {}
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(const PreviewStep('Deps', 'ok', 'node_modules ready'));
      steps.add(PreviewStep('Server', 'ok', session.url));
      steps.add(const PreviewStep('Preview', 'ok', 'live dev server'));
      previewSteps.assignAll(steps);
      term('✓ preview → live dev server ${session.url}');
      _say('assistant',
          'Dev server is live — the preview now shows the real running app.');
    } on DevServerException catch (e) {
      term('✗ dev server: ${e.message}');
      // Structured mapping (§18): dependency-flavored failures return
      // null and stay on the AI path; the rest become System Logs.
      try {
        final code = devServerCodeToCw(e.code, e.message);
        if (code != null) {
          final cls = classifyFailure(
              command: 'npm run dev',
              stderr: e.message,
              platform: _cwPlatform());
          _cw?.log(
            severity: CwSeverity.error,
            category: cls.category,
            component: 'DEV_SERVER',
            errorCode: code,
            title: CwCodes.titleFor(code),
            message: e.message,
            operation: 'npm run dev',
            projectId: p.id,
            traceId: currentTraceId,
            platform: _cwPlatform(),
            aiCanFix: false,
            fallbackAvailable: cls.fallbackAvailable.isEmpty
                ? 'USE_CLOUD_RUNTIME'
                : cls.fallbackAvailable,
          );
          term('■ $code — ${CwCodes.titleFor(code)} (see System Logs)');
        }
      } catch (_) {}
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(PreviewStep('Server', 'fail', e.code));
      steps.add(const PreviewStep('Preview', 'fail', 'server did not start'));
      previewSteps.assignAll(steps);
      lastError.value = e.message;
      _say('assistant', 'The dev server could not start: ${e.message}');
    } catch (e) {
      term('✗ dev server failed: $e');
      lastError.value = '$e';
    } finally {
      devServerStarting.value = false;
      buildStatus.value = null;
    }
  }

  /// Crash handler (§18 RUNTIME_CRASHED): drop the dead URL, fall
  /// back to static serving, and say so — never leave Preview aimed
  /// at a dead port, and never auto-rewrite files for a dead server.
  void _onDevServerCrashed(String pid, int code) {
    if (project.value?.id != pid) return;
    if (devServerUrl.value == null) return;
    devServerUrl.value = null;
    term('✗ RUNTIME_CRASHED — dev server exited ($code) unexpectedly');
    try {
      _cw?.log(
        severity: CwSeverity.error,
        category: CwCategory.preview,
        component: 'DEV_SERVER',
        errorCode: CwCodes.devServerFailed,
        title: 'Development server stopped unexpectedly',
        message:
            'The dev server process exited with code $code. The environment killed or crashed it — rewriting source files will not help.',
        operation: 'npm run dev',
        projectId: pid,
        traceId: currentTraceId,
        platform: _cwPlatform(),
        aiCanFix: false,
        fallbackAvailable: 'RETRY',
      );
    } catch (_) {}
    _say('assistant',
        'The dev server crashed (exit $code). Preview fell back to static files — tap “Restart dev server” to bring the live app back.');
    unawaited(_fallbackToStatic());
  }

  Future<void> _fallbackToStatic() async {
    final p = project.value;
    if (p == null) return;
    try {
      final dir = await _ws.dirFor(p.id);
      previewUrl.value = await _preview.start(p.id, dir.path);
      final steps = previewSteps.toList()
        ..removeWhere((s) => s.label == 'Preview' || s.label == 'Server');
      steps.add(const PreviewStep('Server', 'fail', 'crashed'));
      steps.add(const PreviewStep('Preview', 'info', 'static fallback'));
      previewSteps.assignAll(steps);
      _touch();
    } catch (_) {}
  }

  /// Stop + start the dev server (the diagnosis "Restart" action).
  /// Unlike [startDevServer] (which reuses a live server), this always
  /// bounces the process.
  Future<void> restartDevServer() async {
    final p = project.value;
    if (p == null || devServerStarting.value) return;
    try {
      await Get.find<DevServerManager>().stop(p.id);
    } catch (_) {}
    devServerUrl.value = null;
    term('■ dev server stopped — restarting…');
    await startDevServer();
  }

  /// Stop this project's dev server (if any). Never throws.
  Future<void> stopDevServer() async {
    final p = project.value;
    try {
      if (p != null) await Get.find<DevServerManager>().stop(p.id);
    } catch (_) {}
    devServerUrl.value = null;
    term('■ dev server stopped');
  }

  /// Re-probe the runtime and re-route preview (UI "Recheck" action).
  Future<void> recheckRuntimeAndServe() async {
    try {
      await Get.find<RuntimeManager>().refresh(force: true);
    } catch (_) {}
    final st = Get.find<RuntimeManager>().status.value;
    term(st.nodeAvailable
        ? '✓ runtime ready — node ${st.nodeVersion}, npm ${st.npmVersion}'
        : '✗ runtime still unavailable — ${st.lastError ?? 'no Node found'}');
    await _serve();
  }

  /// One-tap repair for structural preview blockers: feeds the issues
  /// back into the normal modify flow so the AI fixes them.
  Future<void> fixPreviewIssues() async {
    final blockers = previewIssues.where((i) => i.blocksPreview).toList();
    if (blockers.isEmpty || generating.value || fixing.value) return;
    topic.value =
        'Fix these preview blockers in the "${project.value?.name}" project:\n'
        '${blockers.map((i) => '• [${i.path ?? 'project'}] ${i.message}').join('\n')}\n'
        'Return a files-JSON object with the corrected files (complete new contents).';
    await modifyProject();
  }

  /// Alias for runShellCommand to support interactive studio naming.
  Future<void> runTerminal(String command) => runShellCommand(command);

  /// Run a real shell command in the project dir (or app docs when no
  /// project). Output streams into the terminal buffer with exit code.
  /// `node --version`, `npm install`, `ls` etc. produce ACTUAL output.
  Future<void> runShellCommand(String command) async {
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    if (!ProcessRunner.isSupported) {
      term('✗ shell unavailable on Web builds.');
      return;
    }
    // Secrets never hit the log or the persisted history.
    term('> ${redactCommand(cmd)}');
    try {
      Get.find<CliManagerService>().recordCommand(cmd);
    } catch (_) {}
    final parts = _splitCommand(cmd);
    if (parts.isEmpty) return;
    String workDir;
    try {
      final p = project.value;
      if (p == null) {
        // No project: run in the app's private docs dir (never a fake
        // project dir, never outside the sandbox).
        workDir = (await getApplicationDocumentsDirectory()).path;
      } else {
        workDir = (await _ws.dirFor(p.id)).path;
      }
    } catch (_) {
      workDir = '';
    }
    Map<String, String>? env;
    try {
      env = await Get.find<CliManagerService>().managedEnv();
    } catch (_) {}
    // Evidence buffer for classification (stderr-ish tail, capped).
    final evidence = StringBuffer();
    void collect(String line) {
      if (evidence.length < 2000) {
        evidence.writeln(line);
        if (evidence.length > 2000) {
          final s = evidence.toString();
          evidence
            ..clear()
            ..write(s.substring(s.length - 2000));
        }
      }
    }

    try {
      final exe =
          await ProcessRunner.resolveExecutable(parts.first) ?? parts.first;
      final session = await ProcessRunner.startSession(
        exe,
        parts.sublist(1),
        workingDirectory: workDir.isEmpty ? null : workDir,
        environment: env,
        commandLabel: cmd,
      );
      final sub1 = session.stdoutLines.listen((l) {
        term(l);
        collect(l);
      });
      final sub2 = session.stderrLines.listen((l) {
        term(l);
        collect(l);
      });
      final code = await session.exitCode;
      try {
        await sub1.cancel();
      } catch (_) {}
      try {
        await sub2.cancel();
      } catch (_) {}
      term(code == 0 ? '✓ exit 0' : '✗ exit $code');
      // Classify failures at the source (§12/39): environment evidence
      // becomes a System Log; ordinary failures stay terminal-only.
      if (code != 0) {
        try {
          final ev = _cw?.logClassified(
            component: 'TERMINAL',
            operation: 'shell',
            command: cmd,
            exitCode: code,
            stderr: evidence.toString(),
            platform: _cwPlatform(),
            projectId: project.value?.id ?? '',
            traceId: currentTraceId,
          );
          if (ev != null) {
            term(
                '■ ${ev.errorCode} — ${ev.title} (see System Logs; no code rewrite)');
          }
        } catch (_) {}
      }
      // Adopt terminal-installed CLIs into the manager (§34).
      if (code == 0) {
        try {
          final found =
              await Get.find<CliManagerService>().detectAfterCommand(cmd, code);
          if (found != null) {
            detectedCliId.value = found.id;
            detectedCliVersion.value =
                Get.find<CliManagerService>().versions[found.id] ?? '';
          }
        } catch (_) {}
      }
    } catch (e) {
      term('✗ could not run "${redactCommand(cmd)}": $e');
      // Spawn failure IS evidence (executable missing, exec format…).
      try {
        final ev = _cw?.logClassified(
          component: 'TERMINAL',
          operation: 'shell-spawn',
          command: cmd,
          exception: e,
          processSpawnFailed: true,
          platform: _cwPlatform(),
          projectId: project.value?.id ?? '',
          traceId: currentTraceId,
        );
        if (ev != null) {
          term('■ ${ev.errorCode} — ${ev.title} (see System Logs)');
        }
      } catch (_) {}
    }
  }

  // ── Interactive CLI sessions ──

  /// Launch a managed CLI's real executable inside the current project
  /// (shared workspace) and attach the terminal input to its stdin.
  Future<void> openCli(String manifestId) async {
    CliManagerService mgr;
    try {
      mgr = Get.find<CliManagerService>();
    } catch (_) {
      term('✗ CLI manager unavailable.');
      return;
    }
    final m = mgr.manifestById(manifestId);
    if (m == null) return;
    await stopActiveCli(silent: true);
    String workDir;
    try {
      final p = project.value;
      workDir = p == null
          ? (await getApplicationDocumentsDirectory()).path
          : (await _ws.dirFor(p.id)).path;
    } catch (_) {
      term('✗ could not resolve working directory.');
      return;
    }
    try {
      final session = await mgr.launchInProject(m, workDir);
      activeCliId.value = m.id;
      final where = project.value?.name ?? 'sandbox';
      term(
          '▶ ${m.displayName} started (pid ${session.pid}) in $where — type below to interact, ■ to stop');
      session.stdoutLines.listen(term);
      session.stderrLines.listen(term);
      unawaited(session.exitCode.then((code) {
        if (activeCliId.value == m.id) activeCliId.value = null;
        term(code == 0
            ? '■ ${m.displayName} exited (0)'
            : '■ ${m.displayName} exited ($code)');
      }));
    } catch (e) {
      term('✗ could not start ${m.displayName}: $e');
      AppSnackbar.showTop(
        '${m.displayName} could not start',
        '$e',
        logHistory: false,
      );
    }
  }

  /// Send a line to the attached CLI's stdin (redacted in logs).
  void sendStdinToCli(String line) {
    final id = activeCliId.value;
    if (id == null) return;
    try {
      final s = Get.find<CliManagerService>().launchedSession(id);
      if (s == null) {
        activeCliId.value = null;
        term('■ session already ended');
        return;
      }
      term('› ${redactCommand(line)}');
      s.writeStdin('$line\n');
    } catch (_) {
      activeCliId.value = null;
    }
  }

  /// Stop the attached CLI: Ctrl+C (SIGINT) first, SIGTERM fallback.
  Future<void> stopActiveCli({bool silent = false}) async {
    final id = activeCliId.value;
    if (id == null) return;
    activeCliId.value = null;
    CliManagerService? mgr;
    try {
      mgr = Get.find<CliManagerService>();
    } catch (_) {}
    final s = mgr?.launchedSession(id);
    if (s == null) {
      if (!silent) term('■ session already ended');
      return;
    }
    if (!silent) term('■ stopping (Ctrl+C)…');
    try {
      await s.interrupt();
      await s.exitCode.timeout(const Duration(seconds: 3));
      if (!silent) term('■ stopped');
    } catch (_) {
      try {
        await mgr?.killLaunched(id);
        if (!silent) term('■ stopped');
      } catch (_) {}
    }
  }

  /// "Ask AI to Fix": send the latest terminal failure to the builder
  /// agent with command + error + project context (info only, the agent
  /// edits files through its normal confirmed flow).
  Future<void> askAiToFixTerminalError() async {
    if (generating.value || fixing.value) return;
    final p = project.value;
    if (p == null) {
      AppSnackbar.showTop('No project open',
          'Open or build a project first, then ask AI to fix.',
          logHistory: false);
      return;
    }
    final lines = terminal.toList();
    String lastCmd = '';
    final errs = <String>[];
    for (var i = lines.length - 1;
        i >= 0 && errs.length < 15 && (lines.length - i) < 60;
        i--) {
      final l = lines[i];
      final stripped = l.replaceFirst(RegExp(r'^\[\d{2}:\d{2}:\d{2}\] '), '');
      if (stripped.startsWith('> ') && lastCmd.isEmpty) {
        lastCmd = stripped.substring(2);
      }
      if (RegExp(r'✗|error|Error|ERR|failed|FAIL|Exception|EACCES|ENOENT')
          .hasMatch(l)) {
        errs.insert(0, l);
      }
    }
    if (errs.isEmpty) {
      AppSnackbar.showTop('No errors', 'The terminal shows no recent failures.',
          logHistory: false);
      return;
    }
    topic.value = 'Fix this terminal failure in the "${p.name}" project'
        '${lastCmd.isEmpty ? '' : ' (command: $lastCmd)'}:\n'
        '${errs.join('\n')}\n\n'
        'LOCAL DEV CLIs (on-device): ${_cliContextLine()}\n'
        'Return a files-JSON object with the corrected files (complete new contents).';
    await modifyProject();
  }

  /// Cloud fallback tap (§18/41): no backend is bundled, so this
  /// records CW-CLOUD-001 (the ORIGINAL local failure stays visible)
  /// and explains honestly instead of pretending to deploy.
  void useCloudFallback() {
    final p = project.value;
    try {
      _cw?.log(
        severity: CwSeverity.warning,
        category: CwCategory.cloud,
        component: 'CLOUD',
        errorCode: CwCodes.cloudUnavailable,
        title: CwCodes.titleFor(CwCodes.cloudUnavailable),
        message:
            'Cloud execution was requested${p == null ? '' : ' for "${p.name}"'}, but no cloud runtime is configured in this build.',
        operation: 'cloud-fallback',
        projectId: p?.id ?? '',
        traceId: currentTraceId,
        platform: _cwPlatform(),
        aiCanFix: false,
      );
    } catch (_) {}
    AppSnackbar.showTop(
      'Cloud runtime',
      cloudRuntime.unavailableReason,
      logHistory: false,
    );
  }

  /// First-run welcome lines (§61). Shown once ever.
  Future<void> ensureTerminalWelcome() async {
    try {
      final mgr = Get.find<CliManagerService>();
      if (await mgr.consumeWelcome()) {
        term('Welcome to CubicLM Terminal');
        term('• Run real commands: node --version · npm install · ls');
        term('• Tap the package icon to install AI coding CLIs');
        term('• Launched CLIs run inside the current project');
      }
    } catch (_) {}
  }

  /// One info line for AI prompts so the agent knows local CLIs (§33).
  String _cliContextLine() {
    try {
      return Get.find<CliManagerService>().cliContextLine();
    } catch (_) {
      return 'none installed';
    }
  }

  /// Minimal shell-like split (handles single/double quotes).
  List<String> _splitCommand(String cmd) {
    final out = <String>[];
    final buf = StringBuffer();
    String? quote;
    for (var i = 0; i < cmd.length; i++) {
      final ch = cmd[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == ' ' || ch == '\t') {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }
}
