import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_display_header.dart';
import 'device_info_display_specs.dart';

/// Display tab: resolution header + rows. All values measured live
/// (Display APIs + Settings.System reads, no permissions).
///
/// Thin shell: the outer Obx ONLY gates `loading`. The display bundle
/// is a static snapshot (60s cache) read once (non-reactively) — nothing
/// on this tab rebuilds on the sampling timer.
class DisplayTab extends StatelessWidget {
  const DisplayTab({super.key});

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
      return const _DisplayBody();
    });
  }
}

/// Static body: one-shot snapshot read (no Rx subscription), so the 2s
/// sampling timer never rebuilds this subtree.
class _DisplayBody extends StatelessWidget {
  const _DisplayBody();

  @override
  Widget build(BuildContext context) {
    final d =
        Get.find<DeviceInfoController>().display.value;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        DisplayHeader(display: d),
        const SizedBox(height: 14),
        DisplaySpecs(display: d),
      ],
    );
  }
}
