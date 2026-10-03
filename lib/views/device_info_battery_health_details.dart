import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_widgets.dart';

/// Health / capacity details for the Battery tab. Each row owns a
/// tiny Obx over just its source Rx so the 2s sampling timer rebuilds
/// only the live numbers — never the whole column.
class BatteryHealthDetailsCard extends StatelessWidget {
  const BatteryHealthDetailsCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  num? _numOf(Map<String, dynamic>? live, String k) {
    final v = live?[k];
    if (v is num) return v;
    return null;
  }

  String _status(
      Map<String, dynamic>? live, int lvl, bool chg) {
    return live?['status']?.toString() ??
        (lvl < 0
            ? '—'
            : (chg ? 'Charging' : 'Discharging'));
  }

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Obx(() {
              final ex = c.extras.value;
              return devRow(
                  context, 'Health', ex?.battHealth ?? '—');
            }),
            Obx(() {
              final lvl = c.batteryLevel.value;
              return devRow(context, 'Level',
                  lvl >= 0 ? '$lvl%' : '—');
            }),
            Obx(() {
              final live = c.battLive.value;
              final lvl = c.batteryLevel.value;
              final chg = c.batteryCharging.value;
              return devRow(
                  context, 'Status', _status(live, lvl, chg));
            }),
            Obx(() {
              final live = c.battLive.value;
              final plugged =
                  live?['plugged']?.toString() ?? 'Battery';
              return devRow(
                  context, 'Power Source', plugged);
            }),
            Obx(() {
              final ex = c.extras.value;
              return devRow(
                  context, 'Technology', ex?.battTech ?? '—');
            }),
            Obx(() {
              final live = c.battLive.value;
              final ex = c.extras.value;
              final tempC =
                  _numOf(live, 'tempC')?.toDouble() ??
                      (ex?.battTempC ?? -1);
              final tempTxt = tempC >= 0
                  ? '${tempC.toStringAsFixed(0)} °C'
                  : '—';
              return devRow(
                  context, 'Temperature', tempTxt);
            }),
            Obx(() {
              final live = c.battLive.value;
              final ua = _numOf(live, 'currentUa');
              final hasCurrent = ua != null && ua != -1;
              final ma = (ua != null && ua != -1)
                  ? ua / 1000.0
                  : 0.0;
              final curTxt =
                  hasCurrent ? '${ma.round()} mA' : '—';
              return devRow(context, 'Current', curTxt);
            }),
            Obx(() {
              final live = c.battLive.value;
              final ex = c.extras.value;
              final ua = _numOf(live, 'currentUa');
              final hasCurrent = ua != null && ua != -1;
              final ma = (ua != null && ua != -1)
                  ? ua / 1000.0
                  : 0.0;
              final voltMv =
                  _numOf(live, 'voltageMv')?.toInt() ??
                      (ex != null && ex.battVoltageMv > 0
                          ? ex.battVoltageMv
                          : -1);
              final watts = (voltMv > 0 && hasCurrent)
                  ? (voltMv / 1000.0) * ma
                  : null;
              final powTxt = watts == null
                  ? '—'
                  : '${watts.toStringAsFixed(2)} W';
              return devRow(context, 'Power', powTxt);
            }),
            Obx(() {
              final live = c.battLive.value;
              final ex = c.extras.value;
              final voltMv =
                  _numOf(live, 'voltageMv')?.toInt() ??
                      (ex != null && ex.battVoltageMv > 0
                          ? ex.battVoltageMv
                          : -1);
              return devRow(context, 'Voltage',
                  voltMv > 0 ? '$voltMv mV' : '—');
            }),
            Obx(() {
              final live = c.battLive.value;
              final lvl = c.batteryLevel.value;
              final chg = c.batteryCharging.value;
              final ua = _numOf(live, 'currentUa');
              final ma = (ua != null && ua != -1)
                  ? ua / 1000.0
                  : 0.0;
              final counterMah =
                  _numOf(live, 'counterMah')?.toInt() ?? -1;
              final fullMah =
                  _numOf(live, 'fullMah')?.toInt() ?? -1;
              final status = _status(live, lvl, chg);
              String eta() {
                if (status == 'Charging' &&
                    ma > 0 &&
                    fullMah > 0 &&
                    counterMah >= 0 &&
                    fullMah > counterMah) {
                  final mins =
                      ((fullMah - counterMah) / ma * 60)
                          .round();
                  if (mins < 60) return '$mins min';
                  return '${mins ~/ 60}h ${mins % 60}m';
                }
                if (status == 'Charged') return 'Charged';
                if (status == 'Discharging') {
                  return 'Discharging';
                }
                return status;
              }

              return devRow(
                  context, 'Time to charge', eta());
            }),
            Obx(() {
              final live = c.battLive.value;
              final counterMah =
                  _numOf(live, 'counterMah')?.toInt() ?? -1;
              return devRow(
                  context,
                  'Capacity (Charged)',
                  counterMah > 0
                      ? '$counterMah mAh'
                      : '—');
            }),
            Obx(() {
              final live = c.battLive.value;
              final lvl = c.batteryLevel.value;
              final counterMah =
                  _numOf(live, 'counterMah')?.toInt() ?? -1;
              final estimatedMah =
                  (counterMah > 0 && lvl > 0)
                      ? (counterMah / lvl * 100).round()
                      : -1;
              return devRow(
                  context,
                  'Capacity (Estimated)',
                  estimatedMah > 0
                      ? '$estimatedMah mAh'
                      : '—');
            }),
            Obx(() {
              final live = c.battLive.value;
              final designMah =
                  _numOf(live, 'designMah')?.toInt() ?? -1;
              return devRow(
                  context,
                  'Capacity (System)',
                  designMah > 0
                      ? '$designMah mAh'
                      : '—',
                  last: true);
            }),
          ],
        ));
  }
}
