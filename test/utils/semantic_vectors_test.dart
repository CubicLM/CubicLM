import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/memory_extract.dart';
import 'package:cubiclm/utils/semantic_vectors.dart';

/// Trigram-vector semantics for memory recall: paraphrase matching
/// without any model download. Pure functions.
void main() {
  group('semanticVector / cosineSimilarity', () {
    test('identical text scores ~1.0', () {
      final v = semanticVector('User lives in Dhaka');
      expect(cosineSimilarity(v, semanticVector('User lives in Dhaka')),
          closeTo(1.0, 0.001));
    });

    test('empty text scores 0', () {
      expect(
          cosineSimilarity(
              semanticVector(''), semanticVector('anything here')),
          0);
    });

    test('paraphrase outranks unrelated text', () {
      final q = semanticVector('where does the user reside');
      final para = cosineSimilarity(q, semanticVector('User lives in Dhaka'));
      final other =
          cosineSimilarity(q, semanticVector('quantum field equations'));
      expect(para, greaterThan(other));
      expect(para, greaterThanOrEqualTo(semanticRescueThreshold));
      expect(other, lessThan(semanticRescueThreshold));
    });

    test('fusedRelevance keeps keyword hits dominant', () {
      expect(fusedRelevance(keywordScore: 1, cosine: 0.0),
          greaterThan(fusedRelevance(keywordScore: 0, cosine: 1.0)));
    });

    test('thresholdForStrictness orders strict > balanced > loose', () {
      expect(thresholdForStrictness('strict'), greaterThan(thresholdForStrictness('balanced')));
      expect(thresholdForStrictness('balanced'), greaterThan(thresholdForStrictness('loose')));
      expect(thresholdForStrictness('bogus'), thresholdForStrictness('balanced'));
    });
  });

  group('rankFacts semantic rescue', () {
    test('paraphrase with zero shared keywords is still recalled', () {
      const facts = [
        'User lives in Dhaka',
        'User owns a red bicycle',
      ];
      final ranked =
          rankFacts(facts, query: 'where does the user reside?');
      expect(ranked, isNotEmpty);
      expect(ranked.first, contains('Dhaka'));
    });

    test('keyword hits still rank first', () {
      const facts = [
        'User\'s name is Abir',
        'User\'s project: CubicLM',
      ];
      final ranked =
          rankFacts(facts, query: 'what is my project called?');
      expect(ranked.first, contains('CubicLM'));
    });
  });
}
