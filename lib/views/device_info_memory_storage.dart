import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Memory tab: Internal Storage card with legend rows.
/// Storage split from StatFs (system+vendor partitions measured).
/// The ONLY live card on this tab: it wraps just itself in a tiny Obx
/// on [DeviceInfoController.storage] (~10s cache cadence, not the 2s
/// tick). [parts] is a static snapshot (system/vendor bytes).
class InternalStorageCard extends StatelessWidget {
  final Map<String, dynamic>? parts;
  const InternalStorageCard(
      {super.key, required this.parts});

  String _mfmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _mGb1(int bytes) =>
      '${(bytes / 1000000000).toStringAsFixed(1)} GB';

  Widget _memLegend(BuildContext context, Color dot,
      String label, int bytes, int total) {
    final pct = total > 0
        ? (bytes / total * 100).clamp(0.0, 100.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5)),
          ),
          Text('${_mfmt(bytes)} · ${pct.toStringAsFixed(1)}%',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  Widget _memBar(BuildContext context, double frac) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: frac.clamp(0.0, 1.0),
          minHeight: 8,
          backgroundColor: Theme.of(context)
              .dividerColor
              .withValues(alpha: 0.35),
          valueColor:
              const AlwaysStoppedAnimation<Color>(
                  Dt.accent),
        ),
      ),
    );
  }

  Widget _memChip(String s) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(s,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Dt.accent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final st =
          Get.find<DeviceInfoController>().storage.value;
      final dTotal = st?.totalBytes ?? 0;
      final dFree = st?.freeBytes ?? 0;
      final dUsed =
          (dTotal - dFree).clamp(0, dTotal);
      final dFrac =
          dTotal > 0 ? dUsed / dTotal : 0.0;
      final sysRes =
          ((parts?['systemBytes'] as num?)?.toInt() ??
                  0) +
              ((parts?['vendorBytes'] as num?)
                      ?.toInt() ??
                  0);
      final appsData =
          (dUsed - sysRes).clamp(0, dUsed);
      final sysResClamped =
          (dUsed - appsData).clamp(0, dUsed);

      return devCard(context,
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
                                fontSize: 14,
                                fontWeight:
                                    FontWeight.w800)),
                  ),
                  Icon(LucideIcons.hardDrive,
                      size: 22,
                      color: Dt.accent
                          .withValues(alpha: 0.5)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  dTotal > 0
                      ? '${(dFrac * 100).toStringAsFixed(1)}%'
                      : '—',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  Text('/data',
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .hintColor)),
                  _memChip(_mGb1(dTotal)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  dTotal > 0
                      ? '${_mfmt(dUsed)} / ${_mfmt(dTotal)}'
                      : '—',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      color:
                          Theme.of(context).hintColor)),
              _memBar(context, dFrac),
              const SizedBox(height: 4),
              _memLegend(context, Dt.accent,
                  'Apps and data', appsData, dTotal),
              _memLegend(
                  context,
                  Theme.of(context).hintColor,
                  'System and reserved',
                  sysResClamped,
                  dTotal),
              _memLegend(
                  context,
                  const Color(0xFF7A7A52),
                  'Free',
                  dFree,
                  dTotal),
            ],
          ));
    });
  }
}
