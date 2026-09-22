import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../services/memory_service.dart';
import '../core/routes.dart';
import '../core/colors.dart';
import '../services/tts_service.dart';
import 'about_view.dart';
import 'language_picker_view.dart';
import 'log_view.dart';
import 'memory_view.dart';
import 'server_view.dart';
import 'settings_view.dart';
import 'setup_recommendations_view.dart';
import 'settings/dev_tools_view.dart';
import 'settings/data_view.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_ui.dart';
import '../widgets/thinking_orb.dart';

/// Dedicated App Settings page — personalisation & about info.
///
/// Split out of the main Config page: appearance (theme), typography
/// scale, and app info live here; everything inference/model related
/// stays in Config.
/// One jump target in Settings search.
class _SettingSearchEntry {
  final String title;
  final String keywords;
  final int tab;
  final VoidCallback? open;

  const _SettingSearchEntry({
    required this.title,
    this.keywords = '',
    required this.tab,
    this.open,
  });

  String get hint {
    const names = [
      'General',
      'Nodes',
      'Config',
      'Parameters',
      'Dev Tools',
      'Data'
    ];
    return (tab >= 0 && tab < names.length) ? names[tab] : '';
  }

  /// Tab icon shown next to the result.
  IconData get icon {
    switch (tab) {
      case 1:
        return LucideIcons.server;
      case 2:
        return LucideIcons.slidersHorizontal;
      case 3:
        return LucideIcons.gauge;
      case 4:
        return LucideIcons.wrench;
      case 5:
        return LucideIcons.database;
      default:
        return LucideIcons.settings;
    }
  }
}

class AppSettingsView extends GetView<SettingsController> {
  AppSettingsView({super.key});

  /// Inline expand state for the Composer-buttons section (no drawer —
  /// the four visibility switches live right under the header row).
  final _composerOpen = false.obs;

  void _showCodeEditorInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Code Editor Comparison'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Canvas Split Editor (Recommended)',
                  'Custom TextField with dynamic line-number gutter, auto-closing brackets (), {}, [], <>, side-by-side live preview (HTML / Mermaid), AI iteration loop, and JavaScript console output without external bloat.'),
              _infoRow('Lightweight Plain Editor',
                  'Clean TextField with line numbers only. Best if you just want to edit raw text quickly without rendering previews or executing scripts.'),
              _infoRow('Dependency vs Performance',
                  'Heavy external packages (e.g. re_editor or flutter_code_editor) add extra APK size and memory overhead. CubicLM gives you high performance with zero extra dependencies so the app stays lightning-fast.'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: Obx(() => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: AppColors.blurSigma, sigmaY: AppColors.blurSigma),
            child: Container(color: Colors.transparent),
          )),
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('settings_title'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -1)),
        toolbarHeight: 70,
        centerTitle: false,
        actions: [
          Obx(() => IconButton(
                tooltip: 'Search settings',
                icon: Icon(
                    controller.settingsSearching.value
                        ? LucideIcons.x
                        : LucideIcons.search,
                    size: 20),
                onPressed: () {
                  final s = controller;
                  final on = !s.settingsSearching.value;
                  s.settingsSearching.value = on;
                  if (on) {
                    _searchCtrl.clear();
                    s.settingsSearchQuery.value = '';
                  }
                },
              )),
          IconButton(
            tooltip: 'System logs',
            icon: const Icon(LucideIcons.terminal, size: 20),
            onPressed: () => Get.to(() => const LogView()),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Theme.of(context).primaryColor,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Theme.of(context).hintColor,
          dividerColor: Colors.transparent,
          labelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: 'settings_tab_general'.tr),
            Tab(text: 'nodes_node'.tr),
            Tab(text: 'nodes_config'.tr),
            Tab(text: 'settings_tab_parameters'.tr),
            Tab(text: 'settings_tab_devtools'.tr),
            Tab(text: 'settings_tab_data'.tr),
          ],
        ),
      ),
      body: Obx(() => controller.settingsSearching.value
          ? _buildSearchBody(context)
          : TabBarView(
        children: [
          Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 12),
              _sectionLabel(context, 'settings_appearance'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: Icon(LucideIcons.palette,
                      size: 20, color: Theme.of(context).primaryColor),
                  title: 'settings_personalize'.tr,
                  subtitle: 'settings_personalize_desc'.tr,
                  trailing: const Icon(LucideIcons.chevronRight, size: 20),
                  onTap: () => Get.toNamed(AppRoutes.personalization),
                ),
                for (final mode in [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system
                ])
                  _appleListTile(
                    context,
                    isDark,
                    leading: Icon(_themeModeIcon(mode),
                        size: 20, color: Theme.of(context).hintColor),
                    title: _themeModeName(mode),
                    trailing: controller.themeMode.value == mode
                        ? Icon(LucideIcons.check,
                            size: 20, color: Theme.of(context).primaryColor)
                        : null,
                    showDivider: mode != ThemeMode.system,
                    onTap: () => controller.setThemeMode(mode),
                  ),
              ]),
              const SizedBox(height: 20),
              _buildFontSizeCard(context, isDark),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_thinking_orbs'.tr),
              _appleGroupedCard(context, isDark, children: [
                _orbTile(context, isDark,
                    icon: LucideIcons.messageSquare,
                    title: 'orb_while_chatting'.tr,
                    subtitle: 'orb_chat_subtitle'.tr,
                    slot: 'chat',
                    selection: controller.orbChatAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.image,
                    title: 'orb_image_gen'.tr,
                    subtitle: 'orb_image_subtitle'.tr,
                    slot: 'image',
                    selection: controller.orbImageAnim),
                _orbTile(context, isDark,
                    icon: LucideIcons.brain,
                    title: 'orb_analyzing'.tr,
                    subtitle: 'orb_analysis_subtitle'.tr,
                    slot: 'analysis',
                    selection: controller.orbAnalysisAnim,
                    showDivider: false),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'READ ALOUD'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.volume2,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'Read aloud',
                      subtitle: controller.readAloudEnabled.value
                          ? 'Tap speaker on assistant messages to hear them'
                          : 'Text-to-speech is off',
                      value: controller.readAloudEnabled.value,
                      onChanged: (v) {
                        controller.setReadAloudEnabled(v);
                        // Stop any ongoing speech when turning off (web stub is no-op).
                        if (!v) {
                          try {
                            if (Get.isRegistered<TtsService>()) {
                              Get.find<TtsService>().stop();
                            }
                          } catch (_) {}
                        }
                      },
                    )),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'MEMORY'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() {
                  final mem = Get.find<MemoryService>();
                  return _appleListTile(
                    context,
                    isDark,
                    leading: Icon(LucideIcons.brain,
                        size: 20, color: Theme.of(context).primaryColor),
                    title: 'Memory',
                    subtitle: mem.isEnabled.value
                        ? '${mem.memoryCount} fact${mem.memoryCount == 1 ? '' : 's'} stored'
                        : 'Disabled — CubicLM won\'t remember facts',
                    trailing: const Icon(LucideIcons.chevronRight, size: 20),
                    onTap: () => Get.to(() => const MemoryView()),
                  );
                }),
              ]),
              const SizedBox(height: 28),
              Row(
                children: [
                  _sectionLabel(context, 'CODE EDITOR'),
                  const Spacer(),
                  IconButton(
                    icon: Icon(LucideIcons.info, size: 16, color: Theme.of(context).primaryColor),
                    tooltip: 'Editor Information',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showCodeEditorInfo(context),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleListTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.layout,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'Canvas Split Editor',
                      subtitle: 'Side-by-side code editor + live preview with auto-close',
                      trailing: controller.codeEditorType.value == 'split'
                          ? Icon(LucideIcons.check, size: 20, color: Theme.of(context).primaryColor)
                          : null,
                      onTap: () => controller.setCodeEditorType('split'),
                    )),
                Obx(() => _appleListTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.code,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'Lightweight Editor',
                      subtitle: 'Plain TextField + line numbers (zero overhead)',
                      trailing: controller.codeEditorType.value == 'plain'
                          ? Icon(LucideIcons.check, size: 20, color: Theme.of(context).primaryColor)
                          : null,
                      onTap: () => controller.setCodeEditorType('plain'),
                    )),
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.clipboardPaste,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'Long-paste to file',
                      subtitle: controller.longPasteToFile.value
                          ? 'Huge pastes attach as .md files'
                          : 'Huge pastes stay as text',
                      value: controller.longPasteToFile.value,
                      onChanged: (v) => controller.setLongPasteToFile(v),
                    )),
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.slidersHorizontal,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'Composer buttons',
                      subtitle: _composerOpen.value
                          ? 'Tap to collapse'
                          : 'Show or hide chat input icons',
                      value: _composerOpen.value,
                      onChanged: (v) => _composerOpen.value = v,
                    )),
                Obx(() => _composerOpen.value
                    ? Column(
                        children: [
                          _appleSwitchTile(
                            context,
                            isDark,
                            leading: Icon(LucideIcons.globe,
                                size: 20,
                                color: Theme.of(context).primaryColor),
                            title: 'Web access',
                            subtitle: controller.showWebAccess.value
                                ? 'Visible in the composer'
                                : 'Hidden from the composer',
                            value: controller.showWebAccess.value,
                            onChanged: (v) =>
                                controller.setShowWebAccess(v),
                          ),
                          _appleSwitchTile(
                            context,
                            isDark,
                            leading: Icon(LucideIcons.search,
                                size: 20,
                                color: Theme.of(context).primaryColor),
                            title: 'Deep Search',
                            subtitle: controller.showDeepSearch.value
                                ? 'Visible in the composer'
                                : 'Hidden from the composer',
                            value: controller.showDeepSearch.value,
                            onChanged: (v) =>
                                controller.setShowDeepSearch(v),
                          ),
                          _appleSwitchTile(
                            context,
                            isDark,
                            leading: Icon(LucideIcons.video,
                                size: 20,
                                color: Theme.of(context).primaryColor),
                            title: 'Live Vision',
                            subtitle: controller.showLiveVision.value
                                ? 'Visible in the composer'
                                : 'Hidden from the composer',
                            value: controller.showLiveVision.value,
                            onChanged: (v) =>
                                controller.setShowLiveVision(v),
                          ),
                          _appleSwitchTile(
                            context,
                            isDark,
                            leading: Icon(LucideIcons.sparkles,
                                size: 20,
                                color: Theme.of(context).primaryColor),
                            title: 'Polish Prompt',
                            subtitle: controller.showPolishPrompt.value
                                ? 'Visible in the composer'
                                : 'Hidden from the composer',
                            value: controller.showPolishPrompt.value,
                            onChanged: (v) =>
                                controller.setShowPolishPrompt(v),
                          ),
                        ],
                      )
                    : const SizedBox.shrink()),
                Obx(() {
                  final style = controller.contextWindowStyle.value;
                  return _appleListTile(
                    context,
                    isDark,
                    leading: Icon(LucideIcons.gauge,
                        size: 20,
                        color: Theme.of(context).primaryColor),
                    title: 'Context window',
                    subtitle: style == 'ring'
                        ? 'Ring badge in the chat header'
                        : style == 'composer'
                            ? 'Bar above the send button'
                            : 'Bar below the chat header',
                    trailing:
                        const Icon(LucideIcons.chevronRight, size: 20),
                    onTap: () =>
                        _showContextWindowSheet(context, isDark),
                  );
                }),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_startup'.tr),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.rocket,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'startup_auto_load'.tr,
                      subtitle: controller.autoLoadLastModel.value
                          ? 'startup_auto_load_on'.tr
                          : 'startup_auto_load_off'.tr,
                      value: controller.autoLoadLastModel.value,
                      onChanged: (v) => controller.setAutoLoadLastModel(v),
                    )),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'SETUP'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: Icon(LucideIcons.listChecks,
                      size: 20, color: Theme.of(context).primaryColor),
                  title: 'Recommended setup',
                  subtitle:
                      'Notifications, battery, runtime, keys — all optional',
                  trailing: const Icon(LucideIcons.chevronRight, size: 20),
                  onTap: () => Get.to(() => const SetupRecommendationsView()),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'SECURITY'),
              _appleGroupedCard(context, isDark, children: [
                Obx(() => _appleSwitchTile(
                      context,
                      isDark,
                      leading: Icon(LucideIcons.fingerprint,
                          size: 20, color: Theme.of(context).primaryColor),
                      title: 'App Lock',
                      subtitle: !controller.biometricsAvailable.value
                          ? 'No biometric hardware detected on this device'
                          : !controller.hasEnrolledBiometrics.value
                              ? 'Nothing enrolled — device PIN will be used'
                              : (controller.appLockEnabled.value
                                  ? 'Biometrics or device PIN required to open the app'
                                  : 'Require biometrics or device PIN to open the app'),
                      value: controller.appLockEnabled.value,
                      onChanged: (v) => controller.setAppLockEnabled(v),
                    )),
                Obx(() {
                  if (!controller.appLockEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  final t = controller.lockTimeoutMinutes.value;
                  final label = t <= 0
                      ? 'Immediately'
                      : t == 1
                          ? 'After 1 min'
                          : 'After $t min';
                  return _appleListTile(
                    context,
                    isDark,
                    leading: Icon(LucideIcons.timer,
                        size: 20, color: Theme.of(context).primaryColor),
                    title: 'Re-lock',
                    subtitle: 'Lock again $label in background',
                    onTap: () => _pickLockTimeout(context, controller),
                  );
                }),
                Obx(() {
                  if (!controller.appLockEnabled.value) {
                    return const SizedBox.shrink();
                  }
                  return _appleSwitchTile(
                    context,
                    isDark,
                    leading: Icon(LucideIcons.scanFace,
                        size: 20, color: Theme.of(context).primaryColor),
                    title: 'Biometric only',
                    subtitle: controller.lockBiometricOnly.value
                        ? 'Device PIN will NOT unlock the app'
                        : 'Allow device PIN as fallback',
                    value: controller.lockBiometricOnly.value,
                    onChanged: (v) => controller.setLockBiometricOnly(v),
                  );
                }),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_language'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      Icon(LucideIcons.globe, size: 20, color: Theme.of(context).primaryColor),
                  title: 'settings_language'.tr,
                  subtitle:
                      '${controller.locale.value.flag}  ${controller.locale.value.nativeName}',
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18, color: Theme.of(context).hintColor),
                  onTap: () => Get.to(() => const LanguagePickerView()),
                ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'settings_app_info'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: Icon(LucideIcons.arrowDownToLine,
                      size: 20, color: Theme.of(context).primaryColor),
                  title: 'View Update',
                  subtitle: 'Version, highlights & update settings',
                  trailing: Icon(LucideIcons.chevronRight,
                      size: 18, color: Theme.of(context).hintColor),
                  onTap: () => Get.toNamed(AppRoutes.update),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: InkWell(
                    onTap: () => Get.to(() => const AboutView()),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(children: [
                      Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/icons/CubicLM.png',
                            fit: BoxFit.cover,
                          )),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CubicLM',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                  'Developed by Abir Hasan Siam (CodeCraftedStudio)',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).primaryColor.withValues(alpha: 0.7))),
                              const SizedBox(height: 1),
                              Obx(() => Text(
                                  controller.appVersion.value.isEmpty
                                      ? 'Engineering Build'
                                      : 'Version ${controller.appVersion.value}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).hintColor))),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 50),
            ],
          )),
          const ServerView(embedded: true),
          const SettingsView(embedded: true, hideParams: true),
          const ParametersView(),
          const DevToolsView(),
          const DataView(),
        ],
      ))));
  }

  // ── Settings search ──

  final _searchCtrl = TextEditingController();

  void _toggleSearching() {
    final on = !controller.settingsSearching.value;
    controller.settingsSearching.value = on;
    if (on) {
      _searchCtrl.clear();
      controller.settingsSearchQuery.value = '';
    }
  }

  void _goToTab(BuildContext context, int tab) {
    controller.settingsSearching.value = false;
    controller.settingsSearchQuery.value = '';
    try {
      DefaultTabController.of(context).animateTo(tab);
    } catch (_) {}
  }

  Widget _buildSearchBody(BuildContext context) {
    final query = controller.settingsSearchQuery.value;
    final results = _filterSettings(query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search settings…',
              prefixIcon:
                  const Icon(LucideIcons.search, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: _toggleSearching,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
            onChanged: (v) =>
                controller.settingsSearchQuery.value = v,
          ),
        ),
        Expanded(
          child: query.trim().isEmpty
              ? Center(
                  child: Text(
                    'Type to jump to any setting.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Theme.of(context).hintColor),
                  ),
                )
              : results.isEmpty
                  ? Center(
                      child: Text(
                        'No settings match "$query".',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Theme.of(context).hintColor),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: results.length,
                      itemBuilder: (ctx, i) {
                        final e = results[i];
                        return _appleListTile(
                          context,
                          Theme.of(context).brightness ==
                              Brightness.dark,
                          leading: Icon(e.icon,
                              size: 20,
                              color:
                                  Theme.of(context).primaryColor),
                          title: e.title,
                          subtitle: e.hint,
                          trailing: const Icon(
                              LucideIcons.chevronRight,
                              size: 18),
                          showDivider: i != results.length - 1,
                          onTap: () {
                            if (e.open != null) {
                              controller.settingsSearching
                                  .value = false;
                              controller.settingsSearchQuery.value =
                                  '';
                              e.open!();
                            } else {
                              _goToTab(context, e.tab);
                            }
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  List<_SettingSearchEntry> _filterSettings(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _settingsIndex()
        .where((e) =>
            e.title.toLowerCase().contains(query) ||
            e.keywords.toLowerCase().contains(query))
        .toList();
  }

  /// Jump index across all six tabs. Entries without [open] just
  /// Jump index across all six tabs. Entries without [open] just
  /// switch to their tab; entries with [open] navigate directly.
  List<_SettingSearchEntry> _settingsIndex() => [
        _SettingSearchEntry(
            title: 'Personalize',
            keywords: 'theme color font typography appearance',
            tab: 0,
            open: () => Get.toNamed(AppRoutes.personalization)),
        const _SettingSearchEntry(
            title: 'Theme mode', keywords: 'dark light system', tab: 0),
        _SettingSearchEntry(
            title: 'Language',
            keywords: 'bangla english locale',
            tab: 0,
            open: () => Get.to(() => const LanguagePickerView())),
        const _SettingSearchEntry(
            title: 'Memory', keywords: 'long term recall facts', tab: 0),
        const _SettingSearchEntry(
            title: 'Read aloud',
            keywords: 'tts speech voice speaker',
            tab: 0),
        const _SettingSearchEntry(
            title: 'Thinking orbs', keywords: 'animation', tab: 0),
        const _SettingSearchEntry(
            title: 'Startup', keywords: 'autoload resume', tab: 0),
        _SettingSearchEntry(
            title: 'App info',
            keywords: 'version about update',
            tab: 0,
            open: () => Get.toNamed(AppRoutes.update)),
        const _SettingSearchEntry(
            title: 'Node server',
            keywords: 'api openai endpoint start stop',
            tab: 1),
        const _SettingSearchEntry(
            title: 'API key',
            keywords: 'token bearer security auth',
            tab: 1),
        const _SettingSearchEntry(
            title: 'Recent requests',
            keywords: 'traffic log server calls',
            tab: 1),
        const _SettingSearchEntry(
            title: 'Hardware',
            keywords: 'device ram soc cpu gpu info',
            tab: 2),
        const _SettingSearchEntry(
            title: 'Inference mode',
            keywords: 'local cloud',
            tab: 2),
        const _SettingSearchEntry(
            title: 'System prompt',
            keywords: 'persona instructions',
            tab: 2),
        const _SettingSearchEntry(
            title: 'Skills', keywords: 'extensions prompts', tab: 2),
        const _SettingSearchEntry(
            title: 'MCP server',
            keywords: 'tools remote model context protocol',
            tab: 2),
        const _SettingSearchEntry(
            title: 'Context size',
            keywords: 'context window memory tokens',
            tab: 3),
        const _SettingSearchEntry(
            title: 'Output tokens',
            keywords: 'max tokens length response',
            tab: 3),
        const _SettingSearchEntry(
            title: 'Temperature',
            keywords: 'sampling top-p top-k creativity',
            tab: 3),
        const _SettingSearchEntry(
            title: 'Image generation',
            keywords: 'steps resolution size stable diffusion',
            tab: 3),
        const _SettingSearchEntry(
            title: 'Strict RAM guard',
            keywords: 'memory safety load block',
            tab: 4),
        const _SettingSearchEntry(
            title: 'Developer tools',
            keywords: 'toolchain node python runtime install',
            tab: 4),
        const _SettingSearchEntry(
            title: 'Linux runtime',
            keywords: 'ubuntu proot terminal history',
            tab: 4),
        const _SettingSearchEntry(
            title: 'Export chats',
            keywords: 'backup json download',
            tab: 5),
        const _SettingSearchEntry(
            title: 'Import chats',
            keywords: 'restore backup upload',
            tab: 5),
        const _SettingSearchEntry(
            title: 'Auto backup',
            keywords: 'automatic schedule',
            tab: 5),
        const _SettingSearchEntry(
            title: 'Export folder',
            keywords: 'downloads directory location',
            tab: 5),
        const _SettingSearchEntry(
            title: 'Usage statistics',
            keywords: 'stats count events',
            tab: 5),
        _SettingSearchEntry(
            title: 'System logs',
            keywords: 'diagnostics errors crash debug health',
            tab: 5,
            open: () => Get.to(() => const LogView())),
      ];

  // ── Typography ──

  Widget _buildFontSizeCard(BuildContext context, bool isDark) {
    const min = 0.8;
    const max = 1.4;

    String scaleLabel(double v) {
      if (v <= 0.85) return 'typography_compact'.tr;
      if (v <= 0.95) return 'typography_default'.tr;
      if (v <= 1.05) return 'typography_comfortable'.tr;
      if (v <= 1.25) return 'typography_large'.tr;
      return 'typography_accessible'.tr;
    }

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(LucideIcons.type, size: 16, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Text('typography_scale'.tr,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(scaleLabel(controller.fontScale.value),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          Slider(
            value: controller.fontScale.value.clamp(min, max),
            min: min,
            max: max,
            divisions: 12,
            activeColor: Theme.of(context).primaryColor,
            onChanged: (v) => controller.setFontScale(v),
          ),
        ]),
      ),
    ]);
  }

  String _themeModeName(ThemeMode m) => m == ThemeMode.light
      ? 'theme_light'.tr
      : m == ThemeMode.dark
          ? 'theme_dark'.tr
          : 'theme_system'.tr;

  IconData _themeModeIcon(ThemeMode m) => m == ThemeMode.light
      ? LucideIcons.sun
      : m == ThemeMode.dark
          ? LucideIcons.moon
          : LucideIcons.sunMoon;

  // ── Thinking Orbs ──

  Widget _orbTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String slot,
    required RxString selection,
    bool showDivider = true,
  }) {
    return Column(children: [
      InkWell(
        onTap: () => _openOrbPicker(context, isDark,
            title: title, slot: slot, selection: selection),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20, color: Theme.of(context).hintColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).hintColor)),
                  ]),
            ),
            const SizedBox(width: 12),
            // Live preview of the current selection.
            Obx(() {
              final fixed = orbStateFromName(selection.value);
              return fixed != null
                  ? ThinkingOrb(size: 26, state: fixed)
                  : const ThinkingOrb(size: 26, autoCycle: true);
            }),
            const SizedBox(width: 10),
            Icon(LucideIcons.chevronRight,
                size: 18, color: Theme.of(context).hintColor),
          ]),
        ),
      ),
      if (showDivider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  void _openOrbPicker(
    BuildContext context,
    bool isDark, {
    required String title,
    required String slot,
    required RxString selection,
  }) {
    showAppBottomSheet(
      context,
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(
                    title: title, onClose: () => Navigator.pop(sheetCtx)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      _orbOption(sheetCtx, isDark,
                          value: 'random',
                          name: 'orb_random'.tr,
                          description: 'orb_random_desc'.tr,
                          icon: LucideIcons.shuffle,
                          slot: slot,
                          selection: selection),
                      for (final s in OrbState.values)
                        _orbOption(sheetCtx, isDark,
                            value: s.name,
                            name: s.label,
                            description: s.description,
                            orbState: s,
                            slot: slot,
                            selection: selection),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _orbOption(
    BuildContext sheetCtx,
    bool isDark, {
    required String value,
    required String name,
    required String description,
    IconData? icon,
    OrbState? orbState,
    required String slot,
    required RxString selection,
  }) {
    final selected = selection.value == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Get.find<SettingsController>().setOrbAnim(slot, value);
        Navigator.pop(sheetCtx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: orbState != null
                  ? ThinkingOrb(size: 24, state: orbState)
                  : Icon(icon, size: 20, color: Theme.of(sheetCtx).hintColor),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? AppColors.textPrimary : Dt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(sheetCtx).hintColor)),
                ]),
          ),
          if (selected)
            Icon(LucideIcons.check, size: 20, color: Theme.of(sheetCtx).primaryColor),
        ]),
      ),
    );
  }

  // ── Shared Apple-style helpers ──

  Widget _appleGroupedCard(BuildContext context, bool isDark,
      {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Dt.pillMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Future<void> _pickLockTimeout(
      BuildContext context, SettingsController controller) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: const Text('Re-lock after'),
        children: [
          for (final m in SettingsController.lockTimeoutOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, m),
              child: Text(m <= 0
                  ? 'Immediately'
                  : m == 1
                      ? 'After 1 minute'
                      : 'After $m minutes'),
            ),
        ],
      ),
    );
    if (picked != null) await controller.setLockTimeoutMinutes(picked);
  }

  Widget _appleListTile(
    BuildContext context,
    bool isDark, {
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showDivider = true,
    VoidCallback? onTap,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 16)],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? AppColors.textPrimary : Dt.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).hintColor))
                  ],
                ])),
            if (trailing != null) trailing,
          ]),
        ),
      ),
      if (showDivider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  Widget _appleSwitchTile(
    BuildContext context,
    bool isDark, {
    Widget? leading,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        if (leading != null) ...[leading, const SizedBox(width: 16)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).hintColor)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeThumbColor: Theme.of(context).primaryColor,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  /// Context-window indicator placement: header bar, composer bar,
  /// or compact ring badge in the chat header.
  void _showContextWindowSheet(BuildContext context, bool isDark) {
    Widget option(String id, String title, String subtitle, IconData icon) {
      return Obx(() {
        final selected = controller.contextWindowStyle.value == id;
        return ListTile(
          dense: true,
          leading: Icon(icon,
              size: 20,
              color: selected
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).hintColor),
          title: Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle,
              style: GoogleFonts.plusJakartaSans(fontSize: 12)),
          trailing: selected
              ? Icon(LucideIcons.check,
                  size: 20, color: Theme.of(context).primaryColor)
              : null,
          onTap: () {
            controller.setContextWindowStyle(id);
            Get.back();
          },
        );
      });
    }

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? Dt.cardDark : Dt.card,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Context window display',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            option('header', 'Chat header',
                'Full bar below the header (default)', LucideIcons.panelTop),
            option('composer', 'Text box',
                'Slim bar above the send button', LucideIcons.textCursorInput),
            option('ring', 'Ring badge',
                'Tiny % circle in the header — tap for details',
                LucideIcons.circleDot),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Theme.of(context).hintColor)),
    );
  }
}
