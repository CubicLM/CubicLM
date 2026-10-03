import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Memory tab: Swap/Zram card.
/// Snapshot passed in as a plain map — fully static, never rebuilds on
/// the sampling timer.
class SwapCard extends StatelessWidget {
  final Map<String, int> mem;
  const SwapCard({super.key, required this.mem});

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

  @override
  Widget build(BuildContext context) {
    int kb(String k) => mem[k] ?? 0;
    final swapTotal = kb('SwapTotal') * 1024;
    final swapFree = kb('SwapFree') * 1024;
    final swapUsed =
        (swapTotal - swapFree).clamp(0, swapTotal);
    final swapFrac =
        swapTotal > 0 ? swapUsed / swapTotal : 0.0;

    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Swap/ Zram',
                      style:
                          GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w800)),
                ),
                Icon(LucideIcons.database,
                    size: 22,
                    color: Dt.accent
                        .withValues(alpha: 0.5)),
              ],
            ),
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
                Theme.of(context).dividerColor,
                'Free',
                swapFree,
                swapTotal > 0 ? swapTotal : 1),
          ],
        ));
  }
}
