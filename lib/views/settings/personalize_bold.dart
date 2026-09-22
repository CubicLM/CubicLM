/// Bold theme section (swatch grid + custom color).
///
/// Split from `personalization_view.dart` - behavior is unchanged.
/// Contains: _buildBoldThemeSection(), _showColorPickerDialog()
part of 'personalization_view.dart';

extension _PersonalizeBold on PersonalizationView {
  Widget _buildBoldThemeSection(BuildContext context, bool isDark, List<_ThemeOption> themes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              _sectionLabel(context, 'pers_bold_theme'.tr),
              _appleGroupedCard(context, isDark, children: [
                _HorizontalThemeGrid(
                  themes: themes,
                  isDark: isDark,
                  isBold: true,
                  swatchBuilder: _colorSwatch,
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
      ],
    );
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
                  'Custom', hsv.toColor(), isBold: controller.isBoldTheme.value);
              Get.back();
            },
            child: const Text('Use color'),
          ),
        ],
      ),
    ).whenComplete(hexCtrl.dispose);
  }
}
