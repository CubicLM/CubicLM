import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Memory tab: RAM card with legend rows.
/// RAM split from /proc/meminfo (no permission); snapshot passed in as
/// a plain map — fully static, never rebuilds on the sampling timer.
class RamCard extends StatelessWidget {
  final Map<String, int> mem;
  final String? ramType;
  const RamCard(
      {super.key, required this.mem, required this.ramType});

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
    int kb(String k) => mem[k] ?? 0;
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
        (total - free - cache - sys - other)
            .clamp(0, total);
    final used = (total - free).clamp(0, total);
    final usedFrac = total > 0 ? used / total : 0.0;
    final totalGb = total > 0
        ? (total / 1e9).toStringAsFixed(0)
        : '—';

    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Memory',
                      style:
                          GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w800)),
                ),
                Icon(LucideIcons.cpu,
                    size: 22,
                    color: Dt.accent
                        .withValues(alpha: 0.5)),
              ],
            ),
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
                  _memChip(ramType!),
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
            _memLegend(
                context, Dt.accent, 'Apps', apps, total),
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
                Theme.of(context).dividerColor,
                'Free',
                free,
                total),
          ],
        ));
  }
}
