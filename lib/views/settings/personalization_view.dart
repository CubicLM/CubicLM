import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';

class PersonalizationView extends GetView<SettingsController> {
  const PersonalizationView({super.key});

  /// Extra preset swatches for the More-themes grid (single-hue
  /// palettes derived from one base color each).
  static List<_ThemeOption> _presetThemes() {
    List<Color> shades(Color c) => [
          c,
          c.withValues(alpha: 0.7),
          c.withValues(alpha: 0.4),
          c.withValues(alpha: 0.2),
        ];
    return [
      _ThemeOption(
          name: 'Custom DeepOrange',
          label: 'Deep Orange',
          palette: shades(Colors.deepOrange)),
      _ThemeOption(
          name: 'Custom LightGreen',
          label: 'Light Green',
          palette: shades(Colors.lightGreen)),
      _ThemeOption(
          name: 'Custom LightBlue',
          label: 'Light Blue',
          palette: shades(Colors.lightBlue)),
      _ThemeOption(
          name: 'Custom Brown', label: 'Brown', palette: shades(Colors.brown)),
      _ThemeOption(
          name: 'Custom BlueGrey',
          label: 'Blue Grey',
          palette: shades(Colors.blueGrey)),
      _ThemeOption(
          name: 'Custom Indigo',
          label: 'Indigo',
          palette: shades(const Color(0xFF6366F1))),
      _ThemeOption(
          name: 'Custom Emerald',
          label: 'Emerald',
          palette: shades(const Color(0xFF10B981))),
      _ThemeOption(
          name: 'Custom Rose',
          label: 'Rose',
          palette: shades(const Color(0xFFF43F5E))),
      _ThemeOption(
          name: 'Custom Violet',
          label: 'Violet',
          palette: shades(const Color(0xFF8B5CF6))),
      _ThemeOption(
          name: 'Custom Pink',
          label: 'Pink',
          palette: shades(const Color(0xFFEC4899))),
    ];
  }

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
      ..._presetThemes(),
      _ThemeOption(
        name: 'Android Blue',
        label: 'Blue',
        palette: [const Color(0xFF1A73E8), const Color(0xFF669DF6), const Color(0xFFADCCFE), const Color(0xFFE8F0FE)],
      ),
      _ThemeOption(
        name: 'Android Green',
        label: 'Green',
        palette: [const Color(0xFF1E8E3E), const Color(0xFF5BB974), const Color(0xFFA1E3AD), const Color(0xFFE6F4EA)],
      ),
      _ThemeOption(
        name: 'Android Purple',
        label: 'Purple',
        palette: [const Color(0xFF9334E6), const Color(0xFFC58AF9), const Color(0xFFE1D0FE), const Color(0xFFF3E8FD)],
      ),
      _ThemeOption(
        name: 'Android Red',
        label: 'Red',
        palette: [const Color(0xFFD93025), const Color(0xFFEE675C), const Color(0xFFF8B0AB), const Color(0xFFFCE8E6)],
      ),
      _ThemeOption(
        name: 'Android Yellow',
        label: 'Yellow',
        palette: [const Color(0xFFF9AB00), const Color(0xFFFDD663), const Color(0xFFFDE293), const Color(0xFFFEF7E0)],
      ),
      _ThemeOption(
        name: 'Android Cyan',
        label: 'Cyan',
        palette: [const Color(0xFF0097A7), const Color(0xFF4DD0E1), const Color(0xFFB2EBF2), const Color(0xFFE0F7FA)],
      ),
      _ThemeOption(
        name: 'Android Teal',
        label: 'Teal',
        palette: [const Color(0xFF00796B), const Color(0xFF4DB6AC), const Color(0xFFB2DFDB), const Color(0xFFE0F2F1)],
      ),
      _ThemeOption(
        name: 'Android Pink',
        label: 'Pink',
        palette: [const Color(0xFFE91E63), const Color(0xFFF06292), const Color(0xFFF8BBD0), const Color(0xFFFCE4EC)],
      ),
      _ThemeOption(
        name: 'Android Indigo',
        label: 'Indigo',
        palette: [const Color(0xFF3F51B5), const Color(0xFF7986CB), const Color(0xFFC5CAE9), const Color(0xFFE8EAF6)],
      ),
      _ThemeOption(
        name: 'Android Orange',
        label: 'Orange',
        palette: [const Color(0xFFFF9800), const Color(0xFFFFB74D), const Color(0xFFFFE0B2), const Color(0xFFFFF3E0)],
      ),
      _ThemeOption(
        name: 'Android DeepPurple',
        label: 'Deep Purple',
        palette: [const Color(0xFF673AB7), const Color(0xFF9575CD), const Color(0xFFD1C4E9), const Color(0xFFEDE7F6)],
      ),
      _ThemeOption(
        name: 'Android Lime',
        label: 'Lime',
        palette: [const Color(0xFFAFB42B), const Color(0xFFDCE775), const Color(0xFFF0F4C3), const Color(0xFFF9FBE7)],
      ),
      _ThemeOption(
        name: 'Android Brown',
        label: 'Brown',
        palette: [const Color(0xFF795548), const Color(0xFFA1887F), const Color(0xFFD7CCC8), const Color(0xFFEFEBE9)],
      ),
      _ThemeOption(
        name: 'Android Slate',
        label: 'Slate',
        palette: [const Color(0xFF607D8B), const Color(0xFF90A4AE), const Color(0xFFCFD8DC), const Color(0xFFECEFF1)],
      ),
      _ThemeOption(
        name: 'Android DeepOrange',
        label: 'Deep Orange',
        palette: [const Color(0xFFE64A19), const Color(0xFFFF7043), const Color(0xFFFFCCBC), const Color(0xFFFBE9E7)],
      ),
      _ThemeOption(
        name: 'Android Orchid',
        label: 'Orchid',
        palette: [const Color(0xFF8E24AA), const Color(0xFFBA68C8), const Color(0xFFE1BEE7), const Color(0xFFF3E5F5)],
      ),
      _ThemeOption(
        name: 'Android Sky',
        label: 'Sky',
        palette: [const Color(0xFF0288D1), const Color(0xFF4FC3F7), const Color(0xFFB3E5FC), const Color(0xFFE1F5FE)],
      ),
      _ThemeOption(
        name: 'Android Forest',
        label: 'Forest',
        palette: [const Color(0xFF388E3C), const Color(0xFF81C784), const Color(0xFFC8E6C9), const Color(0xFFE8F5E9)],
      ),
      _ThemeOption(
        name: 'Android Midnight',
        label: 'Midnight',
        palette: [const Color(0xFF283593), const Color(0xFF5C6BC0), const Color(0xFFC5CAE9), const Color(0xFFE8EAF6)],
      ),
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
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
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
                _MaterialYouTile(isDark: isDark),
                if (controller.dynamicColorEnabled.value)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        _dynamicPalettePreview(context, isDark),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Using system-generated palette based on your current wallpaper.',
                            style: _font(controller.selectedFontFamily.value,
                                fontSize: 12,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'pers_signature_theme'.tr),
              _buildSignatureThemeCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'pers_more_themes'.tr),
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
                      // Cells must fit 58px circle + gap + 1-line label:
                      // square cells overflowed ~14px vertically.
                      childAspectRatio: 0.72,
                    ),
                    itemCount: themes.length,
                    itemBuilder: (ctx, i) => _colorSwatch(context, isDark, themes[i]),
                  ),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: Obx(() {
                    final custom = controller.customAccentColor.value;
                    return Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: custom?.withValues(alpha: 0.1) ?? Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.pipette, size: 16, color: custom ?? Theme.of(context).primaryColor),
                    );
                  }),
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
                          Icon(LucideIcons.layers, size: 16, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 10),
                          Text('pers_glass_intensity'.tr,
                              style: _font(controller.selectedFontFamily.value,
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text('${(controller.glassIntensity.value * 100).round()}%',
                              style: _font(controller.selectedFontFamily.value,
                                  fontSize: 13, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w800)),
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
              _buildFontBox(context, isDark, fonts),
              const SizedBox(height: 28),
              _sectionLabel(context, 'pers_preview'.tr),
              _buildPreviewCard(context, isDark),
              const SizedBox(height: 40),
            ],
          )),
    );
  }

  Widget _dynamicPalettePreview(BuildContext context, bool isDark) {
    final theme = Theme.of(context).colorScheme;
    final palette = [
      theme.primary,
      theme.secondary,
      theme.tertiary,
      theme.primaryContainer,
    ];

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: CustomPaint(
        size: const Size(48, 48),
        painter: _DynamicPalettePainter(palette: palette),
      ),
    );
  }

  /// The original CubicLM theme, prioritized in its own section above
  /// every other swatch. Tapping reselects the default accent.
  Widget _buildSignatureThemeCard(BuildContext context, bool isDark) {
    final palette = [
      Theme.of(context).primaryColor,
      Theme.of(context).primaryColor.withValues(alpha: 0.7),
      Theme.of(context).primaryColor.withValues(alpha: 0.4),
      Theme.of(context).primaryColor.withValues(alpha: 0.2),
    ];
    return Obx(() {
      final selected = controller.selectedThemeName.value == 'CubicLM' &&
          !controller.dynamicColorEnabled.value;
      return GestureDetector(
        onTap: () => controller.setTheme('CubicLM', null),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Dt.pillMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? Theme.of(context).primaryColor : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: 40,
                child: Stack(
                  children: [
                    for (int i = 0; i < palette.length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette[i],
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CubicLM',
                        style: _font(
                            controller.selectedFontFamily.value,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                    const SizedBox(height: 6),
                    _pill(context, 'typography_default'.tr.toUpperCase(),
                        accent: true),
                  ],
                ),
              ),
              if (selected)
                Icon(LucideIcons.checkCircle2,
                    size: 24, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
      );
    });
  }

  /// Typography in one framed, scrollable box. The APK's main font
  /// (Plus Jakarta Sans) stays pinned at the top as the CubicLM font
  /// style with Default priority; every other font scrolls beneath it.
  Widget _buildFontBox(
      BuildContext context, bool isDark, List<String> fonts) {
    return _FontBox(isDark: isDark, fonts: fonts);
  }

  /// Small badge pill used for Default / signature markers.
  Widget _pill(BuildContext context, String text, {bool accent = false}) {
    final color = accent ? Theme.of(context).primaryColor : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: _font(controller.selectedFontFamily.value,
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _colorSwatch(BuildContext context, bool isDark, _ThemeOption theme) {
    return Obx(() {
      final isSelected =
          controller.selectedThemeName.value == theme.name &&
          !controller.dynamicColorEnabled.value;
      
      final primaryColor = theme.palette[0];
      
      return GestureDetector(
        onTap: () => controller.setTheme(theme.name, theme.name == 'CubicLM' ? null : primaryColor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stock-Android minimalist swatch: one flat solid circle.
            // Selected state is a thin ring + check — no gradients,
            // no shadows, no scaling.
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.1)),
                  width: isSelected ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor,
                  ),
                  child: isSelected
                      ? const Icon(LucideIcons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              theme.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _font(controller.selectedFontFamily.value,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected 
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? AppColors.textSecondary : Dt.textSecondary)),
            ),
          ],
        ),
      );
    });
  }

  /// Real custom-color picker: hue / saturation / value sliders plus
  /// hex input and a live preview. No presets here — those live in
  /// the More-themes grid.
  void _showColorPickerDialog(BuildContext context) {
    var hsv = HSVColor.fromColor(
        controller.customAccentColor.value ?? Theme.of(context).primaryColor);
    final hexCtrl = TextEditingController(
        text: '#${hsv.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}');

    String hexOf(HSVColor c) =>
        '#${c.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    Widget sliderRow({
      required String label,
      required double value,
      required double max,
      required Gradient gradient,
      required ValueChanged<double> onChanged,
    }) {
      return Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: const RoundedRectSliderTrackShape(),
                  trackHeight: 28,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 12),
                  thumbColor: Colors.white,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 20),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Get.dialog(
      AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('pers_custom_color'.tr,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: StatefulBuilder(
          builder: (ctx, setState) {
            final preview = hsv.toColor();
            void update(HSVColor next) {
              setState(() {
                hsv = next;
                hexCtrl.text = hexOf(next);
              });
            }

            return SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: preview,
                        border: Border.all(
                          color: Theme.of(context)
                              .hintColor
                              .withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    sliderRow(
                      label: 'Hue',
                      value: hsv.hue,
                      max: 360,
                      gradient: LinearGradient(
                        colors: [
                          for (var h = 0; h <= 360; h += 60)
                            HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                        ],
                      ),
                      onChanged: (v) =>
                          update(hsv.withHue(v.clamp(0, 360).toDouble())),
                    ),
                    const SizedBox(height: 10),
                    sliderRow(
                      label: 'Saturation',
                      value: hsv.saturation,
                      max: 1,
                      gradient: LinearGradient(
                        colors: [
                          hsv.withSaturation(0).toColor(),
                          hsv.withSaturation(1).toColor(),
                        ],
                      ),
                      onChanged: (v) => update(
                          hsv.withSaturation(v.clamp(0.0, 1.0).toDouble())),
                    ),
                    const SizedBox(height: 10),
                    sliderRow(
                      label: 'Brightness',
                      value: hsv.value,
                      max: 1,
                      gradient: LinearGradient(
                        colors: [
                          hsv.withValue(0).toColor(),
                          hsv.withValue(1).toColor(),
                        ],
                      ),
                      onChanged: (v) => update(
                          hsv.withValue(v.clamp(0.0, 1.0).toDouble())),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hexCtrl,
                      decoration: const InputDecoration(
                        labelText: 'HEX',
                        hintText: '#FF4D00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final hex = v.trim().replaceFirst('#', '');
                        final rgb = int.tryParse(hex, radix: 16);
                        if (rgb == null) return;
                        final full =
                            hex.length <= 6 ? 0xFF000000 | rgb : rgb;
                        update(HSVColor.fromColor(Color(full)));
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.setTheme(
                  'Custom', hsv.toColor());
              Get.back();
            },
            child: const Text('Use color'),
          ),
        ],
      ),
    ).whenComplete(hexCtrl.dispose);
  }

  Widget _buildPreviewCard(BuildContext context, bool isDark) {
    final accent = controller.customAccentColor.value ?? Theme.of(context).primaryColor;
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

/// Material You tile with real support detection. Android 12+ exposes
/// wallpaper colors via [DynamicColorPlugin.getCorePalette]; older
/// releases (and some OEM skins) return null — there the switch is
/// disabled with an explanation instead of silently doing nothing.
class _MaterialYouTile extends StatefulWidget {
  final bool isDark;
  const _MaterialYouTile({required this.isDark});

  @override
  State<_MaterialYouTile> createState() => _MaterialYouTileState();
}

class _MaterialYouTileState extends State<_MaterialYouTile> {
  bool? _supported;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (mounted) setState(() => _supported = palette != null);
    } catch (_) {
      if (mounted) setState(() => _supported = false);
    }
  }

  SettingsController get _settings => Get.find<SettingsController>();

  @override
  Widget build(BuildContext context) {
    final supported = _supported ?? true;
    return Obx(() {
      final on = _settings.dynamicColorEnabled.value && supported;
      return _PersonalizeSwitchTile(
        isDark: widget.isDark,
        title: 'pers_material_you'.tr,
        subtitle: supported
            ? 'pers_material_you_desc'.tr
            : 'Requires Android 12+ with wallpaper colors — not available on this device.',
        value: on,
        enabled: supported,
        onChanged: (v) => _settings.setDynamicColorEnabled(v),
        onDisabledTap: () => Get.snackbar(
          'Material You unavailable',
          'Wallpaper colors need Android 12 or newer.',
          snackPosition: SnackPosition.BOTTOM,
        ),
      );
    });
  }
}

/// Switch tile honoring an enabled flag (shared apple tile has none).
class _PersonalizeSwitchTile extends StatelessWidget {
  final bool isDark;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onDisabledTap;

  const _PersonalizeSwitchTile({
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? null : onDisabledTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(LucideIcons.wand2,
                size: 20, color: Theme.of(context).primaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: PersonalizationView._font(
                          Get.find<SettingsController>()
                              .selectedFontFamily
                              .value,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimary
                              : Dt.textPrimary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: PersonalizationView._font(
                          Get.find<SettingsController>()
                              .selectedFontFamily
                              .value,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).hintColor)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              activeThumbColor: Theme.of(context).primaryColor,
              // Disabled switch: null callback greys it out properly.
              onChanged: enabled ? onChanged : null,
            ),
          ]),
        ),
      ),
    );
  }
}
/// thumbVisibility demands one, and there is no PrimaryScrollController
/// inside this card.
class _FontBox extends StatefulWidget {
  final bool isDark;
  final List<String> fonts;

  const _FontBox({required this.isDark, required this.fonts});

  @override
  State<_FontBox> createState() => _FontBoxState();
}

class _FontBoxState extends State<_FontBox> {
  static const _hero = 'Plus Jakarta Sans';
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  SettingsController get _settings => Get.find<SettingsController>();

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final rest = widget.fonts.where((f) => f != _hero).toList();
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Dt.pillMuted.withValues(alpha: 0.5);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _heroRow(context),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1, color: dividerColor),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Scrollbar(
              controller: _scrollCtrl,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _scrollCtrl,
                padding: EdgeInsets.zero,
                itemCount: rest.length,
                separatorBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1, color: dividerColor),
                ),
                itemBuilder: (ctx, i) => _row(ctx, rest[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroRow(BuildContext context) {
    final selected = _settings.selectedFontFamily.value == _hero;
    return InkWell(
      onTap: () => _settings.setFontFamily(_hero),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: selected ? 0.1 : 0.04),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: selected ? 0.5 : 0.2),
          ),
        ),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_hero,
                      style: PersonalizationView._font(_hero,
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _badge(context, 'CubicLM', accent: true),
                      const SizedBox(width: 6),
                      _badge(context, 'typography_default'.tr.toUpperCase(),
                          accent: false),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(LucideIcons.checkCircle2,
                  size: 24, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String name) {
    final selected = _settings.selectedFontFamily.value == name;
    return InkWell(
      onTap: () => _settings.setFontFamily(name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PersonalizationView._font(name,
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (selected)
              Icon(LucideIcons.check, size: 18, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text, {bool accent = false}) {
    final color = accent ? Theme.of(context).primaryColor : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: PersonalizationView._font(
              _settings.selectedFontFamily.value,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color)),
    );
  }
}

class _ThemeOption {
  final String name;
  final String label;
  final List<Color> palette;
  _ThemeOption({required this.name, required this.label, required this.palette});
}

/// Draws a premium 4-color diagonal split palette (Stock Android style)
class _DynamicPalettePainter extends CustomPainter {
  final List<Color> palette;
  _DynamicPalettePainter({required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Top Quadrant
    final path1 = Path()
      ..moveTo(size.width / 2, size.height / 2)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path1, paint..color = palette[0]);

    // Right Quadrant
    final path2 = Path()
      ..moveTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path2, paint..color = palette[1]);

    // Bottom Quadrant
    final path3 = Path()
      ..moveTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path3, paint..color = palette[2]);

    // Left Quadrant
    final path4 = Path()
      ..moveTo(size.width / 2, size.height / 2)
      ..lineTo(0, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path4, paint..color = palette[3]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
