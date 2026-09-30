class SentenceSplitResult {
  final String completedText;
  final String inProgressText;

  const SentenceSplitResult(this.completedText, this.inProgressText);
}

class WordSplitResult {
  final String completedText;
  final String inProgressText;

  const WordSplitResult(this.completedText, this.inProgressText);
}

/// Helper function to split a string into completed sentences and in-progress text.
SentenceSplitResult splitSentences(String text) {
  if (text.isEmpty) return const SentenceSplitResult('', '');

  final sentenceDelimiters = {'.', '!', '?', '\n', '。', '！', '？'};
  int lastDelimiter = -1;

  for (int i = text.length - 1; i >= 0; i--) {
    if (sentenceDelimiters.contains(text[i])) {
      lastDelimiter = i;
      break;
    }
  }

  if (lastDelimiter == -1) {
    return SentenceSplitResult('', text);
  } else {
    return SentenceSplitResult(
      text.substring(0, lastDelimiter + 1),
      text.substring(lastDelimiter + 1),
    );
  }
}

/// Helper function to split a string into completed words and in-progress active word.
WordSplitResult splitWords(String text) {
  if (text.isEmpty) return const WordSplitResult('', '');

  int lastSpace = -1;
  for (int i = text.length - 1; i >= 0; i--) {
    final char = text[i];
    if (char == ' ' || char == '\n' || char == '\t' || char == '.' || char == ',' || char == '!' || char == '?') {
      lastSpace = i;
      break;
    }
  }

  if (lastSpace == -1) {
    return WordSplitResult('', text);
  } else {
    return WordSplitResult(
      text.substring(0, lastSpace + 1),
      text.substring(lastSpace + 1),
    );
  }
}
