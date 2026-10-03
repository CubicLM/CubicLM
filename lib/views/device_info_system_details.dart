import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_android.dart';
import 'device_info_widgets.dart';

/// System tab: version rows card.
/// "Released With" is skipped — the factory-shipped OS is not
/// measurable on-device; everything else is live data.
/// Static values arrive as plain params; the two rows sourced from
/// [DeviceInfoController.extras] (kernel, uptime) live in tiny private
/// Obxs so only those rows rebuild when extras refresh.
class SystemDetailsCard extends StatelessWidget {
  final Map<String, dynamic> sys;
  final AndroidVersionMeta meta;
  final int sdk;
  final String release;
  final String timezoneLabel;
  final String securityPatch;
  final String buildNumber;
  const SystemDetailsCard({
    super.key,
    required this.sys,
    required this.meta,
    required this.sdk,
    required this.release,
    required this.timezoneLabel,
    required this.securityPatch,
    required this.buildNumber,
  });

  String _safe(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    final miui = (sys['miui']?.toString() ?? '').trim();
    return devCard(context,
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
                miui.isEmpty ? '—' : '$release - $miui'),
            devRow(context, 'Security Patch Level',
                securityPatch),
            devRow(context, 'Bootloader',
                _safe(sys['bootloader'])),
            devRow(context, 'Build Number', buildNumber),
            devRow(context, 'Baseband',
                _safe(sys['baseband'])),
            devRow(context, 'Java VM',
                _safe(sys['javaVm'])),
            const _KernelLiveRow(),
            devRow(context, 'Language',
                langLabel(Platform.localeName)),
            devRow(
                context, 'Timezone', timezoneLabel),
            devRow(context, 'OpenGL ES',
                _safe(sys['gles'])),
            devRow(context, 'Root Management Apps',
                _safe(sys['rootApps'])),
            devRow(
                context, 'SELinux', _safe(sys['selinux'])),
            devRow(context, 'Google Play Services',
                _safe(sys['gms'])),
            const _UptimeLiveRow(),
            devRow(context, 'Vulkan',
                _safe(sys['vulkan'])),
            devRow(
                context, 'Treble', _safe(sys['treble'])),
            devRow(context, 'Seamless Updates',
                _safe(sys['seamless'])),
            devRow(context, 'Dynamic Partitions',
                _safe(sys['dynamic']),
                last: true),
          ],
        ));
  }
}

/// Tiny live row: rebuilds only when extras refresh.
class _KernelLiveRow extends StatelessWidget {
  const _KernelLiveRow();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      return devRow(
          context, 'Kernel', ex?.kernelVersion ?? '—');
    });
  }
}

/// Tiny live row: rebuilds only when extras refresh.
class _UptimeLiveRow extends StatelessWidget {
  const _UptimeLiveRow();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      return devRow(context, 'System Uptime',
          clockFmt(ex?.uptimeMs ?? 0));
    });
  }
}
