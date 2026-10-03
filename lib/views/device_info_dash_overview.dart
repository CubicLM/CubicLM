import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Display/sensors row extracted from DashboardTab._displaySensorsRow.
class DashDisplaySensorsRow extends StatelessWidget {
  const DashDisplaySensorsRow({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
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
