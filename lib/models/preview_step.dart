/// One preview-pipeline step for the status checklist UI.
/// Split from `agent_controller.dart` - plain value type, no behavior.
/// Contains: PreviewStep(), label, state, detail
class PreviewStep {
  /// Short label, e.g. 'Detect project'.
  final String label;

  /// 'pending' | 'ok' | 'fail' | 'info'.
  final String state;

  /// Detail line, e.g. 'Vite project' or 'node v22.1.0'.
  final String detail;

  const PreviewStep(this.label, this.state, [this.detail = '']);
}
