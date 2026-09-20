/// Small rows and headers for the model switcher sheet.
///
/// Split from `model_switcher_sheet.dart` - behavior is unchanged.
/// Contains: isDark, PinToChatRow(), build(), isDark, CompareRow(), build(), _pickChallenger(), isDark
///   ManageModelsButton(), build(), isDark, ActiveModelHeader(), build(), _providerLabel(), scope
///   isDark, onChanged, ScopeToggle(), build(), _tab(), title, subtitle, isActive, isLoading
///   progress, badge, badgeColor, isDark, onTap, index, ModelRow(), build(), icon, title, message
///   actionLabel, onAction, isDark, EmptyState(), build(), name
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/home_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../theme/design_tokens.dart';


class PinToChatRow extends StatelessWidget {
  final bool isDark;

  const PinToChatRow({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chat = Get.find<ChatController>();
      if (chat.currentSessionId.value.isEmpty) {
        return const SizedBox.shrink();
      }
      final pinned = chat.chatHasModelPin;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                pinned
                    ? '📌 ${chat.chatPinnedModelLabel} · this chat only'
                    : 'Remember current model for this chat',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).hintColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Switch.adaptive(
              value: pinned,
              activeThumbColor: Dt.accent,
              onChanged: (on) {
                if (on) {
                  chat.pinModelToChat();
                } else {
                  chat.clearChatModelPin();
                }
              },
            ),
          ],
        ),
      );
    });
  }
}

// ── Compare next answer with a challenger (one-shot) ──

class CompareRow extends StatelessWidget {
  final bool isDark;

  const CompareRow({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chat = Get.find<ChatController>();
      final label = chat.compareLabel.value;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.isEmpty
                    ? 'Compare next answer with…'
                    : '⚖️ Next answer also from $label',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).hintColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (label.isNotEmpty)
              IconButton(
                tooltip: 'Clear challenger',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => chat.clearCompareChallenger(),
              )
            else
              IconButton(
                tooltip: 'Pick challenger',
                icon: const Icon(Icons.balance, size: 18),
                onPressed: () => _pickChallenger(context),
              ),
          ],
        ),
      );
    });
  }

  void _pickChallenger(BuildContext context) {
    final cmc = Get.find<CloudModelController>();
    final models = Get.find<ModelController>();
    final entries = <Map<String, String>>[];
    try {
      cmc.modelsByProvider.forEach((provider, list) {
        for (final m in list) {
          entries.add({'mode': 'cloud', 'provider': provider, 'model': m});
        }
      });
    } catch (_) {}
    try {
      for (final m in models.availableModels) {
        if (models.isDownloaded(m.filename) && !models.isImageModel(m)) {
          entries.add({'mode': 'local', 'provider': '', 'model': m.filename});
        }
      }
    } catch (_) {}
    final query = ValueNotifier('');
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Compare with'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Search models…', isDense: true),
                onChanged: (v) => query.value = v.trim().toLowerCase(),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, q, __) {
                    final filtered = q.isEmpty
                        ? entries
                        : entries
                            .where((e) =>
                                (e['model'] ?? '')
                                    .toLowerCase()
                                    .contains(q) ||
                                (e['provider'] ?? '')
                                    .toLowerCase()
                                    .contains(q))
                            .toList();
                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No models found'),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length > 60 ? 60 : filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final title = e['mode'] == 'cloud'
                            ? '${e['provider']}: ${e['model']}'
                            : (e['model'] ?? '').replaceAll('.gguf', '');
                        return ListTile(
                          dense: true,
                          title: Text(title,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(dlgCtx);
                            Get.find<ChatController>().setCompareChallenger(
                                e['mode'] ?? 'cloud',
                                e['provider'] ?? '',
                                e['model'] ?? '');
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel')),
        ],
      ),
    );
  }
}

// ── Header ──

class ManageModelsButton extends StatelessWidget {
  final bool isDark;

  const ManageModelsButton({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        Get.find<HomeController>().changeTab(1);
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(
              'Manage',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Dt.accent,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward_rounded,
                size: 15, color: Dt.accent),
          ],
        ),
      ),
    );
  }
}

class ActiveModelHeader extends StatelessWidget {
  final bool isDark;

  const ActiveModelHeader({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();
      final isCloud = settings.inferenceMode.value == 'cloud';

      final String label;
      final String subtitle;
      final IconData icon;
      final Color accent;

      if (isCloud) {
        final model = settings.selectedCloudModelName;
        label = model.isEmpty ? 'No cloud model selected' : model;
        subtitle = '☁ ${_providerLabel(settings)}';
        icon = Icons.cloud_outlined;
        accent = Dt.accent;
      } else if (inference.isLoadingModel.value) {
        label = inference.loadingModelName.value.isEmpty
            ? 'Loading…'
            : _stripExtension(inference.loadingModelName.value);
        final pct = (inference.modelLoadProgress.value * 100).clamp(0, 100);
        subtitle = 'Loading · ${pct.round()}%';
        icon = Icons.downloading_rounded;
        accent = AppColors.warning;
      } else if (inference.isModelLoaded.value) {
        label = _stripExtension(inference.loadedModelName.value);
        subtitle = inference.isGpuAccelerated.value
            ? '⚡ GPU${inference.gpuName.value.isEmpty ? '' : ': ${inference.gpuName.value}'}'
            : '🖥 CPU Neural Engine';
        icon = inference.isGpuAccelerated.value
            ? Icons.bolt_rounded
            : Icons.memory_rounded;
        accent = AppColors.success;
      } else if (localImage.isModelLoaded.value) {
        label = _stripExtension(localImage.loadedModelName.value);
        subtitle = localImage.isUsingGpu.value
            ? '⚡ GPU Image Synthesis'
            : '🖥 CPU Image Synthesis';
        icon = Icons.image_rounded;
        accent = AppColors.success;
      } else {
        label = 'No model loaded';
        subtitle = 'Pick one below to start chatting';
        icon = Icons.hourglass_empty_rounded;
        accent = AppColors.warning;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Dt.pillMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCloud ? 'ACTIVE CLOUD MODEL' : 'ACTIVE MODEL',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimary
                          : Dt.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.firaCode(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  String _providerLabel(SettingsController settings) {
    final id = settings.cloudProvider.value;
    if (id == 'custom') {
      final name = settings.customCloudName.value;
      return name.isEmpty ? 'Custom API' : name;
    }
    final provider = Get.find<CloudModelController>()
        .providers
        .firstWhereOrNull((p) => p.id == id);
    return provider?.name ?? id;
  }
}

class ScopeToggle extends StatelessWidget {
  final String scope;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const ScopeToggle({super.key,
    required this.scope,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.pillMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('local', 'On Device', Icons.smartphone_rounded, context),
          _tab('cloud', 'Cloud', Icons.cloud_outlined, context),
        ],
      ),
    );
  }

  Widget _tab(String value, String label, IconData icon, BuildContext context) {
    final selected = scope == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.surfaceLight : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(
                    color: Dt.accent.withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? Dt.accent
                      : Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Dt.accent
                      : Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Local models ──

class ModelRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isLoading;
  final double? progress;
  final String? badge;
  final Color? badgeColor;
  final bool isDark;
  final VoidCallback? onTap;
  final int? index;

  const ModelRow({super.key,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isLoading,
    required this.progress,
    required this.badge,
    required this.isDark,
    required this.onTap,
    this.badgeColor,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    final accent = badgeColor ?? Dt.accent;
    final isDisabled = onTap == null && !isActive;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: isActive
                    ? Dt.accent.withValues(alpha: 0.08)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Dt.canvas),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? Dt.accent.withValues(alpha: 0.4)
                      : (isDark
                          ? AppColors.border
                          : AppColors.borderLightMode),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (index != null)
                        Container(
                          width: 26,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Dt.accent.withValues(alpha: 0.15)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${index! + 1}',
                            style: GoogleFonts.firaCode(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? Dt.accent
                                  : Theme.of(context).hintColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (index != null) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _stripExtension(title),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textPrimary
                                    : Dt.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            badge!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      if (isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.warning,
                          ),
                        )
                      else if (isActive)
                        const Icon(Icons.check_circle_rounded,
                            size: 20, color: AppColors.success)
                      else
                        Icon(Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isDark
                                ? AppColors.surfaceLight
                                : Dt.toggleTrackOff),
                    ],
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (progress ?? 0).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: isDark
                            ? AppColors.surfaceLight
                            : Dt.hairline,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isDark;

  const EmptyState({super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 28, color: Dt.accent),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color:
                    isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Dt.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _stripExtension(String name) {
  for (final ext in const ['.gguf', '.litertlm', '.safetensors']) {
    if (name.toLowerCase().endsWith(ext)) {
      return name.substring(0, name.length - ext.length);
    }
  }
  return name;
}
