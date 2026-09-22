/// Character-trigram hashed vectors + cosine similarity (pure Dart,
/// no Flutter imports — safe inside `compute()` isolates).
///
/// Step 1 toward neural embeddings: captures paraphrase/morphology
/// similarity ("my project" vs "the app I'm building") that keyword
/// `indexOf` misses, with zero dependencies, zero downloads, and
/// microsecond cost per comparison. A future step can swap the
/// producer for a neural model (e.g. embeddinggemma via the GGUF
/// slot pool) without changing the scoring call sites.
library;

import 'dart:math' show sqrt;

/// Hash buckets per vector: enough separation for short chat turns
/// and facts, small enough for isolate scoring loops.
const semanticDims = 256;

/// Minimum cosine to rescue a zero-keyword-hit candidate (0..1).
/// Trigram hashing is coarse: genuine paraphrases land ~0.25–0.5,
/// unrelated text stays well below.
const semanticRescueThreshold = 0.25;

/// User-facing recall strictness (Memory page) → rescue threshold.
/// Strict = fewer, safer recalls; loose = more paraphrase rescues.
double thresholdForStrictness(String mode) {
  switch (mode) {
    case 'strict':
      return 0.35;
    case 'loose':
      return 0.15;
    default:
      return semanticRescueThreshold;
  }
}

/// L2-normalized trigram-hash vector for [text]. Empty text → zero
/// vector (cosine 0 against everything).
List<double> semanticVector(String text, {int dims = semanticDims}) {
  final v = List<double>.filled(dims, 0);
  final t = ' ${text.toLowerCase()} ';
  if (t.trim().isEmpty) return v;
  for (var i = 0; i + 3 <= t.length; i++) {
    var h = 0;
    for (var j = 0; j < 3; j++) {
      h = (h * 31 + t.codeUnitAt(i + j)) & 0x7fffffff;
    }
    v[h % dims] += 1;
  }
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  if (norm == 0) return v;
  for (var i = 0; i < dims; i++) {
    v[i] /= norm;
  }
  return v;
}

/// Cosine similarity for L2-normalized vectors (0..1). Mismatched
/// or empty inputs → 0.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return 0;
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot.clamp(0.0, 1.0);
}

/// Fused relevance: keyword hits dominate (×1000), semantic cosine
/// (0..100) reranks and rescues paraphrases with zero shared
/// keywords. Pure — unit tested.
int fusedRelevance({
  required int keywordScore,
  required double cosine,
}) {
  return keywordScore * 1000 + (cosine * 100).round();
}
