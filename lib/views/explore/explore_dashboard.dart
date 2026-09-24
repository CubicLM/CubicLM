/// Explore → Dashboard scope: greeting, full Active Intelligence (rings,
/// RAM zone, chip advice — everything the old standalone card had),
/// downloaded-models framed box with search, usage stats, shortcuts.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../core/routes.dart';
import '../../models/ai_model.dart';
import '../../services/chip_advice.dart';
import '../../services/device_info_service.dart';
import '../../services/inference_service.dart';
import '../../services/soc_family.dart';
import '../hub/hub_widgets.dart';
import 'local_model_card.dart';

/// Dashboard page content hosted inside Explore (ModelView).
class ExploreDashboard extends StatelessWidget {
  const ExploreDashboard({super.key});

  HomeController? get _home {
    try {
      return Get.find<HomeController>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // ── Reactive inputs up front ──
      ProfileController? profile;
      InferenceService? inference;
      DeviceInfoService? dev;
      ChatController? chat;
      ModelController? models;
      try {
        profile = Get.find<ProfileController>();
      } catch (_) {}
      try {
        inference = Get.find<InferenceService>();
      } catch (_) {}
      try {
        dev = Get.find<DeviceInfoService>();
      } catch (_) {}
      try {
        chat = Get.find<ChatController>();
      } catch (_) {}
      try {
        models = Get.find<ModelController>();
      } catch (_) {}

      final greeting = profile?.greetingNow() ?? 'Hello';
      final modelLoaded = inference?.isModelLoaded.value ?? false;
      final modelName = inference?.loadedModelName.value ?? '';
      final gpu = inference?.isGpuAccelerated.value ?? false;
      final gpuName = inference?.gpuName.value ?? '';
      final ctxUsed = inference?.contextTokensUsed.value ?? 0;
      final ctxTotal = inference?.contextTokensTotal.value ?? 0;
      final totalRam = dev?.totalRamGB.value ?? 0.0;
      final availRam = dev?.availableRamGB.value ?? 0.0;
      final chatCount = chat?.sessions.length ?? 0;
      final modelCount = models?.downloadedCount ?? 0;
      double? tps;
      try {
        final res = models?.benchmarkFor(modelName);
        tps = (res?['tps'] as num?)?.toDouble();
      } catch (_) {}
      final advice = adviseChip(
        family: dev?.socFamily.value ?? SocFamily.unknown,
        processorName: dev?.processorName.value ?? '',
        socHardware: dev?.socHardware.value ?? '',
        totalRamGb: totalRam,
      );
      final backend = gpu ? 'GPU · $gpuName' : 'CPU Neural Engine';
      final tier = dev?.deviceTier.value ?? '';
      final tierLabel =
          tier.isEmpty ? '' : '${tier[0].toUpperCase()}${tier.substring(1)}';
      final roomMb = ((availRam - 0.25) / 1.25 * 1024).round();
      String? quant;
      try {
        quant = Get.find<SettingsController>().recommendedQuantization;
      } catch (_) {}
      String? best;
      try {
        best = models?.bestBenchmarkedFilename();
      } catch (_) {}

      final ramFrac =
          totalRam > 0 ? ((totalRam - availRam) / totalRam).clamp(0.0, 1.0) : 0.0;
      final ctxFrac =
          ctxTotal > 0 ? (ctxUsed / ctxTotal).clamp(0.0, 1.0) : 0.0;

      // No own ListView: this renders inline inside ModelView's outer
      // ListView (nested scrollables break). Only the downloaded frame
      // below owns a fixed-height inner scroll.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(_todayLine(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          const HubSectionTitle('Active Intelligence'),
          _activeCard(context,
              loaded: modelLoaded,
              name: modelName,
              backend: backend,
              ctxUsed: ctxUsed,
              ctxTotal: ctxTotal,
              tps: tps,
              ramFrac: ramFrac,
              ctxFrac: ctxFrac,
              availRam: availRam,
              totalRam: totalRam,
              tierLabel: tierLabel,
              roomMb: roomMb,
              quant: quant,
              best: best,
              advice: advice,
              onRefresh: () {
                try {
                  dev?.refreshMemoryInfo();
                } catch (_) {}
              }),
          const SizedBox(height: 20),
          const HubSectionTitle('Downloaded Models'),
          const _DownloadedFrame(),
          const SizedBox(height: 20),
          const HubSectionTitle('Usage'),
          Row(children: [
            Expanded(
                child: HubStatTile(
                    value: '$chatCount',
                    caption: 'Chats',
                    icon: LucideIcons.messageSquare)),
            const SizedBox(width: 10),
            Expanded(
                child: HubStatTile(
                    value: '$modelCount',
                    caption: 'Models on device',
                    icon: LucideIcons.download)),
            const SizedBox(width: 10),
            Expanded(
                child: HubStatTile(
                    value: ctxTotal > 0 ? '$ctxTotal' : '—',
                    caption: 'Context window',
                    icon: LucideIcons.brainCircuit)),
          ]),
          const SizedBox(height: 20),
          const HubSectionTitle('Features'),
          _featureGrid(context, chatCount, modelCount),
          const SizedBox(height: 16),
        ],
      );
    });
  }

  /// "Wednesday, 24 September" — hand-rolled (no intl dependency).
  String _todayLine() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  Widget _activeCard(
    BuildContext context, {
    required bool loaded,
    required String name,
    required String backend,
    required int ctxUsed,
    required int ctxTotal,
    required double? tps,
    required double ramFrac,
    required double ctxFrac,
    required double availRam,
    required double totalRam,
    required String tierLabel,
    required int roomMb,
    required String? quant,
    required String? best,
    required ChipAdvice advice,
    required VoidCallback onRefresh,
  }) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usedRam = (totalRam - availRam).clamp(0.0, totalRam);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.cpu, color: primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loaded ? name : 'No local model loaded',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (loaded)
              const Icon(LucideIcons.checkCircle,
                  color: AppColors.success, size: 22)
            else
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).hintColor.withValues(alpha: 0.35),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            loaded
                ? '$backend${ctxTotal > 0 ? ' · ctx $ctxTotal' : ''}${tps != null ? ' · ${tps.toStringAsFixed(1)} tok/s' : ''}'
                : 'Pick a model below to run it on this device',
            style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              HubRing(
                fraction: ramFrac,
                center: '${(ramFrac * 100).round()}%',
                label: totalRam > 0
                    ? 'RAM · ${availRam.toStringAsFixed(1)} free'
                    : 'RAM',
                color: ramFrac > 0.85 ? AppColors.warning : primary,
              ),
              HubRing(
                fraction: ctxFrac,
                center: ctxTotal > 0 ? '${(ctxFrac * 100).round()}%' : '—',
                label: ctxTotal > 0 ? 'Context · $ctxUsed used' : 'Context',
                color: ctxFrac > 0.9 ? AppColors.warning : primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          // ── RAM zone: label + tier + refresh + info ──
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
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tierLabel,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: primary)),
              ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(LucideIcons.refreshCw, size: 14),
              ),
            ),
            InkWell(
              onTap: () => _showHubInfoDialog(context,
                  totalGb: totalRam,
                  availGb: availRam,
                  usedGb: usedRam,
                  roomMb: roomMb,
                  tierLabel: tierLabel,
                  advice: advice,
                  modelLine: loaded
                      ? '$name · $backend${ctxTotal > 0 ? ' · ctx $ctxTotal' : ''}'
                      : null),
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
                widthFactor: ramFrac,
                child: Container(
                    color: ramFrac > 0.85 ? AppColors.warning : primary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${usedRam.toStringAsFixed(1)} GB used',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor)),
            const Spacer(),
            Text(
                '${availRam.toStringAsFixed(1)} GB free of ${totalRam.toStringAsFixed(1)} GB',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: availRam < 1.5 ? AppColors.warning : null)),
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
          const SizedBox(height: 12),
          Container(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.cpu,
                  size: 15, color: Theme.of(context).hintColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${advice.chipLabel} · ${advice.quantLine} · ${advice.sizeLine}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Full explainer dialog: every number on the card, what it means, and
  /// what to do about it (chip WHY included).
  void _showHubInfoDialog(
    BuildContext context, {
    required double totalGb,
    required double availGb,
    required double usedGb,
    required int roomMb,
    required String tierLabel,
    required ChipAdvice advice,
    required String? modelLine,
  }) {
    final needForRoom =
        roomMb > 0 ? (roomMb * 1.25 / 1024 + 0.25) : availGb;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Active Intelligence'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (modelLine != null)
                _hubInfoRow('Active model', modelLine),
              _hubInfoRow('Total RAM',
                  '${totalGb.toStringAsFixed(1)} GB — your phone\u2019s full memory.'),
              _hubInfoRow('Used',
                  '${usedGb.toStringAsFixed(1)} GB — Android system plus all running apps.'),
              _hubInfoRow('Free',
                  '${availGb.toStringAsFixed(1)} GB — free right now and available for loading a model.'),
              _hubInfoRow(
                  roomMb > 0 ? 'Room for ≈$roomMb MB' : 'No room right now',
                  roomMb > 0
                      ? 'A model file up to ≈$roomMb MB should load (file size × 1.25 working space + safety reserve ≈ ${needForRoom.toStringAsFixed(1)} GB free needed).'
                      : 'Free space is below the safety reserve — close other apps, then tap refresh.'),
              if (tierLabel.isNotEmpty)
                _hubInfoRow('Tier: $tierLabel',
                    'Your device class. Higher tiers run bigger models with longer context windows.'),
              _hubInfoRow('Chip: ${advice.chipLabel}',
                  '${advice.quantLine}. ${advice.sizeLine}.\n\n${advice.explainWhy}${advice.warning != null ? '\n\n${advice.warning}' : ''}'),
              _hubInfoRow('Tips',
                  '• Close heavy apps before loading\n• Prefer smaller (Q4) models on low RAM\n• Rings turn warning-colored past 85–90% — that\u2019s your cue to free space or trim context'),
              _hubInfoRow('Strict RAM guard',
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

  Widget _hubInfoRow(String title, String body) {
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
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  Widget _featureGrid(BuildContext context, int chatCount, int modelCount) {
    final home = _home;
    Tile go(String label, IconData icon, VoidCallback onTap, [String? sub]) =>
        Tile(label: label, icon: icon, onTap: onTap, sub: sub);
    final tiles = <Tile>[
      go('New Chat', LucideIcons.messageSquarePlus, () {
        home?.changeTab(0);
        try {
          Get.find<ChatController>().createNewChat();
        } catch (_) {}
      }, '$chatCount chats'),
      go('Local Models', LucideIcons.download, () {
        try {
          Get.find<ModelController>().modelScope.value = 'local';
        } catch (_) {}
        home?.changeTab(1);
      }, '$modelCount on device'),
      go('Cloud Models', LucideIcons.cloud, () {
        try {
          Get.find<ModelController>().modelScope.value = 'online';
        } catch (_) {}
        home?.changeTab(1);
      }),
      go('Toolkit', LucideIcons.wrench, () => home?.changeTab(2)),
      go('Personalize', LucideIcons.palette,
          () => Get.toNamed(AppRoutes.personalization)),
      go('Settings', LucideIcons.settings, () => home?.changeTab(3)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 96,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }
}

/// Single feature shortcut tile.
class Tile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? sub;

  const Tile(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.sub});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).primaryColor),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (sub != null)
              Text(sub!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Downloaded-models framed box with search, shown under Active
/// Intelligence on the Dashboard. Fixed height with its own scroll so the
/// page keeps moving.
class _DownloadedFrame extends StatefulWidget {
  const _DownloadedFrame();

  @override
  State<_DownloadedFrame> createState() => _DownloadedFrameState();
}

class _DownloadedFrameState extends State<_DownloadedFrame> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(LucideIcons.download,
                size: 15, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Obx(() {
                var n = 0;
                try {
                  n = Get.find<ModelController>().downloadedCount;
                } catch (_) {}
                return Text('Downloaded models ($n)',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis);
              }),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search downloaded models…',
              prefixIcon: const Icon(LucideIcons.search, size: 17),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 300,
            child: Obx(() {
              List<AiModel> items = const [];
              try {
                final mc = Get.find<ModelController>();
                items = mc.displayedModels
                    .where((m) => mc.isDownloaded(m.filename))
                    .where((m) =>
                        _query.isEmpty ||
                        m.name.toLowerCase().contains(_query) ||
                        m.filename.toLowerCase().contains(_query))
                    .toList();
              } catch (_) {}
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.download,
                          size: 36,
                          color: Theme.of(context)
                              .hintColor
                              .withValues(alpha: 0.6)),
                      const SizedBox(height: 10),
                      Text(
                        _query.isEmpty
                            ? 'No models downloaded yet.'
                            : 'No match for “$_query”.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).hintColor),
                      ),
                      if (_query.isEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            try {
                              Get.find<ModelController>()
                                  .modelScope
                                  .value = 'local';
                            } catch (_) {}
                          },
                          icon: const Icon(LucideIcons.download, size: 17),
                          label: Text('Download models',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    buildModelCard(context, items[i]),
              );
            }),
          ),
        ],
      ),
    );
  }
}
