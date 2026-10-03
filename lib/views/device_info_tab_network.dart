import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_network_link_details.dart';
import 'device_info_network_wifi_header.dart';

/// Network tab: Wi-Fi header (IP + generation + Usage/Public IP
/// buttons) then link rows. SSID is never read (needs location).
///
/// Thin shell: the outer Obx gates [DeviceInfoController.loading]
/// only. Live wifi values ticking on the sampling timer are owned by
/// tiny Obxs inside the cards below — the ListView itself never
/// subscribes to them.
class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      if (c.loading.value) {
        return const Center(
            child: CircularProgressIndicator());
      }
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: const [
          NetworkWifiHeaderCard(),
          SizedBox(height: 14),
          NetworkLinkDetailsCard(),
        ],
      );
    });
  }
}
