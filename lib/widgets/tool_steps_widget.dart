import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../theme/design_tokens.dart';

/// Visual stepper widget showing MCP/agent tool call steps.
/// Renders inside a chat bubble when `message.toolSteps` is non-empty.
class ToolStepsWidget extends StatefulWidget {
  final List<Map<String, dynamic>> steps;
  final bool isStreaming;

  const ToolStepsWidget({
    super.key,
    required this.steps,
    this.isStreaming = false,
  });

  @override
  State<ToolStepsWidget> createState() => _ToolStepsWidgetState();
}

class _ToolStepsWidgetState extends State<ToolStepsWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final failCount = widget.steps.where((s) => s['success'] == false).length;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          // Header — always visible.
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(LucideIcons.wrench, size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Tools Used',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Count badges.
                  _badge('${widget.steps.length}', AppColors.primary),
                  if (failCount > 0) ...[
                    const SizedBox(width: 4),
                    _badge('$failCount failed', AppColors.error),
                  ],
                  const Spacer(),
                  // Streaming indicator.
                  if (widget.isStreaming)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: Dt.textSecondary,
                    ),
                ],
              ),
            ),
          ),

          // Expanded step list.
          if (_expanded || widget.isStreaming)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  for (var i = 0; i < widget.steps.length; i++)
                    _stepTile(widget.steps[i], i, isDark,
                        isLast: i == widget.steps.length - 1),
                  // Modified files summary.
                  if (!widget.isStreaming) _modifiedFilesSummary(isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepTile(Map<String, dynamic> step, int index, bool isDark,
      {bool isLast = false}) {
    final name = step['name']?.toString() ?? 'unknown';
    final success = step['success'] as bool? ?? true;
    final output = step['output']?.toString() ?? '';
    final durationMs = step['durationMs'] as int? ?? 0;
    final args = step['args'] as Map<String, dynamic>? ?? {};
    final modifiedFiles =
        (step['modifiedFiles'] as List?)?.cast<String>() ?? [];

    // Summarize args.
    final argSummary = _summarizeArgs(name, args);
    // Summarize output.
    final outputSummary = _summarizeOutput(name, output, modifiedFiles);

    final isRunning = step['running'] == true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line + icon.
        SizedBox(
          width: 24,
          child: Column(
            children: [
              const SizedBox(height: 2),
              // Status icon.
              if (isRunning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Icon(
                  success ? LucideIcons.checkCircle : LucideIcons.xCircle,
                  size: 16,
                  color: success ? AppColors.success : AppColors.error,
                ),
              // Connector line.
              if (!isLast)
                Container(
                  width: 1.5,
                  height: 28,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Content.
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tool name + duration.
                Row(
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.firaCode(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                      ),
                    ),
                    if (durationMs > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        durationMs > 1000
                            ? '${(durationMs / 1000).toStringAsFixed(1)}s'
                            : '${durationMs}ms',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: Dt.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                // Args summary.
                if (argSummary.isNotEmpty)
                  Text(
                    argSummary,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Dt.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                // Output summary.
                if (outputSummary.isNotEmpty)
                  Text(
                    '→ $outputSummary',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: success ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modifiedFilesSummary(bool isDark) {
    final allFiles = <String>{};
    for (final step in widget.steps) {
      final files = (step['modifiedFiles'] as List?)?.cast<String>() ?? [];
      allFiles.addAll(files);
    }
    if (allFiles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.folderOpen, size: 13, color: Dt.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Modified: ${allFiles.map(_basename).join(', ')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: Dt.textSecondary,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────

  String _summarizeArgs(String toolName, Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    // Show most relevant arg based on tool name.
    final key = args.containsKey('path')
        ? 'path'
        : args.containsKey('query')
            ? 'query'
            : args.containsKey('command')
                ? 'command'
                : args.containsKey('pattern')
                    ? 'pattern'
                    : args.keys.first;
    final val = args[key]?.toString() ?? '';
    return val.length > 80 ? '${val.substring(0, 80)}…' : val;
  }

  String _summarizeOutput(
      String toolName, String output, List<String> modifiedFiles) {
    if (output.isEmpty && modifiedFiles.isEmpty) return '';
    if (modifiedFiles.isNotEmpty) {
      return 'Modified ${modifiedFiles.length} file${modifiedFiles.length > 1 ? 's' : ''}';
    }
    final bytes = output.length;
    if (bytes > 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB output';
    }
    return '${bytes}B output';
  }

  String _basename(String path) {
    final sep = path.contains('/') ? '/' : '\\';
    return path.split(sep).last;
  }
}
