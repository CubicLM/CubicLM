/// CubicLM Agentic Tool System — standalone approval dialog.
///
/// Reusable approval dialog for tool calls. Used by both the tool registry
/// and the cloud provider tool approval gate.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Tool risk level for the approval dialog.
enum ToolRiskLevel { safe, review, high }

/// Show a tool approval dialog. Returns the user's decision.
///
/// - `'deny'` — tool call blocked
/// - `'once'` — allow this one call
/// - `'always'` — allow this tool permanently
Future<String?> showToolApprovalDialog({
  required String toolName,
  required String toolDescription,
  required Map<String, dynamic> args,
  ToolRiskLevel risk = ToolRiskLevel.review,
}) async {
  final argsText = _truncateArgs(args);

  return Get.dialog<String>(
    AlertDialog(
      backgroundColor: Get.theme.brightness == Brightness.dark
          ? AppColors.surface
          : Colors.white,
      title: Row(
        children: [
          Icon(
            risk == ToolRiskLevel.high
                ? Icons.warning_amber_rounded
                : Icons.build_rounded,
            color: risk == ToolRiskLevel.high ? AppColors.warning : Dt.accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Allow tool call?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tool name
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              toolName,
              style: GoogleFonts.firaCode(
                  fontSize: 12, fontWeight: FontWeight.bold, color: Dt.accent),
            ),
          ),
          const SizedBox(height: 6),
          // Description
          Text(
            toolDescription,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 10),
          // Arguments
          Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Get.theme.brightness == Brightness.dark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Get.theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                argsText,
                style: GoogleFonts.firaCode(fontSize: 10.5),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: 'deny'),
          child: Text('Deny',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.error, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Get.back(result: 'always'),
          child: Text('Always allow',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.warning, fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Dt.accent,
          ),
          onPressed: () => Get.back(result: 'once'),
          child: Text('Allow once',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
    barrierDismissible: false,
  );
}

String _truncateArgs(Map<String, dynamic> args) {
  try {
    final s = const JsonEncoder.withIndent('  ').convert(args);
    return s.length > 800 ? '${s.substring(0, 800)}…' : s;
  } catch (_) {
    final s = args.toString();
    return s.length > 800 ? '${s.substring(0, 800)}…' : s;
  }
}
