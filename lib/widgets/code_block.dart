import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../core/colors.dart';
import '../services/terminal/terminal_service.dart';
import '../theme/design_tokens.dart';
import '../views/terminal/terminal_view.dart';
import 'html_preview_page.dart';

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent;
    String? language;
    if (element.attributes.containsKey('class')) {
      language = element.attributes['class']?.replaceFirst('language-', '');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _CodeBlock(code: code, language: language),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlock({required this.code, this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  /// True when this code block is a complete, self-contained HTML document
  /// (a "build a game in a single HTML file" style response) that can be
  /// rendered in the live preview. The language tag is optional: an
  /// untagged block starting with a doctype also qualifies.
  bool get _isHtmlDocument {
    final lang = (widget.language ?? '').toLowerCase();
    final code = widget.code.toLowerCase();
    final looksLikeDoc =
        code.contains('<!doctype html') || code.contains('<html');
    if (!looksLikeDoc) return false;
    return lang.isEmpty || lang == 'html' || lang == 'htm';
  }

  /// Live preview is available on platforms with an InAppWebView
  /// implementation (Android + Windows).
  bool get _previewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _shareCode() {
    Share.share(widget.code);
  }

  /// Shell languages whose blocks get a "Run in Terminal" action
  /// (Mobile-Harness parity). Multi-line scripts run as-is through the
  /// sandboxed terminal; blocked commands are rejected there.
  static const _shellLanguages = {
    'sh',
    'bash',
    'shell',
    'zsh',
    'fish',
    'powershell',
    'ps1',
    'pwsh',
    'bat',
    'batch',
    'cmd',
    'console',
    'terminal',
  };

  bool get _isShellScript {
    final lang = (widget.language ?? '').trim().toLowerCase();
    if (_shellLanguages.contains(lang)) return true;
    // Untagged single-line commands are usually shell too.
    if (lang.isEmpty &&
        widget.code.trim().isNotEmpty &&
        !widget.code.contains('\n')) {
      return true;
    }
    return false;
  }

  void _runInTerminal() {
    final code = widget.code.trimRight();
    if (code.isEmpty) return;
    final preview =
        code.split('\n').take(8).join('\n') +
        (code.split('\n').length > 8 ? '\n…' : '');
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('code_run_terminal'.tr,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                preview,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Runs in the sandboxed terminal. Blocked commands are rejected automatically.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(context).hintColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('common_cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Dt.accent),
            onPressed: () {
              Get.back();
              try {
                final term = Get.isRegistered<TerminalService>()
                    ? Get.find<TerminalService>()
                    : Get.put(TerminalService());
                unawaited(term.runCommand(code));
                Get.to(() => const TerminalView());
              } catch (e) {
                Get.snackbar('Cannot run', '$e',
                    snackPosition: SnackPosition.BOTTOM);
              }
            },
            child: Text('code_run_terminal'.tr),
          ),
        ],
      ),
      name: 'run-in-terminal-confirm',
    );
  }

  void _openLivePreview() {
    try {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => HtmlPreviewPage(code: widget.code),
        ),
      );
    } catch (e) {
      Get.snackbar('Preview unavailable', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = widget.language ?? '';
    final lines = widget.code.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            // Narrow screens (360dp + long translated labels + 3 buttons)
            // overflowed this Row by ~39px. Under 320dp the buttons go
            // icon-only (tooltips stay) so it can never overflow.
            child: LayoutBuilder(
              builder: (_, constraints) {
                final compact = constraints.maxWidth < 320;
                return Row(
                  children: [
                    if (lang.isNotEmpty) ...[
                      Icon(Icons.code_rounded,
                          size: 14,
                          color: isDark
                              ? AppColors.textMuted
                              : Dt.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(lang.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textMuted
                                  : Dt.textMuted,
                            )),
                      ),
                    ] else
                      Text('CODE',
                          style: GoogleFonts.firaCode(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.textMuted
                                : Dt.textMuted,
                          )),
                    const Spacer(),
                    if (_isHtmlDocument && _previewSupported)
                      _actionButton(
                        icon: Icons.play_circle_outline_rounded,
                        label: 'code_preview'.tr,
                        showLabel: !compact,
                        color: AppColors.primary,
                        onTap: _openLivePreview,
                        isDark: isDark,
                      ),
                    if (_isHtmlDocument && _previewSupported)
                      const SizedBox(width: 4),
                    if (_isShellScript) ...[
                      _actionButton(
                        icon: Icons.terminal_rounded,
                        label: 'code_run_terminal'.tr,
                        showLabel: !compact,
                        color: AppColors.primary,
                        onTap: _runInTerminal,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 4),
                    ],
                    _actionButton(
                      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                      label: _copied ? 'code_copied'.tr : 'code_copy'.tr,
                      showLabel: !compact,
                      color: _copied ? AppColors.success : null,
                      onTap: _copyCode,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _actionButton(
                      icon: Icons.ios_share_rounded,
                      label: 'code_export'.tr,
                      showLabel: !compact,
                      onTap: _shareCode,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
          ),
          // Code body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: _highlightedCode(lines, lang, isDark),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    bool showLabel = true,
    Color? color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon,
                size: 13,
                color: color ??
                    (isDark
                        ? AppColors.textMuted
                        : Dt.textMuted)),
            if (showLabel) ...[
              const SizedBox(width: 3),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color ??
                        (isDark
                            ? AppColors.textMuted
                            : Dt.textMuted),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _highlightedCode(List<String> lines, String lang, bool isDark) {
    final codeColor = isDark ? const Color(0xFFCDD6F4) : Dt.cardDark;
    final keywordColor = isDark ? const Color(0xFFCBA6F7) : const Color(0xFF7C3AED);
    final stringColor = isDark ? const Color(0xFFA6E3A1) : const Color(0xFF059669);
    final commentColor = isDark ? const Color(0xFF6C7086) : Dt.textMuted;
    final numberColor = isDark ? const Color(0xFFFAB387) : const Color(0xFFEA580C);
    final funcColor = isDark ? const Color(0xFF89DCEB) : const Color(0xFF2563EB);
    final lineNumColor = isDark ? Colors.white24 : Colors.black26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines.length, (i) {
        return Row(
          // The parent is a horizontally scrolling SingleChildScrollView, so
          // incoming width is unbounded. Shrink-wrap and never use a flex child
          // here: a flex under unbounded width leaves the RenderFlex unlaid out.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: lineNumColor,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(width: 16),
            _highlightedLine(
              lines[i],
              lang,
              codeColor,
              keywordColor,
              stringColor,
              commentColor,
              numberColor,
              funcColor,
            ),
          ],
        );
      }),
    );
  }

  Widget _highlightedLine(
    String line,
    String lang,
    Color codeColor,
    Color keywordColor,
    Color stringColor,
    Color commentColor,
    Color numberColor,
    Color funcColor,
  ) {
    final spans = _highlightLine(line, lang, keywordColor, stringColor, commentColor, numberColor, funcColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(children: spans),
        style: GoogleFonts.firaCode(
          fontSize: 13,
          color: codeColor,
          height: 1.6,
        ),
      ),
    );
  }

  List<TextSpan> _highlightLine(
    String line,
    String lang,
    Color keywordColor,
    Color stringColor,
    Color commentColor,
    Color numberColor,
    Color funcColor,
  ) {
    if (line.trimLeft().startsWith('//') ||
        line.trimLeft().startsWith('#') ||
        line.trimLeft().startsWith('/*') ||
        line.trimLeft().startsWith('*')) {
      return [TextSpan(text: line, style: TextStyle(color: commentColor))];
    }

    final spans = <TextSpan>[];
    final pattern = RegExp(
      r"""('[^']*'|"[^"]*"|`[^`]*`)"""
      r"""|(\b(?:import|export|class|extends|implements|void|int|double|String|bool|final|const|var|return|if|else|for|while|do|switch|case|break|continue|new|this|super|static|async|await|try|catch|throw|finally|yield|get|set|factory|abstract|enum|mixin|required|late|dynamic|Map|List|Set|Future|Stream|Function|true|false|null|none|True|False|None|def|lambda|from|as|in|is|not|and|or|with|pass|raise|except|elif|global|nonlocal|assert|del|print|self)\b)"""
      r"""|(\b\d+\.?\d*\b)"""
      r"""|(\w+(?=\s*\())""",
      multiLine: true,
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: line.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: TextStyle(color: stringColor)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: TextStyle(color: keywordColor, fontWeight: FontWeight.w600)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: TextStyle(color: numberColor)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: TextStyle(color: funcColor)));
      }

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.add(TextSpan(text: line.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: line));
    }

    return spans;
  }
}
