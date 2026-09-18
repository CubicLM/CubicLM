/// CubicLM Setup Recommendations — first-launch checklist
/// (Mobile-Harness setup parity: notifications, battery reliability,
/// agent runtime, cloud key, on-device model).
///
/// Everything is OPTIONAL and skippable: rows only report status and
/// deep-link actions, nothing blocks. Used as onboarding page 4 AND as a
/// standalone Settings screen ([SetupRecommendationsView]).
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/home_controller.dart';
import '../core/colors.dart';
import '../services/setup_checklist_service.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import 'runtime/runtime_setup_view.dart';

/// Standalone screen (Settings → Recommended setup).
class SetupRecommendationsView extends StatelessWidget {
  const SetupRecommendationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Recommended setup',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: SetupChecklistCard(
          onOpenExplore: () {
            try {
              Get.back();
              Get.find<HomeController>().changeTab(1);
            } catch (_) {}
          },
        ),
      ),
    );
  }
}

/// Embeddable checklist card (onboarding page + Settings screen share it).
class SetupChecklistCard extends StatefulWidget {
  /// Compact paddings for the onboarding page.
  final bool compact;

  /// Where the Explore-dependent rows (cloud key, on-device model) go.
  /// Onboarding passes finish-and-open-hub; Settings passes pop+tab.
  final VoidCallback? onOpenExplore;

  const SetupChecklistCard({
    super.key,
    this.compact = false,
    this.onOpenExplore,
  });

  @override
  State<SetupChecklistCard> createState() => _SetupChecklistCardState();
}

class _SetupChecklistCardState extends State<SetupChecklistCard>
    with WidgetsBindingObserver {
  SetupItemState _notif = SetupItemState.unknown;
  SetupItemState _battery = SetupItemState.unknown;
  SetupItemState _runtime = SetupItemState.unknown;
  SetupItemState _cloud = SetupItemState.unknown;
  SetupItemState _model = SetupItemState.unknown;
  bool _notifPermanentlyDenied = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User returns from system settings (notifications/battery) —
    // re-read statuses so chips flip without a manual refresh.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      SetupChecklist.notifications(),
      SetupChecklist.battery(),
      SetupChecklist.runtimeCore(),
      SetupChecklist.cloudKey(),
      SetupChecklist.localModel(),
    ]);
    var denied = false;
    try {
      denied = (await Permission.notification.status.timeout(
        const Duration(seconds: 5),
      ))
          .isPermanentlyDenied;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _notif = results[0];
      _battery = results[1];
      _runtime = results[2];
      _cloud = results[3];
      _model = results[4];
      _notifPermanentlyDenied = denied;
    });
  }

  int get _doneCount => [
        if (SetupChecklist.supportsNotifications) _notif,
        if (SetupChecklist.isAndroid) _battery,
        _runtime,
        _cloud,
        _model,
      ].where((s) => s == SetupItemState.done).length;

  int get _totalCount =>
      (SetupChecklist.supportsNotifications ? 1 : 0) +
      (SetupChecklist.isAndroid ? 1 : 0) +
      3;

  Future<void> _allowNotifications() async {
    if (_busy) return;
    _busy = true;
    try {
      final ok = await SetupChecklist.requestNotifications();
      if (!mounted) return;
      if (!ok) {
        AppSnackbar.showTop(
          'Notifications off',
          'Enable them in system settings for task alerts.',
        );
      }
    } finally {
      _busy = false;
    }
    await _refresh();
  }

  Future<void> _openBatterySettings() async {
    final opened = await SetupChecklist.openBatterySettings();
    if (!mounted) return;
    if (opened) {
      AppSnackbar.showTop(
        'Battery settings opened',
        'Exempt CubicLM, then come back — the chip flips on return.',
      );
    } else {
      AppSnackbar.showTop(
        'Could not open settings',
        'Find Battery → Battery optimization manually.',
      );
    }
  }

  void _openRuntime() {
    try {
      Get.to(() => const RuntimeSetupView())?.then((_) => _refresh());
    } catch (_) {}
  }

  void _openExplore() {
    try {
      widget.onOpenExplore?.call();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pad = widget.compact ? 12.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _doneCount == _totalCount
                    ? 'All set — $_doneCount of $_totalCount done'
                    : '$_doneCount of $_totalCount done · all optional',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Re-check',
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: _refresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (SetupChecklist.supportsNotifications)
          _row(
            context,
            isDark,
            pad,
            icon: LucideIcons.bellRing,
            title: 'Task notifications',
            desc:
                'Live progress while models download and a nudge when the agent finishes or needs you.',
            privacy: 'Only progress, completion and error alerts. Nothing else.',
            state: _notif,
            actionLabel: _notifPermanentlyDenied
                ? 'Open settings'
                : 'Allow',
            onAction: _notifPermanentlyDenied
                ? () => SetupChecklist.openNotificationSettings()
                : _allowNotifications,
          ),
        if (SetupChecklist.isAndroid)
          _row(
            context,
            isDark,
            pad,
            icon: LucideIcons.batteryCharging,
            title: 'Background reliability',
            desc:
                'Let CubicLM finish downloads and agent runs when you lock the phone or switch apps.',
            privacy:
                'You can stop every task from its notification. No background work without one.',
            state: _battery,
            actionLabel: 'Open battery settings',
            onAction: _openBatterySettings,
          ),
        _row(
          context,
          isDark,
          pad,
          icon: LucideIcons.terminal,
          title: 'Agent runtime (Ubuntu)',
          desc:
              'Private on-device Linux with Node, Python and toolchains for the agent workspace and terminal.',
          privacy:
              'Lives in app-private storage. No root, no system changes.',
          state: _runtime,
          actionLabel: 'Open runtimes',
          onAction: _openRuntime,
        ),
        _row(
          context,
          isDark,
          pad,
          icon: LucideIcons.cloud,
          title: 'Cloud API key',
          desc:
              'Connect OpenAI, Anthropic, OpenRouter or 20+ others for cloud chat and agents.',
          privacy: 'Keys stay encrypted on this device.',
          state: _cloud,
          actionLabel: 'Open Explore',
          onAction: _openExplore,
        ),
        _row(
          context,
          isDark,
          pad,
          icon: LucideIcons.cpu,
          title: 'On-device model',
          desc:
              'Download a model matched to your RAM for private offline chat.',
          privacy: 'Runs fully offline once downloaded.',
          state: _model,
          actionLabel: 'Open Explore',
          onAction: _openExplore,
        ),
        const SizedBox(height: 10),
        Text(
          'Everything here is optional — skip anytime and change it later from Settings.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: Theme.of(context).hintColor,
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    bool isDark,
    double pad, {
    required IconData icon,
    required String title,
    required String desc,
    required String privacy,
    required SetupItemState state,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final done = state == SetupItemState.done;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? AppColors.success.withValues(alpha: 0.35)
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Dt.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (done ? AppColors.success : Dt.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: done ? AppColors.success : Dt.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _statusChip(context, state),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: 12,
                color: Theme.of(context).hintColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  privacy,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Dt.accent,
                  side: BorderSide(
                      color: Dt.accent.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () {
                  onAction();
                  // Statuses re-read on return/refresh; also poll once in
                  // case the action completed inline (permission grant).
                  Future.delayed(
                    const Duration(seconds: 1),
                    () => _refresh(),
                  );
                },
                child: Text(
                  actionLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, SetupItemState state) {
    final done = state == SetupItemState.done;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (done ? AppColors.success : AppColors.warning)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.circle_outlined,
            size: 12,
            color: done ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            done
                ? 'Done'
                : state == SetupItemState.unknown
                    ? 'Check'
                    : 'To-do',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: done ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
