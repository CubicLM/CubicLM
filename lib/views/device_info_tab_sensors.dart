import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_sensors_banner.dart';
import 'device_info_sensors_row.dart';

/// Sensors tab: count banner + one card per sensor (icon by kind,
/// "name  Wakeup/Non-wakeup", Vendor, Type) + detail dialog.
/// Every sensor the OS reports is listed — nothing is filtered out.
///
/// Thin shell: the outer Obx ONLY gates `loading`. The sensor list is a
/// static snapshot read once (non-reactively) — nothing on this tab
/// rebuilds on the sampling timer.
class SensorsTab extends StatelessWidget {
  const SensorsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Loading gate: without it the first paint scores empty data
      // before native values arrive.
      if (Get.find<DeviceInfoController>()
          .loading
          .value) {
        return const Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ));
      }
      return const _SensorsBody();
    });
  }
}

/// Static body: one-shot snapshot read (no Rx subscription), so the 2s
/// sampling timer never rebuilds this subtree.
/// Lazy rows: same freeze fix as the Apps tab.
class _SensorsBody extends StatelessWidget {
  const _SensorsBody();

  @override
  Widget build(BuildContext context) {
    final list =
        Get.find<DeviceInfoController>().sensors.value ??
            const <Map<String, dynamic>>[];
    return Column(
      children: [
        SensorsBanner(count: list.length),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const SizedBox.shrink()
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  16, 0, 16, 32),
              itemCount: list.length,
              itemBuilder: (_, i) {
                return SensorRow(sensor: list[i]);
              },
            ),
          ),
      ],
    );
  }
}
