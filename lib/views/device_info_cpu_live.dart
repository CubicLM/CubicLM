import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// CPU tab: live per-core frequency bars (Dashboard grid shows the same).
/// The ONLY widget on this tab that rebuilds on the 2s sampling timer:
/// it subscribes to [DeviceInfoController.paintVersion] (read first) and
/// [DeviceInfoController.extras] for the latest `cpuFreqsMHz` sample.
/// [cores] is a static snapshot — core count never changes at runtime.
class CpuLiveFreqCard extends StatelessWidget {
  final int cores;
  const CpuLiveFreqCard({super.key, required this.cores});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final c = Get.find<DeviceInfoController>();
      // Subscribe: repaint on every sampling pass (same freeze fix as
      // the history waves — element reads alone don't reliably notify).
      c.paintVersion.value;
      final freqs =
          c.extras.value?.cpuFreqsMHz ?? const [];
      var liveMax = 1;
      for (final f in freqs) {
        if (f > liveMax) liveMax = f;
      }
      return devCard(context,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text('Live frequency',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (var i = 0; i < cores; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text('Core $i',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12.5)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(3),
                          child:
                              LinearProgressIndicator(
                            value: i < freqs.length
                                ? (freqs[i] / liveMax)
                                    .clamp(0.0, 1.0)
                                : 0,
                            minHeight: 6,
                            backgroundColor:
                                Theme.of(context)
                                    .dividerColor
                                    .withValues(
                                        alpha: 0.4),
                            valueColor:
                                const AlwaysStoppedAnimation<
                                        Color>(
                                    Dt.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 76,
                        child: Text(
                          i < freqs.length
                              ? freqFmt(freqs[i])
                              : '—',
                          textAlign: TextAlign.end,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ));
    });
  }
}
