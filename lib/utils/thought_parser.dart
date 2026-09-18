class ThoughtParts {
  final String thought;
  final String answer;
  final bool isThinking;

  const ThoughtParts({
    required this.thought,
    required this.answer,
    required this.isThinking,
  });

  bool get hasThought => thought.trim().isNotEmpty;
  bool get hasAnswer => answer.trim().isNotEmpty;
}

ThoughtParts splitThoughtTags(String text) {
  final lower = text.toLowerCase();
  final startIdx = lower.indexOf('<think>');

  if (startIdx == -1) {
    return ThoughtParts(thought: '', answer: text, isThinking: false);
  }

  final before = text.substring(0, startIdx);
  final afterStartIdx = startIdx + 7; // Length of '<think>'
  final endIdx = lower.indexOf('</think>', afterStartIdx);

  if (endIdx == -1) {
    return ThoughtParts(
      thought: text.substring(afterStartIdx),
      answer: before,
      isThinking: true,
    );
  }

  final thought = text.substring(afterStartIdx, endIdx);
  final after = text.substring(endIdx + 8); // Length of '</think>'
  final answer = '$before$after'.trimLeft();

  return ThoughtParts(
    thought: thought,
    answer: answer,
    isThinking: false,
  );
}

/// Actionable guidance appended when a generation produced no text.
const String emptyResponseHintLocal =
    'Try: Settings → Parameters → raise Output tokens / Context size (if RAM allows), '
    'ask in smaller steps, use a larger model, or switch to Cloud mode.';

/// Same, for cloud mode (no RAM framing, no "switch to cloud").
const String emptyResponseHintCloud =
    'Try: Settings → Parameters → check Output tokens (if Auto Tune is off), '
    'ask in smaller steps, switch to a non-thinking or larger model, '
    'or try another provider.';

/// Returns the content to save when a generation produced no visible
/// text — a thinking model burning its whole budget reasoning, or a
/// tiny context/output limit cutting a big ask (e.g. a full game file).
/// Keeps any reasoning visible (closing an unclosed think block first
/// so the notice doesn't get swallowed into the thought) and makes the
/// guidance the answer. Returns null when the response already has
/// visible content (or artifacts/tool steps render instead).
/// Pure — unit tested.
String? emptyResponseReplacement({
  required String rawResponse,
  required String cleanContent,
  required bool hasArtifacts,
  required bool hasToolSteps,
  required bool isCloud,
}) {
  if (cleanContent.trim().isNotEmpty || hasArtifacts || hasToolSteps) {
    return null;
  }
  final hint = isCloud ? emptyResponseHintCloud : emptyResponseHintLocal;
  final parts = splitThoughtTags(rawResponse);
  if (!parts.hasThought) {
    return '⚠️ The model returned an empty response.\n\n$hint';
  }
  final thoughtClosed = parts.isThinking
      ? '${rawResponse.trim()}</think>'
      : rawResponse.trim();
  return '$thoughtClosed\n\n> ⚠️ The model only produced reasoning and stopped before writing the answer — usually the output limit was too small for the task.\n>\n> $hint';
}
