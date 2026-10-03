import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_widgets.dart';

/// IP / link details card for the Network tab. Each row owns a tiny
/// Obx so a 2s-ticking wifi update rebuilds only that row — never the
/// whole column.
class NetworkLinkDetailsCard extends StatelessWidget {
  const NetworkLinkDetailsCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  String _wifiStd(int s) {
    switch (s) {
      case 4:
        return 'Wi-Fi 802.11n (Wi-Fi 4)';
      case 5:
        return 'Wi-Fi 802.11ac (Wi-Fi 5)';
      case 6:
        return 'Wi-Fi 802.11ad (WiGig)';
      case 7:
        return 'Wi-Fi 802.11ax (Wi-Fi 6)';
      case 8:
        return 'Wi-Fi 802.11be (Wi-Fi 7)';
      case 1:
        return 'Wi-Fi 802.11a';
      case 2:
        return 'Wi-Fi 802.11b';
      case 3:
        return 'Wi-Fi 802.11g';
      default:
        return '—';
    }
  }

  String _wifiChannel(int freq) {
    if (freq <= 0) return '—';
    if (freq == 2484) return 'CH 14';
    if (freq >= 2412 && freq <= 2472) {
      return 'CH ${(freq - 2407) ~/ 5}';
    }
    if (freq >= 5035 && freq <= 5865) {
      return 'CH ${(freq - 5000) ~/ 5}';
    }
    if (freq >= 5955 && freq <= 7115) {
      return 'CH ${(freq - 5950) ~/ 5}';
    }
    return '—';
  }

  String _lease(String raw) {
    final sec = int.tryParse(raw) ?? -1;
    if (sec < 0) return raw.isEmpty ? '—' : raw;
    if (sec >= 3600) return '${sec ~/ 3600}H';
    if (sec >= 60) return '${sec ~/ 60}M';
    return '${sec}S';
  }

  String _safe(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s == '-1' ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Obx(() {
              final w = c.wifi.value;
              final connected = w?['connected'] == true;
              final ip = w?['ip']?.toString() ?? '—';
              return devRow(context, 'IP Address',
                  connected ? ip : '—');
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context, 'IPv6 Address', _safe(w?['ipv6']));
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context, 'Gateway', _safe(w?['gateway']));
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context, 'Subnet Mask', _safe(w?['mask']));
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context, 'DNS 1', _safe(w?['dns']));
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context,
                  'Lease Duration',
                  _lease(
                      w?['leaseSec']?.toString() ?? ''));
            }),
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context, 'Interface', _safe(w?['iface']));
            }),
            // Ticks with the sampling timer (link speed can move).
            Obx(() {
              final w = c.wifi.value;
              return devRow(
                  context,
                  'Link Speed',
                  (w?['linkMbps'] as num?) != null &&
                          (w?['linkMbps'] as num) >=
                              0
                      ? '${w?['linkMbps']} Mbps'
                      : '—');
            }),
            Obx(() {
              final w = c.wifi.value;
              final freq =
                  (w?['freqMhz'] as num?)?.toInt() ?? -1;
              return devRow(
                  context, 'Channel', _wifiChannel(freq));
            }),
            Obx(() {
              final w = c.wifi.value;
              final freq =
                  (w?['freqMhz'] as num?)?.toInt() ?? -1;
              return devRow(context, 'Frequency',
                  freq > 0 ? '$freq MHz' : '—');
            }),
            Obx(() {
              final w = c.wifi.value;
              final std =
                  (w?['standard'] as num?)?.toInt() ?? -1;
              return devRow(
                  context, 'WiFi Standard', _wifiStd(std),
                  last: true);
            }),
          ],
        ));
  }
}
