/// Translator language catalog.
///
/// Split from `translator_controller.dart` - behavior is unchanged.
/// Contains: TranslatorLanguage, translatorLanguages, translatorLabelOf
part of 'translator_controller.dart';

/// A translatable language (stable id + display label).
class TranslatorLanguage {
  final String id;
  final String label;
  const TranslatorLanguage(this.id, this.label);
}

/// All languages CubicTranslator can target ('auto' is source-only).
const translatorLanguages = [
  TranslatorLanguage('en', 'English'),
  TranslatorLanguage('bn', 'Bengali (Bangla)'),
  TranslatorLanguage('hi', 'Hindi'),
  TranslatorLanguage('ur', 'Urdu'),
  TranslatorLanguage('ar', 'Arabic'),
  TranslatorLanguage('es', 'Spanish'),
  TranslatorLanguage('fr', 'French'),
  TranslatorLanguage('de', 'German'),
  TranslatorLanguage('pt', 'Portuguese'),
  TranslatorLanguage('ru', 'Russian'),
  TranslatorLanguage('zh', 'Chinese (Simplified)'),
  TranslatorLanguage('ja', 'Japanese'),
  TranslatorLanguage('ko', 'Korean'),
  TranslatorLanguage('tr', 'Turkish'),
  TranslatorLanguage('id', 'Indonesian'),
  TranslatorLanguage('vi', 'Vietnamese'),
  TranslatorLanguage('it', 'Italian'),
  TranslatorLanguage('nl', 'Dutch'),
  TranslatorLanguage('th', 'Thai'),
  TranslatorLanguage('ms', 'Malay'),
];

/// Display label for a language id ('auto' → 'Auto').
String translatorLabelOf(String id) {
  if (id == 'auto') return 'Auto';
  for (final l in translatorLanguages) {
    if (l.id == id) return l.label;
  }
  return id;
}
