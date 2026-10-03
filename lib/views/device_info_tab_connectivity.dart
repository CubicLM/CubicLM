import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_connectivity_bluetooth.dart';
import 'device_info_connectivity_nfc.dart';
import 'device_info_connectivity_usb.dart';
import 'device_info_connectivity_uwb.dart';
import 'device_info_connectivity_wifi.dart';

/// Connectivity tab: Wi-Fi / Bluetooth / NFC / UWB / USB sections.
/// Null from native = "could not determine" (never faked).
///
/// Thin shell: the outer Obx ONLY gates `loading`. The radio bundle is
/// a static snapshot (60s cache) read once (non-reactively) — nothing
/// on this tab rebuilds on the sampling timer.
class ConnectivityTab extends StatelessWidget {
  const ConnectivityTab({super.key});

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
      return const _ConnectivityBody();
    });
  }
}

/// Static body: one-shot snapshot read (no Rx subscription), so the 2s
/// sampling timer never rebuilds this subtree.
class _ConnectivityBody extends StatelessWidget {
  const _ConnectivityBody();

  @override
  Widget build(BuildContext context) {
    final m =
        Get.find<DeviceInfoController>().conn.value;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        WifiSection(conn: m),
        const SizedBox(height: 18),
        BluetoothSection(conn: m),
        const SizedBox(height: 18),
        NfcSection(conn: m),
        const SizedBox(height: 18),
        UwbSection(conn: m),
        const SizedBox(height: 18),
        UsbSection(conn: m),
      ],
    );
  }
}
