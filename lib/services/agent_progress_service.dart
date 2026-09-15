/// CubicLM Agentic Workspace — agent run progress notification.
///
/// Mirrors the reference app's foreground progress: while the agent runs,
/// an ongoing Android notification shows the latest step (throttled so
/// each update is cheap). Everything is best-effort and silent on
/// non-Android platforms or when permissions are missing.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

/// Ongoing notification for agent runs (registered in main deferred init).
class AgentProgressService extends GetxService {
  static const int _notificationId = 4301;
  static const String _channelId = 'agent_progress';
  static const String _channelName = 'Agent progress';
  static const int minUpdateGapMs = 2500;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _lastUpdateMs = 0;

  Future<AgentProgressService> init() async {
    await _ensureInit();
    return this;
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      if (!Platform.isAndroid) return;
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _notifications.initialize(settings: settings);
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Live progress of agent runs',
              importance: Importance.low,
            ),
          );
      _initialized = true;
    } catch (_) {}
  }

  /// Pure throttle check (public for unit tests).
  static bool shouldUpdate(int lastMs, int nowMs,
      {int minGapMs = minUpdateGapMs}) {
    if (lastMs <= 0) return true; // first call always fires
    return nowMs - lastMs >= minGapMs;
  }

  /// Show (or refresh, throttled) the ongoing "agent running" notification.
  Future<void> showStarted(String title) async {
    if (!Platform.isAndroid) return;
    await _ensureInit();
    if (!_initialized) return;
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    await _show(title, 'Starting…', ongoing: true);
  }

  /// Refresh the detail line with the latest tool (throttled).
  Future<void> showProgress(String detail) async {
    if (!Platform.isAndroid || !_initialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!shouldUpdate(_lastUpdateMs, now)) return;
    _lastUpdateMs = now;
    await _show('Agent running', detail, ongoing: true);
  }

  /// Replace the ongoing notification with a final result (auto-dismiss).
  Future<void> showFinished(String title) async {
    if (!Platform.isAndroid || !_initialized) return;
    await _show(title, 'Tap to open the trace.', ongoing: false);
  }

  /// Remove the notification (e.g. on cancel).
  Future<void> cancel() async {
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (_) {}
  }

  Future<void> _show(String title, String body,
      {required bool ongoing}) async {
    try {
      await _notifications.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: ongoing,
            autoCancel: !ongoing,
            onlyAlertOnce: true,
          ),
        ),
      );
    } catch (_) {}
  }
}
