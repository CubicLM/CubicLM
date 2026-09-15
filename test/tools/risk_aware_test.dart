import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/shell_tools.dart';
import 'package:cubiclm/services/tools/tool_interface.dart';
import 'package:cubiclm/services/tools/tool_registry.dart';

/// A tool whose base risk is high but per-call risk is safe.
class _ChillTool extends Tool implements RiskAwareTool {
  @override
  String get name => 'chill';

  @override
  String get description => 'risk-aware fake';

  @override
  Map<String, dynamic> get parameters => {'type': 'object'};

  @override
  ToolRisk get risk => ToolRisk.high;

  @override
  ToolRisk riskFor(Map<String, dynamic> args) => ToolRisk.safe;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> args, ToolContext context) async {
    return const ToolResult(output: 'ran without a dialog');
  }
}

ToolContext _ctx() => ToolContext(
      workspacePath: '',
      approve: (_, __) async => true,
    );

void main() {
  group('RunCommandTool.riskFor', () {
    final tool = RunCommandTool();
    test('safe reads classify safe', () {
      expect(tool.riskFor({'command': 'git status'}), ToolRisk.safe);
      expect(tool.riskFor({'command': 'ls -la'}), ToolRisk.safe);
    });

    test('ordinary work classifies review', () {
      expect(tool.riskFor({'command': 'npm test'}), ToolRisk.review);
      expect(tool.riskFor({'command': 'flutter build apk'}),
          ToolRisk.review);
    });

    test('dangerous and blocked commands classify high', () {
      expect(tool.riskFor({'command': 'git push'}), ToolRisk.high);
      expect(tool.riskFor({'command': 'curl https://x'}), ToolRisk.high);
      expect(tool.riskFor({'command': 'rm -rf /'}), ToolRisk.high);
      expect(tool.riskFor({'command': ''}), ToolRisk.high);
    });
  });

  group('ToolRegistry honors RiskAwareTool', () {
    test('per-call safe risk skips the approval dialog', () async {
      final reg = ToolRegistry()..register(_ChillTool());
      // No GetMaterialApp here — a dialog would throw. Safe risk must
      // execute directly.
      final result = await reg.callTool('chill', {}, _ctx());
      expect(result.success, isTrue);
      expect(result.output, 'ran without a dialog');
    });
  });
}
