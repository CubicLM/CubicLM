import 'dart:io';
import 'package:get/get.dart';
import 'app_log_service.dart';

class ToolService extends GetxService {
  
  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    try {
      Get.find<AppLogService>().info('Tool Execution: $name', details: args.toString(), category: LogCategory.chat);
      
      switch (name) {
        case 'read_file':
          return await _readFile(args['path']);
        case 'list_directory':
          return await _listDirectory(args['path']);
        case 'run_shell':
          return await _runShell(args['command']);
        default:
          return 'Error: Unknown tool "$name"';
      }
    } catch (e) {
      return 'Tool Execution Error: $e';
    }
  }

  Future<String> _readFile(dynamic path) async {
    if (path == null) return 'Error: path is required';
    final p = path.toString();
    try {
      final file = File(p);
      if (!await file.exists()) return 'Error: file not found at $p';
      final content = await file.readAsString();
      if (content.length > 20000) {
        return '${content.substring(0, 20000)}\n\n[Truncated due to size]';
      }
      return content;
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  Future<String> _listDirectory(dynamic path) async {
    final p = path?.toString() ?? Directory.current.path;
    try {
      final dir = Directory(p);
      if (!await dir.exists()) return 'Error: directory not found at $p';
      final entities = await dir.list().toList();
      final names = entities.map((e) => '${e is Directory ? "[DIR] " : "[FILE] "}${e.path.split(Platform.pathSeparator).last}').join('\n');
      return names.isEmpty ? 'Directory is empty' : names;
    } catch (e) {
      return 'Error listing directory: $e';
    }
  }

  Future<String> _runShell(dynamic command) async {
    if (command == null) return 'Error: command is required';
    final cmd = command.toString();
    
    // Safety check: Don't allow destructive commands without more thought
    final lower = cmd.toLowerCase();
    if (lower.contains('rm -rf') || lower.contains('format') || lower.contains('del /s')) {
       return 'Error: Potentially destructive command blocked for safety.';
    }

    try {
      // No process_run dependency: run through the platform shell.
      // Windows uses cmd, POSIX uses sh — same string semantics as before.
      final proc = Platform.isWindows ? 'cmd' : 'sh';
      final args = Platform.isWindows ? ['/c', cmd] : ['-c', cmd];
      final result = await Process.run(proc, args).timeout(
        const Duration(seconds: 60),
      );
      final out = '${result.stdout ?? ''}${result.stderr ?? ''}'.trim();
      return out.isEmpty ? '(exit ${result.exitCode}, no output)' : out;
    } catch (e) {
      return 'Shell execution error: $e';
    }
  }
}
