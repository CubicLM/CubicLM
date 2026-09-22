import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/core/app_translations.dart';
import 'package:cubiclm/utils/semantic_vectors.dart';
import 'package:cubiclm/models/chat_session.dart';

void main() {
  group('i18n key parity', () {
    test('all locales expose the same translation keys', () {
      final keys = AppTranslations().keys;
      expect(keys.isNotEmpty, isTrue);
      final en = keys['en'];
      expect(en, isNotNull, reason: 'English map missing');
      final enKeys = en!.keys.toSet();

      final missing = <String, List<String>>{};
      for (final entry in keys.entries) {
        final k = entry.value.keys.toSet();
        final lack = enKeys.difference(k).toList()..sort();
        final extra = k.difference(enKeys).toList()..sort();
        if (lack.isNotEmpty || extra.isNotEmpty) {
          missing[entry.key] = [
            if (lack.isNotEmpty) 'missing: ${lack.take(20).join(', ')}',
            if (extra.isNotEmpty) 'extra: ${extra.take(20).join(', ')}',
          ];
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'Locale key drift:\n${missing.entries.map((e) => '${e.key}: ${e.value.join(' | ')}').join('\n')}',
      );
    });

    test('composer tool strings exist in English', () {
      final en = AppTranslations().keys['en']!;
      for (final key in const [
        'chat_deep_search',
        'chat_live_vision',
        'chat_polish_prompt',
        'chat_stop_generation',
        'chat_hands_free_on',
        'chat_voice_input',
        'chat_more_tools',
        'chat_queued',
      ]) {
        expect(en.containsKey(key), isTrue, reason: 'Missing $key');
        expect(en[key]!.isNotEmpty, isTrue);
      }
    });
  });

  group('semantic embeddings (local API)', () {
    test('vector is unit-norm and deterministic', () {
      final a = semanticVector('hello cubiclm');
      final b = semanticVector('hello cubiclm');
      expect(a.length, semanticDims);
      expect(a, equals(b));
      var norm = 0.0;
      for (final x in a) {
        norm += x * x;
      }
      expect(norm, closeTo(1.0, 0.01));
    });

    test('similar phrases score higher than unrelated ones', () {
      final q = semanticVector('my project deadline');
      final related = semanticVector('the app I am building deadline');
      final unrelated = semanticVector('banana smoothie recipe');
      final hi = cosineSimilarity(q, related);
      final lo = cosineSimilarity(q, unrelated);
      expect(hi, greaterThan(lo));
    });

    test('empty text yields zero vector', () {
      final v = semanticVector('   ');
      expect(v.every((x) => x == 0), isTrue);
    });
  });

  group('ChatSession persona', () {
    test('defaults empty and round-trips through map', () {
      final s = ChatSession(id: 'abc', title: 'T');
      expect(s.persona, '');
      final m = s.toMap();
      expect(m['persona'], '');
      final back = ChatSession.fromMap(m);
      expect(back.persona, '');
      expect(back.id, 'abc');
    });

    test('persona survives copyWith and map round-trip', () {
      final s = ChatSession(id: 'x').copyWith(persona: 'Be concise');
      expect(s.persona, 'Be concise');
      final back = ChatSession.fromMap(s.toMap());
      expect(back.persona, 'Be concise');
    });
  });
}
