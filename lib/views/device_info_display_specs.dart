import 'dart:math' show sqrt;

import 'package:flutter/material.dart';

import 'device_info_widgets.dart';

/// Display tab: spec rows card.
/// Static snapshot (60s cache) passed in as a plain param — no rebuilds
/// on the sampling timer.
class DisplaySpecs extends StatelessWidget {
  final Map<String, dynamic>? display;
  const DisplaySpecs(
      {super.key, required this.display});

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
    final d = display;
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
    String orient() {
      switch (MediaQuery.orientationOf(context)) {
        case Orientation.portrait:
          return 'Portrait';
        case Orientation.landscape:
          return 'Landscape';
      }
    }

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

    // Physical size is also rendered by the header card; the row
    // needs the same value, recomputed here from the same snapshot.
    var inches = '—';
    final xd = dDbl('xdpi');
    final yd = dDbl('ydpi');
    if (w > 0 && h > 0 && xd > 0 && yd > 0) {
      final diag =
          (w / xd) * (w / xd) + (h / yd) * (h / yd);
      // ignore: avoid_math_sqrt
      inches =
          '${(sqrt(diag)).toStringAsFixed(1)} inches';
    }

    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            devRow(context, 'Resolution', res),
            devRow(context, 'Density',
                dpi > 0
                    ? '$dpi dpi (${_dpiBucket(dpi)})'
                    : '—'),
            devRow(context, 'Font Scale', fsTxt),
            devRow(context, 'Physical Size', inches),
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
        ));
  }
}
