import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Device tab: screenshot layout — bold label + accent value below +
/// dividers, Grant Permission button, then type/eSIM/network card.
class DeviceTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  const DeviceTab({super.key, required this.androidInfo});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  Future<void> _grantPhonePermission() async {
    try {
      final st = await Permission.phone.request();
      if (st.isGranted) {
        await c.refreshExtras(force: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AndroidDeviceInfo>(
      future: androidInfo,
      builder: (context, snap) {
        final a = snap.data;
        return Obx(() {
          final ex = c.extras.value;
          final needPerm = ex?.phoneType == 'PERMISSION' ||
              ex?.mobileNet == 'PERMISSION';
          String perm(String? v) =>
              v == 'PERMISSION' ? 'Permission needed' : (v ?? '—');
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      devRow(context, 'Device Name',
                          ex?.deviceName ?? '—'),
                      devRow(context, 'Model',
                          a?.model ?? '—'),
                      devRow(context, 'Manufacturer',
                          a?.manufacturer ?? '—'),
                      devRow(context, 'Device',
                          a?.device ?? '—'),
                      devRow(
                          context, 'Board', a?.board ?? '—'),
                      devRow(context, 'Hardware',
                          a?.hardware ?? '—'),
                      devRow(
                          context, 'Brand', a?.brand ?? '—'),
                      devRow(context, 'Android Device ID',
                          ex?.androidId ?? '—'),
                      devRow(context, 'Build Fingerprint',
                          a?.fingerprint ?? '—',
                          last: true),
                    ],
                  )),
              if (needPerm) ...[
                const SizedBox(height: 14),
                Center(
                  child: FilledButton(
                    onPressed: _grantPhonePermission,
                    style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(24)),
                      textStyle: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w700),
                    ),
                    child:
                        const Text('Grant Permission'),
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 14),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      devRow(context, 'Device Type',
                          perm(ex?.phoneType)),
                      devRow(context, 'eSIM',
                          ex?.esim ?? '—'),
                      devRow(context, 'Network Type',
                          perm(ex?.mobileNet),
                          last: true),
                    ],
                  )),
            ],
          );
        });
      },
    );
  }
}
