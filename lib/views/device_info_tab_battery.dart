import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Battery tab: live header (current + graph + power + status) then
/// Health … Capacity rows. No ads card.
class BatteryTab extends StatelessWidget {
  const BatteryTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

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
    return Obx(() {
      // Explicit paint subscription for battHistory reads.
      c.paintVersion.value;
      final live = c.battLive.value;
      final ex = c.extras.value;
      num? numOf(String k) {
        final v = live?[k];
        if (v is num) return v;
        return null;
      }

      final lvl = c.batteryLevel.value;
      final chg = c.batteryCharging.value;
      final ua = numOf('currentUa');
      final hasCurrent = ua != null && ua != -1;
      final ma =
          (ua != null && ua != -1) ? ua / 1000.0 : 0.0;
      final voltMv = numOf('voltageMv')?.toInt() ??
          (ex != null && ex.battVoltageMv > 0
              ? ex.battVoltageMv
              : -1);
      final watts = (voltMv > 0 && hasCurrent)
          ? (voltMv / 1000.0) * ma
          : null;
      final status = live?['status']?.toString() ??
          (lvl < 0
              ? '—'
              : (chg ? 'Charging' : 'Discharging'));
      final plugged =
          live?['plugged']?.toString() ?? 'Battery';
      final tempC = numOf('tempC')?.toDouble() ??
          (ex?.battTempC ?? -1);
      final counterMah = numOf('counterMah')?.toInt() ?? -1;
      final designMah = numOf('designMah')?.toInt() ?? -1;
      final fullMah = numOf('fullMah')?.toInt() ?? -1;
      final estimatedMah = (counterMah > 0 && lvl > 0)
          ? (counterMah / lvl * 100).round()
          : -1;
      String eta() {
        if (status == 'Charging' &&
            ma > 0 &&
            fullMah > 0 &&
            counterMah >= 0 &&
            fullMah > counterMah) {
          final mins =
              ((fullMah - counterMah) / ma * 60).round();
          if (mins < 60) return '$mins min';
          return '${mins ~/ 60}h ${mins % 60}m';
        }
        if (status == 'Charged') return 'Charged';
        if (status == 'Discharging') return 'Discharging';
        return status;
      }

      final curTxt =
          hasCurrent ? '${ma.round()} mA' : '—';
      final powTxt = watts == null
          ? '—'
          : '${watts.toStringAsFixed(2)} W';
      final tempTxt = tempC >= 0
          ? '${tempC.toStringAsFixed(0)} °C'
          : '—';
      final hist = c.battHistory.toList();

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          devCard(context,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Current : $curTxt',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight:
                                        FontWeight.w800)),
                      ),
                      Text(tempTxt,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                          chg
                              ? LucideIcons
                                  .batteryCharging
                              : LucideIcons
                                  .batteryMedium,
                          size: 40,
                          color: Dt.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 72,
                          child: CustomPaint(
                            painter: SparklinePainter(
                              values: _normBatt(hist),
                              line: Dt.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Power : $powTxt',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight:
                                        FontWeight.w800)),
                      ),
                      Text(
                          status == 'Charging'
                              ? 'Battery Charging'
                              : status == 'Discharging'
                                  ? 'Battery Discharging'
                                  : status,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800)),
                    ],
                  ),
                ],
              )),
          const SizedBox(height: 14),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'Health',
                      ex?.battHealth ?? '—'),
                  devRow(context, 'Level',
                      lvl >= 0 ? '$lvl%' : '—'),
                  devRow(
                      context, 'Status', status),
                  devRow(context, 'Power Source',
                      plugged),
                  devRow(context, 'Technology',
                      ex?.battTech ?? '—'),
                  devRow(context, 'Temperature',
                      tempTxt),
                  devRow(
                      context, 'Current', curTxt),
                  devRow(context, 'Power', powTxt),
                  devRow(context, 'Voltage',
                      voltMv > 0 ? '$voltMv mV' : '—'),
                  devRow(context, 'Time to charge',
                      eta()),
                  devRow(
                      context,
                      'Capacity (Charged)',
                      counterMah > 0
                          ? '$counterMah mAh'
                          : '—'),
                  devRow(
                      context,
                      'Capacity (Estimated)',
                      estimatedMah > 0
                          ? '$estimatedMah mAh'
                          : '—'),
                  devRow(
                      context,
                      'Capacity (System)',
                      designMah > 0
                          ? '$designMah mAh'
                          : '—',
                      last: true),
                ],
              )),
        ],
      );
    });
  }
}
