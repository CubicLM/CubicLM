import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/home_controller.dart';
import '../controllers/model_controller.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_category_widgets.dart';
import 'device_info_widgets.dart';

/// AI sweet-spot card: quant/size lines are static inputs; only the
/// "Room right now" line subscribes to free RAM (tiny Obx).
class CategoryAdviceCard extends StatelessWidget {
  final String quant;
  final String sizeLine;
  const CategoryAdviceCard(
      {super.key, required this.quant, required this.sizeLine});

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.sparkles,
                    size: 18, color: Dt.accent),
                const SizedBox(width: 8),
                Text('AI sweet spot for this device',
                    style: GoogleFonts
                        .plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight:
                                FontWeight.w800)),
                const CatInfoBtn('AI sweet spot',
                    '"Best" is the quantization family that balances speed and quality on your chip (e.g. Q4_K_M). "Stick to ≤1B" is the largest model size class that fits your RAM with working headroom. "Room right now" = (free RAM − 0.25 GB reserve) ÷ 1.25 model overhead — the biggest GGUF file you can load at this moment.'),
              ],
            ),
            const SizedBox(height: 8),
            Text(quant,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text(sizeLine,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color:
                        Theme.of(context).hintColor)),
            Obx(() {
              var roomMb = 0;
              try {
                final avail = Get.find<DeviceInfoService>()
                    .availableRamGB
                    .value;
                roomMb = avail > 0
                    ? (((avail - 0.25) / 1.25 * 1024)
                            .round()
                            .clamp(0, 1 << 30))
                    : 0;
              } catch (_) {}
              if (roomMb <= 0) return const SizedBox.shrink();
              return Text(
                  'Room right now ≈ $roomMb MB — download from the Local marketplace.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color: Theme.of(context)
                          .hintColor));
            }),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  try {
                    Get.find<ModelController>()
                        .modelScope
                        .value = 'local';
                  } catch (_) {}
                  try {
                    Get.find<HomeController>()
                        .changeTab(1);
                    Get.back();
                  } catch (_) {}
                },
                icon: const Icon(
                    LucideIcons.download,
                    size: 16),
                label: const Text(
                    'Open Local marketplace'),
                style: FilledButton.styleFrom(
                  backgroundColor: Dt.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(
                          vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                              12)),
                ),
              ),
            ),
          ],
        ));
  }
}
