// Helpers for long-paste-to-file (GPT/Claude-style composer behavior).
// Pure — unit tested.

int _commonPrefixLength(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

int _commonSuffixLength(String a, String b, int prefixLen) {
  var i = 0;
  while (i + prefixLen < a.length &&
      i + prefixLen < b.length &&
      a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}

/// The substring inserted to turn [before] into [after] (single
/// contiguous insertion assumed — true for paste/IME commits).
/// Returns '' when [after] is not longer than [before].
String extractInserted(String before, String after) {
  if (after.length <= before.length) return '';
  final prefix = _commonPrefixLength(before, after);
  final suffix = _commonSuffixLength(before, after, prefix);
  return after.substring(prefix, after.length - suffix);
}

/// [before] with the inserted chunk removed (the surrounding text the
/// user had typed is preserved).
String removeInserted(String before, String after) {
  if (after.length <= before.length) return after;
  final prefix = _commonPrefixLength(before, after);
  final suffix = _commonSuffixLength(before, after, prefix);
  return before.substring(0, prefix) +
      before.substring(before.length - suffix);
}

/// True when a text change looks like a bulk insert (paste), not typing.
bool looksLikeBulkInsert(String before, String after, int threshold) {
  return after.length - before.length >= threshold;
}
