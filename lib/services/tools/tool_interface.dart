/// CubicLM Agentic Tool System — abstract interface for built-in tools.
///
/// Every tool implements [Tool] and returns a [ToolResult]. Tools are
/// registered in [ToolRegistry] and dispatched by the agent loop.
library;

/// Result of a tool execution.
class ToolResult {
  /// Human-readable output (shown to LLM and user).
  final String output;

  /// Whether the tool executed successfully.
  final bool success;

  /// Files that were modified by this tool (for checkpoint/diff tracking).
  final List<String> modifiedFiles;

  /// Whether the output was truncated (for UI indication).
  final bool truncated;

  const ToolResult({
    required this.output,
    this.success = true,
    this.modifiedFiles = const [],
    this.truncated = false,
  });

  factory ToolResult.error(String message) => ToolResult(
        output: 'Error: $message',
        success: false,
      );

  factory ToolResult.truncated(String output, {List<String> modifiedFiles = const []}) =>
      ToolResult(
        output: output,
        truncated: true,
        modifiedFiles: modifiedFiles,
      );
}

/// Context passed to tools during execution.
class ToolContext {
  /// Root path of the current workspace.
  final String workspacePath;

  /// Approval callback — returns true if the tool call is allowed.
  final Future<bool> Function(String toolName, Map<String, dynamic> args) approve;

  const ToolContext({
    required this.workspacePath,
    required this.approve,
  });
}

/// Abstract interface for a tool that the agent can invoke.
///
/// Tools have a JSON Schema for their parameters (used in the LLM request)
/// and an [execute] method that performs the actual work.
abstract class Tool {
  /// Unique tool name (e.g. 'read_file', 'run_command').
  String get name;

  /// Human-readable description (included in LLM tool schema).
  String get description;

  /// JSON Schema describing the tool's parameters.
  ///
  /// Example:
  /// ```json
  /// {
  ///   "type": "object",
  ///   "properties": {
  ///     "path": {"type": "string", "description": "File path relative to workspace"}
  ///   },
  ///   "required": ["path"]
  /// }
  /// ```
  Map<String, dynamic> get parameters;

  /// Risk level for approval gate classification.
  ToolRisk get risk => ToolRisk.safe;

  /// Execute the tool with the given arguments and context.
  ///
  /// The tool MUST respect [ToolContext.workspacePath] for path-based tools.
  /// Paths MUST be relative to the workspace (no absolute paths, no `..`).
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context);
}

/// Risk classification for tool approval.
enum ToolRisk {
  /// Always allowed (read-only, no side effects).
  safe,

  /// Requires approval once, then can be always-allowed.
  review,

  /// Always requires explicit approval (destructive operations).
  high,
}

/// Optional per-arguments risk classification.
///
/// Tools with argument-dependent danger (e.g. shell commands) implement
/// this so the approval gate can auto-allow harmless calls (`git status`)
/// while still gating real side effects (`rm -rf build`).
///
/// Extends [Tool] so Dart's type promotion works when checking
/// `tool is RiskAwareTool` in [ToolRegistry].
abstract class RiskAwareTool extends Tool {
  /// Risk for this specific call. The registry falls back to [Tool.risk]
  /// for tools that do not implement this interface.
  ToolRisk riskFor(Map<String, dynamic> args);
}

/// Convert a [Tool] to OpenAI function-calling format.
Map<String, dynamic> toolToOpenAI(Tool tool) => {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      },
    };

/// Convert a [Tool] to Anthropic tool format.
Map<String, dynamic> toolToAnthropic(Tool tool) => {
      'name': tool.name,
      'description': tool.description,
      'input_schema': tool.parameters,
    };

/// Lightweight record emitted after every tool dispatch.
///
/// The agent loop subscribes to these to surface per-tool progress in the
/// UI without duplicating provider tool-execution logic. Argument values
/// are intentionally NOT included (may contain file contents / secrets).
class ToolExecutionRecord {
  final String toolName;
  final bool success;
  final int outputChars;
  final int elapsedMs;
  final int timestampMs;

  const ToolExecutionRecord({
    required this.toolName,
    required this.success,
    required this.outputChars,
    required this.elapsedMs,
    required this.timestampMs,
  });
}
