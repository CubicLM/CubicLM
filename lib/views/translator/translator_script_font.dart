import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Script-aware text style for translator input/output.
///
/// PlusJakartaSans (app font) has no Bengali/Arabic/CJK glyphs, so
/// translations rendered tofu boxes (). Picks a Noto family by
/// target language first, then by sniffing the actual text (covers
/// Auto-detect and Bengali→English input). Latin falls back to the
/// app font. Fonts download once via google_fonts, then work offline.
TextStyle translatorTextStyle(
  BuildContext context, {
  required String langId,
  required String text,
  double fontSize = 14,
  double height = 1.55,
  FontWeight weight = FontWeight.w400,
  Color? color,
}) {
  final base = GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    height: height,
    fontWeight: weight,
    color: color,
  );
  switch (langId) {
    case 'bn':
      return GoogleFonts.notoSansBengali(textStyle: base);
    case 'hi':
      return GoogleFonts.notoSansDevanagari(textStyle: base);
    case 'ar':
    case 'ur':
      return GoogleFonts.notoSansArabic(textStyle: base);
    case 'zh':
      return GoogleFonts.notoSansSc(textStyle: base);
    case 'ja':
      return GoogleFonts.notoSansJp(textStyle: base);
    case 'ko':
      return GoogleFonts.notoSansKr(textStyle: base);
    case 'th':
      return GoogleFonts.notoSansThai(textStyle: base);
  }
  // Sniff the text itself (Auto source, or non-Latin input).
  bool has(RegExp re) => re.hasMatch(text);
  if (has(RegExp(r'[\u0980-\u09FF]'))) {
    return GoogleFonts.notoSansBengali(textStyle: base);
  }
  if (has(RegExp(r'[\u0900-\u097F]'))) {
    return GoogleFonts.notoSansDevanagari(textStyle: base);
  }
  if (has(RegExp(r'[\u0600-\u06FF]'))) {
    return GoogleFonts.notoSansArabic(textStyle: base);
  }
  if (has(RegExp(r'[\u3040-\u30FF]'))) {
    return GoogleFonts.notoSansJp(textStyle: base);
  }
  if (has(RegExp(r'[\uAC00-\uD7AF]'))) {
    return GoogleFonts.notoSansKr(textStyle: base);
  }
  if (has(RegExp(r'[\u0E00-\u0E7F]'))) {
    return GoogleFonts.notoSansThai(textStyle: base);
  }
  if (has(RegExp(r'[Ⰰ-鿿]'))) {
    return GoogleFonts.notoSansSc(textStyle: base);
  }
  return base;
}
