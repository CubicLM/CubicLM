import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';

/// Device tab: Grant Permission button block.
/// Visibility depends on [DeviceInfoController.extras], so the gate
/// lives in a tiny Obx wrapping just this block (button + its spacing).
class DevicePermissionBlock extends StatelessWidget {
  const DevicePermissionBlock({super.key});

  Future<void> _grantPhonePermission() async {
    try {
      final st = await Permission.phone.request();
      if (st.isGranted) {
        await Get.find<DeviceInfoController>()
            .refreshExtras(force: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      final needPerm = ex?.phoneType == 'PERMISSION' ||
          ex?.mobileNet == 'PERMISSION';
      if (!needPerm) {
        return const SizedBox(height: 14);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Center(
            child: FilledButton(
              onPressed: _grantPhonePermission,
              style: FilledButton.styleFrom(
                backgroundColor: Dt.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(24)),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              child:
                  const Text('Grant Permission'),
            ),
          ),
          const SizedBox(height: 14),
        ],
      );
    });
  }
}
