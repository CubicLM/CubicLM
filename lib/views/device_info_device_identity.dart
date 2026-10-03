import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_widgets.dart';

/// Device tab: identity card (device name, model, manufacturer, IDs…).
/// Future values are static plain params; the two rows sourced from
/// [DeviceInfoController.extras] live in tiny private Obxs so only
/// those rows rebuild when extras refresh.
class DeviceIdentityCard extends StatelessWidget {
  final String? model;
  final String? manufacturer;
  final String? device;
  final String? board;
  final String? hardware;
  final String? brand;
  final String? fingerprint;
  const DeviceIdentityCard({
    super.key,
    required this.model,
    required this.manufacturer,
    required this.device,
    required this.board,
    required this.hardware,
    required this.brand,
    required this.fingerprint,
  });

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const _DeviceNameLiveRow(),
            devRow(context, 'Model', model ?? '—'),
            devRow(context, 'Manufacturer',
                manufacturer ?? '—'),
            devRow(context, 'Device', device ?? '—'),
            devRow(context, 'Board', board ?? '—'),
            devRow(
                context, 'Hardware', hardware ?? '—'),
            devRow(context, 'Brand', brand ?? '—'),
            const _AndroidIdLiveRow(),
            devRow(context, 'Build Fingerprint',
                fingerprint ?? '—',
                last: true),
          ],
        ));
  }
}

/// Tiny live row: rebuilds only when extras refresh.
class _DeviceNameLiveRow extends StatelessWidget {
  const _DeviceNameLiveRow();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      return devRow(
          context, 'Device Name', ex?.deviceName ?? '—');
    });
  }
}

/// Tiny live row: rebuilds only when extras refresh.
class _AndroidIdLiveRow extends StatelessWidget {
  const _AndroidIdLiveRow();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      return devRow(context, 'Android Device ID',
          ex?.androidId ?? '—');
    });
  }
}
