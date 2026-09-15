/// CubicLM Agentic Tool System — built-in file operation tools.
///
/// Provides read_file, write_file, edit_file, list_files, and search_code.
/// All paths are relative to the workspace and validated for safety.
library;

import 'dart:io';

import 'tool_interface.dart';

/// Read a file's content.
class ReadFileTool extends Tool {
  @override
  String get name => 'read_file';

  @override
  String get description => 'Read the content of a file. Returns the full text content.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path to the file (e.g. "src/main.dart")',
          },
        },
        'required': ['path'],
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final path = args['path'] as String? ?? '';
    if (path.isEmpty) return ToolResult.error('Path is required.');

    final safePath = _safePath(path, context.workspacePath);
    if (safePath == null) return ToolResult.error('Invalid path (traversal not allowed).');

    final file = File(safePath);
    if (!await file.exists()) return ToolResult.error('File not found: $path');

    try {
      final content = await file.readAsString();
      if (content.length > 50000) {
        return ToolResult.truncated(
          content.substring(0, 50000),
        );
      }
      return ToolResult(output: content);
    } catch (e) {
      return ToolResult.error('Failed to read file: $e');
    }
  }
}

/// Write content to a file (create or overwrite).
class WriteFileTool extends Tool {
  @override
  String get name => 'write_file';

  @override
  String get description =>
      'Write content to a file. Creates the file if it doesn\'t exist, overwrites if it does. Creates parent directories automatically.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path to the file (e.g. "src/main.dart")',
          },
          'content': {
            'type': 'string',
            'description': 'The content to write to the file',
          },
        },
        'required': ['path', 'content'],
      };

  @override
  ToolRisk get risk => ToolRisk.review;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final path = args['path'] as String? ?? '';
    final content = args['content'] as String? ?? '';
    if (path.isEmpty) return ToolResult.error('Path is required.');

    final safePath = _safePath(path, context.workspacePath);
    if (safePath == null) return ToolResult.error('Invalid path (traversal not allowed).');

    try {
      final file = File(safePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return ToolResult(
        output: 'File written: $path (${content.length} chars)',
        modifiedFiles: [path],
      );
    } catch (e) {
      return ToolResult.error('Failed to write file: $e');
    }
  }
}

/// Find-and-replace edit in a file.
class EditFileTool extends Tool {
  @override
  String get name => 'edit_file';

  @override
  String get description =>
      'Replace exact text in a file. The old_text must match exactly (including whitespace and indentation).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path to the file',
          },
          'old_text': {
            'type': 'string',
            'description': 'The exact text to find and replace',
          },
          'new_text': {
            'type': 'string',
            'description': 'The replacement text',
          },
        },
        'required': ['path', 'old_text', 'new_text'],
      };

  @override
  ToolRisk get risk => ToolRisk.review;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final path = args['path'] as String? ?? '';
    final oldText = args['old_text'] as String? ?? '';
    final newText = args['new_text'] as String? ?? '';
    if (path.isEmpty) return ToolResult.error('Path is required.');
    if (oldText.isEmpty) return ToolResult.error('old_text is required.');

    final safePath = _safePath(path, context.workspacePath);
    if (safePath == null) return ToolResult.error('Invalid path (traversal not allowed).');

    final file = File(safePath);
    if (!await file.exists()) return ToolResult.error('File not found: $path');

    try {
      var content = await file.readAsString();
      if (!content.contains(oldText)) {
        return ToolResult.error('old_text not found in $path');
      }
      content = content.replaceFirst(oldText, newText);
      await file.writeAsString(content);
      return ToolResult(
        output: 'File edited: $path',
        modifiedFiles: [path],
      );
    } catch (e) {
      return ToolResult.error('Failed to edit file: $e');
    }
  }
}

/// List files in a directory.
class ListFilesTool extends Tool {
  @override
  String get name => 'list_files';

  @override
  String get description =>
      'List files and directories at a path. Returns names with / for directories.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Relative directory path (e.g. "src" or "" for root). Defaults to workspace root.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'If true, list all files recursively. Default: false.',
          },
        },
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final relPath = (args['path'] as String? ?? '').trim();
    final recursive = args['recursive'] as bool? ?? false;

    final dirPath = relPath.isEmpty
        ? context.workspacePath
        : _safePath(relPath, context.workspacePath);
    if (dirPath == null) return ToolResult.error('Invalid path.');

    final dir = Directory(dirPath);
    if (!await dir.exists()) return ToolResult.error('Directory not found: $relPath');

    final entries = <String>[];
    try {
      if (recursive) {
        await for (final entity in dir.list(recursive: true)) {
          final relative = entity.path
              .replaceFirst(context.workspacePath, '')
              .replaceFirst(RegExp(r'^[/\\]'), '');
          if (entity is Directory) {
            entries.add('$relative/');
          } else {
            entries.add(relative);
          }
        }
      } else {
        await for (final entity in dir.list()) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (entity is Directory) {
            entries.add('$name/');
          } else {
            entries.add(name);
          }
        }
      }
    } catch (e) {
      return ToolResult.error('Failed to list directory: $e');
    }

    if (entries.isEmpty) return const ToolResult(output: '(empty directory)');
    return ToolResult(output: entries.join('\n'));
  }
}

/// Search for a pattern across files (grep-like).
class SearchCodeTool extends Tool {
  @override
  String get name => 'search_code';

  @override
  String get description =>
      'Search for a text pattern across files in the workspace. Returns matching lines with file paths and line numbers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Text pattern to search for (case-insensitive)',
          },
          'path': {
            'type': 'string',
            'description':
                'Relative directory to search in. Defaults to entire workspace.',
          },
          'include': {
            'type': 'string',
            'description':
                'File pattern to include (e.g. "*.dart", "*.js"). Default: all files.',
          },
        },
        'required': ['pattern'],
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final pattern = args['pattern'] as String? ?? '';
    final relPath = (args['path'] as String? ?? '').trim();
    final include = args['include'] as String? ?? '';

    if (pattern.isEmpty) return ToolResult.error('Pattern is required.');

    final searchDir = relPath.isEmpty
        ? context.workspacePath
        : _safePath(relPath, context.workspacePath);
    if (searchDir == null) return ToolResult.error('Invalid path.');

    final dir = Directory(searchDir);
    if (!await dir.exists()) return ToolResult.error('Directory not found: $relPath');

    final regex = RegExp(pattern, caseSensitive: false);
    final includeGlob = include.isNotEmpty
        ? RegExp(include.replaceAll('*', '.*'), caseSensitive: false)
        : null;

    final results = <String>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (includeGlob != null &&
            !includeGlob.hasMatch(entity.path.split(Platform.pathSeparator).last)) {
          continue;
        }

        final relative = entity.path
            .replaceFirst(context.workspacePath, '')
            .replaceFirst(RegExp(r'^[/\\]'), '');

        try {
          final lines = await entity.readAsLines();
          for (var i = 0; i < lines.length; i++) {
            if (regex.hasMatch(lines[i])) {
              results.add('$relative:${i + 1}: ${lines[i].trim()}');
              if (results.length >= 50) break;
            }
          }
          if (results.length >= 50) break;
        } catch (_) {
          // Skip binary files or unreadable files
        }
      }
    } catch (e) {
      return ToolResult.error('Search failed: $e');
    }

    if (results.isEmpty) return const ToolResult(output: 'No matches found.');
    final truncated = results.length >= 50;
    return ToolResult(
      output: results.join('\n'),
      truncated: truncated,
    );
  }
}

// ── Path Safety ──────────────────────────────────────────────────────

/// Validate and resolve a relative path against the workspace.
/// Returns null if the path attempts traversal or is absolute.
String? _safePath(String relativePath, String workspacePath) {
  if (relativePath.startsWith('/') || relativePath.contains(':')) {
    return null; // Absolute path rejected
  }
  if (relativePath.contains('..')) {
    return null; // Traversal rejected
  }
  final sanitized = relativePath.replaceAll('\\', '/');
  final parts = sanitized.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;

  return '$workspacePath${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
}

/// Get all built-in file tools.
List<Tool> fileTools() => [
      ReadFileTool(),
      WriteFileTool(),
      EditFileTool(),
      ListFilesTool(),
      SearchCodeTool(),
    ];
