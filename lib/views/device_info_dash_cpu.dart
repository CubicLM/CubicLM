import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// CPU grid card extracted from DashboardTab._cpuGridCard (pure move).
class DashCpuCard extends StatelessWidget {
  const DashCpuCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
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
}
