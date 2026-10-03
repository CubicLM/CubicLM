import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_device_identity.dart';
import 'device_info_device_network.dart';
import 'device_info_device_permission.dart';

/// Device tab: screenshot layout — bold label + accent value below +
/// dividers, Grant Permission button, then type/eSIM/network card.
///
/// Thin shell: the outer Obx ONLY gates `loading`. Future values are
/// static; extras-driven rows subscribe inside their own tiny Obxs
/// ([DeviceIdentityCard], [DevicePermissionBlock],
/// [DeviceNetworkCard]).
class DeviceTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  const DeviceTab({super.key, required this.androidInfo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AndroidDeviceInfo>(
      future: androidInfo,
      builder: (context, snap) {
        final a = snap.data;
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
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              DeviceIdentityCard(
                model: a?.model,
                manufacturer: a?.manufacturer,
                device: a?.device,
                board: a?.board,
                hardware: a?.hardware,
                brand: a?.brand,
                fingerprint: a?.fingerprint,
              ),
              const DevicePermissionBlock(),
              const DeviceNetworkCard(),
            ],
          );
        });
      },
    );
  }
}
