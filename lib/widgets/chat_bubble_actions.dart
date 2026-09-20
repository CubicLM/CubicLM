/// Action bar, branch picker, and TTS controls.
///
/// Split from `chat_bubble.dart` - behavior is unchanged.
/// Contains: _buildActionBar(), _branchPickerButton(), _showBranchPicker(), _jumpToRevision()
///   _actionButton(), _buildTtsButton()
part of 'chat_bubble.dart';

extension _ChatBubbleActions on _ChatBubbleState {
  Widget _buildActionBar(BuildContext context, bool isUser, bool isDark) {
    final iconColor =
        isDark ? AppColors.textMuted.withValues(alpha: 0.6) : Dt.textMuted;
    const double iconSize = 16;
    final revisions = widget.message.revisions;
    final hasRevisions = revisions != null && revisions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Branch Navigation ──
          if (hasRevisions)
            _branchPickerButton(context, revisions, widget.message.revisionIndex, iconColor),

          if (isUser) ...[
            // User: View toggle + Edit + Copy + Share (+ .md / PDF in raw mode)
            _actionButton(
              icon: _rawMode ? Icons.visibility_outlined : Icons.code_rounded,
              tooltip:
                  _rawMode ? 'prompt_view_rendered'.tr : 'prompt_view_raw'.tr,
              onTap: () => _refresh(() => _rawMode = !_rawMode),
              color: _rawMode ? AppColors.primary : iconColor,
              size: iconSize,
            ),
            if (widget.onEdit != null)
              _actionButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onTap: widget.onEdit!,
                color: iconColor,
                size: iconSize,
              ),
            _actionButton(
              icon: widget.message.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              tooltip: widget.message.isPinned ? 'Unpin from context' : 'Pin to context',
              onTap: () => Get.find<ChatController>().toggleMessagePin(widget.message),
              color: widget.message.isPinned ? AppColors.primary : iconColor,
              size: iconSize,
            ),
            _actionButton(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              tooltip: _copied ? 'prompt_copied'.tr : 'prompt_copy_exact'.tr,
              onTap: () {
                final visible = widget.message.fileName == null
                    ? widget.message.content
                    : widget.message.content.split('\n\nAttached file:').first;
                Clipboard.setData(ClipboardData(text: visible));
                HapticFeedback.selectionClick();
                _refresh(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) _refresh(() => _copied = false);
                });
              },
              color: iconColor,
              size: iconSize,
            ),
            _actionButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: () {
                final text = widget.message.content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
              color: iconColor,
              size: iconSize,
            ),
            if (_rawMode) ...[
              _actionButton(
                icon: Icons.download_rounded,
                tooltip: 'prompt_download_md'.tr,
                onTap: () => PromptExport.shareAsMarkdown(
                  widget.message.content,
                  baseName: 'prompt',
                ),
                color: iconColor,
                size: iconSize,
              ),
              _actionButton(
                icon: Icons.picture_as_pdf_rounded,
                tooltip: 'prompt_download_pdf'.tr,
                onTap: () => PromptExport.shareAsPdf(
                  widget.message.content,
                  baseName: 'prompt',
                ),
                color: iconColor,
                size: iconSize,
              ),
            ],
          ] else ...[
            // Assistant: View/Raw toggle + Copy + Read aloud + Share +
            // Regenerate + Branch (+ .md / PDF in raw mode, like Claude's
            // artifact Code tab). Raw mode shows/copies/exports the exact
            // visible answer (think tags stripped).
            _actionButton(
              icon: _rawMode ? Icons.visibility_outlined : Icons.code_rounded,
              tooltip:
                  _rawMode ? 'prompt_view_rendered'.tr : 'prompt_view_raw'.tr,
              onTap: () => _refresh(() => _rawMode = !_rawMode),
              color: _rawMode ? AppColors.primary : iconColor,
              size: iconSize,
            ),
            _actionButton(
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              tooltip: _copied ? 'prompt_copied'.tr : 'prompt_copy_exact'.tr,
              onTap: () {
                final parts = splitThoughtTags(
                    _cleanAssistantText(widget.message.content));
                final text = parts.answer.trim().isNotEmpty
                    ? parts.answer.trim()
                    : widget.message.content;
                Clipboard.setData(ClipboardData(text: text));
                HapticFeedback.selectionClick();
                _refresh(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) _refresh(() => _copied = false);
                });
              },
              color: iconColor,
              size: iconSize,
            ),
            if (_rawMode) ...[
              _actionButton(
                icon: Icons.download_rounded,
                tooltip: 'prompt_download_md'.tr,
                onTap: () {
                  final parts = splitThoughtTags(
                      _cleanAssistantText(widget.message.content));
                  final text = parts.answer.trim().isNotEmpty
                      ? parts.answer.trim()
                      : widget.message.content;
                  PromptExport.shareAsMarkdown(text, baseName: 'prompt');
                },
                color: iconColor,
                size: iconSize,
              ),
              _actionButton(
                icon: Icons.picture_as_pdf_rounded,
                tooltip: 'prompt_download_pdf'.tr,
                onTap: () {
                  final parts = splitThoughtTags(
                      _cleanAssistantText(widget.message.content));
                  final text = parts.answer.trim().isNotEmpty
                      ? parts.answer.trim()
                      : widget.message.content;
                  PromptExport.shareAsPdf(text, baseName: 'prompt');
                },
                color: iconColor,
                size: iconSize,
              ),
            ],
            if (!isUser) _buildTtsButton(iconColor, iconSize),
            _actionButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: () {
                final text = widget.message.content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
              color: iconColor,
              size: iconSize,
            ),
            if (widget.onRetry != null)
              _actionButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Regenerate',
                onTap: widget.onRetry!,
                color: iconColor,
                size: iconSize,
              ),
            if (widget.onBranch != null)
              _actionButton(
                icon: Icons.call_split_rounded,
                tooltip: 'Branch in new chat',
                onTap: widget.onBranch!,
                color: iconColor,
                size: iconSize,
              ),
            const SizedBox(width: 8),
            // Feedback
            _actionButton(
              icon: widget.message.feedback == 'helpful'
                  ? Icons.thumb_up_rounded
                  : Icons.thumb_up_outlined,
              tooltip: 'Helpful',
              onTap: () => Get.find<ChatController>()
                  .setFeedback(widget.message.id, 'helpful'),
              color: widget.message.feedback == 'helpful'
                  ? AppColors.success
                  : iconColor,
              size: iconSize - 2,
            ),
            _actionButton(
              icon: widget.message.feedback == 'unhelpful'
                  ? Icons.thumb_down_rounded
                  : Icons.thumb_down_outlined,
              tooltip: 'Not helpful',
              onTap: () => Get.find<ChatController>()
                  .setFeedback(widget.message.id, 'unhelpful'),
              color: widget.message.feedback == 'unhelpful'
                  ? AppColors.error
                  : iconColor,
              size: iconSize - 2,
            ),
            _actionButton(
              icon: widget.message.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              tooltip: widget.message.isPinned ? 'Unpin from context' : 'Pin to context',
              onTap: () => Get.find<ChatController>().toggleMessagePin(widget.message),
              color: widget.message.isPinned ? AppColors.primary : iconColor,
              size: iconSize - 2,
            ),
          ],
        ],
      ),
    );
  }

  Widget _branchPickerButton(BuildContext context,
      List<Map<String, dynamic>> revisions, int current, Color iconColor) {
    return InkWell(
      onTap: () => _showBranchPicker(context, revisions, current),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.gitBranch, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(
              '${current + 1}/${revisions.length}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: iconColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBranchPicker(
      BuildContext context, List<Map<String, dynamic>> revisions, int current) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Message History',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: revisions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final rev = revisions[i];
                  final content = rev['content'] as String;
                  final active = i == current;
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? AppColors.primary
                            : (isDark ? AppColors.surfaceLight : Dt.hairline),
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: active ? Colors.white : Dt.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ),
                    title: Text(
                      content.replaceAll('\n', ' ').trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                    ),
                    trailing: active
                        ? const Icon(Icons.check_circle,
                            color: AppColors.success, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      // Jump directly to the tapped revision.
                      _jumpToRevision(i, current);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToRevision(int target, int current) {
    final diff = target - current;
    if (diff == 0) return;
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

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
    required double size,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildTtsButton(Color iconColor, double iconSize) {
    // Resolve the speakable text (answer without thinking tags / file footer).
    String resolveSpeakText() {
      final visible = widget.message.fileName == null
          ? widget.message.content
          : widget.message.content.split('\n\nAttached file:').first;
      final parts = splitThoughtTags(_cleanAssistantText(visible));
      final answer = parts.answer.trim();
      return answer.isEmpty ? widget.message.content : answer;
    }

    if (!Get.isRegistered<TtsService>()) {
      return _actionButton(
        icon: Icons.volume_up_rounded,
        tooltip: 'Read aloud',
        onTap: () {
          if (Get.isRegistered<TtsService>()) {
            Get.find<TtsService>().speak(resolveSpeakText());
          }
        },
        color: iconColor,
        size: iconSize,
      );
    }
    return Obx(() {
      final tts = Get.find<TtsService>();
      final isSpeaking = tts.isSpeaking.value;
      return _actionButton(
        icon: isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
        tooltip: isSpeaking ? 'Stop' : 'Read aloud',
        onTap: () => tts.speak(resolveSpeakText()),
        color: iconColor,
        size: iconSize,
      );
    });
  }
}
