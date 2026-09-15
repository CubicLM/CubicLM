/// Strip lone surrogates (U+D800..U+DFFF) that cause
/// "string is not well-formed UTF-16" crashes in TextSpan.build and
/// RenderEditable.performLayout.
///
/// LLM output, web extracts, shared intents and voice results can all carry
/// truncated surrogate pairs. Apply to any external text before assigning it
/// to a [TextEditingController] or rendering it in [Text]/[TextField].
String sanitizeUtf16(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final cu = s.codeUnitAt(i);
    if (cu >= 0xD800 && cu <= 0xDFFF) {
      // High surrogate must be followed by low surrogate.
      if (cu <= 0xDBFF && i + 1 < s.length) {
        final next = s.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          buf.write(s[i]);
          buf.write(s[i + 1]);
          i++; // skip the low surrogate
          continue;
        }
      }
      // Lone surrogate: skip it.
      continue;
    }
    buf.write(s[i]);
  }
  return buf.toString();
}
