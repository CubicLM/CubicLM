import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../services/inference_service.dart';
import '../../services/notification_history_service.dart';
import '../../theme/design_tokens.dart';
import '../notification_history_view.dart';
import 'chat_format.dart';

/// Top bars (find, bell, loading, context).
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

/// Placement choices for the context-window indicator.
class ContextWindowStyle {
  static const header = 'header';
  static const composer = 'composer';
  static const ring = 'ring';
}

/// One snapshot of context usage, shared by the header bar, the
/// composer bar and the ring. Pure data — unit tested.
class ContextWindowData {
  final bool isLocal;
  final int used;
  final int total;
  final double progress;
  final String label;
  final String value;
  final bool warn;

  const ContextWindowData({
    required this.isLocal,
    required this.used,
    required this.total,
    required this.progress,
    required this.label,
    required this.value,
    required this.warn,
  });

  /// Short "380 / 512" form for tooltips.
  String get shortfall =>
      isLocal ? '$used / $total' : value;

  /// Percent text for the ring center.
  String get percentLabel =>
      '${(progress * 100).round()}%';

  static ContextWindowData local({
    required int used,
    required int total,
  }) {
    final t = total <= 0 ? 1 : total;
    final u = used.clamp(0, t);
    final pct = (u / t).clamp(0.0, 1.0).toDouble();
    return ContextWindowData(
      isLocal: true,
      used: u,
      total: t,
      progress: pct,
      label: 'Local Context Window',
      value: '${fmtK(u)} / ${fmtK(t)} tokens',
      warn: pct >= 0.8,
    );
  }

  static ContextWindowData cloud({
    required String providerLabel,
    required String modelName,
    required int sessionTokens,
  }) {
    return ContextWindowData(
      isLocal: false,
      used: sessionTokens,
      total: -1,
      progress: 0,
      label: '$providerLabel · $modelName',
      value: '${fmtK(sessionTokens)} session tokens',
      warn: false,
    );
  }
}

/// Reads the current snapshot, or null when no active session exists.
/// Single source of truth for all three placements.
ContextWindowData? readContextWindow() {
  if (_c.currentSessionId.value.isEmpty || _c.messages.isEmpty) {
    return null;
  }
  final settings = Get.find<SettingsController>();
  final isLocal = settings.inferenceMode.value == 'local';
  if (isLocal) {
    final inf = Get.find<InferenceService>();
    final total = inf.contextTokensTotal.value > 0
        ? inf.contextTokensTotal.value
        : settings.contextSize.value;
    final est = _c.messages.fold<int>(0, (s, m) => s + m.content.length);
    final used = (inf.contextTokensUsed.value > 0
            ? inf.contextTokensUsed.value
            : (est / 4).ceil())
        .clamp(0, total)
        .toInt();
    return ContextWindowData.local(used: used, total: total);
  }
  final totalChars =
      _c.messages.fold<int>(0, (s, m) => s + m.content.length);
  final providerId = settings.cloudProvider.value;
  final providerLabel = providerId == 'custom'
      ? settings.customCloudName.value
      : providerId.capitalizeFirst ?? providerId;
  return ContextWindowData.cloud(
    providerLabel: providerLabel,
    modelName: settings.selectedCloudModelName,
    sessionTokens: (totalChars / 4).ceil(),
  );
}

/// Placement-aware visibility: only the chosen surface renders.
bool showContextAt(String placement) {
  try {
    return Get.find<SettingsController>().contextWindowStyle.value ==
        placement;
  } catch (_) {
    return placement == ContextWindowStyle.header;
  }
}

Widget findBar(BuildContext context, bool isDark) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).dividerColor,
      ),
    ),
    child: Row(
      children: [
        Icon(LucideIcons.search,
            size: 18, color: Theme.of(context).colorScheme.onSurface),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _c.findController,
            autofocus: true,
            onChanged: _c.updateFind,
            onSubmitted: (_) => _c.stepFind(1),
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Find in this chat…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Theme.of(context).hintColor),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Obx(() {
          final n = _c.findMatches.length;
          final q = _c.findQuery.value;
          final label = q.isEmpty
              ? ''
              : n == 0
                  ? '0'
                  : '${_c.findIndex.value + 1}/$n';
          return Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor));
        }),
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(LucideIcons.chevronUp, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.stepFind(-1),
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(LucideIcons.chevronDown, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.stepFind(1),
        ),
        IconButton(
          tooltip: 'Close find',
          icon: const Icon(LucideIcons.x, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => _c.toggleFind(false),
        ),
      ],
    ),
  );
}

Widget notificationBell(BuildContext context, bool isDark) {
  // Never throw if DI isn't ready yet (cold-start race) — bell just
  // shows no badge until the service lands.
  if (!Get.isRegistered<NotificationHistoryService>()) {
    return IconButton(
      tooltip: 'Notifications',
      icon: Icon(LucideIcons.bell,
          size: Dt.iconSize - 2,
          color: Theme.of(context).colorScheme.onSurface),
      onPressed: () => Get.to(() => const NotificationHistoryView(),
          transition: Transition.rightToLeft,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic),
    );
  }
  final svc = Get.find<NotificationHistoryService>();
  return Obx(() {
    final unread = svc.unreadCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: Icon(LucideIcons.bell,
              size: Dt.iconSize - 2,
              color: Theme.of(context).colorScheme.onSurface),
          onPressed: () {
            svc.markAllRead();
            Get.to(() => const NotificationHistoryView(),
                transition: Transition.rightToLeft,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic);
          },
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
              ),
              child: Center(
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1),
                ),
              ),
            ),
          ),
      ],
    );
  });
}

// ── Model Loading ──
Widget modelLoadingBar(BuildContext context, bool isDark) {
  return Obx(() {
    final inf = Get.find<InferenceService>();
    if (!inf.isLoadingModel.value) return const SizedBox.shrink();
    final pct = (inf.modelLoadProgress.value * 100).toStringAsFixed(0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppColors.blurSigma, sigmaY: AppColors.blurSigma),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
            border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Theme.of(context).primaryColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Text("${'chat_sync_intelligence'.tr} $pct%",
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 14),
            Stack(
              children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        value: inf.modelLoadProgress.value,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        color: Theme.of(context).primaryColor,
                        minHeight: 6)),
                if (inf.modelLoadProgress.value > 0.05)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: inf.modelLoadProgress.value,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  });
}

// ── Context Bar ──
Widget contextBar(BuildContext context, bool isDark) {
  return Obx(() {
    if (!showContextAt(ContextWindowStyle.header)) {
      return const SizedBox.shrink();
    }
    final data = readContextWindow();
    if (data == null) return const SizedBox.shrink();

    final accent = data.isLocal
        ? (data.warn ? AppColors.warning : AppColors.primary)
        : Dt.accent;
    return _buildModernBar(
      context,
      isDark,
      icon: data.isLocal ? Icons.memory_rounded : Icons.cloud_done_rounded,
      label: data.label,
      value: data.value,
      progress: data.isLocal ? data.progress : null,
      accent: accent,
    );
  });
}

/// Compact ring indicator (percentage circle, ~34dp). Lives in the chat
/// header when the ring placement is chosen. Long-press shows the
/// numbers via tooltip; tap opens the full details sheet.
Widget contextRingButton(BuildContext context, bool isDark) {
  return Obx(() {
    if (!showContextAt(ContextWindowStyle.ring)) {
      return const SizedBox.shrink();
    }
    final data = readContextWindow();
    if (data == null) return const SizedBox.shrink();

    final accent = data.isLocal
        ? (data.warn ? AppColors.warning : AppColors.primary)
        : Dt.accent;
    return Tooltip(
      message: 'Context window: ${data.shortfall} tokens',
      child: GestureDetector(
        onTap: () => _showContextDetails(context, isDark, data),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  value: data.isLocal ? data.progress : null,
                  strokeWidth: 3,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              Text(
                data.isLocal ? data.percentLabel : '∞',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  });
}

void _showContextDetails(
    BuildContext context, bool isDark, ContextWindowData data) {
  final accent = data.isLocal
      ? (data.warn ? AppColors.warning : AppColors.primary)
      : Dt.accent;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernBar(
              ctx,
              isDark,
              icon: data.isLocal
                  ? Icons.memory_rounded
                  : Icons.cloud_done_rounded,
              label: data.label,
              value: data.value,
              progress: data.isLocal ? data.progress : null,
              accent: accent,
            ),
            if (data.warn) ...[
              const SizedBox(height: 12),
              Text(
                'Context is nearly full — start a new chat or raise Context size in Settings → Parameters.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppColors.warning),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _buildModernBar(
  BuildContext context,
  bool isDark, {
  required IconData icon,
  required String label,
  required String value,
  double? progress,
  required Color accent,
}) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.black.withValues(alpha: 0.02),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.7)
                                : Dt.textSecondary,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text(value,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: isDark ? Colors.white : Dt.textPrimary,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    color: accent,
                    minHeight: 3.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
