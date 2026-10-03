import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Live battery header for the Battery tab: current + temp row, icon +
/// sparkline graph, power + status row. Only the tiny Obxs below
/// subscribe to the 2s sampling timer; the card shell itself is static.
class BatteryLiveHeaderCard extends StatelessWidget {
  const BatteryLiveHeaderCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  num? _numOf(Map<String, dynamic>? live, String k) {
    final v = live?[k];
    if (v is num) return v;
    return null;
  }

  List<double> _normBatt(List<double> hist) {
    if (hist.length < 2) return const [];
    var lo = hist.first;
    var hi = hist.first;
    for (final v in hist) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if ((hi - lo).abs() < 1) {
      return List.filled(hist.length, 0.5);
    }
    return [for (final v in hist) (v - lo) / (hi - lo)];
  }

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  // Live current only.
                  child: Obx(() {
                    final live = c.battLive.value;
                    final ua = _numOf(live, 'currentUa');
                    final ma = (ua != null && ua != -1)
                        ? ua / 1000.0
                        : 0.0;
                    final hasCurrent =
                        ua != null && ua != -1;
                    final curTxt = hasCurrent
                        ? '${ma.round()} mA'
                        : '—';
                    return Text('Current : $curTxt',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight:
                                    FontWeight.w800));
                  }),
                ),
                // Live temperature only.
                Obx(() {
                  final live = c.battLive.value;
                  final ex = c.extras.value;
                  final tempC =
                      _numOf(live, 'tempC')?.toDouble() ??
                          (ex?.battTempC ?? -1);
                  final tempTxt = tempC >= 0
                      ? '${tempC.toStringAsFixed(0)} °C'
                      : '—';
                  return Text(tempTxt,
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight:
                                  FontWeight.w800));
                }),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Charging icon only.
                Obx(() {
                  final chg = c.batteryCharging.value;
                  return Icon(
                      chg
                          ? LucideIcons
                              .batteryCharging
                          : LucideIcons
                              .batteryMedium,
                      size: 40,
                      color: Dt.accent);
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 72,
                    // Graph only — the single widget that rebuilds per tick.
                    child: Obx(() {
                      // Explicit paint subscription for battHistory reads.
                      c.paintVersion.value;
                      final hist =
                          c.battHistory.toList();
                      return CustomPaint(
                        painter: SparklinePainter(
                          values: _normBatt(hist),
                          line: Dt.accent,
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  // Live power only.
                  child: Obx(() {
                    final live = c.battLive.value;
                    final ex = c.extras.value;
                    final ua = _numOf(live, 'currentUa');
                    final hasCurrent =
                        ua != null && ua != -1;
                    final ma = (ua != null && ua != -1)
                        ? ua / 1000.0
                        : 0.0;
                    final voltMv =
                        _numOf(live, 'voltageMv')
                                ?.toInt() ??
                            (ex != null &&
                                    ex.battVoltageMv > 0
                                ? ex.battVoltageMv
                                : -1);
                    final watts =
                        (voltMv > 0 && hasCurrent)
                            ? (voltMv / 1000.0) * ma
                            : null;
                    final powTxt = watts == null
                        ? '—'
                        : '${watts.toStringAsFixed(2)} W';
                    return Text('Power : $powTxt',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight:
                                    FontWeight.w800));
                  }),
                ),
                // Live status only.
                Obx(() {
                  final live = c.battLive.value;
                  final lvl = c.batteryLevel.value;
                  final chg = c.batteryCharging.value;
                  final status = live?['status']
                          ?.toString() ??
                      (lvl < 0
                          ? '—'
                          : (chg
                              ? 'Charging'
                              : 'Discharging'));
                  return Text(
                      status == 'Charging'
                          ? 'Battery Charging'
                          : status == 'Discharging'
                              ? 'Battery Discharging'
                              : status,
                      style: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight:
                                  FontWeight.w800));
                }),
              ],
            ),
          ],
        ));
  }
}
