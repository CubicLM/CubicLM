import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Card 1: AI Hardware & LLM Readiness Card for the Dashboard.
class DashAiAdvisorCard extends StatelessWidget {
  const DashAiAdvisorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dev = Get.find<DeviceInfoService>();

    return Obx(() {
      final ram = dev.totalRamGB.value;
      final tensor = dev.isTensorSoC.value;
      final hw = dev.socHardware.value.toLowerCase();
      final proc = dev.processorName.value.toLowerCase();

      // Calculate AI score
      int score;
      String tierLabel;
      Color tierColor;

      if (ram >= 12) {
        score = 95;
        tierLabel = 'Ultra AI Ready 🚀';
        tierColor = const Color(0xFF10B981);
      } else if (ram >= 8) {
        score = 85;
        tierLabel = 'High Performance 💪';
        tierColor = Dt.accent;
      } else if (ram >= 6) {
        score = 72;
        tierLabel = 'Mid-tier AI Ready 📱';
        tierColor = const Color(0xFFE8A317);
      } else {
        score = 50;
        tierLabel = 'Basic AI Ready ⚠️';
        tierColor = const Color(0xFFEF4444);
      }

      // NPU detection
      String npuName;
      if (tensor) {
        npuName = 'Google Tensor TPU (Titan M2)';
      } else if (hw.contains('qcom') || proc.contains('snapdragon')) {
        npuName = 'Qualcomm Hexagon NPU (HTP Tensor)';
      } else if (hw.contains('mt') || proc.contains('dimensity')) {
        npuName = 'MediaTek APU (NeuroPilot GenAI)';
      } else if (hw.contains('exynos')) {
        npuName = 'Samsung Dual-NPU / Neural Engine';
      } else if (Platform.isIOS || Platform.isMacOS) {
        npuName = 'Apple Neural Engine (16-core ANE)';
      } else if (Platform.isWindows) {
        npuName = 'DirectML / Windows AI Accelerator';
      } else {
        npuName = 'Vulkan / OpenCL GPU Acceleration';
      }

      return devCard(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Dt.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.sparkles,
                        size: 18, color: Dt.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Hardware & LLM Readiness',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800)),
                        Text(npuName,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).hintColor)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: tierColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '$score/100 · $tierLabel',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: tierColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 0.5,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text('On-Device Model Compatibility:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _modelRow(
                context,
                label: 'Small Models (1B - 3B)',
                status: '🟢 Excellent (~35-60 t/s)',
                models: 'Llama 3.2 3B, Qwen 2.5 3B, Phi-3.5',
              ),
              const SizedBox(height: 6),
              _modelRow(
                context,
                label: 'Medium Models (7B)',
                status: ram >= 6
                    ? '🟢 Supported (4-bit INT4)'
                    : '🟡 Limited RAM Headroom',
                models: 'Qwen 2.5 7B, Mistral 7B',
              ),
              const SizedBox(height: 6),
              _modelRow(
                context,
                label: 'Large Models (14B+)',
                status: ram >= 12
                    ? '🟡 Supported with Swap'
                    : '🔴 High RAM Requirement',
                models: 'Qwen 14B, DeepSeek R1 14B',
              ),
            ],
          ));
    });
  }

  Widget _modelRow(BuildContext context,
      {required String label,
      required String status,
      required String models}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                Text(models,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          Text(status,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
