///
/// Previously two separate widgets (active-model banner + RAM bar +
/// advice row); now one card, one file, more signal:
/// - Active zone: loaded local/cloud model, backend, context window,
///   last measured tok/s (when benchmarked), or an empty state.
/// - RAM zone (local scope, load-capable platforms only): used/free
///   bar, tier chip, refresh, room-for-model estimate, quant advice,
///   fastest-benchmark note, and the explainer dialog.
/// All services resolve via Get with guards — missing services render
/// nothing instead of red-screening.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/cloud_model_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../services/chip_advice.dart';
import '../../services/device_info_service.dart';
import '../../services/inference_service.dart';
import '../../services/local_image_service.dart';
import '../../services/soc_family.dart';

/// Combined Active Intelligence + RAM Status card for the Explore hub.

class DeviceIntelligenceCard extends StatelessWidget {
  const DeviceIntelligenceCard({super.key});

  ModelController? get _models {
    try {
      return Get.find<ModelController>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mc = _models;
    if (mc == null) return const SizedBox.shrink();
    return Obx(() {
      // Read every reactive input up front: returning before any Rx
      // read trips GetX's empty-scope error.
      final scope = mc.modelScope.value;
      final online = scope == 'online';
      DeviceInfoService? dev;
      try {
        dev = Get.find<DeviceInfoService>();
      } catch (_) {}
      final total = dev?.totalRamGB.value ?? 0.0;
      final avail = dev?.availableRamGB.value ?? 0.0;
      final tier = dev?.deviceTier.value ?? '';
      mc.bestBenchmarkedFilename();
      if (online) return _cloudZone(context, mc);
      return _localZone(context, mc, total, avail, tier);
    });
  }

  // ── Active zone: cloud ──────────────────────────────────────────

  Widget _cloudZone(BuildContext context, ModelController mc) {
    SettingsController? settings;
    CloudModelController? clouds;
    try {
      settings = Get.find<SettingsController>();
      clouds = Get.find<CloudModelController>();
    } catch (_) {}
    final providerId = settings?.cloudProvider.value ?? '';
    final provider = clouds?.providers.firstWhereOrNull(
      (p) => p.id == providerId,
    );
    final providerName = providerId == 'custom'
        ? (settings?.customCloudName.value ?? 'Custom')
        : (provider?.name ?? providerId);
    final model = clouds?.activeModelFor(providerId) ?? '';
    final hasModel =
        (clouds?.canSelectModel(providerId) ?? false) && model.isNotEmpty;
    return _shell(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(
            context,
            icon: Icons.cloud_done,
            label: 'ACTIVE INTELLIGENCE',
            trailing: const Icon(Icons.check_circle,
                color: AppColors.success, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'Cloud · $providerName',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            hasModel ? model : 'No cloud model selected',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Active + RAM zones: local ───────────────────────────────────

  Widget _localZone(BuildContext context, ModelController mc, double total,
      double avail, String tier) {
    InferenceService? inference;
    LocalImageService? localImage;
    try {
      inference = Get.find<InferenceService>();
      localImage = Get.find<LocalImageService>();
    } catch (_) {}
    final isImage = localImage?.isModelLoaded.value ?? false;
    final isText = inference?.isModelLoaded.value ?? false;
    final name = isImage
        ? (localImage?.loadedModelName.value ?? '')
        : (inference?.loadedModelName.value ?? '');
    final useGpu = isImage
        ? (localImage?.isUsingGpu.value ?? false)
        : (inference?.isGpuAccelerated.value ?? false);
    final backend = isImage
        ? (useGpu ? 'GPU Accelerated Rendering' : 'CPU Image Synthesis')
        : (useGpu
            ? 'GPU · ${inference?.gpuName.value ?? ''}'
            : 'CPU Neural Engine');
    final ctx = inference?.contextTokensTotal.value ?? 0;
    double? tps;
    try {
      final res = mc.benchmarkFor(name);
      tps = (res?['tps'] as num?)?.toDouble();
    } catch (_) {}
    final showRam = mc.canLoadLocal && total > 0;

    return _shell(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(
            context,
            icon: useGpu ? LucideIcons.zap : LucideIcons.cpu,
            label: 'ACTIVE INTELLIGENCE',
            trailing: (isImage || isText)
                ? const Icon(LucideIcons.checkCircle,
                    color: AppColors.success, size: 22)
                : _idleDot(context),
          ),
          const SizedBox(height: 6),
          Text(
            (isImage || isText) ? name : 'No local model loaded',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            (isImage || isText)
                ? '$backend${ctx > 0 ? ' · ctx $ctx' : ''}${tps != null ? ' · ${tps.toStringAsFixed(1)} tok/s' : ''}'
                : 'Pick a model below to run it on this device',
            style: GoogleFonts.firaCode(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showRam) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            _ramZone(context, mc, total, avail, tier),
          ],
        ],
      ),
    );
  }

  Widget _idleDot(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).hintColor.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _shell(BuildContext context, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: child,
    );
  }

  Widget _headerRow(BuildContext context,
      {required IconData icon,
      required String label,
      required Widget trailing}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: Theme.of(context).primaryColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing,
      ],
    );
  }

  // ── RAM zone ────────────────────────────────────────────────────

  Widget _ramZone(BuildContext context, ModelController mc, double total,
      double avail, String tier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final used = (total - avail).clamp(0.0, total);
    final pct = (used / total).clamp(0.0, 1.0);
    final low = avail < 1.5;
    final barColor = low
        ? AppColors.warning
        : avail < 3.0
            ? AppColors.primary
            : Theme.of(context).primaryColor;
    final tierLabel =
        tier.isEmpty ? '' : '${tier[0].toUpperCase()}${tier.substring(1)}';
    final roomMb = ((avail - 0.25) / 1.25 * 1024).round();
    String? quant;
    try {
      quant = Get.find<SettingsController>().recommendedQuantization;
    } catch (_) {}
    String? best;
    try {
      best = mc.bestBenchmarkedFilename();
    } catch (_) {}
    DeviceInfoService? dev;
    try {
      dev = Get.find<DeviceInfoService>();
    } catch (_) {}
    final chipLabel = dev?.processorName.value ?? '';
    final socFam = dev?.socFamily.value ?? SocFamily.unknown;
    final advice = adviseChip(
      family: socFam,
      processorName: chipLabel,
      socHardware: dev?.socHardware.value ?? '',
      totalRamGb: total,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(LucideIcons.memoryStick, size: 15),
          const SizedBox(width: 8),
          Text('RAM Status',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (tierLabel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tierLabel,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).primaryColor)),
            ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              try {
                dev?.refreshMemoryInfo();
              } catch (_) {}
            },
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(LucideIcons.refreshCw, size: 14),
            ),
          ),
          InkWell(
            onTap: () => _showRamInfoDialog(context,
                totalGb: total,
                availGb: avail,
                usedGb: used,
                roomMb: roomMb,
                tierLabel: tierLabel,
                advice: advice),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(LucideIcons.info, size: 14),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 8,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: Container(color: barColor),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('${used.toStringAsFixed(1)} GB used',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).hintColor)),
          const Spacer(),
          Text(
              '${avail.toStringAsFixed(1)} GB free of ${total.toStringAsFixed(1)} GB',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: low ? AppColors.warning : null)),
        ]),
        const SizedBox(height: 4),
        Text(
          roomMb > 0
              ? 'Room for ≈$roomMb MB${quant != null ? ' · $quant' : ''}${best != null ? ' · ⚡ $best' : ''}'
              : 'Memory critically low — close other apps before loading',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: roomMb > 0 ? FontWeight.w500 : FontWeight.w600,
              color: roomMb > 0
                  ? Theme.of(context).hintColor
                  : AppColors.warning),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
        const SizedBox(height: 10),
        _chipAdviceRow(context, advice),
      ],
    );
  }

  /// Smart per-device recommendation: names the actual chip ("Snapdragon
  /// 845"), says which quants it handles and which size to stick to.
  Widget _chipAdviceRow(BuildContext context, ChipAdvice advice) {
    final sub = Theme.of(context).hintColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(LucideIcons.cpu,
              color: Theme.of(context).primaryColor, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                advice.chipLabel,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                advice.quantLine,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w500, color: sub),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                advice.sizeLine,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w600, color: sub),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (advice.warning != null) ...[
                const SizedBox(height: 2),
                Text(
                  advice.warning!,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showRamInfoDialog(
    BuildContext context, {
    required double totalGb,
    required double availGb,
    required double usedGb,
    required int roomMb,
    required String tierLabel,
    required ChipAdvice advice,
  }) {
    final needForRoom =
        roomMb > 0 ? (roomMb * 1.25 / 1024 + 0.25) : availGb;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('RAM Status'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ramInfoRow('Total RAM',
                  '${totalGb.toStringAsFixed(1)} GB — your phone\'s full memory.'),
              _ramInfoRow('Used',
                  '${usedGb.toStringAsFixed(1)} GB — Android system plus all running apps.'),
              _ramInfoRow('Free',
                  '${availGb.toStringAsFixed(1)} GB — free right now and available for loading a model.'),
              _ramInfoRow(
                  roomMb > 0 ? 'Room for ≈$roomMb MB' : 'No room right now',
                  roomMb > 0
                      ? 'With your current free space, a model file up to ≈$roomMb MB should load. A model needs its file size × 1.25 as working space, plus a 256 MB–1 GB safety reserve (small models need less) — so ≈$roomMb MB needs about ${needForRoom.toStringAsFixed(1)} GB free.'
                      : 'Free space is below the safety reserve, so no model can load safely yet. Close other apps, then tap refresh.'),
              if (tierLabel.isNotEmpty)
                _ramInfoRow('Tier: $tierLabel',
                    'Your device class. Higher tiers can run bigger models with longer context windows.'),
              _ramInfoRow('Chip: ${advice.chipLabel}',
                  '${advice.quantLine}. ${advice.sizeLine}.${advice.warning != null ? ' ${advice.warning}' : ''}'),
              _ramInfoRow('Tips',
                  '• Close heavy apps before loading\n• Prefer smaller (Q4) models on low RAM\n• If a load is blocked, free space or pick a smaller file\n• Power users: Settings → Strict RAM guard can downgrade blocks to confirmed risky loads'),
              _ramInfoRow('Strict RAM guard',
                  'ON blocks loads that would crash the app; OFF asks to proceed anyway instead. Change it in Settings → Strict RAM guard.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _ramInfoRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}
