import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';
import '../theme/design_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData buildTheme(Brightness brightness, {Color? accentColor, String? fontFamily, ColorScheme? colorScheme}) {
    return _buildTheme(brightness, accentColor: accentColor, fontFamily: fontFamily, colorScheme: colorScheme);
  }

  static ThemeData _buildTheme(Brightness brightness, {Color? accentColor, String? fontFamily, ColorScheme? colorScheme}) {
    final isDark = brightness == Brightness.dark;

    // Two paths, by design:
    // - Signature (no custom accent): the original Claude-warm look —
    //   parchment/paper surfaces. NEVER touched by theme picks.
    // - Swatch / custom accent: a full colorful scheme seeded from the
    //   picked color (backgrounds, surfaces, texts all follow it).
    // - Explicit scheme (Dynamic Color): honored as given, INCLUDING
    //   its primary as the accent — otherwise wallpaper sync would
    //   tint surfaces but leave buttons/switches orange.
    late final Color accent;
    final family = fontFamily ?? 'Plus Jakarta Sans';

    late final Color bg;
    late final Color surface;
    late final Color surfaceHigh;
    late final Color textPrimary;
    late final Color textSecondary;
    late final ColorScheme scheme;
    if (colorScheme != null) {
      scheme = colorScheme;
      accent = scheme.primary;
      bg = scheme.surface;
      surface = scheme.surfaceContainerLow;
      surfaceHigh = scheme.surfaceContainerHigh;
      textPrimary = scheme.onSurface;
      textSecondary = scheme.onSurfaceVariant;
    } else if (accentColor != null) {
      accent = accentColor;
      scheme = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        primary: accent,
      );
      bg = scheme.surface;
      surface = scheme.surfaceContainerLow;
      surfaceHigh = scheme.surfaceContainerHigh;
      textPrimary = scheme.onSurface;
      textSecondary = scheme.onSurfaceVariant;
    } else {
      accent = Dt.accent;
      bg = isDark ? AppColors.bg : AppColors.bgLight;
      surface = isDark ? AppColors.surface : AppColors.surfaceLightMode;
      surfaceHigh = isDark ? AppColors.surfaceLight : Dt.pillMuted;
      textPrimary = isDark ? AppColors.textPrimary : Dt.textPrimary;
      textSecondary = isDark ? AppColors.textSecondary : Dt.textSecondary;
      scheme = ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        error: AppColors.error,
        onError: Colors.white,
        surfaceContainerHighest: surfaceHigh,
      );
    }
    final textMuted = isDark ? AppColors.textMuted : Dt.textMuted;
    final separator = isDark ? AppColors.border : AppColors.borderLightMode;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      cardColor: surface,
      hintColor: textMuted,
      dividerColor: separator,
      colorScheme: scheme,
      textTheme: GoogleFonts.getTextTheme(
        family,
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withValues(alpha: 0.8),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.getFont(
          family,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : Dt.iconDefault),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      // ── Card ──
      cardTheme: CardThemeData(
        color: isDark ? Dt.cardDark : Dt.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Dt.hairline,
            width: 1,
          ),
        ),
      ),

      // ── Bottom Nav ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: isDark ? Colors.white : Dt.textPrimary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
      ),

      // ── Input ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: GoogleFonts.getFont(family, color: textMuted, fontSize: 15),
        labelStyle: GoogleFonts.getFont(family, color: textMuted, fontSize: 14),
      ),

      // ── Buttons ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.getFont(family, fontSize: 15, fontWeight: FontWeight.w700),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.1)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: separator, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.getFont(family, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: GoogleFonts.getFont(family, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.getFont(family, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      // ── Switches & Sliders ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return isDark ? AppColors.surfaceLight : Dt.toggleTrackOff;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: surfaceHigh,
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.1),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 2),
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: accent.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.getFont(family, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // ── Segmented Button ──
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return textSecondary;
          }),
          side: WidgetStateProperty.all(BorderSide(color: separator)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          textStyle: WidgetStateProperty.all(GoogleFonts.getFont(family, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),

      // ── Misc ──
      dividerTheme: DividerThemeData(color: separator, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: GoogleFonts.getFont(family, fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        titleTextStyle: GoogleFonts.getFont(family, fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        subtitleTextStyle: GoogleFonts.getFont(family, fontSize: 14, color: textSecondary),
        iconColor: textSecondary,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return textMuted;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceHigh,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: GoogleFonts.getFont(family, fontSize: 14, color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
    );
  }

  // Bubble colors
  static Color userBubbleColor(BuildContext context) {
    return Theme.of(context).primaryColor;
  }

  static Color aiBubbleColor(BuildContext context) {
    return Theme.of(context).cardColor;
  }

  static Color cmdBubbleColor(BuildContext context) {
    return Theme.of(context).colorScheme.secondary;
  }
}
