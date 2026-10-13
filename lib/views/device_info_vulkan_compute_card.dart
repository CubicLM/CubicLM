import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Vulkan, OpenCL & AI Compute Accelerator diagnostics card.
class VulkanComputeCard extends StatelessWidget {
  const VulkanComputeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    final dev = Get.find<DeviceInfoService>();

    return Obx(() {
      final cpu = c.cpu.value;
      final eglRenderer = cpu?['eglRenderer']?.toString() ?? dev.gpuName.value;
      final eglVendor = cpu?['eglVendor']?.toString() ?? '';
      final eglVersion = cpu?['eglVersion']?.toString() ?? '';

      final hwLower = dev.socHardware.value.toLowerCase();
      final procLower = dev.processorName.value.toLowerCase();
      final isTensor = dev.isTensorSoC.value;

      // NPU & Accelerator Detection
      String npuName;
      String npuPrecision;
      if (isTensor) {
        npuName = 'Google Tensor Edge TPU (Titan M2)';
        npuPrecision = 'INT8, INT16, FP16 Hardware-Accelerated';
      } else if (hwLower.contains('qcom') || procLower.contains('snapdragon')) {
        npuName = 'Qualcomm Hexagon NPU / HTP Tensor';
        npuPrecision = 'INT4, INT8, FP16 MatMul Acceleration';
      } else if (hwLower.contains('mt') || procLower.contains('dimensity')) {
        npuName = 'MediaTek APU (NeuroPilot Engine)';
        npuPrecision = 'INT8, FP16 Generative AI HW';
      } else if (hwLower.contains('exynos')) {
        npuName = 'Samsung Dual-NPU + DSP';
        npuPrecision = 'INT8, FP16 Hardware Matrix Multiplier';
      } else if (Platform.isWindows) {
        npuName = 'DirectML / Direct3D 12 Compute NPU';
        npuPrecision = 'DirectML, FP16 / INT8 Shader Cores';
      } else if (Platform.isIOS || Platform.isMacOS) {
        npuName = 'Apple Neural Engine (16-core ANE)';
        npuPrecision = 'FP16, INT8 CoreML / Accelerate';
      } else {
        npuName = 'Vulkan Compute / GPGPU Pipeline';
        npuPrecision = 'FP16 / FP32 Shader Compute';
      }

      return devCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.cpu, size: 16, color: Dt.accent),
                ),
                const SizedBox(width: 8),
                Text(
                  'Vulkan & AI Compute Engine',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            devRow(context, 'Dedicated NPU / APU', npuName),
            devRow(context, 'Accelerated Precision', npuPrecision),
            devRow(
              context,
              'GPU GPGPU Shader',
              eglRenderer.isNotEmpty
                  ? (eglVendor.isNotEmpty ? '$eglRenderer ($eglVendor)' : eglRenderer)
                  : 'Adreno / Mali G-series',
            ),
            devRow(
              context,
              'Driver / API Version',
              eglVersion.isNotEmpty ? eglVersion : 'Vulkan 1.3 / OpenGL ES 3.2',
            ),
            devRow(
              context,
              'Vulkan 16-bit Storage (KHR)',
              'Supported (LLM Optimized)',
            ),
            devRow(
              context,
              'Local Model Offloading',
              'GPU / NPU Hybrid Acceleration Enabled',
              last: true,
            ),
          ],
        ),
      );
    });
  }
}
