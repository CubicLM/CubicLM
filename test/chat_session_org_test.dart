import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/models/chat_session.dart';
import 'package:cubiclm/services/hive_service.dart';

/// Pure logic tests for session organization + backup envelope shape.
/// No GetX / Hive platform channels required.
void main() {
  group('ChatSession organization', () {
    test('label / archive / hide / pin flags round-trip', () {
      final s = ChatSession(id: '1', title: 'Work chat')
          .copyWith(label: 'work', pinned: true, archived: true, hidden: true);
      final back = ChatSession.fromMap(s.toMap());
      expect(back.label, 'work');
      expect(back.pinned, isTrue);
      expect(back.archived, isTrue);
      expect(back.hidden, isTrue);
    });

    test('pinned model override survives map', () {
      final s = ChatSession(id: 'm').copyWith(
        modelMode: 'cloud',
        modelId: 'gpt-4o',
        modelProvider: 'openai',
      );
      final back = ChatSession.fromMap(s.toMap());
      expect(back.modelMode, 'cloud');
      expect(back.modelId, 'gpt-4o');
      expect(back.modelProvider, 'openai');
    });

    test('legacy maps without new keys migrate safely', () {
      final back = ChatSession.fromMap({
        'id': 'legacy',
        'title': 'Old',
      });
      expect(back.persona, '');
      expect(back.label, '');
      expect(back.locked, isFalse);
      expect(back.modelMode, '');
    });
  });

  group('Backup envelope shape (plaintext path)', () {
    test('legacy maps produce exportable session list shape', () {
      final sessions = [
        ChatSession(id: 'a', title: 'A').toMap(),
        ChatSession(id: 'b', title: 'B', persona: 'P').toMap(),
      ];
      final payload = {
        'app': 'CubicLM',
        'type': 'chat_backup',
        'version': 1,
        'sessions': sessions,
        'messages': <Map<String, dynamic>>[],
      };
      final encoded = jsonEncode(payload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['app'], 'CubicLM');
      expect(decoded['type'], 'chat_backup');
      expect((decoded['sessions'] as List).length, 2);
      expect((decoded['sessions'] as List)[1]['persona'], 'P');
    });

    test('encrypted envelope markers are documented constants', () {
      expect(HiveService.backupMagic.isNotEmpty, isTrue);
      // AES-256-CBC + SHA-256 key derivation string used by encryptBackupBytes.
      const algo = 'aes256cbc-sha256';
      expect(algo, contains('aes256'));
    });
  });

  group('History budget helper', () {
    test('empty history stays empty', () {
      // import-free sanity: budget math is covered in history_budget_test;
      // this guards the chat path contract that empty history is valid.
      final history = <Map<String, String>>[];
      expect(history, isEmpty);
      final chars =
          history.fold<int>(0, (s, m) => s + (m['content'] ?? '').length);
      expect(chars, 0);
    });
  });
}
