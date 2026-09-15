import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/workspace/checkpoint_manager.dart';

void main() {
  group('sha256Hex', () {
    test('matches the known abc vector', () {
      expect(
        sha256Hex('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('empty input hashes like sha256("")', () {
      expect(
        sha256Hex(const []),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('sha256File', () {
    test('streams binary content identically', () async {
      final tmp = await Directory.systemTemp.createTemp('clm_sha_');
      try {
        final bytes = 'CubicLM checkpoint test content.\n'.codeUnits;
        final file = File('${tmp.path}/blob.bin');
        await file.writeAsBytes(bytes);
        expect(await sha256File(file), sha256Hex(bytes));
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('deterministic across calls', () async {
      final tmp = await Directory.systemTemp.createTemp('clm_sha2_');
      try {
        final bytes = List<int>.generate(200000, (i) => i % 251);
        final file = File('${tmp.path}/blob.bin');
        await file.writeAsBytes(bytes);
        final h1 = await sha256File(file);
        final h2 = await sha256File(file);
        expect(h1, equals(h2));
        expect(h1.length, 64); // SHA-256 hex is 64 chars
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('diffHashes', () {
    test('detects added, modified, deleted by digest', () {
      final diff = diffHashes(
        {'a': 'h1', 'b': 'h2', 'c': 'h3'},
        {'a': 'h1', 'b': 'h2x', 'd': 'h4'},
      );
      expect(diff.added, ['d']);
      expect(diff.modified, ['b']);
      expect(diff.deleted, ['c']);
    });

    test('identical maps diff empty', () {
      expect(diffHashes({'a': 'h1'}, {'a': 'h1'}).isEmpty, isTrue);
    });
  });
}
