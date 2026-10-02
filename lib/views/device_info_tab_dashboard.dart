import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import '../views/hub/hub_widgets.dart';
import 'device_info_widgets.dart';
import 'storage_details_view.dart';

/// Dashboard tab: RAM card, CPU grid, storage bar, battery card,
/// display/sensors row.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _ramCard(context),
        const SizedBox(height: 12),
        _cpuGridCard(context),
        const SizedBox(height: 12),
        _storageCard(context),
        const SizedBox(height: 12),
        _batteryCard(context),
        const SizedBox(height: 12),
        _displaySensorsRow(context),
      ],
    );
  }

  Widget _ramCard(BuildContext context) {
    final dev = Get.find<DeviceInfoService>();
    return Obx(() {
      // paintVersion FIRST: history .toList()/[] reads alone do not
      // reliably resubscribe (blank wave until remount).
      c.paintVersion.value;
      final total = dev.totalRamGB.value;
      final avail = dev.availableRamGB.value;
      final used = (total - avail).clamp(0.0, total);
      final frac = total > 0 ? used / total : 0.0;
      final hist = c.ramHistory.toList();

      var maxFrac = frac;
      var minFrac = frac;
      if (hist.isNotEmpty) {
        for (final v in hist) {
          if (v > maxFrac) maxFrac = v;
          if (v < minFrac) minFrac = v;
        }
      }
      final peakGb = total > 0 ? maxFrac * total : 0.0;
      final minGb = total > 0 ? minFrac * total : 0.0;

      return devCard(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          total > 0
                              ? 'RAM · ${total.toStringAsFixed(1)} GB Total'
                              : 'RAM',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.greenAccent,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text('Live',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Dt.accent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    total > 0
                        ? '${used.toStringAsFixed(1)} GB Used'
                        : '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Dt.accent),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  HubRing(
                    fraction: frac,
                    center: total > 0
                        ? '${(frac * 100).round()}%'
                        : '—',
                    label: 'USED',
                    color: frac > 0.85
                        ? AppColors.warning
                        : Dt.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 92,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: SparklinePainter(
                                values: hist,
                                line: frac > 0.85
                                    ? AppColors.warning
                                    : Dt.accent,
                              ),
                            ),
                          ),
                          if (total > 0)
                            Positioned(
                              top: 2,
                              right: 4,
                              child: Text(
                                'Peak: ${peakGb.toStringAsFixed(1)} GB (${(maxFrac * 100).round()}%)',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .hintColor
                                        .withValues(alpha: 0.85)),
                              ),
                            ),
                          if (total > 0)
                            Positioned(
                              bottom: 2,
                              right: 4,
                              child: Text(
                                'Min: ${minGb.toStringAsFixed(1)} GB (${(minFrac * 100).round()}%)',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .hintColor
                                        .withValues(alpha: 0.85)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    total > 0
                        ? 'Buffer: ${((total - used) * 1024).round()} MB'
                        : '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor),
                  ),
                  Text(
                    total > 0
                        ? '${avail.toStringAsFixed(1)} GB Free (${((1 - frac) * 100).round()}%)'
                        : '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ],
          ));
    });
  }

  Widget _cpuGridCard(BuildContext context) {
    return Obx(() {
      // See _ramCard: explicit paint subscription for history reads.
      c.paintVersion.value;
      final freqs = c.extras.value?.cpuFreqsMHz ?? const [];
      final cpuInfo = c.cpu.value;
      final maxF = (cpuInfo?['maxFreqs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [];
      final minF = (cpuInfo?['minFreqs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [];

      final cores = freqs.isEmpty
          ? Get.find<DeviceInfoService>().cpuCores.value
          : freqs.length;

      return devCard(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('CPU Status · $cores Cores',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Dt.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Live Wave Monitor',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Dt.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (cores <= 0)
                Text('—',
                    style: GoogleFonts.plusJakartaSans(
                        color: Theme.of(context).hintColor))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cores,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.55,
                  ),
                  itemBuilder: (_, i) {
                    final mhz = i < freqs.length ? freqs[i] : -1;
                    final coreMax = (i < maxF.length && maxF[i] > 0)
                        ? maxF[i]
                        : 2800;
                    final coreMin = (i < minF.length && minF[i] > 0)
                        ? minF[i]
                        : 300;
                    final loadPct = mhz > 0
                        ? ((mhz / coreMax) * 100).clamp(0, 100).round()
                        : 0;

                    final coreHist = c.cpuCoreHistory[i] ?? const [];

                    final isHeavy = loadPct > 80;
                    final waveColor = isHeavy ? AppColors.warning : Dt.accent;
                    final textPrimary = Theme.of(context).colorScheme.onSurface;

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isHeavy
                              ? AppColors.warning.withValues(alpha: 0.4)
                              : Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: waveColor,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text('Core $i',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimary)),
                              const Spacer(),
                              Text(freqFmt(mhz),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: CustomPaint(
                                painter: CoreWavePainter(
                                  values: coreHist,
                                  line: waveColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${freqFmt(coreMin)} - ${freqFmt(coreMax)}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).hintColor),
                              ),
                              Text(
                                '$loadPct%',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: waveColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ));
    });
  }

  Widget _storageCard(BuildContext context) {
    return Obx(() {
      final s = c.storage.value;
      final total = s?.totalBytes ?? 0;
      final free = s?.freeBytes ?? 0;
      final used = (total - free).clamp(0, total);
      final frac = total > 0 ? used / total : 0.0;
      return InkWell(
        onTap: () =>
            Get.to(() => const StorageDetailsView()),
        borderRadius: BorderRadius.circular(16),
        child: devCard(context,
            child: Row(
              children: [
                const Icon(LucideIcons.hardDrive,
                    size: 26, color: Dt.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Internal Storage',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight:
                                            FontWeight.w700)),
                          ),
                          Text(
                            total > 0
                                ? '${(frac * 100).round()}%'
                                : '—',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? frac : null,
                          minHeight: 6,
                          backgroundColor:
                              Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.4),
                          valueColor:
                              const AlwaysStoppedAnimation<
                                  Color>(Dt.accent),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        total > 0
                            ? 'Free: ${(free / 1e9).toStringAsFixed(1)} GB, Total: ${(total / 1e9).toStringAsFixed(1)} GB'
                            : 'Tap for details',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color:
                                Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight,
                    size: 18,
                    color: Theme.of(context).hintColor),
              ],
            )),
      );
    });
  }

  Widget _batteryCard(BuildContext context) {
    return Obx(() {
      final lvl = c.batteryLevel.value;
      final chg = c.batteryCharging.value;
      final ex = c.extras.value;
      final sub = StringBuffer();
      if (ex != null && ex.battVoltageMv > 0) {
        sub.write('Voltage: ${ex.battVoltageMv}mV');
      }
      if (ex != null && ex.battTempC >= 0) {
        if (sub.isNotEmpty) sub.write(', ');
        sub.write(
            'Temperature: ${ex.battTempC.toStringAsFixed(1)}°C');
      }
      return devCard(context,
          child: Row(
            children: [
              Icon(
                  chg
                      ? LucideIcons.batteryCharging
                      : LucideIcons.batteryMedium,
                  size: 26,
                  color: Dt.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              chg
                                  ? 'Battery · charging'
                                  : 'Battery',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 13.5,
                                      fontWeight:
                                          FontWeight.w700)),
                        ),
                        Text(lvl >= 0 ? '$lvl%' : '—',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: lvl >= 0
                            ? lvl / 100
                            : null,
                        minHeight: 6,
                        backgroundColor:
                            Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.4),
                        valueColor:
                            const AlwaysStoppedAnimation<
                                Color>(Dt.accent),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(sub.toString(),
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 11.5,
                                  color: Theme.of(context)
                                      .hintColor)),
                    ],
                  ],
                ),
              ),
            ],
          ));
    });
  }

  Widget _displaySensorsRow(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Obx(() {
      final sensors = c.extras.value?.sensorCount ?? -1;
      return Row(
        children: [
          Expanded(
            child: devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.monitor,
                        size: 24, color: Dt.accent),
                    const SizedBox(height: 8),
                    Text('Display',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(
                      '${size.width.toStringAsFixed(0)} x ${size.height.toStringAsFixed(0)} · ${dpr.toStringAsFixed(2)}x',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color:
                              Theme.of(context).hintColor),
                    ),
                  ],
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.radio,
                        size: 24, color: Dt.accent),
                    const SizedBox(height: 8),
                    Text(
                        sensors >= 0 ? '$sensors' : '—',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text('Sensors',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color:
                                Theme.of(context).hintColor)),
                  ],
                )),
          ),
        ],
      );
    });
  }
}
