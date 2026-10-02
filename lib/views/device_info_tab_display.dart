import 'dart:math' show sqrt;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Display tab: resolution header + rows. All values measured live
/// (Display APIs + Settings.System reads, no permissions).
class DisplayTab extends StatelessWidget {
  const DisplayTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  String _dpiBucket(int dpi) {
    const buckets = {
      120: 'LDPI',
      160: 'MDPI',
      213: 'TVDPI',
      240: 'HDPI',
      320: 'XHDPI',
      480: 'XXHDPI',
      640: 'XXXHDPI',
    };
    if (buckets.containsKey(dpi)) return buckets[dpi]!;
    var best = 160;
    var bestD = 1 << 30;
    for (final k in buckets.keys) {
      final d = (k - dpi).abs();
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return buckets[best]!;
  }

  String _resClass(int w) {
    final m = w;
    if (m >= 1440) return ' (QHD+)';
    if (m >= 1080) return ' (FHD+)';
    if (m >= 720) return ' (HD+)';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = c.display.value;
      int dNum(String k) =>
          (d?[k] as num?)?.toInt() ?? -1;
      double dDbl(String k) =>
          (d?[k] as num?)?.toDouble() ?? -1;
      final w = dNum('wPx');
      final h = dNum('hPx');
      final dpi = dNum('densityDpi');
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
      final allHz = ((d?['refreshAll'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      final caps = ((d?['hdrCaps'] as List?) ?? const [])
          .map((e) => '$e')
          .toList();
      final bright = dNum('brightness');
      final timeout =
          (d?['timeoutMs'] as num?)?.toInt() ?? -1;
      final fs = (d?['fontScale'] as num?)?.toDouble();
      final fsTxt =
          fs == null ? '—' : fs.toStringAsFixed(1);
      String orient() {
        switch (MediaQuery.orientationOf(context)) {
          case Orientation.portrait:
            return 'Portrait';
          case Orientation.landscape:
            return 'Landscape';
        }
      }

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          devCard(context,
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
                                    color: Theme.of(
                                            context)
                                        .hintColor)),
                        Text(orient(),
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight:
                                        FontWeight.w600,
                                    color: Theme.of(
                                            context)
                                        .hintColor)),
                      ],
                    ),
                  ),
                ],
              )),
          const SizedBox(height: 14),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'Resolution', res),
                  devRow(context, 'Density',
                      dpi > 0
                          ? '$dpi dpi (${_dpiBucket(dpi)})'
                          : '—'),
                  devRow(
                      context, 'Font Scale', fsTxt),
                  devRow(
                      context, 'Physical Size', inches),
                  devRow(
                      context,
                      'Refresh Rate',
                      allHz.isEmpty
                          ? '—'
                          : allHz
                              .map((r) =>
                                  '• ${r.toStringAsFixed(1)} Hz')
                              .join('\n')),
                  devRow(context, 'HDR',
                      (d?['hdr'] == true)
                          ? 'Supported'
                          : 'Not Supported'),
                  devRow(context, 'HDR Capabilities',
                      caps.isEmpty ? '—' : caps.join(', ')),
                  devRow(context, 'Wide Color Gamut',
                      (d?['wideGamut'] == true)
                          ? 'Supported'
                          : 'Not Supported'),
                  devRow(
                      context,
                      'Brightness Level',
                      bright >= 0
                          ? '${(bright / 255 * 100).round()}%'
                          : '—'),
                  devRow(context, 'Brightness Mode',
                      d?['brightnessMode']?.toString() ?? '—'),
                  devRow(
                      context,
                      'Screen Timeout',
                      timeout >= 0
                          ? '${timeout ~/ 1000} Seconds'
                          : '—'),
                  devRow(context, 'Orientation', orient(),
                      last: true),
                ],
              )),
        ],
      );
    });
  }
}
