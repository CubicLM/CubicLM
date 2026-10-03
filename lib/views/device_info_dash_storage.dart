import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';
import 'storage_details_view.dart';

/// Storage card extracted from DashboardTab._storageCard (pure move).
class DashStorageCard extends StatelessWidget {
  const DashStorageCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
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
}
