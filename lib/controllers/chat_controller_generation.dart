/// Message generation pipeline for [ChatController]: send, history
/// budgeting, the generation loop with streaming/fluid UI, tool-call
/// follow-ups, suggestions, memories extraction, outbox and AI helpers
/// (one-shot, polish, categorize). The beating heart of the app.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: _bgGenAllowed(), askOnce(), askInNewChat(), polishPrompt(), autoCategorizeChat()
///   smartOrganizeAll(), sendMessage(), _historyCharBudget(), _generateAIResponse()
///   _extractMemories(), _generateSuggestions(), _enqueueOutbox(), _flushOutbox()
part of 'chat_controller.dart';

extension ChatControllerGeneration on ChatController {
  // ─── Send Message ───────────────────────────────

  /// Silent one-shot completion for background features (download file
  /// rename, page skim, theme palettes). Follows the same cloud/local
  /// dispatch as [_generateSuggestions] but never touches the visible
  /// session. Returns null when no engine is available or the call fails.
  /// Whether a non-essential background generation (suggestions,
  /// auto-categorize, silent one-shots) may run right now. False when
  /// the engine is busy (a turn is active — piling on risks the
  /// stop/start race that aborts the process) or free RAM is critical.
  /// Foreground user turns never consult this.
  bool _bgGenAllowed() {
    try {
      if (Get.isRegistered<InferenceService>()) {
        if (Get.find<InferenceService>().isGenerating.value) return false;
      }
      if (Get.isRegistered<DeviceInfoService>()) {
        final free = Get.find<DeviceInfoService>().availableRamGB.value;
        if (free > 0 && free < 1.0) return false;
      }
    } catch (_) {}
    return true;
  }

  Future<String?> askOnce(String prompt,
      {int maxTokens = 300, String source = 'browser'}) async {
    try {
      final cloud = Get.find<CloudService>();
      final inference = Get.find<InferenceService>();
      final settings = Get.find<SettingsController>();
      if (settings.inferenceMode.value == 'cloud') {
        final raw = await cloud.sendMessage(
          messages: [
            {'role': 'user', 'content': prompt}
          ],
          maxTokens: maxTokens,
        );
        return raw.trim().isEmpty ? null : raw;
      }
      if (!inference.isModelLoaded.value) return null;
      if (!_bgGenAllowed()) return null;
      final raw = await inference.generate(prompt: prompt, source: source);
      if (raw.startsWith('ERROR:') || raw.trim().isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  /// Posts [prompt] as a fresh visible turn: opens a new chat session,
  /// fills the composer, and streams the reply. Used by browser/AI
  /// features that hand off to the Chat tab.
  Future<void> askInNewChat(String prompt) async {
    createNewChat();
    withoutPasteWatch(() {
      textController.text = prompt;
    });
    inputText.value = prompt;
    await sendMessage();
  }

  Future<void> polishPrompt() async {
    final draft = textController.text.trim();
    if (draft.isEmpty) return;

    Get.snackbar('Polishing...', 'Rewriting your prompt for better results',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1));

    final prompt =
        "You are a prompt engineering expert. Rewrite the following user prompt to be more clear, detailed, and effective for an LLM. "
        "Maintain the original intent. Return ONLY the improved prompt text, no conversational filler.\n\n"
        "Original Prompt: $draft";

    final polished = await askOnce(prompt, maxTokens: 500);
    if (polished != null && polished.trim().isNotEmpty) {
      withoutPasteWatch(() {
        textController.text = polished.trim();
      });
      inputText.value = textController.text;
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> autoCategorizeChat(String sessionId) async {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null || session.folderId != null) return;

    final firstMsg = messages.firstWhereOrNull((m) => m.role == 'user');
    if (firstMsg == null) return;

    final prompt = "Analyze this chat title and user query. Return ONLY a single-word general category (e.g. Coding, Writing, Math, Research, Social, Travel, Finance, Science, Health). No punctuation.\n\n"
        "Title: ${session.title}\n"
        "Query: ${firstMsg.content.substring(0, min(firstMsg.content.length, 200))}";

    final category = await askOnce(prompt, maxTokens: 10);
    if (category != null && category.trim().isNotEmpty) {
      final name = category.trim().replaceAll(RegExp(r'[^\w\s]'), '');
      if (name.length > 20) return;

      var folder = folders.firstWhereOrNull((f) => f.name.toLowerCase() == name.toLowerCase());
      if (folder == null) {
        createFolder(name);
        folder = folders.firstWhereOrNull((f) => f.name.toLowerCase() == name.toLowerCase());
      }
      
      if (folder != null) {
        addChatToFolder(sessionId, folder.id);
      }
    }
  }

  Future<void> smartOrganizeAll() async {
    Get.snackbar('Organizing...', 'AI is categorizing your chats', snackPosition: SnackPosition.BOTTOM);
    for (final s in sessions) {
      if (s.folderId == null && !s.archived && !s.hidden) {
        await autoCategorizeChat(s.id);
        await Future.delayed(const Duration(milliseconds: 500)); // Rate limit safety
      }
    }
    Get.snackbar('Organized', 'All chats have been grouped into folders.', snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> sendMessage() async {
    final text = textController.text.trim();
    final hasAttachment =
        selectedImagePath.value != null || selectedFileName.value != null;
    if (text.isEmpty && !hasAttachment) return;

    final fileName = selectedFileName.value;
    final fileContent = selectedFileContent.value;
    final filePath = selectedFilePath.value;
    final fileType = selectedFileType.value;
    final fileSize = selectedFileSize.value;
    final imagePath = selectedImagePath.value;
    final imageBase64 = selectedImageBase64.value;

    final visibleText =
        text.isEmpty ? _defaultAttachmentPrompt(fileType) : text;
    final effectiveText = (fileContent != null && fileContent.trim().isNotEmpty)
        ? '$visibleText\n\nAttached file: $fileName\n```text\n$fileContent\n```'
        : visibleText;

    if (currentSessionId.value.isEmpty) {
      createNewChat();
    }

    final userMsgId = _uuid.v4();
    String? persistedImagePath = imagePath;
    if (imagePath != null && !kIsWeb) {
      persistedImagePath = await _persistImageFile(imagePath, userMsgId);
    }

    final isBusy = isLoading.value || isStreaming.value;

    final userMsg = ChatMessage(
      id: userMsgId,
      chatId: currentSessionId.value,
      role: 'user',
      content: effectiveText,
      imageBase64: null,
      imagePath: persistedImagePath,
      fileName: fileName,
      fileContent: fileContent,
      filePath: filePath,
      fileType: fileType,
      fileSize: fileSize > 0 ? fileSize : null,
      isQueued: isBusy,
    );
    messages.add(userMsg);
    _hive.saveMessage(userMsg.id, userMsg.toMap());

    textController.clear();
    inputText.value = '';
    clearImage(deleteFile: false);
    clearFile();
    _scrollToBottom(force: true);

    if (isBusy) {
      pendingQueue.add({
        'prompt': effectiveText,
        'imagePath': imagePath,
        'imageBase64': imageBase64,
        'fileType': fileType,
        'filePath': filePath,
        'userMsgId': userMsgId,
      });
      return;
    }

    unawaited(HapticFeedback.lightImpact());

    String? imgBase64 = imageBase64;
    if (imgBase64 == null && imagePath != null && !kIsWeb) {
      try {
        imgBase64 =
            await compute(base64Encode, await File(imagePath).readAsBytes());
      } catch (_) {}
    }

    if (messages.where((m) => m.role == 'user').length == 1) {
      final title = visibleText.length > 40
          ? '${visibleText.substring(0, 40)}...'
          : visibleText;
      final session =
          sessions.firstWhere((s) => s.id == currentSessionId.value);
      final updated = session.copyWith(title: title, lastMessage: visibleText);
      _hive.saveSession(updated.id, updated.toMap());
      final idx = sessions.indexWhere((s) => s.id == updated.id);
      if (idx >= 0) sessions[idx] = updated;
    }

    await _flushOutbox();
    StatsService.tap(StatsService.eventChatSent);

    await _generateAIResponse(
      prompt: effectiveText,
      imagePath: imagePath,
      imgBase64: imgBase64,
      fileType: fileType,
      filePath: filePath,
    );
  }

  int _historyCharBudget() {
    var ctx = AppConstants.defaultContextSize;
    try {
      if (Get.isRegistered<SettingsController>()) {
        ctx = Get.find<SettingsController>().contextSize.value;
      }
    } catch (_) {}
    if (ctx <= 0) ctx = AppConstants.defaultContextSize;
    return (ctx * 0.6 * 4).toInt();
  }

  Future<bool> _generateAIResponse({
    required String prompt,
    String? imagePath,
    String? imgBase64,
    String? fileType,
    String? filePath,
    int? insertAt,
    bool isSecond = false,
    bool isThird = false,
    int agenticLoopCount = 0,
    String? toolOutputs,
  }) async {
    final generationId = (isSecond || isThird) ? _generationSerial : ++_generationSerial;
    if (!isSecond && !isThird && agenticLoopCount == 0) {
      isLoading.value = true;
      isStreaming.value = true;
    }
    // Past turns auto-recalled from other chats this turn (drives the
    // 🧠 chip on the saved bubble). Declared up here: finalizeMessage
    // is defined before the recall site runs.
    var recalledCount = 0;
    streamingAttachmentType.value =
        (imagePath != null || fileType == 'audio') ? fileType : null;
    streamingResponse.value = '';
    streamingThought.value = '';
    streamingAnswer.value = '';
    streamingIsThinking.value = false;
    generationStartTime.value = DateTime.now();

    // ── Project Context Injection ──
    String projectContext = '';
    if (currentProjectId.value != null) {
      final project = projects.firstWhereOrNull((p) => p.id == currentProjectId.value);
      if (project != null) {
        projectContext = await _getProjectRelevantContext(prompt, project);
      }
    }
    
    unawaited(HapticFeedback.mediumImpact());
    generationLiveDurationSecs.value = 0;
    _generationTimer?.cancel();
    _generationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (generationStartTime.value != null) {
        generationLiveDurationSecs.value =
            DateTime.now().difference(generationStartTime.value!).inSeconds;
      }
    });
    _followStreaming = true;
    _scrollToBottom(force: true);

    final List<String> displayQueue = [];
    String fullResponse = '';
    Timer? fluidTimer;
    bool generationDone = false;
    bool hasSeenThoughtTag = false;
    DateTime? thoughtStartedAt;
    int? thoughtDurationSeconds;

    void trackThoughtTiming() {
      final current = streamingResponse.value;
      if (!hasSeenThoughtTag) {
        if (current.contains('<think')) {
          hasSeenThoughtTag = true;
        } else {
          streamingAnswer.value = current;
          return;
        }
      }
      
      final parts = splitThoughtTags(current);
      streamingThought.value = parts.thought;
      streamingAnswer.value = parts.answer;
      streamingIsThinking.value = parts.isThinking;

      if (thoughtDurationSeconds != null) return;
      
      if (parts.hasThought && parts.isThinking && thoughtStartedAt == null) {
        thoughtStartedAt = DateTime.now();
      }
      if (parts.hasThought &&
          !parts.isThinking &&
          thoughtStartedAt != null) {
        thoughtDurationSeconds =
            DateTime.now().difference(thoughtStartedAt!).inSeconds;
      }
    }

    Future<void> finalizeMessage({
      required String rawResponse,
      required List<WebSource> webSources,
      required List<String> usedSkillNames,
      required int? tps,
      required int? thoughtDurationSeconds,
      required List<Map<String, String>> history,
      required String systemPrompt,
      required bool isCloud,
    bool isSecond = false,
    bool isThird = false,
    }) async {
      if (generationId != _generationSerial && !isSecond && !isThird) return;
      
      // If it was a dual or triple response, handle next generation
      if (responseMode.value >= 1 && !isSecond && !isThird && !rawResponse.startsWith('[IMAGE_BASE64]')) {
        unawaited(_generateAIResponse(
          prompt: prompt,
          imagePath: imagePath,
          imgBase64: imgBase64,
          fileType: fileType,
          filePath: filePath,
          insertAt: insertAt,
          isSecond: true,
        ));
      } else if (responseMode.value >= 2 && isSecond && !isThird) {
         unawaited(_generateAIResponse(
          prompt: prompt,
          imagePath: imagePath,
          imgBase64: imgBase64,
          fileType: fileType,
          filePath: filePath,
          insertAt: insertAt,
          isThird: true,
        ));
      }

      final totalDurationMs = generationStartTime.value != null
          ? DateTime.now().difference(generationStartTime.value!).inMilliseconds
          : null;

      final imageDurationMs = imageGenStartTime.value != null
          ? DateTime.now().difference(imageGenStartTime.value!).inMilliseconds
          : null;

      _generationTimer?.cancel();
      _generationTimer = null;
      fluidTimer?.cancel();
      
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      streamingThought.value = '';
      streamingAnswer.value = '';
      streamingIsThinking.value = false;
      generationStartTime.value = null;
      generationLiveDurationSecs.value = 0;
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;

      String? outImageBase64;
      String? outImagePath;
      if (rawResponse.startsWith('[IMAGE_BASE64]')) {
        outImageBase64 = rawResponse.substring('[IMAGE_BASE64]'.length);
        rawResponse = 'Here is your generated image:';
      }

      final aiMsgId = _uuid.v4();
      if (outImageBase64 != null && outImageBase64.isNotEmpty && !kIsWeb) {
        try {
          final bytes = base64Decode(outImageBase64);
          outImagePath = await _persistImageBytes(bytes, aiMsgId);
          if (outImagePath != null) outImageBase64 = null;
        } catch (_) {}
      }

      final artifactsDetected = parseArtifacts(rawResponse);
      final cleanContent = removeArtifacts(rawResponse);

      // Never save a silent empty bubble. Typical cause: a thinking
      // model burns the whole output budget reasoning (long "thinking",
      // then cut off by context/output limits before writing the
      // answer) — brutal on low-RAM devices for big asks like a full
      // game file. Say so + how to fix instead of showing blank.
      var effectiveContent = cleanContent;
      final replacement = emptyResponseReplacement(
        rawResponse: rawResponse,
        cleanContent: cleanContent,
        hasArtifacts: artifactsDetected.isNotEmpty,
        hasToolSteps: currentToolSteps.isNotEmpty,
        isCloud: isCloud,
      );
      if (replacement != null) {
        String diag = '';
        try {
          var provider = '?';
          var model = '?';
          var auto = '?';
          var maxTok = '?';
          if (Get.isRegistered<SettingsController>()) {
            final s = Get.find<SettingsController>();
            try {
              provider = s.cloudProvider.value;
            } catch (_) {}
            try {
              model = s.selectedCloudModelName;
            } catch (_) {}
            try {
              auto = s.autoTuneParams.value.toString();
              maxTok = s.maxTokens.value.toString();
            } catch (_) {}
          }
          diag =
              'rawLen=${rawResponse.length} historyTurns=${history.length} '
              'cloud=$isCloud provider=$provider model=$model autoTune=$auto maxTokens=$maxTok '
              'durationMs=${totalDurationMs ?? -1} thoughtSecs=${thoughtDurationSeconds ?? -1} tps=${tps ?? 0}';
        } catch (_) {
          diag = 'rawLen=${rawResponse.length} historyTurns=${history.length}';
        }
        try {
          Get.find<AppLogService>().warning(
            replacement.startsWith('⚠️ The model only')
                ? 'Empty answer: model only produced reasoning'
                : 'Empty answer: model returned no text',
            details: diag,
            category: LogCategory.chat,
          );
        } catch (_) {}
        effectiveContent = replacement;
      }

      if ((isSecond || isThird) && messages.isNotEmpty && messages.last.role == 'assistant') {
        final last = messages.last;
        final updated = ChatMessage(
          id: last.id,
          chatId: last.chatId,
          role: last.role,
          content: last.content,
          imageBase64: last.imageBase64,
          imagePath: last.imagePath,
          tokensPerSec: last.tokensPerSec,
          thoughtDurationSeconds: last.thoughtDurationSeconds,
          imageGenDurationMs: last.imageGenDurationMs,
          generationDurationMs: last.generationDurationMs,
          webSources: last.webSources,
          usedSkills: last.usedSkills,
          artifacts: last.artifacts,
          citations: last.citations,
          alternatives: [...(last.alternatives ?? []), cleanContent],
          preferredIndex: last.preferredIndex,
          feedback: last.feedback,
          suggestions: last.suggestions,
          revisions: last.revisions,
          revisionIndex: last.revisionIndex,
        );
        messages[messages.length - 1] = updated;
        await _hive.saveMessage(updated.id, updated.toMap());
        return;
      }

      // ── Tool Call Detection & Execution ──
      final toolCallMatches = RegExp(r'<tool_call name="(.*?)">([\s\S]*?)</tool_call>').allMatches(rawResponse);
      final StringBuffer loopOutputs = StringBuffer();
      
      if (toolCallMatches.isNotEmpty) {
        for (final match in toolCallMatches) {
          final name = match.group(1)!;
          final argsStr = match.group(2)!;
          try {
            final args = jsonDecode(argsStr) as Map<String, dynamic>;
            addToolStep(name: name, args: args, running: true);
            final output = await Get.find<ToolService>().executeTool(name, args);
            
            if (currentToolSteps.isNotEmpty) {
              currentToolSteps[currentToolSteps.length - 1] = {
                ...currentToolSteps.last,
                'output': output,
                'running': false,
                'success': !output.startsWith('Error'),
              };
            }
            loopOutputs.writeln('Tool: $name\nOutput: $output');
          } catch (e) {
            loopOutputs.writeln('Tool: $name\nError: $e');
          }
        }
      }

      final aiMsg = ChatMessage(
        id: aiMsgId,
        chatId: currentSessionId.value,
        role: 'assistant',
        content: effectiveContent,
        imageBase64: outImageBase64,
        imagePath: outImagePath,
        tokensPerSec: (tps != null && tps > 0) ? tps.toDouble() : null,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageDurationMs,
        generationDurationMs: totalDurationMs,
        webSources: webSources.isEmpty ? null : webSources,
        usedSkills: usedSkillNames.isEmpty ? null : usedSkillNames,
        recalledTurns: recalledCount,
        artifacts: artifactsDetected.isEmpty ? null : artifactsDetected.map((e) => {
          'id': e.id ?? _uuid.v4(),
          'type': e.type ?? 'code',
          'title': e.title ?? 'Artifact',
          'content': e.content,
        }).toList(),
        toolSteps: currentToolSteps.isNotEmpty ? List.from(currentToolSteps) : null,
      );

      if (insertAt != null && insertAt >= 0 && insertAt <= messages.length) {
        messages.insert(insertAt, aiMsg);
      } else {
        messages.add(aiMsg);
      }
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
      imageGenStartTime.value = null;

      if (toolCallMatches.isNotEmpty && agenticLoopCount < 2) {
        unawaited(_generateAIResponse(
          prompt: prompt,
          imagePath: imagePath,
          imgBase64: imgBase64,
          fileType: fileType,
          filePath: filePath,
          insertAt: insertAt != null ? insertAt + 1 : null,
          agenticLoopCount: agenticLoopCount + 1,
          toolOutputs: loopOutputs.toString(),
        ));
        return;
      }

      final session = sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
      if (session != null) {
        final updated = session.copyWith(lastMessage: aiMsg.content);
        _hive.saveSession(updated.id, updated.toMap());
        final idx = sessions.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) sessions[idx] = updated;
      }
      
      unawaited(HapticFeedback.mediumImpact());
      _dropStreamingDraft();

      // One-shot compare: challenger answers the same prompt
      if (_compareRef != null && outImageBase64 == null) {
        await _runComparison(
          prompt: prompt,
          systemPrompt: systemPrompt,
          history: history,
        );
      }

      // ── Long-term Memory Extraction ──
      unawaited(_extractMemories(prompt, rawResponse));

      // ── Follow-up Suggestions ──
      unawaited(_generateSuggestions(rawResponse));

      // ── Auto Categorization ──
      if (agenticLoopCount == 0 && !isSecond && !isThird) {
         unawaited(autoCategorizeChat(currentSessionId.value));
      }
      
      isLoading.value = false;
      _scrollToBottom();

      // ── Process Queue ──
      if (pendingQueue.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          final next = pendingQueue.removeAt(0);
          final userMsgId = next['userMsgId'] as String;
          final idx = messages.indexWhere((m) => m.id == userMsgId);
          if (idx >= 0) {
            final updated = messages[idx].copyWithQueued(false);
            messages[idx] = updated;
            _hive.saveMessage(updated.id, updated.toMap());
          }
          
          _generateAIResponse(
            prompt: next['prompt'] as String,
            imagePath: next['imagePath'] as String?,
            imgBase64: next['imageBase64'] as String?,
            fileType: next['fileType'] as String?,
            filePath: next['filePath'] as String?,
          );
        });
      }
    }

    void startFluidEngine({
      required List<WebSource> webSources,
      required List<String> usedSkillNames,
      required List<Map<String, String>> history,
      required String systemPrompt,
    }) {
      fluidTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
        if (displayQueue.isEmpty && generationDone) {
          timer.cancel();
          final inferenceMode = _hive.getSetting(AppConstants.keyInferenceMode, defaultValue: 'local') ?? 'local';
          final tps = inferenceMode == 'local' ? Get.find<InferenceService>().tokensPerSecond.value.toInt() : null;
          finalizeMessage(
            rawResponse: fullResponse, // Uses outer scope fullResponse
            webSources: webSources,
            usedSkillNames: usedSkillNames,
            tps: tps,
            thoughtDurationSeconds: thoughtDurationSeconds,
            history: history,
            systemPrompt: systemPrompt,
            isCloud: inferenceMode != 'local',
            isSecond: isSecond,
            isThird: isThird,
          );
          return;
        }

        if (displayQueue.isNotEmpty) {
          int burst = 1;
          final qLen = displayQueue.length;
          if (qLen > 400) {
            burst = 15;
          } else if (qLen > 150) {
            burst = 8;
          } else if (qLen > 50) {
            burst = 4;
          } else if (qLen > 15) {
            burst = 2;
          }

          final toAdd = displayQueue.take(burst).join();
          displayQueue.removeRange(0, min(burst, displayQueue.length));
          
          streamingResponse.value += toAdd;
          trackThoughtTiming();
          _scrollToBottom();
        }
      });
    }

    void bufferToken(String t) {
      for (var i = 0; i < t.length; i++) {
        displayQueue.add(t[i]);
      }
    }

    try {
      final inferenceMode = _hive.getSetting(
            AppConstants.keyInferenceMode,
            defaultValue: 'local',
          ) ??
          'local';

      final storedForHistory = _hive.getMessagesForChatPaged(
        currentSessionId.value,
        limit: 100, // Increase limit to find pinned messages
      );
      
      var rawHistory = storedForHistory.map((m) {
        final role = m['role']?.toString() ?? '';
        var content = m['content']?.toString() ?? '';
        if (role == 'assistant') {
          content = splitThoughtTags(content).answer;
        }
        return {
          'role': role, 
          'content': content, 
          'pinned': (m['isPinned'] ?? false).toString()
        };
      }).toList();

      if (toolOutputs != null && toolOutputs.isNotEmpty) {
        rawHistory.add({
          'role': 'system',
          'content': 'Tool execution results:\n$toolOutputs\nPlease analyze these and provide the next step or final answer.',
          'pinned': 'false'
        });
      }

      // Separate pinned and unpinned
      final pinnedTurns = rawHistory.where((m) => m['pinned'] == 'true').toList();
      final unpinnedTurns = rawHistory.where((m) => m['pinned'] != 'true').toList();

      final historyBudget =
          inferenceMode == 'local' ? _historyCharBudget() : 48000;
      
      // Always keep pinned turns first, then fit remaining budget with unpinned
      final pinnedChars = pinnedTurns.fold<int>(0, (s, m) => s + (m['content'] ?? '').length);
      final remainingBudget = max(2000, historyBudget - pinnedChars);

      final fittedUnpinned = await compute(
        (Map<String, dynamic> p) => fitHistoryToBudget(p['h'] as List<Map<String, String>>, p['b'] as int), 
        {'h': unpinnedTurns.map((m) => {'role': m['role']!, 'content': m['content']!}).toList(), 'b': remainingBudget}
      );

      var history = [...pinnedTurns.map((m) => {'role': m['role']!, 'content': m['content']!}), ...fittedUnpinned];

      // ── Long-term recall (ROM, not RAM) ─────────────────────
      // Past chats live in Hive forever, but the model only ever sees
      // this turn's history. When budget room remains, pull the most
      // relevant turns from OTHER chats in as a leading system block.
      // Skipped for dual-response follow-ups (same prompt, no gain).
      if (!isSecond && !isThird) {
        try {
          final histChars =
              history.fold<int>(0, (s, m) => s + (m['content'] ?? '').length);
          if (Get.isRegistered<MemoryService>() &&
              Get.find<MemoryService>().isEnabled.value &&
              historyBudget - histChars > 1500) {
            final kws = extractKeywords(prompt);
            if (kws.length >= 2) {
              final hits = await Get.find<HiveService>().recallPastTurns(
                keywords: kws,
                query: prompt,
                excludeChatId: currentSessionId.value,
                maxHits: 3,
              );
              if (hits.isNotEmpty) {
                recalledCount = hits.length;
                final buf = StringBuffer(
                    '[Auto-recalled past conversations — may be outdated; '
                    'the current chat wins on conflict]');
                for (final h in hits) {
                  buf.writeln();
                  buf.write(
                      'From "${h['chat'] ?? 'past chat'}" (${h['role'] ?? 'user'}): ${h['text'] ?? ''}');
                }
                // Just before the current question (recency effect) —
                // or at the end when history is empty. Pinned leading
                // turns keep their priority either way.
                final block = {
                  'role': 'system',
                  'content': buf.toString(),
                };
                if (history.isNotEmpty &&
                    history.last['role'] == 'user') {
                  history.insert(history.length - 1, block);
                } else {
                  history.add(block);
                }
                Get.find<AppLogService>().info(
                  'Recalled ${hits.length} past turn(s) from other chats',
                  category: LogCategory.chat,
                );
              }
            }
          }
        } catch (_) {}
      }

      try {
        final preTrimTurns = pinnedTurns.length + unpinnedTurns.length;
        final chars =
            history.fold<int>(0, (s, m) => s + (m['content'] ?? '').length);
        final roles = history.isEmpty
            ? 'none'
            : '${history.first['role']}…${history.last['role']}';
        final trimmed = preTrimTurns > history.length
            ? ', trimmed ${preTrimTurns - history.length}'
            : '';
        Get.find<AppLogService>().info(
          'Chat context: ${history.length} turns, ~${chars ~/ 4} tokens ($roles$trimmed)',
          category: LogCategory.chat,
        );
      } catch (_) {}

      final settingsForPrompt = Get.find<SettingsController>();
      final modelNameForPrompt = inferenceMode == 'local'
          ? Get.find<InferenceService>().loadedModelName.value
          : settingsForPrompt.selectedCloudModelName;
      final relevantSkills = SkillInjector.selectRelevantSkills(prompt);
      final List<String> usedSkillNames =
          relevantSkills.map((s) => s.name).toList();
      var basePrompt =
          settingsForPrompt.baseSystemPromptForModel(modelNameForPrompt);
      final persona = currentPersona;
      if (persona.isNotEmpty) {
        basePrompt = '$basePrompt\n\n[Chat persona]\n$persona';
      }
      
      if (projectContext.isNotEmpty) {
        basePrompt = '$basePrompt\n\n[Project Context]:\n$projectContext';
      }

      basePrompt = "$basePrompt\n\n--- Available Tools ---\n"
          "You can call tools by using the format: <tool_call name=\"tool_name\">{\"arg\": \"val\"}</tool_call>\n"
          "1. read_file(path: string): Reads content of a local file.\n"
          "2. list_directory(path: string): Lists files in a directory.\n"
          "3. run_shell(command: string): Executes a terminal command.\n"
          "Always provide reasoning before calling a tool. Use only one tool call per response."
          "\n--- End Tools ---";

      final String systemPromptForThisTurn = Get.find<MemoryService>().injectRelevantMemories(
      relevantSkills.isEmpty
          ? basePrompt
          : '$basePrompt${SkillInjector.buildForSkills(relevantSkills)}',
      prompt,
    );

      List<WebSource> webSources = [];
      try {
        final s = Get.find<SettingsController>();
        if (s.webFetchEnabled.value) {
          final pagesRead = WebFetchService.countUrls(prompt);
          if (pagesRead > 0) {
            Get.snackbar(
              'Web Access',
              'Reading $pagesRead link${pagesRead > 1 ? 's' : ''} into context…',
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 2),
            );
          }
          final result = await WebFetchService.augmentWithSources(prompt);
          if (result.augmentedText != prompt) {
            prompt = result.augmentedText;
            if (history.isNotEmpty && history.last['role'] == 'user') {
              history[history.length - 1] = {
                'role': 'user',
                'content': prompt,
              };
            }
          }
          webSources = result.sources.where((w) => w.success).toList();
        }
      } catch (_) {}

      final cloud = Get.find<CloudService>();
      fullResponse = '';

      if (isSearchMode.value && cloud.isProviderConfigured('perplexity')) {
        addToolStep(name: 'web_search', args: {'query': prompt}, running: true);
        final apiMessages = [
          {
            'role': 'system',
            'content':
                'You are a helpful assistant with real-time web search capabilities. Provide comprehensive answers with citations where possible.'
          },
          ...history,
          {'role': 'user', 'content': prompt},
        ];

        startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
        final buffer = StringBuffer();
        try {
          await for (final chunk in cloud.streamMessageAs(
            providerId: 'perplexity',
            model: 'sonar-pro',
            messages: apiMessages,
          )) {
            buffer.write(chunk);
            bufferToken(chunk);
          }
          fullResponse = buffer.toString();
          if (currentToolSteps.isNotEmpty && currentToolSteps.last['name'] == 'web_search') {
             currentToolSteps[currentToolSteps.length - 1] = {
               ...currentToolSteps.last,
               'output': 'Found relevant web sources and summarized.',
               'running': false,
               'success': true,
             };
          }
        } catch (e) {
          fullResponse = 'Search failed: $e';
        }
      } else if (inferenceMode == 'local') {
        final localImage = Get.find<LocalImageService>();

        if (localImage.isModelLoaded.value &&
            _isImageGenerationPrompt(prompt)) {
          final settings = Get.find<SettingsController>();
          final imageNotifications =
              Get.find<ImageGenerationNotificationService>();
          final steps = _hive.getSetting<int>(AppConstants.keyImageSteps,
                  defaultValue: AppConstants.defaultImageSteps) ??
              AppConstants.defaultImageSteps;
          final sizeSetting = settings.imageGenSize.value;
          final sizeLabel =
              sizeSetting == 0 ? 'Auto size' : '${sizeSetting}x$sizeSetting';
          final backendLabel = localImage.currentBackend.value == Backend.cpu
              ? 'CPU'
              : localImage.currentBackend.value.displayName
                  .split(' ')
                  .first
                  .toUpperCase();
          imageGenStep.value = 0;
          imageGenTotal.value = steps;
          imageGenEstimatedSecs.value = 0;
          imageGenStartTime.value = DateTime.now();
          imageGenDecoding.value = false;
          await imageNotifications.start(
            modelName: localImage.loadedModelName.value,
            backend: backendLabel,
            steps: steps,
            sizeLabel: sizeLabel,
          );

          final pngBytes = await localImage.generateImage(
            prompt: prompt,
            onProgress: (step, total) {
              imageGenStep.value = step;
              imageGenTotal.value = total;
              if (step >= total && total > 0) {
                imageGenDecoding.value = true;
                imageNotifications.decoding();
              }
              if (step > 0 && total > 0 && step < total) {
                final start = imageGenStartTime.value;
                if (start != null) {
                  final elapsed =
                      DateTime.now().difference(start).inMilliseconds;
                  final avgMsPerStep = elapsed / step;
                  final remainingSteps = total - step;
                  imageGenEstimatedSecs.value =
                      (avgMsPerStep * remainingSteps / 1000).ceil();
                }
              }
              imageNotifications.update(
                step: step,
                total: total,
                etaSeconds: imageGenEstimatedSecs.value,
                elapsedSeconds: imageGenStartTime.value == null
                    ? 0
                    : DateTime.now()
                        .difference(imageGenStartTime.value!)
                        .inSeconds,
              );
              _scrollToBottom();
            },
          );

          if (pngBytes != null) {
            fullResponse = '[IMAGE_BASE64]${await compute(base64Encode, pngBytes)}';
          } else {
            fullResponse = '❌ Local image generation failed.';
          }
          generationDone = true;
          startFluidEngine(
            webSources: webSources,
            usedSkillNames: usedSkillNames,
            history: history,
            systemPrompt: systemPromptForThisTurn,
          );
        } else {
          startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
          final inference = Get.find<InferenceService>();
          fullResponse = await inference.generate(
            prompt: prompt,
            systemPrompt: systemPromptForThisTurn,
            conversationHistory: history,
            source: 'chat',
            imagePath: imagePath,
            audioPath: fileType == 'audio' ? filePath : null,
            onToken: bufferToken,
          );
        }
      } else {
        final cloud = Get.find<CloudService>();
        final settings = Get.find<SettingsController>();
        final apiMessages = [
          {'role': 'system', 'content': systemPromptForThisTurn},
          ...history,
        ];
        
        startFluidEngine(
          webSources: webSources,
          usedSkillNames: usedSkillNames,
          history: history,
          systemPrompt: systemPromptForThisTurn,
        );
        fullResponse = await cloud.sendMessage(
          messages: apiMessages,
          imageBase64: imgBase64,
          temperature:
              (settings.temperature.value + ((isSecond || isThird) ? 0.1 : 0.0)).clamp(0.0, 1.0),
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
          onToken: bufferToken,
        );
      }

      generationDone = true;
      return true;
    } catch (e) {
      generationDone = true;
      if (generationId != _generationSerial) {
        fluidTimer?.cancel();
        return true;
      }
      fluidTimer?.cancel();
      isStreaming.value = false;
      streamingAttachmentType.value = null;
      streamingResponse.value = '';
      streamingThought.value = '';
      streamingAnswer.value = '';
      streamingIsThinking.value = false;
      imageGenStep.value = 0;
      imageGenTotal.value = 0;
      imageGenDecoding.value = false;
      if (imageGenStartTime.value != null) {
        await Get.find<ImageGenerationNotificationService>().failed();
      }
      imageGenStartTime.value = null;
      Get.find<AppLogService>().error('Chat response failed',
          details: e, category: LogCategory.chat);
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: _friendlyGenerationError(e),
      );
      messages.add(errorMsg);
      _hive.saveMessage(errorMsg.id, errorMsg.toMap());
      unawaited(HapticFeedback.heavyImpact());
      final queued = _isNetworkError(e) &&
          await _enqueueOutbox(
            prompt: prompt,
            imagePath: null,
            fileType: fileType,
            filePath: filePath,
          );
      if (queued) {
        Get.snackbar(
            'Queued — offline', 'Will auto-send when you are back online.',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 3));
      }
      return false;
    }
  }

  /// Learns durable user facts from a user turn into ROM-backed
  /// MemoryService — model-free heuristics (no extra generation, safe
  /// on 1GB-RAM devices). Deduplicates both ways, max 2 per turn.
  /// Review/delete anytime on the Memory page.
  Future<void> _extractMemories(String userMsg, String aiMsg) async {
    try {
      if (!Get.isRegistered<MemoryService>()) return;
      final mem = Get.find<MemoryService>();
      if (!mem.isEnabled.value) return;
      final cands = extractFacts(userMsg);
      if (cands.isEmpty) return;
      final existing =
          mem.getAllMemories().map((e) => e.toLowerCase()).toList();
      var added = 0;
      for (final c in cands) {
        if (added >= 2) break;
        final lc = c.toLowerCase();
        if (existing.any((e) => e.contains(lc) || lc.contains(e))) {
          continue;
        }
        await mem.replaceTopic(factTopic(c), c);
        existing.add(lc);
        added++;
      }
    } catch (_) {}
  }

  Future<void> _generateSuggestions(String lastAnswer) async {
    if (lastAnswer.isEmpty || lastAnswer.startsWith('[IMAGE_BASE64]')) return;
    
    try {
      final cloud = Get.find<CloudService>();
      final inference = Get.find<InferenceService>();
      final settings = Get.find<SettingsController>();
      final mode = settings.inferenceMode.value;

      final prompt = "Based on this AI response, suggest 3 extremely short and natural follow-up questions the user might ask next. "
          "Return ONLY a JSON list of strings, e.g. [\"Question 1\", \"Question 2\"]. No preamble.\n\n"
          "Response: ${lastAnswer.length > 500 ? lastAnswer.substring(0, 500) : lastAnswer}";

      String raw;
      if (mode == 'cloud') {
        raw = await cloud.sendMessage(
          messages: [{'role': 'user', 'content': prompt}],
          maxTokens: 100,
        );
      } else {
        if (!inference.isModelLoaded.value) return;
        if (!_bgGenAllowed()) return;
        raw = await inference.generate(
          prompt: prompt,
          source: 'suggestions',
        );
      }

      final jsonMatch = RegExp(r'\[.*\]').firstMatch(raw);
      if (jsonMatch != null) {
        final List<dynamic> list = jsonDecode(jsonMatch.group(0)!);
        final suggestions = list.map((e) => e.toString()).toList();
        
        if (messages.isNotEmpty && messages.last.role == 'assistant') {
          final last = messages.last;
          final updated = ChatMessage(
            id: last.id,
            chatId: last.chatId,
            role: last.role,
            content: last.content,
            imageBase64: last.imageBase64,
            imagePath: last.imagePath,
            tokensPerSec: last.tokensPerSec,
            suggestions: suggestions,
            timestamp: last.timestamp,
            webSources: last.webSources,
            usedSkills: last.usedSkills,
            artifacts: last.artifacts,
            citations: last.citations,
            revisions: last.revisions,
            revisionIndex: last.revisionIndex,
          );
          messages[messages.length - 1] = updated;
          await _hive.saveMessage(updated.id, updated.toMap());
        }
      }
    } catch (_) {}
  }

  Future<bool> _enqueueOutbox({
    required String prompt,
    String? imagePath,
    String? fileType,
    String? filePath,
  }) async {
    try {
      if (imagePath != null && imagePath.isNotEmpty) return false;
      final raw = _hive
              .getSetting<List>(AppConstants.keyChatOutbox, defaultValue: []) ??
          [];
      final list = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      list.add({
        'chatId': currentSessionId.value,
        'prompt': prompt,
        'fileType': fileType,
        'filePath': filePath,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      while (list.length > 20) {
        list.removeAt(0);
      }
      await _hive.setSetting(AppConstants.keyChatOutbox, list);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushOutbox() async {
    if (_flushingOutbox) return;
    final backoff = _outboxBackoffUntil;
    if (backoff != null && DateTime.now().isBefore(backoff)) return;
    _flushingOutbox = true;
    try {
      final raw = _hive
              .getSetting<List>(AppConstants.keyChatOutbox, defaultValue: []) ??
          [];
      var list = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final mine =
          list.where((e) => e['chatId'] == currentSessionId.value).toList();
      for (final e in mine) {
        list.remove(e);
        await _hive.setSetting(AppConstants.keyChatOutbox, list);
        final ok = await _generateAIResponse(
          prompt: (e['prompt'] ?? '').toString(),
          fileType: e['fileType']?.toString(),
          filePath: e['filePath']?.toString(),
        );
        if (!ok) {
          _outboxBackoffUntil = DateTime.now().add(const Duration(minutes: 2));
          return;
        }
      }
    } catch (_) {
    } finally {
      _flushingOutbox = false;
    }
  }
}
