import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_android.dart';
import 'device_info_system_details.dart';
import 'device_info_system_drm.dart';

/// System tab: version header card + rows + DRM card.
/// "Released With" is skipped — the factory-shipped OS is not
/// measurable on-device; everything else is live data.
///
/// Thin shell: the outer Obx ONLY gates `loading`. Future values are
/// static snapshots; extras-driven rows (kernel, uptime) subscribe
/// inside their own tiny Obxs in [SystemDetailsCard].
class SystemTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  final Future<Map<String, dynamic>?>? sysInfo;
  const SystemTab(
      {super.key, required this.androidInfo, required this.sysInfo});

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

        final off = DateTime.now().timeZoneOffset;
        final sign = off.isNegative ? '-' : '+';
        final oh = off.inHours.abs().toString().padLeft(2, '0');
        final om =
            (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final tz =
            '${sys['tzId'] ?? '—'} (GMT$sign$oh:$om/ ${sys['tzName'] ?? '—'})';

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
              AndroidVersionHeader(
                meta: meta,
                sdk: sdk,
                release: release,
              ),
              const SizedBox(height: 14),
              SystemDetailsCard(
                sys: sys,
                meta: meta,
                sdk: sdk,
                release: release,
                timezoneLabel: tz,
                securityPatch:
                    a?.version.securityPatch ?? '—',
                buildNumber: a?.display ?? '—',
              ),
              const SizedBox(height: 18),
              Text('DRM',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              DrmCard(sys: sys),
            ],
          );
        });
      },
    );
  }
}
