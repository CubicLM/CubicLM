import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Battery card with live current (mA) and thermal warning alerts.
class DashBatteryCard extends StatelessWidget {
  const DashBatteryCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final lvl = c.batteryLevel.value;
      final chg = c.batteryCharging.value;
      final ex = c.extras.value;
      final live = c.battLive.value;

      final currentUa = (live?['currentUa'] as num?)?.toDouble() ?? 0;
      final currentMa = (currentUa / 1000).round();
      final tempC = ex?.battTempC ?? -1;
      final isOverheat = tempC >= 42;

      final sub = StringBuffer();
      if (ex != null && ex.battVoltageMv > 0) {
        sub.write('${ex.battVoltageMv} mV');
      }
      if (tempC >= 0) {
        if (sub.isNotEmpty) sub.write(' · ');
        sub.write('${tempC.toStringAsFixed(1)}°C');
      }
      if (currentMa != 0) {
        if (sub.isNotEmpty) sub.write(' · ');
        final sign = currentMa > 0 ? '+' : '';
        sub.write('$sign$currentMa mA');
      }

      return devCard(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      chg
                          ? LucideIcons.batteryCharging
                          : LucideIcons.batteryMedium,
                      size: 26,
                      color: isOverheat ? AppColors.warning : Dt.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  chg
                                      ? 'Battery · Charging'
                                      : 'Battery · Discharging',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            Text(lvl >= 0 ? '$lvl%' : '—',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: lvl >= 0 ? lvl / 100 : null,
                            minHeight: 6,
                            backgroundColor: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.4),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                isOverheat ? AppColors.warning : Dt.accent),
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(sub.toString(),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (isOverheat) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'High Temperature (${tempC.toStringAsFixed(1)}°C) — Rest device before heavy LLM inference.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ));
    });
  }
}
