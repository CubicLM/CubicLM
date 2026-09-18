import 'package:cubiclm/utils/thought_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emptyResponseReplacement', () {
    test('returns null when visible content exists', () {
      expect(
          emptyResponseReplacement(
            rawResponse: 'here is your game',
            cleanContent: 'here is your game',
            hasArtifacts: false,
            hasToolSteps: false,
            isCloud: false,
          ),
          isNull);
    });

    test('returns null when artifacts render instead', () {
      expect(
          emptyResponseReplacement(
            rawResponse: '<artifact type="html">x</artifact>',
            cleanContent: '',
            hasArtifacts: true,
            hasToolSteps: false,
            isCloud: false,
          ),
          isNull);
    });

    test('returns null when tool steps render instead', () {
      expect(
          emptyResponseReplacement(
            rawResponse: '',
            cleanContent: '',
            hasArtifacts: false,
            hasToolSteps: true,
            isCloud: false,
          ),
          isNull);
    });

    test('fully empty response gets plain notice + hint', () {
      final out = emptyResponseReplacement(
        rawResponse: '   ',
        cleanContent: '',
        hasArtifacts: false,
        hasToolSteps: false,
        isCloud: false,
      );
      expect(out, isNotNull);
      expect(out, contains('empty response'));
      expect(out, contains('Settings → Parameters'));
    });

    test('cloud notice drops RAM framing and cloud-switch advice', () {
      final out = emptyResponseReplacement(
        rawResponse: '',
        cleanContent: '',
        hasArtifacts: false,
        hasToolSteps: false,
        isCloud: true,
      );
      expect(out, isNotNull);
      expect(out, contains('non-thinking or larger model'));
      expect(out, isNot(contains('switch to Cloud mode')));
      expect(out, isNot(contains('RAM')));
    });

    test('thinking-only response keeps thought and adds guidance', () {
      const raw = '<think>plan the snake game loop</think>';
      final out = emptyResponseReplacement(
        rawResponse: raw,
        cleanContent: '',
        hasArtifacts: false,
        hasToolSteps: false,
        isCloud: false,
      );
      expect(out, isNotNull);
      // Thought preserved for the ThoughtDisclosure…
      expect(out, contains('plan the snake game loop'));
      // …guidance becomes the visible answer.
      expect(out, contains('only produced reasoning'));
      final parts = splitThoughtTags(out!);
      expect(parts.hasAnswer, isTrue);
      expect(parts.hasThought, isTrue);
    });

    test('unclosed think block is closed before the notice', () {
      const raw = '<think>reasoning cut off mid-way';
      final out = emptyResponseReplacement(
        rawResponse: raw,
        cleanContent: '',
        hasArtifacts: false,
        hasToolSteps: false,
        isCloud: false,
      );
      expect(out, isNotNull);
      final parts = splitThoughtTags(out!);
      // Notice must land in the answer, not inside the thought.
      expect(parts.isThinking, isFalse);
      expect(parts.answer, contains('only produced reasoning'));
      expect(parts.thought, contains('cut off mid-way'));
    });
  });
}
