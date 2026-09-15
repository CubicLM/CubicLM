/// CubicLM LCS-based diff engine for showing line-level file changes.
///
/// Produces a list of [DiffLine] objects from two file contents, similar
/// to Mobile-Harness's `buildDiffLines()` but pure Dart (no Flutter).
library;

/// Type of a single diff line.
enum DiffLineType { context, addition, deletion }

/// A single line in a unified-style diff.
class DiffLine {
  final DiffLineType type;
  final String content;
  final int? oldLine; // line number in old file (null for additions)
  final int? newLine; // line number in new file (null for deletions)

  const DiffLine({
    required this.type,
    required this.content,
    this.oldLine,
    this.newLine,
  });

  bool get isChange => type != DiffLineType.context;
}

/// Collapse marker for long runs of unchanged lines.
class CollapsedMarker extends DiffLine {
  final int hiddenCount;
  const CollapsedMarker(this.hiddenCount)
      : super(type: DiffLineType.context, content: '… $hiddenCount unchanged lines …');
}

/// Full diff result for a single file.
class FileDiffResult {
  final String path;
  final List<DiffLine> lines;
  final int additions;
  final int deletions;

  const FileDiffResult({
    required this.path,
    required this.lines,
    this.additions = 0,
    this.deletions = 0,
  });

  bool get isEmpty => lines.isEmpty || (!lines.any((l) => l.isChange));
}

/// LCS-based line diff.  Pure Dart, zero dependencies.
///
/// Returns a list of [DiffLine] objects representing the unified diff
/// between [oldText] and [newText].  Long runs of context lines are
/// collapsed with a [CollapsedMarker] to keep the output scannable.
List<DiffLine> buildDiffLines(String oldText, String newText,
    {int contextLines = 3}) {
  final oldLines = oldText.split('\n');
  final newLines = newText.split('\n');

  // LCS table
  final m = oldLines.length;
  final n = newLines.length;
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (oldLines[i - 1] == newLines[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  // Backtrack to find the edit script
  final edits = <_Edit>[]; // in reverse
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (oldLines[i - 1] == newLines[j - 1]) {
      edits.add(_Edit(_EditType.equal, i - 1, j - 1));
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      edits.add(_Edit(_EditType.delete, i - 1, -1));
      i--;
    } else {
      edits.add(_Edit(_EditType.insert, -1, j - 1));
      j--;
    }
  }
  while (i > 0) {
    edits.add(_Edit(_EditType.delete, i - 1, -1));
    i--;
  }
  while (j > 0) {
    edits.add(_Edit(_EditType.insert, -1, j - 1));
    j--;
  }
  final reversedEdits = edits.reversed.toList();

  // Build raw diff lines
  final raw = <DiffLine>[];
  var oldNum = 1;
  var newNum = 1;
  for (final e in reversedEdits) {
    switch (e.type) {
      case _EditType.equal:
        raw.add(DiffLine(
          type: DiffLineType.context,
          content: oldLines[e.oldIdx!],
          oldLine: oldNum++,
          newLine: newNum++,
        ));
      case _EditType.delete:
        raw.add(DiffLine(
          type: DiffLineType.deletion,
          content: oldLines[e.oldIdx!],
          oldLine: oldNum++,
        ));
      case _EditType.insert:
        raw.add(DiffLine(
          type: DiffLineType.addition,
          content: newLines[e.newIdx!],
          newLine: newNum++,
        ));
    }
  }

  // Collapse long runs of unchanged lines
  if (contextLines <= 0) return raw;
  final result = <DiffLine>[];
  var i0 = 0;
  while (i0 < raw.length) {
    if (raw[i0].isChange) {
      result.add(raw[i0]);
      i0++;
      continue;
    }
    // Find the run of context lines
    var runEnd = i0;
    while (runEnd < raw.length && !raw[runEnd].isChange) {
      runEnd++;
    }
    final runLen = runEnd - i0;
    if (runLen <= contextLines * 2 + 1) {
      // Short enough: show all
      result.addAll(raw.sublist(i0, runEnd));
    } else {
      // Show contextLines from start, marker, contextLines from end
      for (var k = i0; k < i0 + contextLines; k++) {
        result.add(raw[k]);
      }
      result.add(CollapsedMarker(runLen - contextLines * 2));
      for (var k = runEnd - contextLines; k < runEnd; k++) {
        result.add(raw[k]);
      }
    }
    i0 = runEnd;
  }
  return result;
}

/// Summary counts from a list of diff lines.
(int additions, int deletions) countChanges(List<DiffLine> lines) {
  var adds = 0, dels = 0;
  for (final l in lines) {
    if (l.type == DiffLineType.addition) adds++;
    if (l.type == DiffLineType.deletion) dels++;
  }
  return (adds, dels);
}

// ── Internal ────────────────────────────────────────────────────────

enum _EditType { equal, delete, insert }

class _Edit {
  final _EditType type;
  final int? oldIdx;
  final int? newIdx;
  const _Edit(this.type, this.oldIdx, this.newIdx);
}
