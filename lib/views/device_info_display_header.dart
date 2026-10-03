import 'dart:math' show sqrt;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Display tab: resolution header card.
/// All values measured live (Display APIs + Settings.System reads, no
/// permissions); the bundle is a static snapshot (60s cache) passed in
/// as a plain param — no rebuilds on the sampling timer.
class DisplayHeader extends StatelessWidget {
  final Map<String, dynamic>? display;
  const DisplayHeader(
      {super.key, required this.display});

  String _resClass(int w) {
    final m = w;
    if (m >= 1440) return ' (QHD+)';
    if (m >= 1080) return ' (FHD+)';
    if (m >= 720) return ' (HD+)';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final d = display;
    int dNum(String k) =>
        (d?[k] as num?)?.toInt() ?? -1;
    double dDbl(String k) =>
        (d?[k] as num?)?.toDouble() ?? -1;
    final w = dNum('wPx');
    final h = dNum('hPx');
    final res = (w > 0 && h > 0)
        ? '$h x $w Pixels${_resClass(w)}'
        : '—';
    var inches = '—';
    final xd = dDbl('xdpi');
    final yd = dDbl('ydpi');
    if (w > 0 && h > 0 && xd > 0 && yd > 0) {
      final diag = (w / xd) * (w / xd) +
          (h / yd) * (h / yd);
      // ignore: avoid_math_sqrt
      inches =
          '${(sqrt(diag)).toStringAsFixed(1)} inches';
    }
    final nowHz = dDbl('refreshNow');
    String orient() {
      switch (MediaQuery.orientationOf(context)) {
        case Orientation.portrait:
          return 'Portrait';
        case Orientation.landscape:
          return 'Landscape';
      }
    }

    return devCard(context,
        child: Row(
          children: [
            const Icon(LucideIcons.smartphone,
                size: 34, color: Dt.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(res,
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 15,
                              fontWeight:
                                  FontWeight.w800)),
                  Text(
                      (d?['builtIn'] == true)
                          ? 'Built-in Screen'
                          : 'External Screen',
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w700)),
                  Text(
                      '${inches == '—' ? '—' : inches.split(' ').first} | ${nowHz > 0 ? '${nowHz.toStringAsFixed(1)} Hz' : '—'}',
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight:
                                  FontWeight.w600,
                              color: Theme.of(context)
                                  .hintColor)),
                  Text(orient(),
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight:
                                  FontWeight.w600,
                              color: Theme.of(context)
                                  .hintColor)),
                ],
              ),
            ),
          ],
        ));
  }
}
