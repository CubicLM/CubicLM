import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/controllers/agent_runner_controller.dart';

void main() {
  group('AgentRunnerController.formatElapsed', () {
    test('formats seconds as m:ss', () {
      expect(AgentRunnerController.formatElapsed(0), '0:00');
      expect(AgentRunnerController.formatElapsed(7000), '0:07');
      expect(AgentRunnerController.formatElapsed(83000), '1:23');
      expect(AgentRunnerController.formatElapsed(3599000), '59:59');
    });

    test('formats hours as h:mm:ss', () {
      expect(AgentRunnerController.formatElapsed(3600000), '1:00:00');
      expect(AgentRunnerController.formatElapsed(3723000), '1:02:03');
    });

    test('clamps negative input', () {
      expect(AgentRunnerController.formatElapsed(-5000), '0:00');
    });
  });
}
