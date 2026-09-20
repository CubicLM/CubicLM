import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/download_native.dart'
    show getDownloadedModels;

/// Windows regression: model filenames must be basenames, never full
/// paths. `path.split('/')` leaks `C:\...\models\foo.gguf` as the
/// "filename" on Windows, which breaks isDownloaded(), the Load button
/// and loadModel() ("Not Downloaded" for imported models).
void main() {
  group('getDownloadedModels', () {
    test('returns basenames only (Windows backslash paths)', () async {
      final dir = await Directory.systemTemp.createTemp('cubiclm-models');
      try {
        await File('${dir.path}/qwen-test.gguf').writeAsString('x');
        await File('${dir.path}/notes.txt').writeAsString('x');
        final names = await getDownloadedModels(dir.path);
        expect(names, ['qwen-test.gguf']);
        for (final n in names) {
          expect(n.contains('/'), isFalse);
          expect(n.contains('\\'), isFalse);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('missing dir returns empty', () async {
      expect(
          await getDownloadedModels(
              '${Directory.systemTemp.path}/cubiclm-nope-${DateTime.now().millisecondsSinceEpoch}'),
          isEmpty);
    });
  });
}
