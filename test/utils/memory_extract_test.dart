import 'package:cubiclm/utils/memory_extract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractKeywords', () {
    test('keeps meaningful words, drops stopwords and short tokens', () {
      final kws = extractKeywords(
          'build a snake game using single html file');
      expect(kws,
          containsAll(['build', 'snake', 'game', 'single', 'html', 'file']));
      expect(kws, isNot(contains('using')));
      expect(kws, isNot(contains('a')));
    });

    test('keeps Bangla script tokens', () {
      final kws = extractKeywords('amar project CubicLM niye kaj');
      expect(kws, contains('cubiclm'));
      expect(kws, contains('project'));
    });

    test('caps at max and dedupes', () {
      final kws = extractKeywords(
          'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu',
          max: 5);
      expect(kws.length, 5);
      expect(kws.toSet().length, 5);
    });
  });

  group('extractFacts', () {
    test('name patterns (EN + romanized BN)', () {
      expect(extractFacts('hi, my name is Abir'),
          contains('User\'s name is Abir'));
      expect(extractFacts('amar nam Siam'),
          contains('User\'s name is Siam'));
    });

    test('project and building patterns', () {
      expect(
          extractFacts('my project is called CubicLM'),
          contains('User\'s project: CubicLM'));
      expect(
          extractFacts('I am building a Flutter app').join(' '),
          contains('building'));
    });

    test('explicit remember wins verbatim-ish', () {
      final facts =
          extractFacts('remember that my API key is in the vault');
      expect(facts.length, 1);
      expect(facts.first, startsWith('Remember:'));
    });

    test('ignores chit-chat', () {
      expect(extractFacts('ok thanks bye'), isEmpty);
      expect(extractFacts('hi'), isEmpty);
      expect(extractFacts('what is 2+2?'), isEmpty);
    });

    test('rejects moods and activities, keeps real roles', () {
      expect(extractFacts('I am happy today'), isEmpty);
      expect(extractFacts('I am going to market'), isEmpty);
      expect(extractFacts('I am a student'), contains('User is a student'));
      expect(extractFacts('I am an engineer'),
          contains('User is an engineer'));
    });

    test('caps at 3 candidates', () {
      final facts = extractFacts(
          'my name is Abir. I live in Dhaka. I am building CubicLM. remember my birthday is June 1.');
      expect(facts.length, lessThanOrEqualTo(3));
    });
  });

  group('factTopic', () {
    test('stable topics for replaceable facts', () {
      expect(factTopic('User\'s name is Abir'), 'name');
      expect(factTopic('User\'s project: CubicLM'), 'project');
      expect(factTopic('User lives in / is from Dhaka'), 'live');
      expect(factTopic('User is an engineer'), 'role');
      expect(factTopic('User\'s favorite color is red'), 'fav:color');
    });

    test('builds and remembrances keep multiples', () {
      expect(factTopic('User is building: CubicLM'), isEmpty);
      expect(factTopic('Remember: my key is safe'), isEmpty);
    });
  });

  group('centeredSnippet', () {
    test('short text passes through', () {
      expect(centeredSnippet('hello world', ['hello'], 100),
          'hello world');
    });

    test('windows around the hit with affixes', () {
      final text = '${'filler '.padRight(400, 'x')}snake game rules${' tail'.padRight(400, 'y')}';
      final out = centeredSnippet(text, ['snake'], 100);
      expect(out, contains('snake game rules'));
      expect(out.startsWith('…'), isTrue);
      expect(out.endsWith('…'), isTrue);
      expect(out.length, lessThanOrEqualTo(102));
    });

    test('no hit falls back to head', () {
      final out = centeredSnippet('a b c d e f g', ['zzz'], 5);
      expect(out, startsWith('a b'));
      expect(out.endsWith('…'), isTrue);
    });
  });

  group('rankFacts', () {
    const facts = [
      'User\'s name is Abir',
      'User\'s project: CubicLM',
      'User lives in / is from Dhaka',
    ];

    test('ranks keyword hits first', () {
      final ranked = rankFacts(facts, query: 'what is my project called?');
      expect(ranked.first, contains('CubicLM'));
    });

    test('empty query falls back to recency within budget', () {
      final ranked = rankFacts(facts, query: 'hi');
      expect(ranked, isNotEmpty);
      expect(ranked.first, facts.first);
    });

    test('respects maxChars budget', () {
      final ranked = rankFacts(facts,
          query: 'project building app', maxChars: 10);
      expect(ranked.join().length, lessThanOrEqualTo(10));
    });

    test('empty facts return empty', () {
      expect(rankFacts([], query: 'anything'), isEmpty);
    });
  });
}
