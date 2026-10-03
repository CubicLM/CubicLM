import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';
import 'device_info_memory_ram.dart';
import 'device_info_memory_storage.dart';
import 'device_info_memory_swap.dart';
import 'device_info_soc.dart';

/// Memory tab: Memory / Internal Storage / Swap cards with legend rows.
/// RAM split from /proc/meminfo (no permission); storage split from
/// StatFs (system+vendor partitions measured).
///
/// Thin shell: the outer Obx ONLY gates `loading`. Static snapshots are
/// read once (non-reactively) in [_MemoryBody]; only the storage card
/// re-reads [DeviceInfoController.storage] in its own tiny Obx.
class MemoryTab extends StatelessWidget {
  const MemoryTab({super.key});

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
      return const _MemoryBody();
    });
  }
}

/// Static body: one-shot snapshot reads (no Rx subscription), so the 2s
/// sampling timer never rebuilds this subtree.
class _MemoryBody extends StatelessWidget {
  const _MemoryBody();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    final m = c.mem.value ?? const <String, int>{};
    final parts = c.sysParts.value;

    var hw = '';
    String? ramType;
    try {
      final dev = Get.find<DeviceInfoService>();
      hw =
          '${dev.socHardware.value} ${dev.processorName.value}';
      ramType = ramFor(hw);
    } catch (_) {}

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // ── Memory (RAM) ──
        RamCard(mem: m, ramType: ramType),
        const SizedBox(height: 12),
        // ── Internal Storage ──
        InternalStorageCard(parts: parts),
        const SizedBox(height: 12),
        // ── Swap / Zram ──
        SwapCard(mem: m),
      ],
    );
  }
}
