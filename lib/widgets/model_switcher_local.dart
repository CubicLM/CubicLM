/// Local-model tab of the model switcher sheet.
///
/// Split from `model_switcher_sheet.dart` - behavior is unchanged.
/// Contains: scrollController, isDark, LocalModelList(), createState(), build(), _localSubtitle()
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/home_controller.dart';
import '../controllers/model_controller.dart';
import '../core/colors.dart';
import '../models/ai_model.dart';
import '../services/inference_service.dart';
import '../theme/design_tokens.dart';
import 'model_switcher_widgets.dart';

class LocalModelList extends StatefulWidget {
  final ScrollController scrollController;
  final bool isDark;

  const LocalModelList({super.key,
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<LocalModelList> createState() => LocalModelListState();
}

class LocalModelListState extends State<LocalModelList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Obx(() {
      final models = Get.find<ModelController>();
      final inference = Get.find<InferenceService>();

      final entries = models.availableModels
          .where((model) =>
              models.isDownloaded(model.filename) && !models.isImageModel(model))
          .toList()
        ..sort((a, b) {
          final active = inference.loadedModelName.value;
          if (a.filename == active) return -1;
          if (b.filename == active) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      if (entries.isEmpty) {
        return EmptyState(
          icon: Icons.download_rounded,
          title: 'No models downloaded',
          message: 'Download a model to chat on device.',
          actionLabel: 'Browse models',
          onAction: () {
            Navigator.pop(context);
            Get.find<HomeController>().changeTab(1);
          },
          isDark: isDark,
        );
      }

      final q = _query.trim().toLowerCase();
      final filtered = q.isEmpty
          ? entries
          : entries
              .where((m) =>
                  m.name.toLowerCase().contains(q) ||
                  m.filename.toLowerCase().contains(q))
              .toList();

      final activeName = inference.loadedModelName.value;
      final loadingName = inference.isLoadingModel.value
          ? inference.loadingModelName.value
          : '';

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search downloaded models…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() => _query = ''),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Dt.pillMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching models',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final model = filtered[index];
                      final isActive = model.filename == activeName;
                      final isLoading = model.filename == loadingName;
                      final isResident = !models.isLiteRtModel(model) &&
                          inference.isResident(model.filename);
                      return ModelRow(
                        index: index,
                        title: model.name,
                        subtitle: _localSubtitle(models, model),
                        isActive: isActive,
                        isLoading: isLoading,
                        progress:
                            isLoading ? inference.modelLoadProgress.value : null,
                        badge: models.isLiteRtModel(model)
                            ? 'LiteRT'
                            : isResident
                                ? 'In memory · instant'
                                : 'GGUF',
                        badgeColor: models.isLiteRtModel(model)
                            ? AppColors.secondary
                            : isResident
                                ? AppColors.success
                                : null,
                        isDark: isDark,
                        // Any load while one is in flight is dropped by
                        // ModelController, so disable the rows rather than
                        // let taps silently no-op.
                        onTap: isActive || inference.isLoadingModel.value
                            ? null
                            : () {
                                Navigator.pop(context);
                                models.loadModel(model.filename);
                              },
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  String _localSubtitle(ModelController models, AiModel model) {
    final size = models.modelSizeLabel(model);
    if (models.isVisionModel(model)) {
      return size.isEmpty ? 'Vision' : '$size · Vision';
    }
    return size;
  }
}

// ── Cloud models ──

/// Cloud tab of the switcher: every configured provider gets its own
/// collapsible section (like the Explore page's Online list), plus a
/// global search box that matches models across ALL providers at once.
