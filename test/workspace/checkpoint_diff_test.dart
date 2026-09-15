import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/workspace/checkpoint_manager.dart';

void main() {
  group('diffSnapshots', () {
    test('detects added, modified, and deleted files', () {
      final before = {'a.txt': 'a', 'b.txt': 'b', 'c.txt': 'c'};
      final after = {'a.txt': 'a', 'b.txt': 'B', 'd.txt': 'd'};
      final diff = diffSnapshots(before, after);
      expect(diff.added, ['d.txt']);
      expect(diff.modified, ['b.txt']);
      expect(diff.deleted, ['c.txt']);
      expect(diff.isEmpty, isFalse);
      expect(diff.allChanged, ['b.txt', 'c.txt', 'd.txt']);
    });

    test('identical snapshots diff empty', () {
      final snap = {'a.txt': 'a'};
      expect(diffSnapshots(snap, Map.of(snap)).isEmpty, isTrue);
    });

    test('null means absent (added vs deleted)', () {
      final diff = diffSnapshots({'x': null}, {'x': 'now'});
      expect(diff.added, ['x']);
      final diff2 = diffSnapshots({'x': 'was'}, {'x': null});
      expect(diff2.deleted, ['x']);
    });

    test('results are sorted', () {
      final diff = diffSnapshots(
        {},
        {'z.txt': 'z', 'a.txt': 'a', 'm.txt': 'm'},
      );
      expect(diff.added, ['a.txt', 'm.txt', 'z.txt']);
    });
  });
}
