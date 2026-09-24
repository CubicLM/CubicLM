/// Contains: HubDashboardTab (greeting, advanced Active Intelligence with
/// rings, usage stats, feature shortcuts).
part of 'hub_view.dart';

class HubDashboardTab extends StatelessWidget {
  const HubDashboardTab({super.key});

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

      final ramFrac =
          totalRam > 0 ? ((totalRam - availRam) / totalRam).clamp(0.0, 1.0) : 0.0;
      final ctxFrac =
          ctxTotal > 0 ? (ctxUsed / ctxTotal).clamp(0.0, 1.0) : 0.0;

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(greeting,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text("Here's your setup at a glance",
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
              advice: advice),
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
          _featureGrid(context),
        ],
      );
    });
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
    required ChipAdvice advice,
  }) {
    final primary = Theme.of(context).primaryColor;
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
                  color: AppColors.success, size: 22),
          ]),
          const SizedBox(height: 4),
          Text(
            loaded
                ? '$backend${ctxTotal > 0 ? ' · ctx $ctxTotal' : ''}${tps != null ? ' · ${tps.toStringAsFixed(1)} tok/s' : ''}'
                : 'Pick a model in Explore to run it on this device',
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

  Widget _featureGrid(BuildContext context) {
    final home = _home;
    Tile go(String label, IconData icon, VoidCallback onTap) =>
        Tile(label: label, icon: icon, onTap: onTap);
    final tiles = <Tile>[
      go('New Chat', LucideIcons.messageSquarePlus, () {
        home?.changeTab(0);
        try {
          Get.find<ChatController>().createNewChat();
        } catch (_) {}
      }),
      go('Local Models', LucideIcons.download, () {
        try {
          Get.find<ModelController>().modelScope.value = 'local';
        } catch (_) {}
        home?.changeTab(1);
      }),
      go('Cloud Models', LucideIcons.cloud, () {
        try {
          Get.find<ModelController>().modelScope.value = 'online';
        } catch (_) {}
        home?.changeTab(1);
      }),
      go('Toolkit', LucideIcons.wrench, () => home?.changeTab(2)),
      go('Personalize', LucideIcons.palette,
          () => Get.toNamed(AppRoutes.personalization)),
      go('Settings', LucideIcons.settings, () => home?.changeTab(4)),
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

  const Tile(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap});

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
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
