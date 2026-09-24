import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'web_source.dart';

class ChatMessage {
  final String id;
  final String chatId;
  final String role; // 'user', 'assistant', 'system', 'cmd'
  final String content;
  final String? imageBase64; // For multimodal
  final String? imagePath;
  final String? fileName;
  final String? fileContent;
  final String? filePath;
  final String? fileType;
  final int? fileSize;
  final String? cmdOutput; // Result of CMD: execution
  final bool isCommand;
  final double? tokensPerSec;
  final int? thoughtDurationSeconds;
  final int? imageGenDurationMs; // Time taken to generate image locally
  final int? generationDurationMs; // Total time taken for text response
  final DateTime timestamp;

  /// Web sources fetched for this turn (only on assistant messages).
  final List<WebSource>? webSources;

  /// Skill names that were injected for this prompt (assistant messages).
  final List<String>? usedSkills;

  /// Claude-style artifacts detected in this message.
  final List<Map<String, String>>? artifacts;

  /// Citations for RAG (assistant messages).
  final List<Map<String, dynamic>>? citations;

  /// Secondary responses for dual-response mode (assistant messages).
  final List<String>? alternatives;

  /// User choice for dual responses (0 = primary, 1+ = alternatives).
  final int? preferredIndex;

  /// Feedback string ('helpful', 'unhelpful', 'refused', etc).
  final String? feedback;

  /// Suggested follow-up questions.
  final List<String>? suggestions;

  /// Edit history: each entry is {'content': String, 'response': String?}
  /// revisions[0] = first version, revisions[last] = latest version
  final List<Map<String, dynamic>>? revisions;

  /// Index into revisions for the currently viewed version
  final int revisionIndex;

  /// Whether this message is pinned to context.
  final bool isPinned;

  /// Whether this message is waiting in the queue.
  final bool isQueued;

  /// Tool call steps for MCP/agent visualization.
  /// Each entry: {'name': String, 'args': Map, 'output': String,
  ///              'success': bool, 'durationMs': int, 'modifiedFiles': List}
  final List<Map<String, dynamic>>? toolSteps;

  /// Past turns auto-recalled from other chats for this turn (0 = none).
  final int recalledTurns;

  // Cache decoded bytes to prevent flickering on re-build
  Uint8List? _decodedImageBytes;
  Uint8List? get decodedImageBytes {
    if (imageBase64 != null) {
      _decodedImageBytes ??= base64Decode(imageBase64!);
      return _decodedImageBytes;
    }
    if (imagePath != null && !kIsWeb) {
      if (_decodedImageBytes != null) return _decodedImageBytes;
      try {
        final f = File(imagePath!);
        if (f.existsSync()) {
          _decodedImageBytes = f.readAsBytesSync();
          return _decodedImageBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Async twin of [decodedImageBytes] for preloading: `readAsBytes()`
  /// dispatches to the IO thread pool instead of blocking the UI thread
  /// like the sync getter. Safe to fire-and-forget from `openChat`.
  Future<Uint8List?> preloadImageBytes() async {
    if (_decodedImageBytes != null) return _decodedImageBytes;
    if (imageBase64 != null) {
      try {
        _decodedImageBytes = base64Decode(imageBase64!);
      } catch (_) {}
      return _decodedImageBytes;
    }
    if (imagePath != null && !kIsWeb) {
      try {
        final f = File(imagePath!);
        if (await f.exists()) _decodedImageBytes = await f.readAsBytes();
      } catch (_) {}
    }
    return _decodedImageBytes;
  }

  /// Raw bytes for viewer/share — prefers base64, falls back to file.
  Uint8List? get imageBytesForViewer {
    if (decodedImageBytes != null) return decodedImageBytes;
    return null;
  }

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.imageBase64,
    this.imagePath,
    this.fileName,
    this.fileContent,
    this.filePath,
    this.fileType,
    this.fileSize,
    this.cmdOutput,
    this.isCommand = false,
    this.tokensPerSec,
    this.thoughtDurationSeconds,
    this.imageGenDurationMs,
    this.generationDurationMs,
    DateTime? timestamp,
    this.webSources,
    this.usedSkills,
    this.artifacts,
    this.citations,
    this.alternatives,
    this.preferredIndex,
    this.feedback,
    this.suggestions,
    this.revisions,
    this.revisionIndex = 0,
    this.isPinned = false,
    this.isQueued = false,
    this.toolSteps,
    this.recalledTurns = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'role': role,
        'content': content,
        'imageBase64': imageBase64,
        'imagePath': imagePath,
        'fileName': fileName,
        'fileContent': fileContent,
        'filePath': filePath,
        'fileType': fileType,
        'fileSize': fileSize,
        'cmdOutput': cmdOutput,
        'isCommand': isCommand,
        'tokensPerSec': tokensPerSec,
        'thoughtDurationSeconds': thoughtDurationSeconds,
        'imageGenDurationMs': imageGenDurationMs,
        'generationDurationMs': generationDurationMs,
        'timestamp': timestamp.toIso8601String(),
        'webSources': webSources?.map((e) => e.toMap()).toList(),
        'usedSkills': usedSkills,
        'artifacts': artifacts,
        'citations': citations,
        'alternatives': alternatives,
        'preferredIndex': preferredIndex,
        'feedback': feedback,
        'suggestions': suggestions,
        'revisions': revisions,
        'revisionIndex': revisionIndex,
        'isPinned': isPinned,
        'isQueued': isQueued,
        'toolSteps': toolSteps,
        'recalledTurns': recalledTurns,
      };

  /// Returns a copy with updated suggestions (preserves all other fields).
  ChatMessage copyWithSuggestions(List<String>? newSuggestions) => ChatMessage(
        id: id,
        chatId: chatId,
        role: role,
        content: content,
        imageBase64: imageBase64,
        imagePath: imagePath,
        fileName: fileName,
        fileContent: fileContent,
        filePath: filePath,
        fileType: fileType,
        fileSize: fileSize,
        cmdOutput: cmdOutput,
        isCommand: isCommand,
        tokensPerSec: tokensPerSec,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageGenDurationMs,
        generationDurationMs: generationDurationMs,
        timestamp: timestamp,
        webSources: webSources,
        usedSkills: usedSkills,
        artifacts: artifacts,
        citations: citations,
        alternatives: alternatives,
        preferredIndex: preferredIndex,
        feedback: feedback,
        suggestions: newSuggestions,
        revisions: revisions,
        revisionIndex: revisionIndex,
        isPinned: isPinned,
        isQueued: isQueued,
        toolSteps: toolSteps,
        recalledTurns: recalledTurns,
      );

  /// Returns a copy with updated artifacts (for persistence after editing).
  ChatMessage copyWithArtifacts(List<Map<String, String>> newArtifacts) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        role: role,
        content: content,
        imageBase64: imageBase64,
        imagePath: imagePath,
        fileName: fileName,
        fileContent: fileContent,
        filePath: filePath,
        fileType: fileType,
        fileSize: fileSize,
        cmdOutput: cmdOutput,
        isCommand: isCommand,
        tokensPerSec: tokensPerSec,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageGenDurationMs,
        generationDurationMs: generationDurationMs,
        timestamp: timestamp,
        webSources: webSources,
        usedSkills: usedSkills,
        artifacts: newArtifacts,
        citations: citations,
        alternatives: alternatives,
        preferredIndex: preferredIndex,
        feedback: feedback,
        suggestions: suggestions,
        revisions: revisions,
        revisionIndex: revisionIndex,
        isPinned: isPinned,
        isQueued: isQueued,
        toolSteps: toolSteps,
      );

  ChatMessage copyWithPinned(bool pinned) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        role: role,
        content: content,
        imageBase64: imageBase64,
        imagePath: imagePath,
        fileName: fileName,
        fileContent: fileContent,
        filePath: filePath,
        fileType: fileType,
        fileSize: fileSize,
        cmdOutput: cmdOutput,
        isCommand: isCommand,
        tokensPerSec: tokensPerSec,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageGenDurationMs,
        generationDurationMs: generationDurationMs,
        timestamp: timestamp,
        webSources: webSources,
        usedSkills: usedSkills,
        artifacts: artifacts,
        citations: citations,
        alternatives: alternatives,
        preferredIndex: preferredIndex,
        feedback: feedback,
        suggestions: suggestions,
        revisions: revisions,
        revisionIndex: revisionIndex,
        isPinned: pinned,
        isQueued: isQueued,
        toolSteps: toolSteps,
      );

  ChatMessage copyWithQueued(bool queued) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        role: role,
        content: content,
        imageBase64: imageBase64,
        imagePath: imagePath,
        fileName: fileName,
        fileContent: fileContent,
        filePath: filePath,
        fileType: fileType,
        fileSize: fileSize,
        cmdOutput: cmdOutput,
        isCommand: isCommand,
        tokensPerSec: tokensPerSec,
        thoughtDurationSeconds: thoughtDurationSeconds,
        imageGenDurationMs: imageGenDurationMs,
        generationDurationMs: generationDurationMs,
        timestamp: timestamp,
        webSources: webSources,
        usedSkills: usedSkills,
        artifacts: artifacts,
        citations: citations,
        alternatives: alternatives,
        preferredIndex: preferredIndex,
        feedback: feedback,
        suggestions: suggestions,
        revisions: revisions,
        revisionIndex: revisionIndex,
        isPinned: isPinned,
        isQueued: queued,
        toolSteps: toolSteps,
      );

  factory ChatMessage.fromMap(Map<dynamic, dynamic> map) => ChatMessage(
        id: map['id'] ?? '',
        chatId: map['chatId'] ?? '',
        role: map['role'] ?? 'user',
        content: map['content'] ?? '',
        imageBase64: map['imageBase64'],
        imagePath: map['imagePath'],
        fileName: map['fileName'],
        fileContent: map['fileContent'],
        filePath: map['filePath'],
        fileType: map['fileType'],
        fileSize:
            map['fileSize'] != null ? (map['fileSize'] as num).toInt() : null,
        cmdOutput: map['cmdOutput'],
        isCommand: map['isCommand'] ?? false,
        tokensPerSec: map['tokensPerSec'] != null
            ? (map['tokensPerSec'] as num).toDouble()
            : null,
        thoughtDurationSeconds: map['thoughtDurationSeconds'] != null
            ? (map['thoughtDurationSeconds'] as num).toInt()
            : null,
        imageGenDurationMs: map['imageGenDurationMs'] != null
            ? (map['imageGenDurationMs'] as num).toInt()
            : null,
        generationDurationMs: map['generationDurationMs'] != null
            ? (map['generationDurationMs'] as num).toInt()
            : null,
        timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
        webSources: map['webSources'] != null
            ? (map['webSources'] as List)
                .map((e) =>
                    WebSource.fromMap(Map<dynamic, dynamic>.from(e as Map)))
                .toList()
            : null,
        usedSkills: map['usedSkills'] != null
            ? List<String>.from(map['usedSkills'] as List)
            : null,
        artifacts: map['artifacts'] != null
            ? (map['artifacts'] as List)
                .map((e) => Map<String, String>.from(e as Map))
                .toList()
            : null,
        citations: map['citations'] != null
            ? (map['citations'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : null,
        alternatives: map['alternatives'] != null
            ? List<String>.from(map['alternatives'] as List)
            : null,
        preferredIndex: map['preferredIndex'] != null
            ? (map['preferredIndex'] as num).toInt()
            : null,
        feedback: map['feedback']?.toString(),
        suggestions: map['suggestions'] != null
            ? List<String>.from(map['suggestions'] as List)
            : null,
        revisions: map['revisions'] != null
            ? List<Map<String, dynamic>>.from((map['revisions'] as List)
                .map((e) => Map<String, dynamic>.from(e)))
            : null,
        revisionIndex: map['revisionIndex'] != null
            ? (map['revisionIndex'] as num).toInt()
            : 0,
        isPinned: map['isPinned'] ?? false,
        isQueued: map['isQueued'] ?? false,
        toolSteps: map['toolSteps'] != null
            ? List<Map<String, dynamic>>.from((map['toolSteps'] as List)
                .map((e) => Map<String, dynamic>.from(e)))
            : null,
        recalledTurns: map['recalledTurns'] != null
            ? (map['recalledTurns'] as num).toInt()
            : 0,
      );
}
