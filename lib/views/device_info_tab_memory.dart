import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_soc.dart';
import 'device_info_widgets.dart';

/// Memory tab: Memory / Internal Storage / Swap cards with legend rows.
/// RAM split from /proc/meminfo (no permission); storage split from
/// StatFs (system+vendor partitions measured).
class MemoryTab extends StatelessWidget {
  const MemoryTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

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

  Widget _memLegend(
      BuildContext context, Color dot, String label, int bytes,
      int total) {
    final pct =
        total > 0 ? (bytes / total * 100).clamp(0.0, 100.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: dot, shape: BoxShape.circle),
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
          valueColor: const AlwaysStoppedAnimation<Color>(
              Dt.accent),
        ),
      ),
    );
  }

  Widget _memChip(String s) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
      final m = c.mem.value ?? const {};
      int kb(String k) => m[k] ?? 0;
      final total = kb('MemTotal') * 1024;
      final free = kb('MemFree') * 1024;
      final cache = (kb('Cached') +
              kb('Buffers') +
              kb('SReclaimable')) *
          1024;
      final sys = (kb('Slab') +
              kb('KernelStack') +
              kb('PageTables')) *
          1024;
      final other = kb('Shmem') * 1024;
      final apps =
          (total - free - cache - sys - other).clamp(0, total);
      final used = (total - free).clamp(0, total);
      final usedFrac =
          total > 0 ? used / total : 0.0;

      final swapTotal = kb('SwapTotal') * 1024;
      final swapFree = kb('SwapFree') * 1024;
      final swapUsed =
          (swapTotal - swapFree).clamp(0, swapTotal);
      final swapFrac =
          swapTotal > 0 ? swapUsed / swapTotal : 0.0;

      final st = c.storage.value;
      final dTotal = st?.totalBytes ?? 0;
      final dFree = st?.freeBytes ?? 0;
      final dUsed = (dTotal - dFree).clamp(0, dTotal);
      final dFrac = dTotal > 0 ? dUsed / dTotal : 0.0;
      final parts = c.sysParts.value;
      final sysRes = ((parts?['systemBytes'] as num?)?.toInt() ??
              0) +
          ((parts?['vendorBytes'] as num?)?.toInt() ?? 0);
      final appsData =
          (dUsed - sysRes).clamp(0, dUsed);
      final sysResClamped =
          (dUsed - appsData).clamp(0, dUsed);

      var hw = '';
      String? ramType;
      try {
        final dev = Get.find<DeviceInfoService>();
        hw =
            '${dev.socHardware.value} ${dev.processorName.value}';
        ramType = ramFor(hw);
      } catch (_) {}
      final totalGb =
          total > 0 ? (total / 1e9).toStringAsFixed(0) : '—';

      Widget titleRow(String title, IconData icon) {
        return Row(
          children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
            Icon(icon,
                size: 22,
                color: Dt.accent.withValues(alpha: 0.5)),
          ],
        );
      }

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Memory (RAM) ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  titleRow('Memory', LucideIcons.cpu),
                  const SizedBox(height: 4),
                  Text(
                      total > 0
                          ? '${(usedFrac * 100).toStringAsFixed(1)}%'
                          : '—',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (ramType != null)
                        _memChip(ramType),
                      _memChip('$totalGb GB'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      total > 0
                          ? '${_mfmt(used)} / ${_mfmt(total)}'
                          : '—',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color:
                              Theme.of(context).hintColor)),
                  _memBar(context, usedFrac),
                  const SizedBox(height: 4),
                  _memLegend(context, Dt.accent, 'Apps',
                      apps, total),
                  _memLegend(
                      context,
                      Theme.of(context).hintColor,
                      'Cache',
                      cache,
                      total),
                  _memLegend(context, const Color(0xFF7A7A52),
                      'System', sys, total),
                  _memLegend(context, const Color(0xFFB08968),
                      'Other', other, total),
                  _memLegend(
                      context,
                      Theme.of(context)
                          .dividerColor,
                      'Free',
                      free,
                      total),
                ],
              )),
          const SizedBox(height: 12),
          // ── Internal Storage ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  titleRow(
                      'Internal Storage',
                      LucideIcons.hardDrive),
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
              )),
          const SizedBox(height: 12),
          // ── Swap / Zram ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  titleRow('Swap/ Zram',
                      LucideIcons.database),
                  const SizedBox(height: 4),
                  Text(
                      swapTotal > 0
                          ? '${(swapFrac * 100).toStringAsFixed(1)}%'
                          : '0.0%',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      swapTotal > 0
                          ? '${_mfmt(swapUsed)} / ${_mfmt(swapTotal)}'
                          : 'Not available',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color:
                              Theme.of(context).hintColor)),
                  _memBar(context, swapFrac),
                  const SizedBox(height: 4),
                  _memLegend(
                      context,
                      Theme.of(context)
                          .dividerColor,
                      'Free',
                      swapFree,
                      swapTotal > 0
                          ? swapTotal
                          : 1),
                ],
              )),
        ],
      );
    });
  }
}
