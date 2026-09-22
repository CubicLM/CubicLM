/// Signature (CubicLM default) theme card.
///
/// Split from `personalization_view.dart` - behavior is unchanged.
/// Contains: _buildSignatureThemeCard()
part of 'personalization_view.dart';

extension _PersonalizeSignature on PersonalizationView {
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
        onTap: () => controller.setTheme('CubicLM', null, isBold: false),
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
                        style: PersonalizationView._font(
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
}
