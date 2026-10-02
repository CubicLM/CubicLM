import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_android.dart';
import 'device_info_widgets.dart';

/// System tab: version header card + rows + DRM card.
/// "Released With" is skipped — the factory-shipped OS is not
/// measurable on-device; everything else is live data.
class SystemTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  final Future<Map<String, dynamic>?>? sysInfo;
  const SystemTab(
      {super.key, required this.androidInfo, required this.sysInfo});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([androidInfo!, sysInfo!]),
      builder: (context, snap) {
        final a = snap.data?[0] as AndroidDeviceInfo?;
        final sys =
            (snap.data?.length ?? 0) > 1 && snap.data?[1] is Map
                ? Map<String, dynamic>.from(snap.data?[1] as Map)
                : <String, dynamic>{};
        final sdk = a?.version.sdkInt ?? 0;
        final release = a?.version.release ?? '—';
        final meta = androidMetaFor(sdk);
        final miui = (sys['miui']?.toString() ?? '').trim();
        String safe(dynamic v) {
          final s = v?.toString().trim() ?? '';
          return s.isEmpty ? '—' : s;
        }

        final off = DateTime.now().timeZoneOffset;
        final sign = off.isNegative ? '-' : '+';
        final oh = off.inHours.abs().toString().padLeft(2, '0');
        final om =
            (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final tz =
            '${sys['tzId'] ?? '—'} (GMT$sign$oh:$om/ ${sys['tzName'] ?? '—'})';

        return Obx(() {
          final ex = c.extras.value;
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              AndroidVersionHeader(
                meta: meta,
                sdk: sdk,
                release: release,
              ),
              const SizedBox(height: 14),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      devRow(context, 'Code Name',
                          '${meta.label} - ${meta.codename}'),
                      devRow(context, 'API Level', '$sdk'),
                      devRow(context, 'SDK Extensions',
                          '${sys['sdkExt'] ?? '—'}'),
                      devRow(context, 'MIUI',
                          miui.isEmpty
                              ? '—'
                              : '$release - $miui'),
                      devRow(context, 'Security Patch Level',
                          a?.version.securityPatch ?? '—'),
                      devRow(context, 'Bootloader',
                          safe(sys['bootloader'])),
                      devRow(context, 'Build Number',
                          a?.display ?? '—'),
                      devRow(context, 'Baseband',
                          safe(sys['baseband'])),
                      devRow(context, 'Java VM',
                          safe(sys['javaVm'])),
                      devRow(context, 'Kernel',
                          ex?.kernelVersion ?? '—'),
                      devRow(context, 'Language',
                          langLabel(Platform.localeName)),
                      devRow(context, 'Timezone', tz),
                      devRow(context, 'OpenGL ES',
                          safe(sys['gles'])),
                      devRow(context, 'Root Management Apps',
                          safe(sys['rootApps'])),
                      devRow(context, 'SELinux',
                          safe(sys['selinux'])),
                      devRow(context, 'Google Play Services',
                          safe(sys['gms'])),
                      devRow(context, 'System Uptime',
                          clockFmt(ex?.uptimeMs ?? 0)),
                      devRow(context, 'Vulkan',
                          safe(sys['vulkan'])),
                      devRow(context, 'Treble',
                          safe(sys['treble'])),
                      devRow(context, 'Seamless Updates',
                          safe(sys['seamless'])),
                      devRow(context, 'Dynamic Partitions',
                          safe(sys['dynamic']),
                          last: true),
                    ],
                  )),
              const SizedBox(height: 18),
              Text('DRM',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      devRow(context, 'Vendor',
                          safe(sys['drmVendor'])),
                      devRow(context, 'Description',
                          safe(sys['drmDesc'])),
                      devRow(context, 'Version',
                          safe(sys['drmVersion'])),
                      devRow(context, 'Algorithms',
                          safe(sys['drmAlgos'])),
                      devRow(context, 'Security Level',
                          safe(sys['drmSec'])),
                      devRow(context, 'Max HDCP level',
                          safe(sys['drmHdcp']),
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
