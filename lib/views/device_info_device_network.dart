import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_widgets.dart';

/// Device tab: type/eSIM/network card.
/// All three rows come from [DeviceInfoController.extras], so the whole
/// (small) card sits in one tiny Obx — the ListView itself never
/// subscribes to the sampling timer.
class DeviceNetworkCard extends StatelessWidget {
  const DeviceNetworkCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      String perm(String? v) => v == 'PERMISSION'
          ? 'Permission needed'
          : (v ?? '—');
      return devCard(context,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              devRow(context, 'Device Type',
                  perm(ex?.phoneType)),
              devRow(context, 'eSIM', ex?.esim ?? '—'),
              devRow(context, 'Network Type',
                  perm(ex?.mobileNet),
                  last: true),
            ],
          ));
    });
  }
}
