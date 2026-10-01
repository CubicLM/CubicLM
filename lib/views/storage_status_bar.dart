import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/model_controller.dart';
import '../services/download_service.dart';
import '../services/storage_info_service.dart';
import '../theme/design_tokens.dart';
import 'storage_details_view.dart';

/// Storage Status bar for Explore → Local: device free/total space
/// with a usage meter, plus models footprint (N files · X GB).
/// Pinned above the filter chips (never scrolls away). Rebuilds live
/// off downloadedFiles/fileSizes; free space refreshes via channel.
class StorageStatusBar extends StatelessWidget {
  const StorageStatusBar({super.key});

  // Decimal GB like MIUI Settings (1 GB = 1e9): 47.07e9 bytes shows
  // "47.1 GB", exactly matching Settings → Storage. Binary GiB made
  // the same bytes read ~7% lower ("43.8 GB") and looked wrong.
  String _gb(int bytes) =>
      '${(bytes / 1000000000).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final mc = Get.find<ModelController>();
    return Obx(() {
      // Tracked reads (.length is the proven subscription in this
      // codebase): rebuild on download/delete/import.
      mc.downloadedFiles.length;
      mc.fileSizes.length;
      final files = mc.downloadedFiles.toList();
      var modelBytes = 0;
      for (final f in files) {
        modelBytes += mc.fileSizes[f] ?? 0;
      }
      final count = files.length;
      return FutureBuilder<StorageStats?>(
        future: StorageInfoService.getStats(),
        builder: (context, snap) {
          final total = snap.data?.totalBytes ?? 0;
          final free = snap.data?.freeBytes ?? 0;
          final hasStats = total > 0;
          // NOTE: total is the userdata PARTITION (~116.9e9 here), not
          // the 128e9 chip — the missing ~11.1e9 is MIUI's "System"
          // row (128 − 116.93 = 11.07). Free matches Settings exactly.
          final used = (total - free).clamp(0, total);
          final freeTxt = hasStats ? _gb(free) : '—';
          final usedTxt = hasStats
              ? _gb(used)
              : '—';
          final totalTxt = hasStats ? _gb(total) : '—';
          final frac =
              hasStats ? used / total : 0.0;
          final barColor = !hasStats
              ? Theme.of(context).hintColor
              : frac >= 0.9
                  ? Colors.redAccent
                  : frac >= 0.75
                      ? Colors.orange
                      : Dt.accent;
          return InkWell(
            onTap: () => Get.to(() => const StorageDetailsView()),
            borderRadius: BorderRadius.circular(16),
            child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color:
                        Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                      LucideIcons.hardDrive,
                      size: 20,
                      color: Dt.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              hasStats
                                  ? '$freeTxt available'
                                  : 'Storage unavailable',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight:
                                          FontWeight.w800),
                            ),
                          ),
                          Text(
                            '$count model${count == 1 ? '' : 's'} · ${DownloadService.formatBytes(modelBytes)}',
                            style: GoogleFonts.firaCode(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .hintColor,
                                fontWeight:
                                    FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: hasStats ? frac : null,
                          minHeight: 6,
                          backgroundColor:
                              Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.4),
                          valueColor:
                              AlwaysStoppedAnimation<
                                  Color>(barColor),
                        ),
                      ),
                      if (hasStats) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$usedTxt used of $totalTxt device storage',
                          style: GoogleFonts.firaCode(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .hintColor,
                              fontWeight:
                                  FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            ),
          );
        },
      );
    });
  }
}
