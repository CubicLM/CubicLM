import 'package:cubiclm/utils/paste_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractInserted', () {
    test('append', () {
      expect(extractInserted('hello', 'hello WORLD'), ' WORLD');
    });

    test('prepend', () {
      expect(extractInserted('hello', 'SAY hello'), 'SAY ');
    });

    test('middle insert', () {
      expect(extractInserted('hllo', 'hello'), 'e');
      expect(
          extractInserted('abXXcd', 'ab123XXcd'), '123');
    });

    test('no growth returns empty', () {
      expect(extractInserted('hello', 'hello'), isEmpty);
      expect(extractInserted('hello', 'hell'), isEmpty);
      expect(extractInserted('hello', 'jello'), isEmpty);
    });
  });

  group('removeInserted', () {
    test('restores surroundings', () {
      expect(removeInserted('hello', 'hello WORLD'), 'hello');
      expect(removeInserted('hello', 'SAY hello'), 'hello');
      expect(removeInserted('abXXcd', 'ab123XXcd'), 'abXXcd');
    });

    test('no growth returns after as-is', () {
      expect(removeInserted('hello', 'jello'), 'jello');
    });
  });

  group('looksLikeBulkInsert', () {
    test('threshold gate', () {
      expect(looksLikeBulkInsert('', 'x' * 1999, 2000), isFalse);
      expect(looksLikeBulkInsert('', 'x' * 2000, 2000), isTrue);
      expect(looksLikeBulkInsert('typed', 'typed+x' * 500, 2000), isTrue);
      // single-char typing never qualifies
      expect(looksLikeBulkInsert('a' * 100, 'a' * 101, 2000), isFalse);
    });
  });
}
