import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';

class PersonalizationView extends GetView<SettingsController> {
  const PersonalizationView({super.key});

  /// Crash-proof font lookup. GoogleFonts.getFont THROWS for families
  /// absent from the bundled map (e.g. a stale persisted value like
  /// 'Source Sans Pro', or offline first run) — that killed this whole
  /// page 44x. Falls back to the default text style instead.
  static TextStyle _font(String family,
      {double? fontSize,
      FontWeight? fontWeight,
      Color? color,
      double? letterSpacing}) {
    try {
      return GoogleFonts.getFont(family,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing);
    } catch (_) {
      return TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final themes = [
      _ThemeOption(name: 'CubicLM', label: 'CubicLM', color: Dt.accent),
      _ThemeOption(name: 'Android Blue', label: 'Blue', color: Colors.blue),
      _ThemeOption(name: 'Android Green', label: 'Green', color: Colors.green),
      _ThemeOption(name: 'Android Purple', label: 'Purple', color: Colors.purple),
      _ThemeOption(name: 'Android Red', label: 'Red', color: Colors.red),
      _ThemeOption(name: 'Android Yellow', label: 'Yellow', color: Colors.amber),
      _ThemeOption(name: 'Android Cyan', label: 'Cyan', color: Colors.cyan),
      _ThemeOption(name: 'Android Indigo', label: 'Indigo', color: Colors.indigo),
      _ThemeOption(name: 'Android Pink', label: 'Pink', color: Colors.pink),
      _ThemeOption(name: 'Android Teal', label: 'Teal', color: Colors.teal),
      _ThemeOption(name: 'Android Orange', label: 'Orange', color: Colors.orange),
      _ThemeOption(name: 'Android DeepPurple', label: 'Deep Purple', color: Colors.deepPurple),
    ];

    final fonts = [
      'Plus Jakarta Sans',
      'Inter',
      'Roboto',
      'Outfit',
      'Work Sans',
      'Lexend',
      'Montserrat',
      'Open Sans',
      'Poppins',
      'Source Sans 3',
    ];

    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor: (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: Obx(() => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: AppColors.blurSigma, sigmaY: AppColors.blurSigma),
            child: Container(color: Colors.transparent),
          )),
        ),
        title: Text('settings_personalize'.tr,
            style: _font(controller.selectedFontFamily.value,
                fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -1)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
      ),
      body: Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _sectionLabel(context, 'pers_dynamic_color'.tr),
              _appleGroupedCard(context, isDark, children: [
                _appleSwitchTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.wand2, size: 20, color: Dt.accent),
                  title: 'pers_material_you'.tr,
                  subtitle: 'pers_material_you_desc'.tr,
                  value: controller.dynamicColorEnabled.value,
                  onChanged: (v) => controller.setDynamicColorEnabled(v),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'pers_theme_colors'.tr),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    itemCount: themes.length,
                    itemBuilder: (ctx, i) => _colorSwatch(context, isDark, themes[i]),
                  ),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: const Icon(LucideIcons.pipette, size: 20, color: Dt.accent),
                  title: 'pers_custom_color'.tr,
                  subtitle: controller.customAccentColor.value != null
                      ? 'Currently using a custom hex color'
                      : 'pers_custom_color_desc'.tr,
                  onTap: () => _showColorPickerDialog(context),
                  showDivider: false,
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'pers_glass_effects'.tr),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.layers, size: 16, color: Dt.accent),
                          const SizedBox(width: 10),
                          Text('pers_glass_intensity'.tr,
                              style: _font(controller.selectedFontFamily.value,
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text('${(controller.glassIntensity.value * 100).round()}%',
                              style: _font(controller.selectedFontFamily.value,
                                  fontSize: 13, color: Dt.accent, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: controller.glassIntensity.value,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        onChanged: (v) => controller.setGlassIntensity(v),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'pers_typography'.tr),
              _appleGroupedCard(context, isDark, children: [
                for (int i = 0; i < fonts.length; i++)
                  _appleListTile(
                    context,
                    isDark,
                    title: fonts[i],
                    titleStyle: _font(fonts[i], fontSize: 16, fontWeight: FontWeight.w600),
                    trailing: controller.selectedFontFamily.value == fonts[i]
                        ? const Icon(LucideIcons.check, size: 20, color: Dt.accent)
                        : null,
                    onTap: () => controller.setFontFamily(fonts[i]),
                    showDivider: i != fonts.length - 1,
                  ),
              ]),
              const SizedBox(height: 28),
              _sectionLabel(context, 'pers_preview'.tr),
              _buildPreviewCard(context, isDark),
              const SizedBox(height: 40),
            ],
          )),
    );
  }

  Widget _colorSwatch(BuildContext context, bool isDark, _ThemeOption theme) {
    final isSelected = controller.selectedThemeName.value == theme.name && !controller.dynamicColorEnabled.value;
    return InkWell(
      onTap: () => controller.setTheme(theme.name, theme.name == 'CubicLM' ? null : theme.color),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        decoration: BoxDecoration(
          color: theme.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? (isDark ? Colors.white : Colors.black) : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: theme.color.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              )
          ],
        ),
        child: isSelected
            ? const Center(child: Icon(LucideIcons.check, color: Colors.white, size: 18))
            : null,
      ),
    );
  }

  void _showColorPickerDialog(BuildContext context) {
    final extraColors = [
      Colors.deepOrange,
      Colors.lightGreen,
      Colors.lightBlue,
      Colors.brown,
      Colors.blueGrey,
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF43F5E), // Rose
    ];

    Get.dialog(
      AlertDialog(
        title: Text('pers_custom_color'.tr),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in extraColors)
              GestureDetector(
                onTap: () {
                  controller.setTheme('Custom', c);
                  Get.back();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, bool isDark) {
    final accent = controller.customAccentColor.value ?? Dt.accent;
    final family = controller.selectedFontFamily.value;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.sparkles, color: accent, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('pers_sample_header'.tr,
                        style: _font(family, fontWeight: FontWeight.w800, fontSize: 18)),
                    Text('pers_sample_desc'.tr,
                        style: _font(family, fontSize: 13, color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  child: Text('pers_primary_btn'.tr, style: _font(family)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent)),
                  child: Text('pers_secondary_btn'.tr, style: _font(family)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Slider(
            value: 0.6,
            onChanged: (v) {},
            activeColor: accent,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: AppColors.glassDecoration(context, intensity: controller.glassIntensity.value),
            child: Text('pers_glass_preview'.trParams({'font': family}),
                textAlign: TextAlign.center,
                style: _font(family, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _appleGroupedCard(BuildContext context, bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Dt.pillMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _appleSwitchTile(BuildContext context, bool isDark,
      {Widget? leading, required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged}) {
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
                  style: _font(controller.selectedFontFamily.value,
                      fontSize: 15, fontWeight: FontWeight.w700, color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: _font(controller.selectedFontFamily.value,
                        fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeThumbColor: Dt.accent,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _appleListTile(BuildContext context, bool isDark,
      {Widget? leading, required String title, String? subtitle, Widget? trailing, bool showDivider = true, VoidCallback? onTap, TextStyle? titleStyle}) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 16)],
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: titleStyle ?? _font(controller.selectedFontFamily.value,
                      fontSize: 15, fontWeight: FontWeight.w700, color: isDark ? AppColors.textPrimary : Dt.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: _font(controller.selectedFontFamily.value,
                        fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor))
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
              height: 1, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(title,
          style: _font(controller.selectedFontFamily.value,
              fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Theme.of(context).hintColor)),
    );
  }
}

class _ThemeOption {
  final String name;
  final String label;
  final Color color;
  _ThemeOption({required this.name, required this.label, required this.color});
}
