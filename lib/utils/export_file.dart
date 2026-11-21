import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../services/app_log_service.dart';
import '../services/hive_service.dart';
import 'web_download.dart';

/// Direct file export — saves bytes straight to the device with a system
/// Save dialog (Storage Access Framework on Android, NSSavePanel-style
/// picker on desktop, browser download on web).
///
/// Unlike `share_plus`, this never opens the share sheet, so exports work
/// even when no other app can receive the file.
class ExportFile {
  ExportFile._();

  static const _androidChannel =
      MethodChannel('com.cubiclm.app/model_import');

  /// Bumped on every successful save — the Saved Files tab listens and
  /// reloads, so fresh exports appear without pull-to-refresh.
  static final savedVersion = ValueNotifier<int>(0);

  static void _noteSaved() {
    try {
      savedVersion.value++;
    } catch (_) {}
  }

  /// Saves [bytes] as [fileName]. Returns the saved path (or file name on
  /// web), or null when the user cancels / the platform cannot save.
  static Future<String?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      try {
        if (await downloadWebFile(
            bytes, fileName, mimeType ?? 'application/octet-stream')) {
          return fileName;
        }
      } catch (_) {}
      return null;
    }
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    try {
      return await FilePicker.saveFile(
        dialogTitle: dialogTitle ?? 'Save $fileName',
        fileName: fileName,
        type: ext.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: ext.isEmpty ? null : [ext],
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Text twin of [saveBytes].
  static Future<String?> saveText({
    required String text,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
  }) =>
      saveBytes(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: fileName,
        dialogTitle: dialogTitle,
        mimeType: mimeType,
      );

  /// Sanitized export subfolder name (user setting or 'CubicLM').
  /// Pure logic — safe to unit test.
  static String appSubfolder() {
    try {
      final raw = Get.isRegistered<HiveService>()
          ? (Get.find<HiveService>()
                  .getSetting<String>(AppConstants.keyExportSubfolder) ??
              '')
          : '';
      final clean = sanitizeExportSubfolder(raw);
      return clean.isEmpty ? AppConstants.defaultExportSubfolder : clean;
    } catch (_) {
      return AppConstants.defaultExportSubfolder;
    }
  }

  /// Keep only filesystem-safe chars for the subfolder name.
  /// Pure logic — safe to unit test.
  static String sanitizeExportSubfolder(String s) {
    var clean = s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean == '.' || clean == '..') return '';
    if (clean.length > 32) clean = clean.substring(0, 32).trim();
    return clean;
  }

  /// Per-feature export folders under Download/<app> (or Documents/<app>
  /// on desktop). Every file-saving caller MUST pass its [category] —
  /// unmapped categories fall back to the root AND log a warning row so
  /// hidden exports without a location get a folder assigned.
  static const Map<String, String> exportSubfolders = {
    'logs': 'System Logs',
    'slides': 'Slide Maker',
    'web': 'CubicWeb Builder',
    'datasheet': 'CubicDataSheet',
    'browser': 'CubicWeb Browser',
    'chat': 'Chat Exports',
    'cubicapp': 'CubicApp Builder',
    'agent': 'Agent Runs',
    'backup': 'Backups',
  };

  /// Resolves a category to its relative subfolder path
  /// (`CubicLM/System Logs`). Unknown or blank categories resolve to
  /// the root AND emit the audit warning. Pure apart from the log call.
  static String resolveSubfolder(String? category) {
    final base = appSubfolder();
    final key = (category ?? '').trim().toLowerCase();
    if (key.isEmpty) return base;
    final mapped = exportSubfolders[key];
    if (mapped == null) {
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().warning(
            'Export without location: "$category"',
            details:
                'No folder is registered for this export kind — the file lands directly in $base/. '
                'Report this to the developer so a dedicated folder gets created.',
            category: LogCategory.system,
          );
        }
      } catch (_) {}
      return base;
    }
    return '$base/$mapped';
  }

  /// Short display label for Settings, e.g. 'Download/CubicLM'.
  static String exportLocationLabel() {
    if (kIsWeb) return 'Browser downloads';
    try {
      if (Platform.isAndroid) {
        final treeName = Get.isRegistered<HiveService>()
            ? (Get.find<HiveService>()
                    .getSetting<String>(AppConstants.keyExportTreeName) ??
                '')
            : '';
        if (treeName.isNotEmpty) return '$treeName (custom)';
        return 'Download/${appSubfolder()}';
      }
      if (!Platform.isIOS) {
        final custom = Get.isRegistered<HiveService>()
            ? (Get.find<HiveService>()
                    .getSetting<String>(AppConstants.keyExportCustomDir) ??
                '')
            : '';
        if (custom.isNotEmpty) return custom;
        return 'Documents/${appSubfolder()}';
      }
    } catch (_) {}
    return appSubfolder();
  }

  /// Opens the system folder picker (Android file manager) for the export
  /// destination. Returns {'uri', 'name'} or null when cancelled.
  /// Caller persists via SettingsController.setExportTree.
  static Future<Map<String, String>?> pickExportFolder() async {
    if (kIsWeb) return null;
    try {
      if (!Platform.isAndroid) return null;
      final res = await _androidChannel
          .invokeMapMethod<String, dynamic>('pickExportFolder');
      if (res == null) return null;
      final uri = res['uri']?.toString() ?? '';
      final name = res['name']?.toString() ?? '';
      if (uri.isEmpty) return null;
      return {'uri': uri, 'name': name.isEmpty ? 'Picked folder' : name};
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearExportTree() async {
    try {
      if (Get.isRegistered<HiveService>()) {
        final hive = Get.find<HiveService>();
        await hive.setSetting(AppConstants.keyExportTreeUri, '');
        await hive.setSetting(AppConstants.keyExportTreeName, '');
      }
    } catch (_) {}
  }

  /// Saves [bytes] straight into the app export folder — no dialog.
  /// Android: Download/\<subfolder\> via MediaStore (no permission needed).
  /// Desktop/iOS: Documents (or the custom dir) / \<subfolder\>.
  /// Pass [category] (see [exportSubfolders]) for per-feature folders.
  /// Returns the saved display path, or null on failure.
  static Future<String?> saveToAppFolder({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? category,
  }) async {
    if (kIsWeb) {
      try {
        if (await downloadWebFile(
            bytes, fileName, mimeType ?? _mimeFor(fileName))) {
          return fileName;
        }
      } catch (_) {}
      return null;
    }
    if (Platform.isAndroid) {
      // A user-picked system folder wins; on lost permission fall back
      // to the default (and drop the stale keys so Settings reflects it).
      try {
        final hive = Get.isRegistered<HiveService>()
            ? Get.find<HiveService>()
            : null;
        final treeUri = hive?.getSetting<String>(
                AppConstants.keyExportTreeUri) ??
            '';
        if (treeUri.isNotEmpty) {
          final ok = await _androidChannel.invokeMethod<bool>(
              'checkTreeFolderAccess', {'treeUri': treeUri});
          if (ok == true) {
            final path = await _androidChannel.invokeMethod<String>(
                'saveBytesToTreeFolder', {
              'filename': fileName,
              'bytes': bytes,
              'mimeType': mimeType ?? _mimeFor(fileName),
              'treeUri': treeUri,
            });
            if (path != null && path.isNotEmpty) {
              _noteSaved();
              return path;
            }
          } else {
            await clearExportTree();
          }
        }
      } catch (_) {}
      try {
        final subfolder = resolveSubfolder(category);
        final path =
            await _androidChannel.invokeMethod<String>('saveBytesToDownloads', {
          'filename': fileName,
          'bytes': bytes,
          'mimeType': mimeType ?? _mimeFor(fileName),
          'subfolder': subfolder,
        });
        if (path == null || path.isEmpty) return null;
        _noteSaved();
        return path;
      } catch (_) {
        return null;
      }
    }
    try {
      final dir = await _desktopExportDir(subfolder: resolveSubfolder(category));
      final f = File('${dir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      _noteSaved();
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Text twin of [saveToAppFolder].
  static Future<String?> saveTextToAppFolder({
    required String text,
    required String fileName,
    String? mimeType,
    String? category,
  }) =>
      saveToAppFolder(
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileName: fileName,
        mimeType: mimeType,
        category: category,
      );

  static Future<Directory> _desktopExportDir({String? subfolder}) async {
    final sub = (subfolder == null || subfolder.isEmpty)
        ? appSubfolder()
        : subfolder;
    final parts = sub
        .split('/')
        .map((s) => sanitizeExportSubfolder(s))
        .where((s) => s.isNotEmpty);
    Directory joinParts(String root) {
      var d = Directory(root);
      for (final part in parts) {
        d = Directory('${d.path}${Platform.pathSeparator}$part');
      }
      return d;
    }
    try {
      final custom = Get.isRegistered<HiveService>()
          ? (Get.find<HiveService>()
                  .getSetting<String>(AppConstants.keyExportCustomDir) ??
              '')
          : '';
      if (custom.isNotEmpty) {
        final base = Directory(custom);
        if (await base.exists()) {
          final d = joinParts(base.path);
          await d.create(recursive: true);
          return d;
        }
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    final d = joinParts(docs.path);
    await d.create(recursive: true);
    return d;
  }

  static String _mimeFor(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'md':
      case 'markdown':
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'zip':
        return 'application/zip';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  /// Shares [bytes] via the system share sheet (staged through cache).
  static Future<bool> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String? text,
    String? subject,
  }) async {
    try {
      if (kIsWeb) {
        await Share.share(text ?? fileName, subject: subject);
        return true;
      }
      final tmp = await getTemporaryDirectory();
      final dir =
          Directory('${tmp.path}${Platform.pathSeparator}cubiclm_share');
      await dir.create(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path)],
          text: text, subject: subject);
      return true;
    } catch (e) {
      // Never swallow silently: release-only share failures (R8, OEM
      // share-sheet quirks) are otherwise indistinguishable from "it
      // just didn't work". The row below is what future bug reports
      // will quote instead of a bare snackbar.
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().error(
            'Share failed: $fileName',
            details:
                'error=$e, bytes=${bytes.length}, platform=${Platform.operatingSystem}',
            category: LogCategory.system,
          );
        }
      } catch (_) {}
      return false;
    }
  }

  /// One-call export: saves into the app folder (no dialog), then shows a
  /// snackbar with the location and a Share action. Returns the saved
  /// path, or null on failure (a failure snackbar is shown).
  /// Pass [category] (see [exportSubfolders]) for per-feature folders —
  /// unmapped categories land in the root + log the audit warning.
  static Future<String?> quickExport({
    Uint8List? bytes,
    String? text,
    required String fileName,
    String? mimeType,
    String? shareText,
    String? shareSubject,
    String? category,
  }) async {
    final data = bytes ??
        (text != null ? Uint8List.fromList(utf8.encode(text)) : null);
    if (data == null) return null;
    final saved = await saveToAppFolder(
        bytes: data,
        fileName: fileName,
        mimeType: mimeType,
        category: category);
    if (saved == null) {
      Get.snackbar('Export failed', 'Could not save $fileName.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
      return null;
    }
    Get.snackbar(
      'Export saved',
      saved,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
      mainButton: TextButton(
        onPressed: () {
          try {
            if (Get.isSnackbarOpen) Get.back();
          } catch (_) {}
          unawaited(shareBytes(
              bytes: data,
              fileName: fileName,
              text: shareText,
              subject: shareSubject));
        },
        child: const Text('Share'),
      ),
    );
    return saved;
  }

  /// Returns the path of the export directory (for display).
  static Future<String> getExportDirPath() async {
    if (kIsWeb) return 'Browser downloads';
    if (Platform.isAndroid) {
      try {
        final hive = Get.isRegistered<HiveService>()
            ? Get.find<HiveService>()
            : null;
        final treeUri =
            hive?.getSetting<String>(AppConstants.keyExportTreeUri) ?? '';
        if (treeUri.isNotEmpty) {
          final ok = await _androidChannel.invokeMethod<bool>(
              'checkTreeFolderAccess', {'treeUri': treeUri});
          if (ok == true) {
            final path = await _androidChannel.invokeMethod<String>(
                'getTreeFolderPath', {'treeUri': treeUri});
            if (path != null && path.isNotEmpty) return path;
          }
        }
      } catch (_) {}
      // Default: Download/CubicLM
      try {
        final dl = await _androidChannel.invokeMethod<String>(
            'getDownloadsPath');
        if (dl != null && dl.isNotEmpty) {
          return '$dl${Platform.pathSeparator}${appSubfolder()}';
        }
      } catch (_) {}
      return 'Download/${appSubfolder()}';
    }
    try {
      final dir = await _desktopExportDir();
      return dir.path;
    } catch (_) {}
    return appSubfolder();
  }

  /// Lists saved log/export files (*.txt, *.log) in the export directory.
  static Future<List<ExportedFile>> listSavedLogFiles() async {
    if (kIsWeb) return [];
    try {
      if (Platform.isAndroid) {
        return await _listAndroidLogFiles();
      }
      final dir = await _desktopExportDir();
      return await _listDirFiles(dir);
    } catch (_) {
      return [];
    }
  }

  /// Lists ALL files (every type) the app has in its export tree:
  /// the root folder plus every per-feature subfolder
  /// ([exportSubfolders]). Android merges per-folder MediaStore
  /// queries; desktop walks the tree recursively. Duplicates are
  /// removed by path so overlapping folder queries stay clean.
  static Future<List<ExportedFile>> listAllFiles() async {
    if (kIsWeb) return [];
    final out = <String, ExportedFile>{};
    void absorb(List<ExportedFile> list) {
      for (final f in list) {
        if (f.name.isEmpty) continue;
        out[f.path] = f;
      }
    }

    try {
      if (Platform.isAndroid) {
        // Root + each registered per-feature folder. MediaStore queries
        // are prefix-matched, so children folders are covered too.
        final folders = <String>{appSubfolder(), ...exportSubfolders.values};
        for (final folder in folders) {
          try {
            absorb(await _listAndroidFiles(subfolder: folder, all: true));
          } catch (_) {}
        }
        return out.values.toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
      }
      final dir = await _desktopExportDir();
      absorb(await _listDirFilesDeep(dir));
      return out.values.toList()
        ..sort((a, b) => b.modified.compareTo(a.modified));
    } catch (_) {
      return out.values.toList();
    }
  }

  /// Recursively lists files under [dir] (all types, follows the export
  /// tree on desktop). Never throws.
  static Future<List<ExportedFile>> _listDirFilesDeep(Directory dir) async {
    final files = <ExportedFile>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            final stat = await e.stat();
            final name = e.path.split(Platform.pathSeparator).last;
            files.add(ExportedFile(
              name: name,
              path: e.path,
              sizeBytes: stat.size,
              modified: stat.modified,
              relPath: e.path.startsWith(dir.path)
                  ? e.path.substring(dir.path.length + 1)
                  : null,
            ));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return files;
  }

  /// Android: list files via MediaStore or direct Downloads path.
  /// [subfolder] overrides [appSubfolder] (used by the deep listing).
  static Future<List<ExportedFile>> _listAndroidFiles(
      {bool all = false, String? subfolder}) async {
    final folder = (subfolder == null || subfolder.isEmpty)
        ? appSubfolder()
        : subfolder;
    // A user-picked SAF folder wins (saves go there).
    try {
      final hive = Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;
      final treeUri = hive?.getSetting<String>(AppConstants.keyExportTreeUri) ?? '';
      if (treeUri.isNotEmpty && folder == appSubfolder()) {
        final ok = await _androidChannel.invokeMethod<bool>('checkTreeFolderAccess', {'treeUri': treeUri});
        if (ok == true) {
          final results = await _androidChannel.invokeMethod<List>('listTreeFiles', {'treeUri': treeUri});
          if (results != null) {
            return results
                .map((m) => ExportedFile.fromMap(Map<String, dynamic>.from(m)))
                .where((f) => f.name.isNotEmpty && (all || f.name.endsWith('.txt') || f.name.endsWith('.log')))
                .toList();
          }
        }
      }
    } catch (_) {}
    try {
      final results = await _androidChannel.invokeMethod<List>(
          'listExportFiles', {'subfolder': folder, 'all': all});
      if (results != null) {
        return results
            .map((m) => ExportedFile.fromMap(Map<String, dynamic>.from(m)))
            .where((f) => f.name.isNotEmpty && (all || f.name.endsWith('.txt') || f.name.endsWith('.log')))
            .toList();
      }
    } catch (_) {}
    // Fallback: try listing via the Documents directory
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sub = Directory('${docs.path}${Platform.pathSeparator}$folder');
      if (await sub.exists()) return await _listDirFiles(sub, all: all);
    } catch (_) {}
    return [];
  }

  /// Lists files in a directory.
  static Future<List<ExportedFile>> _listDirFiles(Directory dir, {bool all = false}) async {
    final files = <ExportedFile>[];
    await for (final f in dir.list(followLinks: false)) {
      if (f is File) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (all || name.endsWith('.txt') || name.endsWith('.log')) {
          final stat = await f.stat();
          files.add(ExportedFile(
            name: name,
            path: f.path,
            sizeBytes: stat.size,
            modified: stat.modified,
          ));
        }
      }
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// Android: list .txt/.log files via MediaStore or direct Downloads path.
  static Future<List<ExportedFile>> _listAndroidLogFiles() => _listAndroidFiles(all: false);

  /// Deletes a saved file by path. Content/tree URIs (MediaStore, SAF)
  /// go through the native side — direct File access can't touch them
  /// under scoped storage.
  static Future<bool> deleteFile(String path) async {
    try {
      if (!kIsWeb &&
          Platform.isAndroid &&
          (path.startsWith('content://'))) {
        final ok = await _androidChannel.invokeMethod<bool>(
            'deleteExportFile', {'uri': path});
        return ok == true;
      }
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Reads a saved export file. Content/tree URIs go through the native
  /// side; plain paths read directly. Returns null on failure.
  static Future<Uint8List?> readExportFile(String path) async {
    try {
      if (!kIsWeb &&
          Platform.isAndroid &&
          (path.startsWith('content://'))) {
        final bytes = await _androidChannel.invokeMethod<List>(
            'readExportFile', {'uri': path});
        if (bytes == null) return null;
        return Uint8List.fromList(bytes.cast<int>());
      }
      final f = File(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }


}

/// Metadata for a saved export file.
class ExportedFile {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;

  /// Relative path inside the export tree when the platform provides
  /// one (desktop walk / MediaStore RELATIVE_PATH). Null otherwise.
  final String? relPath;

  ExportedFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    this.relPath,
  });

  factory ExportedFile.fromMap(Map<String, dynamic> m) {
    final mod = m['modified'];
    DateTime parsed;
    if (mod is DateTime) {
      parsed = mod;
    } else if (mod is int) {
      parsed = DateTime.fromMillisecondsSinceEpoch(mod);
    } else {
      parsed = DateTime.tryParse(mod?.toString() ?? '') ?? DateTime.now();
    }
    return ExportedFile(
      name: m['name']?.toString() ?? '',
      path: m['uri']?.toString() ?? m['path']?.toString() ?? '',
      sizeBytes: m['size'] is int ? m['size'] : 0,
      modified: parsed,
      relPath: m['relPath']?.toString(),
    );
  }

  /// Lowercase extension without the dot ('' when none).
  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  /// Broad kind bucket driving the icon/color in the Saved Files tree.
  String get kind {
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'heic':
      case 'bmp':
      case 'svg':
        return 'image';
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return 'video';
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'aac':
      case 'ogg':
      case 'flac':
        return 'audio';
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return 'archive';
      case 'pptx':
      case 'ppt':
        return 'slides';
      case 'docx':
      case 'doc':
        return 'docs';
      case 'json':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'csv':
        return 'data';
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'kt':
      case 'java':
      case 'html':
      case 'css':
      case 'php':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'rb':
      case 'sh':
        return 'code';
      case 'txt':
      case 'log':
      case 'md':
      case 'markdown':
        return 'text';
      default:
        return 'other';
    }
  }

  /// Folder this file lives in, relative to the export root (e.g.
  /// 'System Logs'). Best effort from [relPath] or the plain path.
  String get folderLabel {
    final rel = relPath;
    if (rel != null && rel.isNotEmpty) {
      final parts = rel.split('/');
      return parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
    }
    if (!path.startsWith('content://')) {
      final norm = path.replaceAll('\\', '/');
      final marker = ExportFile.appSubfolder();
      final i = norm.indexOf('$marker/');
      if (i >= 0) {
        final tail = norm.substring(i + marker.length + 1);
        final parts = tail.split('/');
        return parts.length > 1
            ? parts.sublist(0, parts.length - 1).join('/')
            : '';
      }
    }
    return '';
  }

  String get sizeLabel {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String get dateLabel {
    final now = DateTime.now();
    final diff = now.difference(modified);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
  }
}
