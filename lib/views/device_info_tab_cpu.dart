import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';
import '../widgets/soc_brand_icon.dart';
import 'device_info_cpu_header.dart';
import 'device_info_cpu_live.dart';
import 'device_info_cpu_specs.dart';
import 'device_info_soc.dart';

/// CPU tab: SoC header card + spec rows + live bars.
/// Marketing lines (name/clusters/process) come from the static SoC
/// table when hardware matches; otherwise measured data only.
///
/// Thin shell: the outer Obx ONLY gates `loading`. Static snapshots are
/// read once (non-reactively) in [_CpuBody]; the live bars subscribe to
/// the 2s sampling timer inside [CpuLiveFreqCard] only.
class CpuTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  const CpuTab({super.key, required this.androidInfo});

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
          return _CpuBody(a: a);
        });
      },
    );
  }
}

/// Static body: one-shot snapshot reads (no Rx subscription), so the 2s
/// sampling timer never rebuilds this subtree.
class _CpuBody extends StatelessWidget {
  final AndroidDeviceInfo? a;
  const _CpuBody({required this.a});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    final dev = Get.find<DeviceInfoService>();
    final cpu = c.cpu.value;
    var maxF = const <int>[];
    var minF = const <int>[];
    try {
      maxF = (cpu?['maxFreqs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [];
      minF = (cpu?['minFreqs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [];
    } catch (_) {}
    final cores = maxF.isNotEmpty
        ? maxF.length
        : dev.cpuCores.value;
    final hw =
        '${dev.socHardware.value} ${a?.model ?? ''} ${a?.hardware ?? ''}';
    final spec = socSpecFor(hw);
    final img =
        SocBrandIcon.assetFor(dev.socFamily.value);
    final abis = a?.supportedAbis ?? const [];
    final is64 = (a?.supported64BitAbis ?? const [])
        .isNotEmpty;
    String safe(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? '—' : s;
    }

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // SoC header (app card language, not the brown slab).
        CpuSocHeader(
          displayName: spec?.name ??
              (dev.socHardware.value.isEmpty
                  ? 'Processor'
                  : dev.socHardware.value),
          clusterLines: spec?.clusters
                  .map((e) => e.line)
                  .toList() ??
              const [],
          process: spec?.process,
          brandAsset: img,
          hasSpec: spec != null,
        ),
        const SizedBox(height: 14),
        CpuSpecsCard(
          processor: safe(dev.socHardware.value),
          supportedAbis: abis,
          is64Bit: is64,
          cpuHardware: a?.hardware ?? '—',
          governor: safe(cpu?['governor']),
          cores: cores,
          maxFreqs: maxF,
          minFreqs: minF,
          eglRenderer: safe(cpu?['eglRenderer']),
          eglVendor: safe(cpu?['eglVendor']),
          eglVersion: safe(cpu?['eglVersion']),
          archLinesOverride: spec?.clusters
              .map((e) => e.line)
              .toList(),
        ),
        // Live per-core bars (Dashboard grid shows the same).
        if (cores > 0) ...[
          const SizedBox(height: 14),
          CpuLiveFreqCard(cores: cores),
        ],
      ],
    );
  }
}
