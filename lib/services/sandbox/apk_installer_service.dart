/// CubicLM — on-device APK installer service.
///
/// Installs a locally built/downloaded APK through Android's package
/// installer without ADB (PackageInstaller session on modern Android,
/// ACTION_INSTALL_PACKAGE fallback for MIUI/older):
/// - MethodChannel `com.cubiclm.app/apkinstaller`, method `installApk`
///   {path: String} → {ok: bool, error: String?}.
/// - Native side: MainActivity hosts the channel; on success it opens
///   a PackageInstaller session, streams the file, and commits (user
///   confirms on-device). ApkInstallReceiver forwards the system
///   confirmation dialog, auto-launches on success, and toasts failures.
/// - Desktop/web: returns an explanatory error (APK install is Android-only).
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Installs APK files on Android. Safe no-ops everywhere else.
class ApkInstallerService extends GetxService {
  static const MethodChannel _channel =
      MethodChannel('com.cubiclm.app/apkinstaller');

  Future<ApkInstallerService> init() async => this;

  /// Install the APK at [path]. Returns null on success, else an error.
  Future<String?> installApkFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return 'APK not found: $path';
    if (!path.toLowerCase().endsWith('.apk')) {
      return 'Not an APK file: $path';
    }
    try {
      final size = await file.length();
      if (size <= 0) return 'APK is empty: $path';
    } catch (e) {
      return 'Cannot read APK: $e';
    }
    if (!Platform.isAndroid) {
      return 'APK install needs Android — copy $path to your phone and tap it, or push it via the GitHub build.';
    }
    try {
      final raw = await _channel.invokeMethod<Map>('installApk', {
        'path': file.path,
      }).timeout(const Duration(seconds: 30));
      final map = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
      if (map['ok'] == true) return null;
      return (map['error'] ?? 'Installer rejected the APK.').toString();
    } on MissingPluginException {
      return 'On-device installer is not wired yet — open the APK from Downloads to install it manually.';
    } catch (e) {
      return 'Install failed: $e';
    }
  }

  /// Let the user pick an APK (SAF on Android) and install it.
  /// Returns null on success, else an error. Null pick = user cancelled
  /// (reported as 'No file picked.' so the UI can stay silent).
  Future<String?> pickAndInstall() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
        dialogTitle: 'Pick an APK to install',
      );
    } catch (e) {
      return 'File picker failed: $e';
    }
    return installPickedPath(picked?.files.single.path);
  }

  /// Install an already-picked APK path (UI layer passes the picker result).
  Future<String?> installPickedPath(String? path) async {
    if (path == null || path.isEmpty) return 'No file picked.';
    return installApkFile(path);
  }
}
