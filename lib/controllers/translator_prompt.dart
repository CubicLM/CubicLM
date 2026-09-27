/// Translation prompt + output cleanup (pure functions).
///
/// Split from `translator_controller.dart` - behavior is unchanged.
/// Contains: buildTranslationPrompt(), cleanTranslationOutput()
part of 'translator_controller.dart';

/// Strict small-model-friendly prompt: translation only, nothing else.
String buildTranslationPrompt({
  required String sourceLabel,
  required String targetLabel,
  required String text,
}) =>
    'Translate the following text from $sourceLabel to $targetLabel. '
    'Output ONLY the translation — no explanations, no quotes, '
    'no notes, no romanization:\n\n$text';

/// Small models often echo the input or wrap it in quotes/fences.
String cleanTranslationOutput(String raw, String inputEcho) {
  var v = raw.trim();
  final input = inputEcho.trim();
  if (input.isNotEmpty && v.startsWith(input)) {
    v = v.substring(input.length).trim();
  }
  if (v.length >= 2) {
    const pairs = [
      ['"', '"'],
      ["'", "'"],
      ['«', '»'],
      ['“', '”'],
    ];
    for (final p in pairs) {
      if (v.startsWith(p[0]) && v.endsWith(p[1])) {
        v = v.substring(1, v.length - 1).trim();
        break;
      }
    }
  }
  v = v.replaceAll(RegExp(r'^```\w*\n?'), '');
  v = v.replaceAll(RegExp(r'\n?```$'), '');
  return v.trim();
}
