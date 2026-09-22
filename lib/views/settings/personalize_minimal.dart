/// Minimal light theme section (swatch grid).
///
/// Split from `personalization_view.dart` - behavior is unchanged.
/// Contains: _buildMinimalThemeSection()
part of 'personalization_view.dart';

extension _PersonalizeMinimal on PersonalizationView {
  Widget _buildMinimalThemeSection(BuildContext context, bool isDark, List<_ThemeOption> themes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              _sectionLabel(context, 'pers_minimal_light_theme'.tr),
              _appleGroupedCard(context, isDark, children: [
                _HorizontalThemeGrid(
                  themes: themes,
                  isDark: isDark,
                  isBold: false,
                  swatchBuilder: _colorSwatch,
                ),
              ]),
      ],
    );
  }
}
