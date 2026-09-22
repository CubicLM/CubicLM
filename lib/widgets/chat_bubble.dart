import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' show min;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/chat_message.dart';
import '../models/web_source.dart';
import '../utils/prompt_export.dart';
import '../utils/text_sanitize.dart';
import '../utils/thought_parser.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/syntax_highlight.dart';
import '../services/tts_service.dart';
import 'attachment_preview.dart';
import 'citation_link_builder.dart';
import 'code_block.dart';
import 'image_viewer.dart';
import 'thought_disclosure.dart';
import 'chat_branch_timeline.dart';
import 'suggestion_chips.dart';
import 'tool_steps_widget.dart';
import '../views/chat/project_context_view.dart';

part 'chat_bubble_actions.dart';
part 'chat_bubble_bars.dart';
part 'chat_bubble_helpers.dart';
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onBranch;
  final VoidCallback? onEdit;
  final VoidCallback? onPrevRevision;
  final VoidCallback? onNextRevision;
  final VoidCallback? onDelete;

  const ChatBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onBranch,
    this.onEdit,
    this.onPrevRevision,
    this.onNextRevision,
    this.onDelete,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  /// setState bridge for `part` extensions (extensions cannot call the
  /// protected [State.setState] directly).
  void _refresh(VoidCallback fn) => setState(fn);

  bool _copied = false;
  final SettingsController _settings = Get.find<SettingsController>();

  /// Claude-style prompt view toggle: rendered markdown (default) ↔ exact
  /// raw text (code format). Per-bubble state, not persisted.
  bool _rawMode = false;

  // Memoized per state instance: stylesheet + code builders are rebuilt
  // only when inherited deps change (theme/brightness), not on every
  // build — previously paid fromTheme + GoogleFonts + 2 allocs per bubble
  // per frame while streaming.
  MarkdownStyleSheet? _mdSheet;
  MarkdownStyleSheet? _thoughtSheet;
  CodeBlockBuilder? _codeBuilder;
  CitationLinkBuilder? _citationBuilder;
  Brightness? _sheetBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_mdSheet == null || _sheetBrightness != brightness) {
      _sheetBrightness = brightness;
      _mdSheet = _markdownStyle(context);
      _thoughtSheet = _thoughtMarkdownStyle(context);
      _codeBuilder = CodeBlockBuilder(context);
      _citationBuilder = CitationLinkBuilder(
        context,
        widget.message.citations,
        widget.message.webSources,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final visibleContent = widget.message.fileName == null
        ? widget.message.content
        : widget.message.content.split('\n\nAttached file:').first;

    final thoughtParts = isUser
        ? const ThoughtParts(thought: '', answer: '', isThinking: false)
        : splitThoughtTags(_cleanAssistantText(visibleContent));

    final answerContent = isUser ? visibleContent : thoughtParts.answer.trim();

    final displayContent = isUser
        ? visibleContent
        : answerContent.replaceAllMapped(
            RegExp(r'\[cite:(\d+)\]'),
            (m) => '[${m.group(1)}](cite:${m.group(1)})',
          );

    // Raw/code view shows exactly what "Copy exact text" copies: the
    // prompt without the attachment metadata footer.
    final rawContent = widget.message.fileName == null
        ? widget.message.content
        : widget.message.content.split('\n\nAttached file:').first;

    final revisions = widget.message.revisions;
    final hasRevisions = revisions != null && revisions.isNotEmpty;

    final alternatives = widget.message.alternatives;
    final hasAlternatives = alternatives != null && alternatives.isNotEmpty;
    final preferredIdx = widget.message.preferredIndex;

    // Entrance animation lives only in ChatView._MessageEntrance — a second
    // TweenAnimationBuilder here re-animates on every rebuild (jank + double motion).
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => _showContextMenu(context, isUser),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        (isUser ? 0.82 : 0.92),
                  ),
                  decoration: isUser
                      ? BoxDecoration(
                          // Claude: user message = soft warm surface pill, flat.
                          color: isDark ? Dt.pillMutedDark : Dt.pillMuted,
                          borderRadius: BorderRadius.circular(20),
                        )
                      : null,
                  child: Padding(
                    padding: isUser
                        ? const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12)
                        : const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image attachment
                        if (widget.message.decodedImageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () {
                                final b = widget.message.decodedImageBytes;
                                if (b != null) {
                                  ImageViewer.showBytes(context, b);
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(
                                  widget.message.decodedImageBytes!,
                                  width: double.infinity,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  // Thumbnail only — decode at ~640px instead
                                  // of full resolution (viewer gets full bytes).
                                  cacheWidth: 640,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.black
                                              .withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Center(
                                        child: Icon(Icons.broken_image_rounded,
                                            size: 28)),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Thought disclosure
                        if (!isUser && thoughtParts.hasThought)
                          ThoughtDisclosure(
                            thought: thoughtParts.thought,
                            durationSeconds:
                                widget.message.thoughtDurationSeconds,
                            styleSheet:
                                _thoughtSheet ?? _thoughtMarkdownStyle(context),
                          ),

                        // Message content
                        if (isUser)
                          _rawMode
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E1E2E)
                                        : const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black
                                              .withValues(alpha: 0.08),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: SelectableText(
                                    rawContent,
                                    style: GoogleFonts.firaCode(
                                      fontSize: 12.5,
                                      height: 1.6,
                                      color: isDark
                                          ? const Color(0xFFCDD6F4)
                                          : Dt.textPrimary,
                                    ),
                                  ),
                                )
                              : MarkdownBody(
                                  data: visibleContent,
                                  selectable: true,
                                  styleSheet:
                                      _mdSheet ?? _markdownStyle(context),
                                  builders: {
                                    'latex': LatexElementBuilder(
                                      textStyle: _mdSheet?.p,
                                    ),
                                    'code': _codeBuilder ??
                                        CodeBlockBuilder(context),
                                    'pre': _codeBuilder ??
                                        CodeBlockBuilder(context),
                                    'a': _citationBuilder ??
                                        CitationLinkBuilder(
                                            context,
                                            widget.message.citations,
                                            widget.message.webSources),
                                  },
                                  extensionSet: md.ExtensionSet(
                                    [
                                      ...md.ExtensionSet.gitHubFlavored
                                          .blockSyntaxes,
                                      LatexBlockSyntax(),
                                    ],
                                    [
                                      ...md.ExtensionSet.gitHubFlavored
                                          .inlineSyntaxes,
                                      LatexInlineSyntax(),
                                    ],
                                  ),
                                )
                        else ...[
                          if (hasAlternatives && preferredIdx == null)
                            _buildArenaResponses(
                                answerContent, alternatives, isDark)
                          else
                            _buildSingleResponse(
                                preferredIdx == null
                                    ? answerContent
                                    : (preferredIdx == 0
                                        ? answerContent
                                        : alternatives![preferredIdx - 1]),
                                displayContent,
                                isDark),
                        ],

                        // Activated skills (intelligent per-prompt)
                        if (!isUser &&
                            widget.message.usedSkills != null &&
                            widget.message.usedSkills!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _skillsUsedBar(
                                context, widget.message.usedSkills!, isDark),
                          ),

                        // Past turns auto-recalled from other chats (ROM).
                        if (!isUser && widget.message.recalledTurns > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _recallBar(
                                context,
                                widget.message.recalledTurns,
                                isDark),
                          ),

                        // Claude-style artifacts detected in this message
                        if (!isUser &&
                            widget.message.artifacts != null &&
                            widget.message.artifacts!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _artifactsBar(
                                context, widget.message.artifacts!, isDark),
                          ),

                        // Web sources fetched for this turn
                        if (!isUser &&
                            widget.message.webSources != null &&
                            widget.message.webSources!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _webSourcesBar(
                                context, widget.message.webSources!, isDark),
                          ),

                        // Tool call steps visualization
                        if (!isUser &&
                            widget.message.toolSteps != null &&
                            widget.message.toolSteps!.isNotEmpty)
                          ToolStepsWidget(steps: widget.message.toolSteps!),

                        // File attachment
                        if (widget.message.fileName != null) ...[
                          const SizedBox(height: 12),
                          if (widget.message.fileType == 'zip')
                            ProjectContextView(
                              fileName: widget.message.fileName!,
                              structure: widget.message.fileContent
                                      ?.split('---')
                                      .first ??
                                  '',
                              fileCount: widget.message.fileContent
                                      ?.split('---')
                                      .length ??
                                  0,
                            )
                          else
                            AttachmentPreview(
                              fileName: widget.message.fileName!,
                              fileType: widget.message.fileType,
                              fileSize: widget.message.fileSize,
                              imageBase64: widget.message.imageBase64,
                              imagePath: widget.message.imagePath,
                              compact: true,
                            ),
                        ],

                        if (!isUser && widget.message.suggestions != null)
                          SuggestionChips(
                            suggestions: widget.message.suggestions!,
                            isDark: isDark,
                          ),

                        // Footer info
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.message.tokensPerSec != null &&
                                widget.message.tokensPerSec! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  '${widget.message.tokensPerSec!.toStringAsFixed(1)} tok/s',
                                  isUser,
                                  context,
                                ),
                              ),
                            if (widget.message.imageGenDurationMs != null &&
                                widget.message.imageGenDurationMs! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  _formatGenTime(
                                      widget.message.imageGenDurationMs!),
                                  isUser,
                                  context,
                                ),
                              ),
                            if (widget.message.generationDurationMs != null &&
                                widget.message.generationDurationMs! > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  _formatGenTime(
                                      widget.message.generationDurationMs!),
                                  isUser,
                                  context,
                                  icon: Icons.timer_outlined,
                                ),
                              ),
                            if (widget.message.isQueued)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(LucideIcons.clock, size: 10, color: Colors.orange),
                                      const SizedBox(width: 4),
                                      Text(
                                        'chat_queued'.tr,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 9,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (!isUser && _settings.inferenceMode.value == 'cloud')
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _infoBadge(
                                  _estimateCost(widget.message),
                                  isUser,
                                  context,
                                  icon: LucideIcons.dollarSign,
                                ),
                              ),
                            Text(
                              _formatTime(widget.message.timestamp),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: isUser
                                    ? Dt.textMuted.withValues(alpha: 0.8)
                                    : AppColors.textMuted
                                        .withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Inline action bar
            if (hasRevisions)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ChatBranchTimeline(
                  total: revisions.length + 1,
                  current: widget.message.revisionIndex,
                  onSelect: (idx) {
                    final diff = idx - widget.message.revisionIndex;
                    if (diff != 0) {
                      if (diff > 0 && widget.onNextRevision != null) {
                        for (var i = 0; i < diff; i++) {
                          widget.onNextRevision!();
                        }
                      } else if (diff < 0 && widget.onPrevRevision != null) {
                        for (var i = 0; i < -diff; i++) {
                          widget.onPrevRevision!();
                        }
                      }
                    }
                  },
                ),
              ),
            _buildActionBar(context, isUser, isDark),
          ],
        ),
      );
  }

  /// Claude-style raw/code view: exact source text in mono, selectable.
  /// Shared by user and assistant bubbles so View ↔ Code shows and copies
  /// byte-identical text.
  Widget _rawCodeContainer(String text, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? SyntaxColors.surfaceDark
            : SyntaxColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: SelectableText(
        text,
        style: GoogleFonts.firaCode(
          fontSize: 12.5,
          height: 1.6,
          color: isDark ? SyntaxColors.plain : SyntaxColors.plainLight,
        ),
      ),
    );
  }

  Widget _buildSingleResponse(String answer, String display, bool isDark) {
    if (answer.isEmpty) return const SizedBox.shrink();
    return _rawMode
        ? _rawCodeContainer(answer, isDark)
        : MarkdownBody(
            data: display,
            selectable: true,
            styleSheet: _mdSheet ?? _markdownStyle(context),
            builders: {
              'latex': LatexElementBuilder(
                textStyle: _mdSheet?.p,
              ),
              'code': _codeBuilder ?? CodeBlockBuilder(context),
              'pre': _codeBuilder ?? CodeBlockBuilder(context),
              'a': _citationBuilder ??
                  CitationLinkBuilder(context, widget.message.citations,
                      widget.message.webSources),
            },
            extensionSet: md.ExtensionSet(
              [
                ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                LatexBlockSyntax()
              ],
              [
                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                LatexInlineSyntax()
              ],
            ),
          );
  }

  Widget _buildArenaResponses(
      String first, List<String> alternatives, bool isDark) {
    final all = [first, ...alternatives];
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(LucideIcons.gitCompare,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'Which response do you prefer?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800 && all.length >= 3;
          final isMedium = constraints.maxWidth > 600;
          
          if (isWide) {
            // Horizontal for 3 models on wide screen
             return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < all.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < all.length - 1 ? 12 : 0),
                      child: _dualChoiceCard(all[i], i, isDark),
                    ),
                  ),
              ],
            );
          }
          
          if (isMedium) {
            // Stack dual + one full width if triple
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < min(all.length, 2); i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                          child: _dualChoiceCard(all[i], i, isDark),
                        ),
                      ),
                  ],
                ),
                if (all.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _dualChoiceCard(all[2], 2, isDark),
                  ),
              ],
            );
          }
          // Vertical for narrow screens or mobile
          return Column(
            children: [
              for (var i = 0; i < all.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _dualChoiceCard(all[i], i, isDark),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _dualChoiceCard(String content, int index, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Response ${index + 1}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white54 : Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          MarkdownBody(
            data: content,
            styleSheet: _mdSheet ?? _markdownStyle(context),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Get.find<ChatController>()
                  .setPreference(widget.message.id, index),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: Text(
                'I prefer this',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Inline action bar below message ──

}
