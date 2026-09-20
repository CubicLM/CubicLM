/// Message-list operations for [ChatController]: selection, model
/// pin, compare mode, edit/regenerate/branch/delete, revisions,
/// streaming drafts, scrolling and attachment persist helpers.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: toggleSelectionMode(), toggleSelected(), deleteSelected(), selectedAsMarkdown(), chatHasModelPin
///   chatPinnedModelLabel, pinModelToChat(), clearChatModelPin(), _applySessionModel()
///   setCompareChallenger(), clearCompareChallenger(), _runComparison(), _isNetworkError()
///   _friendlyGenerationError(), editMessage(), navigateRevision(), regenerateFromMessage()
///   branchNewChat(), deleteMessage(), toggleMessagePin(), saveStreamingDraft()
///   _dropStreamingDraft(), _saveAssistantMessage(), _handleUserScroll(), jumpToBottom()
///   pauseStreamingFollow(), resumeStreamingFollowIfNearBottom(), _scrollToBottom()
///   _persistImageFile(), _persistImageBytes(), _attachmentTypeForExtension()
///   _defaultAttachmentPrompt()
part of 'chat_controller.dart';

extension ChatControllerMessages on ChatController {
  void toggleSelectionMode([bool? on]) {
    final next = on ?? !selectionMode.value;
    selectionMode.value = next;
    if (!next) selectedIds.clear();
  }

  void toggleSelected(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    if (selectedIds.isEmpty) selectionMode.value = false;
  }

  Future<void> deleteSelected() async {
    final ids = selectedIds.toSet();
    if (ids.isEmpty) return;
    messages.removeWhere((m) => ids.contains(m.id));
    for (final id in ids) {
      try {
        await _hive.deleteMessage(id);
      } catch (_) {}
    }
    toggleSelectionMode(false);
  }

  String selectedAsMarkdown() {
    final sel = messages.where((m) => selectedIds.contains(m.id)).toList();
    final buf = StringBuffer();
    for (final m in sel) {
      buf.writeln(m.role == 'user' ? '## You' : '## AI');
      buf.writeln(m.content.trim());
      buf.writeln();
    }
    return buf.toString().trim();
  }

  bool get chatHasModelPin {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return false;
    final s = sessions.firstWhereOrNull((e) => e.id == sid);
    return s != null && s.modelMode.isNotEmpty;
  }

  String get chatPinnedModelLabel {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return '';
    final s = sessions.firstWhereOrNull((e) => e.id == sid);
    if (s == null || s.modelMode.isEmpty) return '';
    var label = s.modelId;
    if (s.modelMode == 'cloud' && s.modelProvider.isNotEmpty) {
      label = '${s.modelProvider}: $label';
    }
    label = label
        .replaceAll('.gguf', '')
        .replaceAll('.GGUF', '')
        .replaceAll('custom-profile:', 'custom #');
    if (label.length > 20) label = '${label.substring(0, 20)}…';
    return label;
  }

  Future<void> pinModelToChat() async {
    final sid = currentSessionId.value;
    if (sid.isEmpty) {
      Get.snackbar('No open chat', 'Open a chat first, then pin a model.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final settings = Get.find<SettingsController>();
    final mode = settings.inferenceMode.value == 'cloud' ? 'cloud' : 'local';
    String modelId = '';
    String provider = '';
    if (mode == 'cloud') {
      provider = settings.cloudProvider.value;
      if (provider == 'custom') {
        modelId = 'custom-profile:${settings.customCloudProfileIndex.value}';
      } else {
        modelId = settings.selectedCloudModelName;
      }
      if (modelId.isEmpty) {
        Get.snackbar('Nothing to pin', 'Pick a cloud model first.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    } else {
      modelId = Get.find<InferenceService>().loadedModelName.value;
      if (modelId.isEmpty) {
        modelId =
            _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';
      }
      if (modelId.isEmpty) {
        Get.snackbar('Nothing to pin', 'Load a local model first.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }
    final idx = sessions.indexWhere((e) => e.id == sid);
    if (idx < 0) return;
    final updated = sessions[idx].copyWith(
      modelMode: mode,
      modelId: modelId,
      modelProvider: provider,
    );
    sessions[idx] = updated;
    await _hive.saveSession(updated.id, updated.toMap());
    Get.snackbar('Pinned to this chat', chatPinnedModelLabel,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
  }

  Future<void> clearChatModelPin() async {
    final sid = currentSessionId.value;
    if (sid.isEmpty) return;
    final idx = sessions.indexWhere((e) => e.id == sid);
    if (idx < 0) return;
    final updated =
        sessions[idx].copyWith(modelMode: '', modelId: '', modelProvider: '');
    sessions[idx] = updated;
    await _hive.saveSession(updated.id, updated.toMap());
  }

  Future<void> _applySessionModel(ChatSession s) async {
    if (s.modelMode.isEmpty) return;
    try {
      final settings = Get.find<SettingsController>();
      if (s.modelMode == 'cloud') {
        final cmc = Get.find<CloudModelController>();
        if (s.modelProvider == 'custom') {
          final idx =
              int.tryParse(s.modelId.replaceFirst('custom-profile:', '')) ?? 0;
          await cmc.selectCustomProfile(idx);
          await settings.setCloudProvider('custom');
          await settings.setInferenceMode('cloud');
        } else if (s.modelId.isNotEmpty) {
          await cmc.selectModel(s.modelProvider, s.modelId,
              showSnackbar: false);
        }
      } else if (s.modelId.isNotEmpty) {
        await settings.setInferenceMode('local');
        final inference = Get.find<InferenceService>();
        if (inference.loadedModelName.value != s.modelId) {
          await Get.find<ModelController>().loadModel(s.modelId);
        }
      }
    } catch (_) {}
  }

  void setCompareChallenger(String mode, String provider, String model) {
    _compareRef = {'mode': mode, 'provider': provider, 'model': model};
    compareLabel.value = mode == 'cloud'
        ? '$provider: $model'
        : model.replaceAll('.gguf', '').replaceAll('.GGUF', '');
  }

  void clearCompareChallenger() {
    _compareRef = null;
    compareLabel.value = '';
  }

  Future<void> _runComparison({
    required String prompt,
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    final ref = _compareRef;
    _compareRef = null;
    compareLabel.value = '';
    if (ref == null) return;
    final chatId = currentSessionId.value;
    final settings = Get.find<SettingsController>();
    final primaryMode = settings.inferenceMode.value;
    final primaryProvider = settings.cloudProvider.value;
    final primaryCloudModel = settings.selectedCloudModelName;
    final primaryCustomIdx = settings.customCloudProfileIndex.value;
    final primaryLocal = Get.find<InferenceService>().loadedModelName.value;
    final label = ref['mode'] == 'cloud'
        ? '${ref['provider']}: ${ref['model']}'
        : (ref['model'] ?? '').replaceAll('.gguf', '').replaceAll('.GGUF', '');
    Get.snackbar('Comparing…', 'Asking $label too',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
    try {
      String answer;
      if (ref['mode'] == 'cloud') {
        await Get.find<CloudModelController>().selectModel(
            ref['provider'] ?? '', ref['model'] ?? '',
            showSnackbar: false);
        answer = await Get.find<CloudService>().sendMessage(
          messages: [
            {'role': 'system', 'content': systemPrompt},
            ...history,
          ],
          temperature: settings.temperature.value.clamp(0.0, 1.0),
          maxTokens:
              settings.autoTuneParams.value ? null : settings.maxTokens.value,
        );
      } else {
        await settings.setInferenceMode('local');
        await Get.find<ModelController>().loadModel(ref['model'] ?? '');
        final inference = Get.find<InferenceService>();
        if (inference.loadedModelName.value != (ref['model'] ?? '')) {
          throw Exception('challenger model not loaded');
        }
        answer = await inference.generate(
          prompt: prompt,
          systemPrompt: systemPrompt,
          conversationHistory: history,
          source: 'chat-compare',
        );
      }
      if (answer.trim().isEmpty) throw Exception('empty challenger answer');
      if (currentSessionId.value != chatId) return;
      final msg = ChatMessage(
        id: _uuid.v4(),
        chatId: chatId,
        role: 'assistant',
        content: '⚖️ $label\n\n${answer.trim()}',
      );
      messages.add(msg);
      _hive.saveMessage(msg.id, msg.toMap());
    } catch (e) {
      Get.find<AppLogService>()
          .warning('Compare failed: $e', category: LogCategory.chat);
      Get.snackbar('Compare failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      try {
        if (primaryMode == 'cloud') {
          final cmc = Get.find<CloudModelController>();
          if (primaryProvider == 'custom') {
            await cmc.selectCustomProfile(primaryCustomIdx);
            await settings.setCloudProvider('custom');
            await settings.setInferenceMode('cloud');
          } else {
            await cmc.selectModel(primaryProvider, primaryCloudModel,
                showSnackbar: false);
          }
        } else {
          await settings.setInferenceMode('local');
          if (primaryLocal.isNotEmpty &&
              Get.find<InferenceService>().loadedModelName.value !=
                  primaryLocal) {
            await Get.find<ModelController>().loadModel(primaryLocal);
          }
        }
      } catch (_) {}
    }
  }

  bool _isNetworkError(Object e) {
    final lower = e.toString().toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeoutexception');
  }

  String _friendlyGenerationError(Object e) {
    final s = e.toString();
    final lower = s.toLowerCase();
    if (lower.contains('no endpoints found that support image input') ||
        lower.contains('does not support image') ||
        lower.contains('vision is not supported')) {
      return '🖼️ This model doesn\'t support image input.\n\n'
          '• Switch to a vision model (e.g. GPT-4o, Claude, Gemini)\n'
          '• Or remove the image and resend as text';
    }
    final rateLimited = lower.contains('429') ||
        lower.contains('rate_limit') ||
        lower.contains('rate-limit') ||
        lower.contains('rate limited');
    if (rateLimited) {
      var wait = '';
      final m = RegExp(r'retry_after_seconds"?\s*:\s*(\d+)').firstMatch(s);
      if (m != null) wait = ' (~${m.group(1)}s)';
      return '⏳ The provider rate-limited this request$wait '
          '(free shared pool).\n\n• Wait a bit and retry\n'
          '• Or add your own API key: Explore → provider card → Add API Key';
    }
    if (_isNetworkError(e)) {
      return '🌐 Network error — check your connection and retry.';
    }
    if (s.length > 300) {
      return '❌ Error: ${s.substring(0, 300)}…\n'
          '(Full details in System Logs → Chat)';
    }
    return '❌ Error: $s';
  }

  void editMessage(ChatMessage msg, String newContent) {
    if (isLoading.value || isStreaming.value) return;
    if (msg.role != 'user') return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    textController.clear();
    inputText.value = '';

    String? currentAssistantResponse;
    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      currentAssistantResponse = messages[idx + 1].content;
    }

    final allRevisions = List<Map<String, dynamic>>.from(msg.revisions ?? []);

    if (allRevisions.isEmpty) {
      allRevisions.add({
        'content': msg.content,
        'response': currentAssistantResponse,
      });
    } else {
      allRevisions[msg.revisionIndex] = {
        'content': msg.content,
        'response': currentAssistantResponse,
      };
    }

    allRevisions.add({
      'content': newContent,
      'response': null,
    });

    if (idx + 1 < messages.length && messages[idx + 1].role == 'assistant') {
      _hive.deleteMessage(messages[idx + 1].id);
      messages.removeAt(idx + 1);
    }

    final updated = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: newContent,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      fileName: msg.fileName,
      fileContent: msg.fileContent,
      filePath: msg.filePath,
      fileType: msg.fileType,
      fileSize: msg.fileSize,
      timestamp: msg.timestamp,
      revisions: allRevisions,
      revisionIndex: allRevisions.length - 1,
    );
    messages[idx] = updated;
    _hive.saveMessage(updated.id, updated.toMap());

    _generateAIResponse(
      prompt: newContent,
      imagePath: msg.imagePath,
      imgBase64: msg.imageBase64,
      fileType: msg.fileType,
      filePath: msg.filePath,
      insertAt: idx + 1,
    );
  }

  void navigateRevision(ChatMessage msg, int direction) {
    final revisions = msg.revisions;
    if (revisions == null || revisions.isEmpty) return;

    final targetIdx = msg.revisionIndex + direction;
    if (targetIdx < 0 || targetIdx >= revisions.length) return;

    var msgIdx = messages.indexWhere((m) => m.id == msg.id);
    if (msgIdx < 0) return;
    if (msgIdx == 0 && hasOlderMessages.value) {
      unawaited(loadOlderMessages().then((_) {
        navigateRevision(msg, direction);
      }));
      return;
    }

    String? currentResponse;
    if (msgIdx + 1 < messages.length &&
        messages[msgIdx + 1].role == 'assistant') {
      currentResponse = messages[msgIdx + 1].content;
    }

    final updatedRevisions = List<Map<String, dynamic>>.from(revisions);
    updatedRevisions[msg.revisionIndex] = {
      'content': msg.content,
      'response': currentResponse,
    };

    final targetRevision = updatedRevisions[targetIdx];
    final targetContent = targetRevision['content'] as String;
    final targetResponse = targetRevision['response'] as String?;

    final updatedUser = ChatMessage(
      id: msg.id,
      chatId: msg.chatId,
      role: msg.role,
      content: targetContent,
      imageBase64: msg.imageBase64,
      imagePath: msg.imagePath,
      fileName: msg.fileName,
      fileContent: msg.fileContent,
      filePath: msg.filePath,
      fileType: msg.fileType,
      fileSize: msg.fileSize,
      timestamp: msg.timestamp,
      revisions: updatedRevisions,
      revisionIndex: targetIdx,
    );
    messages[msgIdx] = updatedUser;
    _hive.saveMessage(updatedUser.id, updatedUser.toMap());

    if (msgIdx + 1 < messages.length &&
        messages[msgIdx + 1].role == 'assistant') {
      if (targetResponse != null) {
        final oldAssistant = messages[msgIdx + 1];
        final updatedAssistant = ChatMessage(
          id: oldAssistant.id,
          chatId: oldAssistant.chatId,
          role: oldAssistant.role,
          content: targetResponse,
          imageBase64: oldAssistant.imageBase64,
          imagePath: oldAssistant.imagePath,
          tokensPerSec: oldAssistant.tokensPerSec,
          thoughtDurationSeconds: oldAssistant.thoughtDurationSeconds,
          timestamp: oldAssistant.timestamp,
        );
        messages[msgIdx + 1] = updatedAssistant;
        unawaited(_hive.saveMessage(updatedAssistant.id, updatedAssistant.toMap()));
      } else {
        _hive.deleteMessage(messages[msgIdx + 1].id);
        messages.removeAt(msgIdx + 1);
      }
    } else if (targetResponse != null) {
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: msg.chatId,
        role: 'assistant',
        content: targetResponse,
      );
      messages.insert(msgIdx + 1, aiMsg);
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
    }

    messages.refresh();
  }

  void regenerateFromMessage(ChatMessage msg) {
    if (isLoading.value || isStreaming.value) return;
    var idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    if (idx == 0 && hasOlderMessages.value) {
      unawaited(loadOlderMessages().then((_) {
        regenerateFromMessage(msg);
      }));
      return;
    }

    final userMsg = idx > 0 ? messages[idx - 1] : null;
    if (userMsg == null || userMsg.role != 'user') return;

    textController.clear();
    inputText.value = '';

    _hive.deleteMessage(msg.id);
    messages.removeAt(idx);

    _scrollToBottom(force: true);

    _generateAIResponse(
      prompt: userMsg.content,
      imagePath: userMsg.imagePath,
      imgBase64: userMsg.imageBase64,
      fileType: userMsg.fileType,
      filePath: userMsg.filePath,
      insertAt: idx,
    );
  }

  void branchNewChat(ChatMessage msg) {
    if (isLoading.value || isStreaming.value) return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    final stored = _hive.getMessagesForChat(msg.chatId);
    final cutoff = msg.timestamp;
    final historyToCopy = stored.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    historyToCopy.retainWhere((m) =>
        m.id != msg.id &&
        !m.timestamp.isAfter(cutoff) &&
        (m.role == 'user' || m.role == 'assistant'));

    createNewChat();

    for (final m in historyToCopy) {
      final copied = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: m.role,
        content: m.content,
        imageBase64: m.imageBase64,
        imagePath: m.imagePath,
        fileName: m.fileName,
        fileContent: m.fileContent,
        filePath: m.filePath,
        fileType: m.fileType,
        fileSize: m.fileSize,
        tokensPerSec: m.tokensPerSec,
        thoughtDurationSeconds: m.thoughtDurationSeconds,
        timestamp: m.timestamp,
      );
      _hive.saveMessage(copied.id, copied.toMap());
      messages.add(copied);
    }
    _scrollToBottom(force: true);
  }

  void deleteMessage(ChatMessage msg) {
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    _hive.deleteMessage(msg.id);
    messages.removeAt(idx);
    if (messages.isEmpty && hasOlderMessages.value) {
      unawaited(loadOlderMessages());
    }
  }

  void toggleMessagePin(ChatMessage msg) {
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    final updated = msg.copyWithPinned(!msg.isPinned);
    messages[idx] = updated;
    _hive.saveMessage(updated.id, updated.toMap());
    
    Get.snackbar(
      updated.isPinned ? 'Message Pinned' : 'Message Unpinned',
      updated.isPinned ? 'This message will stay in context.' : 'Removed from pinned context.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  void saveStreamingDraft() {
    if (!isStreaming.value) return;
    final text = streamingResponse.value.trim();
    if (text.isEmpty || currentSessionId.value.isEmpty) return;
    _dropStreamingDraft();
    try {
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: currentSessionId.value,
        role: 'assistant',
        content: text,
      );
      messages.add(aiMsg);
      _hive.saveMessage(aiMsg.id, aiMsg.toMap());
      _draftMsgId = aiMsg.id;
      final session =
          sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
      if (session != null) {
        final updated = session.copyWith(lastMessage: text);
        _hive.saveSession(updated.id, updated.toMap());
        final idx = sessions.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) sessions[idx] = updated;
      }
    } catch (_) {}
  }

  void _dropStreamingDraft() {
    final id = _draftMsgId;
    _draftMsgId = null;
    if (id == null || id.isEmpty) return;
    try {
      messages.removeWhere((m) => m.id == id);
      _hive.deleteMessage(id);
    } catch (_) {}
  }

  void _saveAssistantMessage({
    required String content,
    String? imageBase64,
    double? tokensPerSec,
    int? thoughtDurationSeconds,
    int? generationDurationMs,
  }) {
    final aiMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: currentSessionId.value,
      role: 'assistant',
      content: content,
      imageBase64: imageBase64,
      tokensPerSec: tokensPerSec,
      thoughtDurationSeconds: thoughtDurationSeconds,
      generationDurationMs: generationDurationMs,
    );
    messages.add(aiMsg);
    _hive.saveMessage(aiMsg.id, aiMsg.toMap());

    final session =
        sessions.firstWhereOrNull((s) => s.id == currentSessionId.value);
    if (session != null) {
      final updated = session.copyWith(lastMessage: aiMsg.content);
      _hive.saveSession(updated.id, updated.toMap());
      final idx = sessions.indexWhere((s) => s.id == updated.id);
      if (idx >= 0) sessions[idx] = updated;
    }
  }

  void _handleUserScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    showScrollToBottom.value = distanceFromBottom > 200;
    if (position.pixels <= 240 &&
        hasOlderMessages.value &&
        !isLoadingOlder.value &&
        !isLoading.value) {
      unawaited(loadOlderMessages());
    }

    if (!isStreaming.value) {
      _followStreaming = distanceFromBottom <= 180;
    } else if (distanceFromBottom <= 48) {
      _followStreaming = true;
    }
  }

  void jumpToBottom() {
    if (!scrollController.hasClients) return;
    _followStreaming = true;
    _scrollToBottom(force: true);
  }

  void pauseStreamingFollow() {
    if (isStreaming.value) {
      _followStreaming = false;
    }
  }

  void resumeStreamingFollowIfNearBottom() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    if (distanceFromBottom <= 48) {
      _followStreaming = true;
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && isStreaming.value && !_followStreaming) return;
    if (_scrollTimer?.isActive == true) return;

    final delay = isStreaming.value ? 24 : 32;

    _scrollTimer = Timer(Duration(milliseconds: delay), () {
      if (!scrollController.hasClients) return;
      if (!force && isStreaming.value && !_followStreaming) return;
      
      final pos = scrollController.position;
      final target = pos.maxScrollExtent;
      final current = pos.pixels;
      
      if ((target - current).abs() < 4) {
        if (target != current) scrollController.jumpTo(target);
        return;
      }

      final duration = isStreaming.value ? 100 : 250;
      
      scrollController.animateTo(
        target,
        duration: Duration(milliseconds: duration),
        curve: isStreaming.value ? Curves.linear : Curves.easeOutCubic,
      );
    });
  }

  Future<String?> _persistImageFile(String sourcePath, String messageId) async {
    if (kIsWeb) return sourcePath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final chatDir = Directory('${dir.path}/chat_images');
      if (!await chatDir.exists()) await chatDir.create(recursive: true);
      final ext = sourcePath.split('.').last.toLowerCase();
      final validExt =
          {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'}.contains(ext)
              ? ext
              : 'jpg';
      final dest = File('${chatDir.path}/$messageId.$validExt');
      await File(sourcePath).copy(dest.path);
      return dest.path;
    } catch (_) {
      return sourcePath;
    }
  }

  Future<String?> _persistImageBytes(Uint8List bytes, String messageId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final chatDir = Directory('${dir.path}/chat_images');
      if (!await chatDir.exists()) await chatDir.create(recursive: true);
      final dest = File('${chatDir.path}/$messageId.png');
      await dest.writeAsBytes(bytes);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  String _attachmentTypeForExtension(String extension) {
    const imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'};
    const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'};
    const videoExtensions = {'mp4', 'mov', 'avi', 'mkv'};
    const textExtensions = {
      'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', 'xml',
      'dart', 'kt', 'java', 'js', 'ts', 'py',
    };
    if (imageExtensions.contains(extension)) return 'image';
    if (audioExtensions.contains(extension)) return 'audio';
    if (videoExtensions.contains(extension)) return 'video';
    if (extension == 'pdf') return 'pdf';
    if (extension == 'docx') return 'docx';
    if (textExtensions.contains(extension)) return 'text';
    return 'file';
  }

  String _defaultAttachmentPrompt(String? fileType) {
    switch (fileType) {
      case 'image':
        return 'Describe this image.';
      case 'pdf':
        return 'Summarize this PDF.';
      case 'docx':
        return 'Summarize this document.';
      case 'audio':
        return 'Transcribe or analyze this audio.';
      case 'video':
        return 'Summarize this video content based on visual frames.';
      case 'text':
        return 'Review this file.';
      default:
        return 'Review this attachment.';
    }
  }
}
