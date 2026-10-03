import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';
import 'hub/hub_widgets.dart';

/// RAM card extracted from DashboardTab._ramCard (pure move, no changes).
class DashRamCard extends StatelessWidget {
  const DashRamCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
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
}
