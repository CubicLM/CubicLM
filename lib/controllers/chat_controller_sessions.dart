/// Session, folder and project management for [ChatController]:
/// sessions/folders/projects CRUD, pins, labels, personas, locks,
/// history paging, backup import/export and auto-backup.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: loadSessions(), loadProjects(), loadFolders(), createFolder(), deleteFolder(), addChatToFolder()
///   createProject(), deleteProject(), addChatToProject(), _sessionSort(), togglePin()
///   toggleArchive(), where(), toggleHidden(), where(), chatLabels, setLabel(), setPersona()
///   currentPersona, createNewChat(), _resetInferenceContext(), openChat(), _authThenOpen()
///   toggleLocked(), loadOlderMessages(), _preloadChatImages(), deleteChat(), undoDeleteChat()
///   renameChat(), setAutoBackup(), importChats()
part of 'chat_controller.dart';

/// Session/folder/project management as an extension (same library,
/// so private members stay visible). Split from the 3.5k-line
/// controller for navigability; behavior is unchanged.
extension ChatControllerSessions on ChatController {
  // ─── Session Management ─────────────────────────

  void loadSessions() {
    final raw = _hive.getAllSessions();
    sessions.value = raw.map((m) => ChatSession.fromMap(m)).toList()
      ..sort(_sessionSort);
  }

  void loadProjects() {
    final raw = _hive.getAllProjects();
    projects.value = raw.map((m) => ChatProject.fromMap(m)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void loadFolders() {
    final raw = _hive.getAllFolders();
    folders.value = raw.map((m) => ChatFolder.fromMap(m)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void createFolder(String name, {String? parentId}) {
    final id = _uuid.v4();
    final folder = ChatFolder(id: id, name: name, parentId: parentId);
    _hive.saveFolder(id, folder.toMap());
    folders.add(folder);
  }

  void deleteFolder(String id) {
    _hive.deleteFolder(id);
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].folderId == id) {
        final updated = sessions[i].copyWith(folderId: null);
        sessions[i] = updated;
        _hive.saveSession(updated.id, updated.toMap());
      }
    }
  }

  void addChatToFolder(String chatId, String? folderId) {
    final sIdx = sessions.indexWhere((s) => s.id == chatId);
    if (sIdx >= 0) {
      final updated = sessions[sIdx].copyWith(folderId: folderId);
      sessions[sIdx] = updated;
      _hive.saveSession(updated.id, updated.toMap());
    }
  }

  void createProject(String name) {
    final id = _uuid.v4();
    final project = ChatProject(id: id, name: name);
    _hive.saveProject(id, project.toMap());
    projects.insert(0, project);
  }

  void deleteProject(String id) {
    _hive.deleteProject(id);
    projects.removeWhere((p) => p.id == id);
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].projectId == id) {
        final updated = sessions[i].copyWith(projectId: null);
        sessions[i] = updated;
        _hive.saveSession(updated.id, updated.toMap());
      }
    }
  }

  void addChatToProject(String chatId, String projectId) {
    final sIdx = sessions.indexWhere((s) => s.id == chatId);
    if (sIdx >= 0) {
      final updated = sessions[sIdx].copyWith(projectId: projectId);
      sessions[sIdx] = updated;
      _hive.saveSession(updated.id, updated.toMap());
    }
  }

  int _sessionSort(ChatSession a, ChatSession b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  void togglePin(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(pinned: !session.pinned);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
  }

  void toggleArchive(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(archived: !session.archived);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.archived ? 'Chat archived' : 'Chat unarchived',
      updated.archived
          ? 'Hidden from history. Use "Show archived" to reveal.'
          : 'Back in your history.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  int get archivedCount => sessions.where((s) => s.archived).length;

  void toggleHidden(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(hidden: !session.hidden);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.hidden ? 'Chat hidden' : 'Chat unhidden',
      updated.hidden
          ? 'Out of history and search. Use "Show hidden" to reveal.'
          : 'Back in your history.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  int get hiddenCount => sessions.where((s) => s.hidden).length;

  List<String> get chatLabels {
    final set = <String>{};
    for (final s in sessions) {
      final l = s.label.trim();
      if (l.isNotEmpty) set.add(l);
    }
    final out = set.toList()..sort();
    return out;
  }

  void setLabel(String sessionId, String label) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(label: label.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
  }

  void setPersona(String sessionId, String persona) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(persona: persona.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
  }

  String get currentPersona {
    if (currentSessionId.value.isEmpty) return '';
    return sessions
            .firstWhereOrNull((s) => s.id == currentSessionId.value)
            ?.persona ??
        '';
  }

  void createNewChat() {
    final id = _uuid.v4();
    final session = ChatSession(id: id, title: 'New Chat');
    _hive.saveSession(id, session.toMap());
    sessions.add(session);
    sessions.sort(_sessionSort);
    openChat(id);
  }

  void _resetInferenceContext() {
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      unawaited(inference.resetConversation());
    }
  }

  void openChat(String sessionId, {bool unlocked = false}) {
    final target = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (target != null && target.locked && !unlocked) {
      unawaited(_authThenOpen(sessionId));
      return;
    }
    stopGenerating();
    currentSessionId.value = sessionId;
    hasOlderMessages.value = false;
    isLoadingOlder.value = false;
    toggleFind(false);
    _findKeys.clear();
    final raw = _hive.getMessagesForChatPaged(
      sessionId,
      limit: ChatController._chatPageSize,
    );
    messages.value = raw.map((m) => ChatMessage.fromMap(m)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    hasOlderMessages.value = raw.length >= ChatController._chatPageSize;
    unawaited(_preloadChatImages(sessionId, messages.toList()));
    final inference = Get.find<InferenceService>();
    if (inference.isModelLoaded.value) {
      inference.refreshContextInfo();
    }
    _resetInferenceContext();
    final opened = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (opened != null) {
      currentProjectId.value = opened.projectId;
      unawaited(_applySessionModel(opened));
    }
    unawaited(_flushOutbox());
    _scrollToBottom(force: true);
  }

  Future<void> _authThenOpen(String sessionId) async {
    try {
      final ok = await Get.find<SettingsController>()
          .authenticate(reason: 'Unlock this chat');
      if (!ok) {
        Get.snackbar('Locked', 'Authentication failed — chat stays closed.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      if (currentSessionId.value != sessionId) {
        openChat(sessionId, unlocked: true);
      }
    } catch (_) {}
  }

  void toggleLocked(String sessionId) {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(locked: !session.locked);
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
    sessions.sort(_sessionSort);
    Get.snackbar(
      updated.locked ? 'Chat locked' : 'Chat unlocked',
      updated.locked
          ? 'Device auth is required to open it.'
          : 'Opens without authentication.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> loadOlderMessages() async {
    if (isLoadingOlder.value || !hasOlderMessages.value) return;
    if (currentSessionId.value.isEmpty) return;
    if (!scrollController.hasClients) return;
    isLoadingOlder.value = true;
    try {
      final sessionId = currentSessionId.value;
      if (messages.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final oldestMs = messages.first.timestamp.millisecondsSinceEpoch;
      final raw = _hive.getMessagesForChatPaged(
        sessionId,
        limit: ChatController._chatPageSize,
        beforeTimestampMs: oldestMs,
      );
      if (currentSessionId.value != sessionId) return;
      if (raw.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final older = raw.map((m) => ChatMessage.fromMap(m)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final knownIds = messages.map((m) => m.id).toSet();
      older.removeWhere((m) => knownIds.contains(m.id));
      if (older.isEmpty) {
        hasOlderMessages.value = false;
        return;
      }
      final pos = scrollController.position;
      final oldMax = pos.maxScrollExtent;
      final oldPixels = pos.pixels;
      messages.insertAll(0, older);
      unawaited(_preloadChatImages(sessionId, older));
      hasOlderMessages.value = raw.length >= ChatController._chatPageSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        try {
          final newMax = scrollController.position.maxScrollExtent;
          scrollController.jumpTo(
            (oldPixels + (newMax - oldMax)).clamp(0.0, newMax.toDouble()),
          );
        } catch (_) {}
      });
    } finally {
      isLoadingOlder.value = false;
    }
  }

  Future<void> _preloadChatImages(
      String sessionId, List<ChatMessage> msgs) async {
    for (final m in msgs) {
      if (currentSessionId.value != sessionId) return;
      if (m.imageBase64 == null && m.imagePath == null) continue;
      try {
        await m.preloadImageBytes();
      } catch (_) {}
    }
  }

  void deleteChat(String sessionId) {
    if (currentSessionId.value == sessionId && isLoading.value) {
      stopGenerating();
    }
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    _trashSession = session;
    _trashMessages = session == null
        ? []
        : _hive
            .getMessagesForChat(sessionId)
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
    _hive.deleteSession(sessionId);
    sessions.removeWhere((s) => s.id == sessionId);
    if (currentSessionId.value == sessionId) {
      currentSessionId.value = '';
      messages.clear();
      hasOlderMessages.value = false;
    }
    if (session != null) {
      Get.snackbar(
        'Chat deleted',
        session.title,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
        mainButton: TextButton(
          onPressed: () {
            try {
              Get.back();
            } catch (_) {}
            undoDeleteChat();
          },
          child: const Text('UNDO'),
        ),
      );
    }
  }

  Future<void> undoDeleteChat() async {
    final s = _trashSession;
    if (s == null) return;
    _trashSession = null;
    try {
      await _hive.saveSession(s.id, s.toMap());
      for (final m in _trashMessages) {
        try {
          final id = m['id']?.toString() ?? '';
          if (id.isNotEmpty) await _hive.saveMessage(id, m);
        } catch (_) {}
      }
    } catch (_) {}
    _trashMessages = [];
    if (!sessions.any((e) => e.id == s.id)) {
      sessions.add(s);
      sessions.sort(_sessionSort);
    }
    if (currentSessionId.value.isEmpty) openChat(s.id);
  }

  void renameChat(String sessionId, String newTitle) {
    if (newTitle.trim().isEmpty) return;
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) return;
    final updated = session.copyWith(title: newTitle.trim());
    _hive.saveSession(updated.id, updated.toMap());
    final idx = sessions.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) sessions[idx] = updated;
  }

  // ─── Backup & Restore ───────────────────────────

  Future<void> setAutoBackup(bool enabled, [int? days]) async {
    autoBackupEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoBackupEnabled, enabled);
    if (days != null) {
      autoBackupDays.value = days;
      await _hive.setSetting(AppConstants.keyAutoBackupDays, days);
    }
  }

  Future<String?> importChats({String? passphrase}) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final files = picked?.files;
      if (files == null || files.isEmpty) return 'cancelled';
      final platformFile = files.first;

      String? raw;
      if (platformFile.bytes != null && platformFile.bytes!.isNotEmpty) {
        try {
          raw = utf8.decode(platformFile.bytes!);
        } on FormatException {
          raw = null;
        }
      }
      raw ??= platformFile.path != null
          ? await File(platformFile.path!).readAsString()
          : null;
      if (raw == null || raw.isEmpty) return 'invalid';

      final dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return 'invalid';
      }
      var body = decoded;
      if (decoded is Map<String, dynamic> &&
          decoded['type'] == 'chat_backup_encrypted') {
        final algo = decoded['algo']?.toString() ?? 'aes256cbc-sha256';
        if (algo != 'aes256cbc-sha256') return 'invalid';
        final pass = (passphrase ?? '').trim();
        if (pass.isEmpty) return 'locked';
        try {
          final packed = base64Decode(decoded['data']?.toString() ?? '');
          final plain = await _hive.decryptBackupBytes(packed, pass);
          final text = utf8.decode(plain);
          if (!text.startsWith(HiveService.backupMagic)) return 'invalid';
          body = jsonDecode(text.substring(HiveService.backupMagic.length));
        } catch (_) {
          return 'invalid';
        }
      }
      if (body is! Map<String, dynamic>) return 'invalid';
      final t = body['type'];
      final hasData = body['sessions'] is List || body['messages'] is List;
      if (t != 'chat_backup' && !(t == null && hasData)) return 'invalid';

      final existingIds = sessions.map((s) => s.id).toSet();
      var importedSessions = 0;
      var importedMessages = 0;

      final rawSessions = body['sessions'];
      if (rawSessions is List) {
        for (final item in rawSessions) {
          if (item is! Map) continue;
          final session = ChatSession.fromMap(Map<dynamic, dynamic>.from(item));
          if (session.id.isEmpty || existingIds.contains(session.id)) continue;
          await _hive.saveSession(session.id, session.toMap());
          existingIds.add(session.id);
          importedSessions++;
        }
      }

      final existingMessageKeys = _hive
          .getAllMessagesRaw()
          .map((m) => _messageKey(
              m['chatId']?.toString() ?? '', m['id']?.toString() ?? ''))
          .toSet();

      final rawMessages = body['messages'];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is! Map) continue;
          final msg = Map<String, dynamic>.from(item);
          final id = msg['id']?.toString() ?? '';
          final chatId = msg['chatId']?.toString() ?? '';
          if (id.isEmpty) continue;
          final key = _messageKey(chatId, id);
          if (existingMessageKeys.contains(key)) continue;
          await _hive.saveMessage(id, msg);
          existingMessageKeys.add(key);
          importedMessages++;
        }
      }

      if (importedSessions > 0) loadSessions();

      if (importedSessions == 0 && importedMessages == 0) return 'nothing';
      return 'ok:$importedSessions:$importedMessages';
    } catch (e) {
      Get.find<AppLogService>().error('Backup import failed',
          details: e, category: LogCategory.chat);
      return 'error';
    }
  }
}
