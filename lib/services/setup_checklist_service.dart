/// CubicLM Setup Checklist — first-launch recommendations (Mobile-Harness
/// setup parity: notifications, battery reliability, runtime, cloud key,
/// on-device model).
///
/// Everything here is OPTIONAL and skippable — the checklist only reports
/// status and deep-links actions; it never blocks. Pure status helpers so
/// both the onboarding page and Settings reuse them. Never throws.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/cloud_model_controller.dart';
import '../core/constants.dart';
import 'download_service.dart';
import 'runtime/runtime_installer.dart';

/// One checklist item's live status.
enum SetupItemState {
  /// Satisfied (green check).
  done,

  /// Needs attention (amber dot).
  todo,

  /// Cannot be evaluated here (service not running) — treated as todo
  /// without an error.
  unknown,
}

/// Status + actions for the first-launch recommendations page.
class SetupChecklist {
  static const _powerChannel = MethodChannel('com.cubiclm.app/power');

  /// Battery/notification rows only make sense on Android.
  static bool get isAndroid =>
      !kIsWeb && Platform.isAndroid;

  /// Isolated-runtime installs need Android (PRoot + ARM64 rootfs).
  /// Config-page install buttons honor this instead of failing.
  static bool get supportsRuntimeInstall => isAndroid;

  /// Notifications row needs a working permission surface: Android
  /// runtime permission or the Web Notification API. Windows/macOS/Linux
  /// builds use a notification stub, so the row would be dead UI there.
  static bool get supportsNotifications {
    if (kIsWeb) return true;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  // ── Notifications ──────────────────────────────────────────────

  /// True when task-progress notifications can be shown.
  static Future<SetupItemState> notifications() async {
    try {
      final status = await Permission.notification.status.timeout(
        const Duration(seconds: 5),
      );
      if (status.isGranted || status.isLimited) return SetupItemState.done;
      return SetupItemState.todo;
    } catch (_) {
      return SetupItemState.unknown;
    }
  }

  /// Ask for the permission. Returns true when granted afterwards.
  static Future<bool> requestNotifications() async {
    try {
      var status = await Permission.notification.status.timeout(
        const Duration(seconds: 5),
      );
      if (status.isGranted || status.isLimited) return true;
      status = await Permission.notification.request().timeout(
            const Duration(minutes: 2),
          );
      return status.isGranted || status.isLimited;
    } catch (_) {
      return false;
    }
  }

  /// Open the app's system notification settings (user denied twice).
  static Future<void> openNotificationSettings() async {
    try {
      await openAppSettings().timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  // ── Battery reliability (Android only) ─────────────────────────

  /// True when the OS won't throttle CubicLM in the background.
  static Future<SetupItemState> battery() async {
    if (!isAndroid) return SetupItemState.done;
    try {
      final ok = await _powerChannel
          .invokeMethod<bool>('isBatteryUnrestricted')
          .timeout(const Duration(seconds: 5));
      return ok == true ? SetupItemState.done : SetupItemState.todo;
    } catch (_) {
      return SetupItemState.unknown;
    }
  }

  /// Open the system battery-optimization settings. Returns true when a
  /// settings page was launched.
  static Future<bool> openBatterySettings() async {
    if (!isAndroid) return false;
    try {
      final ok = await _powerChannel
          .invokeMethod<bool>('openBatterySettings')
          .timeout(const Duration(seconds: 5));
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Developer options (reference-app "Advanced runtime
  /// reliability" parity): some devices gate child-process execution
  /// behind a developer toggle that kills large builds. Falls back to
  /// the main Settings page. Android only. Never throws.
  static Future<bool> openDeveloperOptions() async {
    if (!isAndroid) return false;
    try {
      final ok = await _powerChannel
          .invokeMethod<bool>('openDeveloperOptions')
          .timeout(const Duration(seconds: 5));
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  // ── Agent runtime ──────────────────────────────────────────────

  /// True when the Core Ubuntu toolchain is installed.
  static Future<SetupItemState> runtimeCore() async {
    try {
      if (!Get.isRegistered<RuntimeInstaller>()) {
        return SetupItemState.unknown;
      }
      return await Get.find<RuntimeInstaller>().isCoreReady
          ? SetupItemState.done
          : SetupItemState.todo;
    } catch (_) {
      return SetupItemState.unknown;
    }
  }

  // ── Cloud key ──────────────────────────────────────────────────

  /// True when any provider has a saved API key.
  static Future<SetupItemState> cloudKey() async {
    try {
      if (!Get.isRegistered<CloudModelController>()) {
        return SetupItemState.unknown;
      }
      final c = Get.find<CloudModelController>();
      final any =
          c.providers.any((p) => c.apiKeyFor(p.id).isNotEmpty);
      return any ? SetupItemState.done : SetupItemState.todo;
    } catch (_) {
      return SetupItemState.unknown;
    }
  }

  // ── On-device model ────────────────────────────────────────────

  /// True when at least one catalog model file is downloaded.
  static Future<SetupItemState> localModel() async {
    try {
      if (!Get.isRegistered<DownloadService>()) {
        return SetupItemState.unknown;
      }
      final dl = Get.find<DownloadService>();
      for (final m in AppConstants.availableModels) {
        final name = m['filename'] ?? '';
        if (name.isEmpty) continue;
        try {
          if (await dl.isModelDownloaded(name)) {
            return SetupItemState.done;
          }
        } catch (_) {}
      }
      return SetupItemState.todo;
    } catch (_) {
      return SetupItemState.unknown;
    }
  }
}
