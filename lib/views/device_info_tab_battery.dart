import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_battery_health_details.dart';
import 'device_info_battery_live_header.dart';

/// Battery tab: live header (current + graph + power + status) then
/// Health … Capacity rows. No ads card.
///
/// Thin shell: the outer Obx gates [DeviceInfoController.loading]
/// only. Values ticking on the 2s sampling timer (battery level,
/// current, temp, battLive, paintVersion-driven graph) are owned by
/// tiny Obxs inside the cards below — the ListView itself never
/// subscribes to them.
class BatteryTab extends StatelessWidget {
  const BatteryTab({super.key});

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
          BatteryLiveHeaderCard(),
          SizedBox(height: 14),
          BatteryHealthDetailsCard(),
        ],
      );
    });
  }
}
