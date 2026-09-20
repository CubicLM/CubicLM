/// Cloud-model tab of the model switcher sheet.
///
/// Split from `model_switcher_sheet.dart` - behavior is unchanged.
/// Contains: scrollController, isDark, CloudModelList(), createState(), build(), _buildGroupedView()
///   _providerSection(), _miniFilterChip(), _companyChip(), _buildSearchView(), _customName()
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/home_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../models/cloud_provider_info.dart';
import 'model_switcher_widgets.dart';

class CloudModelList extends StatefulWidget {
  final ScrollController scrollController;
  final bool isDark;

  const CloudModelList({super.key,
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<CloudModelList> createState() => CloudModelListState();
}

class CloudModelListState extends State<CloudModelList> {
  String _query = '';

  /// One key per provider section so we can auto-scroll an expanded
  /// section into view instead of letting it grow off-screen below.
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Obx(() {
      final cloudModels = Get.find<CloudModelController>();
      final settings = Get.find<SettingsController>();

      // Only providers with a key/config can list models.
      // Use orderedProviders() which already excludes unkeyed.
      final providers = cloudModels.orderedProviders()
          .where((p) => cloudModels.canSelectModel(p.id))
          .toList()
        ..sort((a, b) {
          final activeId = cloudModels.activeProvider;
          if (a.id == activeId) return -1;
          if (b.id == activeId) return 1;
          return cloudModels
              .providerOrderIndex(a.id)
              .compareTo(cloudModels.providerOrderIndex(b.id));
        });

      if (providers.isEmpty) {
        return EmptyState(
          icon: Icons.key_off_rounded,
          title: 'API key needed',
          message:
              'Add a key for any provider to use cloud models.',
          actionLabel: 'Open cloud settings',
          onAction: () {
            Navigator.pop(context);
            Get.find<HomeController>().changeTab(1);
          },
          isDark: isDark,
        );
      }

      return Column(
        children: [
          // ── Global search across all providers ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search all cloud models…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 19),
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
            child: _query.trim().isEmpty
                ? _buildGroupedView(cloudModels, settings, providers, isDark)
                : _buildSearchView(cloudModels, providers, isDark),
          ),
        ],
      );
    });
  }

  // ── Grouped sections (one per provider) ──

  Widget _buildGroupedView(
    CloudModelController cloudModels,
    SettingsController settings,
    List<CloudProviderInfo> providers,
    bool isDark,
  ) {
    final isCloudActive = settings.inferenceMode.value == 'cloud';
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: providers.length,
      itemBuilder: (context, index) => _providerSection(
        cloudModels,
        settings,
        providers[index],
        isDark,
        isActiveSection:
            isCloudActive && providers[index].id == cloudModels.activeProvider,
      ),
    );
  }

  Widget _providerSection(
    CloudModelController cloudModels,
    SettingsController settings,
    CloudProviderInfo provider,
    bool isDark, {
    required bool isActiveSection,
  }) {
    return KeyedSubtree(
      key: _sectionKeys.putIfAbsent(provider.id, () => GlobalKey()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActiveSection
                ? Dt.accent.withValues(alpha: 0.5)
                : (isDark ? AppColors.border : AppColors.borderLightMode),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('switcher_${provider.id}'),
            initiallyExpanded: isActiveSection,
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onExpansionChanged: (open) {
              if (!open) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 260), () {
                  if (!mounted) return;
                  final ctx = _sectionKeys[provider.id]?.currentContext;
                  if (ctx != null && ctx.mounted) {
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      alignment: 0.0,
                    );
                  }
                });
              });
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActiveSection
                    ? Dt.accent.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Dt.pillMuted),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                provider.icon,
                color: isActiveSection
                    ? Dt.accent
                    : Theme.of(context).hintColor,
                size: 20,
              ),
            ),
            title: Text(
              provider.id == 'custom'
                  ? _customName(settings)
                  : provider.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              provider.id == 'custom'
                  ? 'Custom OpenAI-compatible endpoint'
                  : provider.description,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActiveSection)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 22,
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 12),
                    // -- Header with count + free filter (same as Explore) --
                    Obx(() {
                      final all =
                          cloudModels.modelsByProvider[provider.id] ?? [];
                      final freeCount =
                          cloudModels.freeModelCountFor(provider.id);
                      return Row(
                        children: [
                          Text(
                            'Models',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  Dt.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${all.length}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Dt.accent)),
                          ),
                          if (freeCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$freeCount free',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.success)),
                            ),
                          ],
                          const Spacer(),
                          if (freeCount > 0)
                            _miniFilterChip(
                              context,
                              'Free',
                              cloudModels.freeFirstByProvider[provider.id] ==
                                  true,
                              () =>
                                  cloudModels.toggleFreeFirst(provider.id),
                              isDark,
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: 10),
                    // -- Per-provider search (same as Explore) --
                    TextField(
                      onChanged: (v) =>
                          cloudModels.searchByProvider[provider.id] = v,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search models...',
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: Obx(() => (cloudModels.searchByProvider[
                                        provider.id] ??
                                    '')
                                .isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                onPressed: () => cloudModels
                                    .searchByProvider[provider.id] = '',
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                              )
                            : const SizedBox.shrink()),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        fillColor: isDark
                            ? Colors.black.withValues(alpha: 0.2)
                            : Dt.pillMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // -- Auto-detected company filter (same as Explore) --
                    Obx(() {
                      final companies =
                          cloudModels.availableCompaniesFor(provider.id);
                      if (companies.length < 2) {
                        return const SizedBox.shrink();
                      }
                      final selected =
                          cloudModels.companyFilterByProvider[provider.id];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _companyChip(
                                    context,
                                    'All',
                                    Icons.apps,
                                    selected == null || selected.isEmpty,
                                    () => cloudModels
                                        .setCompanyFilter(provider.id, null),
                                    isDark),
                                for (final c in companies)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 6),
                                    child: _companyChip(
                                        context,
                                        cloudModels
                                            .companyDisplayName(c),
                                        cloudModels.companyIcon(c) ??
                                            Icons.cloud_outlined,
                                        selected == c,
                                        () => cloudModels
                                            .setCompanyFilter(provider.id, c),
                                        isDark),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    }),
                    // -- Compact boxed model list (same as Explore) --
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: Obx(() {
                        final filtered =
                            cloudModels.filteredModelsFor(provider.id);
                        if (filtered.isEmpty) {
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Text('No matching models',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color:
                                          Theme.of(context).hintColor)),
                            ),
                          );
                        }
                        final activeModel =
                            cloudModels.activeModelFor(provider.id);
                        return ListView.builder(
                          shrinkWrap: true,
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final model = filtered[index];
                            final isActive = isActiveSection &&
                                activeModel == model;
                            final isFree = cloudModels.isFreeModel(
                                provider.id, model);
                            return ModelRow(
                              index: index,
                              title: model,
                              subtitle: '',
                              isActive: isActive,
                              isLoading: false,
                              progress: null,
                              badge: isFree ? 'FREE' : null,
                              badgeColor:
                                  isFree ? AppColors.success : null,
                              isDark: isDark,
                              onTap: isActive
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      cloudModels.selectModel(
                                          provider.id, model);
                                    },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Small pill chip used in section headers (Free toggle) --
  Widget _miniFilterChip(BuildContext context, String label, bool selected,
      VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Dt.accent.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Dt.pillMuted),
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: Dt.accent.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected
                ? Dt.accent
                : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }

  // -- Company pill chip (auto-detected vendor filters) --
  Widget _companyChip(BuildContext context, String label, IconData icon,
      bool selected, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Dt.accent.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Dt.pillMuted),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Dt.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected
                    ? Dt.accent
                    : Theme.of(context).hintColor),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? Dt.accent
                        : Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  // ── Flat search results across all providers ──

  Widget _buildSearchView(
    CloudModelController cloudModels,
    List<CloudProviderInfo> providers,
    bool isDark,
  ) {
    final q = _query.trim().toLowerCase();
    final settings = Get.find<SettingsController>();
    final isCloudActive = settings.inferenceMode.value == 'cloud';
    final activeProviderId = cloudModels.activeProvider;

    final matches = <MapEntry<CloudProviderInfo, String>>[];
    for (final p in providers) {
      for (final id in cloudModels.modelsByProvider[p.id] ?? const <String>[]) {
        if (id.toLowerCase().contains(q)) {
          matches.add(MapEntry(p, id));
        }
      }
    }

    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No matching models',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final entry = matches[index];
        final provider = entry.key;
        final id = entry.value;
        final isActive = isCloudActive &&
            provider.id == activeProviderId &&
            id == cloudModels.activeModelFor(provider.id);
        final isFree = cloudModels.isFreeModel(provider.id, id);
        return ModelRow(
          index: index,
          title: id,
          subtitle: provider.id == 'custom'
              ? _customName(settings)
              : provider.name,
          isActive: isActive,
          isLoading: false,
          progress: null,
          badge: isFree ? 'FREE' : null,
          badgeColor: isFree ? AppColors.success : null,
          isDark: isDark,
          onTap: isActive
              ? null
              : () {
                  Navigator.pop(context);
                  cloudModels.selectModel(provider.id, id);
                },
        );
      },
    );
  }

  String _customName(SettingsController settings) {
    final name = settings.customCloudName.value;
    return name.isEmpty ? 'Custom API' : name;
  }
}

// ── Shared rows ──

