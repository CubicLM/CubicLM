import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/cloud_model_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import 'app_ui.dart';
import '../theme/design_tokens.dart';
import 'model_switcher_widgets.dart';
import 'model_switcher_local.dart';
import 'model_switcher_cloud.dart';

/// Opens the in-chat model switcher.
///
/// Picking a downloaded local model swaps it in immediately — the resident model
/// is freed and the new one loads in a single tap, no unload step and no app
/// restart. The one exception is a GGUF ↔ LiteRT switch, which still prompts to
/// restart because the two native runtimes cannot safely co-exist in one
/// process (see [ModelController.loadModel]).
void showModelSwitcherSheet(BuildContext context) {
  showAppBottomSheet<void>(
    context,
    builder: (_) => const ModelSwitcherSheet(),
  );
}

class ModelSwitcherSheet extends StatefulWidget {
  const ModelSwitcherSheet({super.key});

  @override
  State<ModelSwitcherSheet> createState() => _ModelSwitcherSheetState();
}

class _ModelSwitcherSheetState extends State<ModelSwitcherSheet> {
  /// 'local' or 'cloud'. Seeded from the current inference mode so the sheet
  /// opens on the tab the user is actually chatting with.
  late String _scope;

  @override
  void initState() {
    super.initState();
    _scope = Get.find<SettingsController>().inferenceMode.value == 'cloud'
        ? 'cloud'
        : 'local';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        // Outer chrome (rounded top + drag handle) comes from AppBottomSheet.
        return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Switch Model',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.textPrimary
                            : Dt.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    ManageModelsButton(isDark: isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ActiveModelHeader(isDark: isDark),
              ),
              Obx(() {
                final isCloud =
                    Get.find<SettingsController>().inferenceMode.value == 'cloud';
                if (!isCloud) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Get.find<CloudModelController>()
                            .deactivateCloudProvider();
                      },
                      icon: const Icon(Icons.phone_android, size: 16),
                      label: Text('Switch to Local Model',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Dt.accent,
                        side: BorderSide(
                            color: Dt.accent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ScopeToggle(
                  scope: _scope,
                  isDark: isDark,
                  onChanged: (value) => setState(() => _scope = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _scope == 'local'
                    ? LocalModelList(
                        scrollController: scrollController, isDark: isDark)
                    : CloudModelList(
                        scrollController: scrollController, isDark: isDark),
              ),
              PinToChatRow(isDark: isDark),
              CompareRow(isDark: isDark),
      ],
        );
      },
    );
  }
}

// ── Pin current model to the open chat ──
