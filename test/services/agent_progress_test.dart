import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/agent_progress_service.dart';

void main() {
  group('AgentProgressService.shouldUpdate', () {
    test('first update always fires', () {
      expect(AgentProgressService.shouldUpdate(0, 1), isTrue);
    });

    test('updates inside the gap are skipped', () {
      expect(AgentProgressService.shouldUpdate(1000, 1000 + 1000), isFalse);
    });

    test('updates past the gap fire', () {
      expect(
          AgentProgressService.shouldUpdate(1000, 1000 + 2500), isTrue);
    });

    test('custom gaps are honored', () {
      // First call (lastMs == 0) always fires regardless of gap.
      expect(
          AgentProgressService.shouldUpdate(0, 500, minGapMs: 1000),
          isTrue);
      // Non-first calls respect the gap.
      expect(
          AgentProgressService.shouldUpdate(100, 500, minGapMs: 1000),
          isFalse);
      expect(
          AgentProgressService.shouldUpdate(100, 1500, minGapMs: 1000),
          isTrue);
    });
  });
}
