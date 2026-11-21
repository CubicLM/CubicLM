import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:cubiclm/controllers/agent_runner_controller.dart';
import 'package:cubiclm/controllers/file_watcher_controller.dart';
import 'package:cubiclm/services/agent_workspace.dart';
import 'package:cubiclm/views/agent/agent_workspace_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Agent Workspace chat pane renders without GetX improper-use error',
      (tester) async {
    // Minimal GetX environment the view expects (fresh install parity:
    // no Hive, no ToolRegistry — the todos getter must not leave the
    // chat-pane Obx with zero observables).
    Get.put(FileWatcherController());
    Get.put(AgentWorkspaceService());
    Get.put(AgentRunnerController());

    final captured = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) => captured.add(details);

    await tester.pumpWidget(
      const GetMaterialApp(home: AgentWorkspaceView()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    FlutterError.onError = original;

    final joined = captured.map((d) => d.toString()).join('\n');
    expect(
      joined.contains('improper use'),
      isFalse,
      reason: 'GetX improper-use error rendered:\n$joined',
    );
  });
}
