import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Battery card extracted from DashboardTab._batteryCard (pure move).
class DashBatteryCard extends StatelessWidget {
  const DashBatteryCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
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
}
