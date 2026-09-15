/// CubicLM Chat Attachments — file picker + copy to workspace for LLM context.
///
/// Enables users to attach local files (images, text, code) from
/// Android SAF / desktop file picker into chat messages, similar to
/// Mobile-Harness's attachment system but cross-platform.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../utils/app_snackbar.dart';

/// Maximum file size for attachments (25 MB).
const maxAttachmentSizeBytes = 25 * 1024 * 1024;

/// Maximum number of attachments per message.
const maxAttachmentsPerMessage = 5;

/// A single attachment ready for inclusion in a chat message.
class ChatAttachment {
  final String displayName;
  final String absolutePath;
  final String mimeType;
  final int sizeBytes;

  const ChatAttachment({
    required this.displayName,
    required this.absolutePath,
    required this.mimeType,
    required this.sizeBytes,
  });

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'absolutePath': absolutePath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };

  static ChatAttachment? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    return ChatAttachment(
      displayName: (raw['displayName'] ?? '').toString(),
      absolutePath: (raw['absolutePath'] ?? '').toString(),
      mimeType: (raw['mimeType'] ?? '').toString(),
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Pick files via FilePicker and return as [ChatAttachment] list.
/// Returns empty list on cancel.
Future<List<ChatAttachment>> pickChatAttachments() async {
  try {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return [];

    final attachments = <ChatAttachment>[];
    for (final file in result.files) {
      if (file.path == null) continue;
      if (attachments.length >= maxAttachmentsPerMessage) {
        AppSnackbar.showTop(
          'Limit reached',
          'Max $maxAttachmentsPerMessage attachments per message.',
        );
        break;
      }
      final f = File(file.path!);
      if (!await f.exists()) continue;
      final stat = await f.stat();
      if (stat.size > maxAttachmentSizeBytes) {
        AppSnackbar.showTop(
          'File too large',
          '${file.name} exceeds 25 MB limit.',
        );
        continue;
      }
      attachments.add(ChatAttachment(
        displayName: file.name,
        absolutePath: f.path,
        mimeType: _guessMime(file.name),
        sizeBytes: stat.size,
      ));
    }
    return attachments;
  } catch (_) {
    return [];
  }
}

/// Copy attachments into a workspace subdirectory for persistence.
/// Returns the list of copied absolute paths.
Future<List<String>> copyAttachmentsToWorkspace(
  List<ChatAttachment> attachments,
  String workspacePath,
) async {
  final copied = <String>[];
  final attachDir = Directory('$workspacePath/attachments');
  if (!await attachDir.exists()) {
    await attachDir.create(recursive: true);
  }
  for (final a in attachments) {
    try {
      final src = File(a.absolutePath);
      if (!await src.exists()) continue;
      final dst = File('${attachDir.path}/${a.displayName}');
      await src.copy(dst.path);
      copied.add(dst.path);
    } catch (_) {}
  }
  return copied;
}

/// Build a text summary of attachments for injection into LLM context.
String attachmentsContextSummary(List<ChatAttachment> attachments) {
  if (attachments.isEmpty) return '';
  final buf = StringBuffer('Attached files:\n');
  for (final a in attachments) {
    buf.writeln('  - ${a.displayName} (${_friendlySize(a.sizeBytes)}, ${a.mimeType})');
  }
  return buf.toString();
}

String _guessMime(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return 'image';
  if (lower.endsWith('.pdf')) return 'pdf';
  if (lower.endsWith('.dart') || lower.endsWith('.py') || lower.endsWith('.js') || lower.endsWith('.ts') || lower.endsWith('.java') || lower.endsWith('.kt') || lower.endsWith('.cpp') || lower.endsWith('.c') || lower.endsWith('.rs') || lower.endsWith('.go')) return 'code';
  if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml') || lower.endsWith('.toml') || lower.endsWith('.xml')) return 'config';
  if (lower.endsWith('.md') || lower.endsWith('.txt') || lower.endsWith('.log')) return 'text';
  return 'unknown';
}

String _friendlySize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
