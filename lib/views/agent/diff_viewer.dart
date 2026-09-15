/// CubicLM Diff Viewer — renders LCS-based diffs with syntax colouring.
///
/// Used in the agent workspace to show per-file changes with line numbers,
/// add/delete highlighting, and collapsible unchanged regions.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/colors.dart';
import '../../services/diff/lcs_diff.dart';

/// A single-file diff viewer widget.
class DiffViewer extends StatelessWidget {
  final String filePath;
  final List<DiffLine> lines;
  final int? additions;
  final int? deletions;

  const DiffViewer({
    super.key,
    required this.filePath,
    required this.lines,
    this.additions,
    this.deletions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adds = additions ?? lines.where((l) => l.type == DiffLineType.addition).length;
    final dels = deletions ?? lines.where((l) => l.type == DiffLineType.deletion).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.grey.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Icon(Icons.compare_arrows_rounded,
                  size: 14, color: Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(filePath,
                    style: GoogleFonts.firaCode(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              if (adds > 0)
                Text('+$adds',
                    style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600)),
              if (adds > 0 && dels > 0) const SizedBox(width: 6),
              if (dels > 0)
                Text('-$dels',
                    style: GoogleFonts.firaCode(
                        fontSize: 11,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        // Diff lines
        Container(
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: lines.length,
            itemBuilder: (_, i) => _diffLine(context, lines[i], isDark),
          ),
        ),
      ],
    );
  }

  Widget _diffLine(BuildContext context, DiffLine line, bool isDark) {
    Color bg;
    String prefix;
    switch (line.type) {
      case DiffLineType.addition:
        bg = Colors.green.withValues(alpha: 0.12);
        prefix = '+';
      case DiffLineType.deletion:
        bg = AppColors.error.withValues(alpha: 0.10);
        prefix = '-';
      case DiffLineType.context:
        bg = Colors.transparent;
        prefix = ' ';
    }

    final lineNum = line.oldLine ?? line.newLine ?? 0;
    final isCollapsed = line is CollapsedMarker;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line number
          SizedBox(
            width: 36,
            child: Text(
              isCollapsed ? '' : '$lineNum',
              style: GoogleFonts.firaCode(
                fontSize: 10,
                color: Theme.of(context).hintColor.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          // Prefix
          SizedBox(
            width: 14,
            child: Text(
              isCollapsed ? '' : prefix,
              style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: line.type == DiffLineType.addition
                    ? Colors.green
                    : line.type == DiffLineType.deletion
                        ? AppColors.error
                        : Theme.of(context).hintColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Content
          Expanded(
            child: isCollapsed
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      line.content,
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: Theme.of(context).hintColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : Text(
                    line.content,
                    style: GoogleFonts.firaCode(
                      fontSize: 11,
                      color: line.type == DiffLineType.addition
                          ? Colors.green.shade300
                          : line.type == DiffLineType.deletion
                              ? AppColors.error.withValues(alpha: 0.9)
                              : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
