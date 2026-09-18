import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/settings_controller.dart';
import '../../services/device_info_service.dart';
import '../../theme/design_tokens.dart';
import 'apple_widgets.dart';
import 'runtime_sections.dart';

/// Dev Tools tab: Strict RAM guard + Developer tools + Linux runtime.
/// Previously scattered across Config and General — now one place.
class DevToolsView extends GetView<SettingsController> {
  const DevToolsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 16),
            if (!kIsWeb) ...[
              sectionLabel(context, 'MEMORY'),
              appleGroupedCard(context, isDark, children: [
                appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.shieldCheck,
                      size: 20, color: Dt.accent),
                  title: 'Strict RAM guard',
                  subtitle: controller.strictRamGuard.value
                      ? 'On — risky loads are blocked'
                      : 'Off — blocked loads ask first (crash risk)',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'How this works',
                        icon: const Icon(LucideIcons.info, size: 19),
                        onPressed: () => _showRamGuardInfo(context),
                      ),
                      Switch.adaptive(
                        value: controller.strictRamGuard.value,
                        activeThumbColor: Dt.accent,
                        onChanged: (v) => _setStrictRamGuard(context, v),
                      ),
                    ],
                  ),
                  onTap: () => _showRamGuardInfo(context),
                  showDivider: false,
                ),
              ]),
              const SizedBox(height: 28),
            ],
            buildDeveloperToolsSection(context, isDark),
            const SizedBox(height: 28),
            LinuxRuntimeSection(isDark: isDark),
            const SizedBox(height: 50),
          ],
        ));
  }

  /// Explains the Strict RAM guard with live numbers: what it blocks,
  /// how the dynamic reserve works, and what turning it off means.
  void _showRamGuardInfo(BuildContext context) {
    double total = 0;
    double avail = 0;
    try {
      if (Get.isRegistered<DeviceInfoService>()) {
        final dev = Get.find<DeviceInfoService>();
        total = dev.totalRamGB.value;
        avail = dev.availableRamGB.value;
      }
    } catch (_) {}
    final roomMb = avail > 0 ? ((avail - 0.25) / 1.25 * 1024).round() : 0;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Strict RAM guard'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('What it does',
                  'Before loading a local model, the app estimates file × 1.25 working space plus context cache. If free RAM cannot cover it, the load is a near-certain native crash — with no error message possible.'),
              _infoRow('Dynamic reserve',
                  'The safety reserve scales with file size (256 MB for tiny models up to 1 GB for huge ones) instead of a fixed 1 GB, so small models are not blocked needlessly.'),
              if (avail > 0)
                _infoRow('Right now',
                    '${avail.toStringAsFixed(1)} GB free of ${total.toStringAsFixed(1)} GB — room for a model up to ≈$roomMb MB.'),
              _infoRow('When off',
                  'Blocked loads ask "Load anyway?" instead of refusing. The loader still frees other models first and uses minimal threads and context — but Android may still close the app mid-load.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  /// Strict-guard toggle with an explicit warning on disable: turning
  /// it off converts would-be refusals into confirmed risky loads, and
  /// the OS may still kill the app mid-load. The switch only flips
  /// after the user accepts that.
  Future<void> _setStrictRamGuard(BuildContext context, bool v) async {
    if (v) {
      await controller.setStrictRamGuard(true);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Turn off Strict RAM guard?'),
        content: const Text(
          'Blocked model loads will ask to proceed anyway instead of '
          'being refused. Android may close CubicLM mid-load if memory '
          'runs out — the loader still minimizes footprint first, but '
          'there is no guarantee.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it on'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I accept the risk'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await controller.setStrictRamGuard(false);
    }
  }
}
