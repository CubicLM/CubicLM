/// Badges, time/cost formatting, and text cleanup helpers.
///
/// Split from `chat_bubble.dart` - behavior is unchanged.
/// Contains: _infoBadge(), _markdownStyle(), _thoughtMarkdownStyle(), _formatTime(), _formatGenTime()
///   _estimateCost(), _cleanAssistantText()
part of 'chat_bubble.dart';

extension _ChatBubbleHelpers on _ChatBubbleState {
  Widget _infoBadge(String label, bool isUser, BuildContext context,
      {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isUser
            ? Dt.textPrimary.withValues(alpha: 0.06)
            : Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: isUser ? Dt.textSecondary : Theme.of(context).primaryColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              color: isUser ? Dt.textSecondary : Theme.of(context).primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.textPrimary : Dt.textPrimary;
    final muted = isDark ? AppColors.textSecondary : Dt.textSecondary;
    // Assistant body reads in a serif — Claude's signature editorial voice.
    final base =
        GoogleFonts.sourceSerif4(fontSize: 15.5, color: color, height: 1.6);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 12),
      h1: base.copyWith(
          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      listIndent: 24,
      code: GoogleFonts.firaCode(
        fontSize: 13,
        color: color,
      ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      blockquote: base.copyWith(color: muted, fontSize: 14),
      blockquoteDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        border: const Border(
          left: BorderSide(
            color: AppColors.primary,
            width: 3,
          ),
        ),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    );
  }

  MarkdownStyleSheet _thoughtMarkdownStyle(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final base =
        GoogleFonts.plusJakartaSans(fontSize: 13, color: muted, height: 1.5);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeBg = isDark ? AppColors.surfaceLight : Dt.hairline;

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base,
      code: GoogleFonts.firaCode(
        fontSize: 11,
        color: muted,
        backgroundColor: codeBg,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatGenTime(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }

  String _estimateCost(ChatMessage msg) {
    // Very simple pricing proxy: GPT-4o mini class vs GPT-4o class.
    final content = msg.content;
    final inChars = (msg.revisions?.last['content'] ?? '').toString().length;
    final outChars = content.length;
    
    // Estimate tokens
    final inTokens = inChars ~/ 4;
    final outTokens = outChars ~/ 4;
    
    final model = _settings.selectedCloudModelName.toLowerCase();
    
    double pricePer1MIn = 0.15; // default mini
    double pricePer1MOut = 0.60;
    
    if (model.contains('gpt-4o') && !model.contains('mini')) {
      pricePer1MIn = 2.50;
      pricePer1MOut = 10.00;
    } else if (model.contains('claude-3-5-sonnet')) {
      pricePer1MIn = 3.00;
      pricePer1MOut = 15.00;
    } else if (model.contains('gemini-1.5-pro')) {
      pricePer1MIn = 3.50;
      pricePer1MOut = 10.50;
    } else if (model.contains('deepseek')) {
      pricePer1MIn = 0.14;
      pricePer1MOut = 0.28;
    }

    final total = (inTokens * pricePer1MIn / 1000000) + (outTokens * pricePer1MOut / 1000000);
    
    if (total < 0.0001) return '<\$0.0001';
    return '\$${total.toStringAsFixed(4)}';
  }

  String _cleanAssistantText(String text) {
    // Safety net: never show raw <tool_call> tags (old saved msgs may
    // contain them, incl. malformed tiny-model variants). Tool steps
    // render via ToolStepsWidget instead.
    var s = text
        .replaceAll('<|endoftext|>', '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|end|>', '');
    s = s.replaceAll(
        RegExp(r'<tool_call\b[^>]*>([\s\S]*?)</tool_call>',
            caseSensitive: false),
        '');
    s = s.replaceAll(
        RegExp(r'<tool_call\b[^>]*?</tool_call>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<tool_call\b[^>]*>', caseSensitive: false), '');
    return sanitizeUtf16(s.trim());
  }
}
