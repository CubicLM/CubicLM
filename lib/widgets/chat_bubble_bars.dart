/// Context menu plus artifact, recall, skills, and source bars.
///
/// Split from `chat_bubble.dart` - behavior is unchanged.
/// Contains: _showContextMenu(), _menuTile(), _artifactsBar(), _recallBar(), _skillsUsedBar()
///   _webSourcesBar()
part of 'chat_bubble.dart';

extension _ChatBubbleBars on _ChatBubbleState {
  void _showContextMenu(BuildContext context, bool isUser) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = widget.message.content;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16, top: 4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceLight : Dt.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _menuTile(
              icon: Icons.copy_rounded,
              label: 'Copy',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: content));
                HapticFeedback.selectionClick();
              },
            ),
            _menuTile(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                final text = content.trim();
                if (text.isNotEmpty) Share.share(text);
              },
            ),
            if (!isUser)
              _menuTile(
                icon: Icons.volume_up_rounded,
                label: 'Read aloud',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  if (Get.isRegistered<TtsService>()) {
                    final visible = widget.message.fileName == null
                        ? widget.message.content
                        : widget.message.content
                            .split('\n\nAttached file:')
                            .first;
                    final parts =
                        splitThoughtTags(_cleanAssistantText(visible));
                    final text = parts.answer.trim().isEmpty
                        ? widget.message.content
                        : parts.answer.trim();
                    Get.find<TtsService>().speak(text);
                  }
                },
              ),
            if (!isUser && widget.onRetry != null)
              _menuTile(
                icon: Icons.refresh_rounded,
                label: 'Regenerate',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onRetry!();
                },
              ),
            if (!isUser && widget.onBranch != null)
              _menuTile(
                icon: Icons.call_split_rounded,
                label: 'Branch in new chat',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onBranch!();
                },
              ),
            if (widget.onDelete != null)
              _menuTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete message',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete!();
                },
              ),
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon,
          size: 22, color: isDark ? AppColors.textPrimary : Dt.textPrimary),
      title: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _artifactsBar(
      BuildContext context, List<Map<String, String>> artifacts, bool isDark) {
    final controller = Get.find<ChatController>();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.layout,
                  size: 12, color: AppColors.primary),
            ),
            const SizedBox(width: 6),
            Text('Artifacts',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.primary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${artifacts.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: artifacts.map((art) {
              final id = art['id'] ?? '';
              final title = art['title'] ?? 'Artifact';
              final type = art['type'] ?? 'code';
              final content = art['content'] ?? '';

              IconData icon = LucideIcons.fileText;
              if (type == 'html') icon = LucideIcons.layout;
              if (type == 'code') icon = LucideIcons.code2;
              if (type == 'mermaid') icon = LucideIcons.gitBranch;

              return InkWell(
                onTap: () => controller.openArtifact(id, content,
                    title: title, type: type),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Dt.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Past-conversation recall indicator: N turns from other chats
  /// informed this answer (long-term ROM memory). Static proof row.
  Widget _recallBar(BuildContext context, int count, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color:
            Theme.of(context).primaryColor.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(LucideIcons.brain,
              size: 12, color: Theme.of(context).primaryColor),
        ),
        const SizedBox(width: 6),
        Text('Memory',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: Theme.of(context).primaryColor)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('+$count past turn${count == 1 ? '' : 's'}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).primaryColor)),
        ),
      ]),
    );
  }

  Widget _skillsUsedBar(
      BuildContext context, List<String> skills, bool isDark) {    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child:
                  Icon(LucideIcons.sparkles, size: 12, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 6),
            Text('Skills used',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Theme.of(context).primaryColor)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${skills.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).primaryColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: skills
                .map((name) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.check,
                              size: 10, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 4),
                          Text(name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isDark ? Colors.white : Dt.textPrimary)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _webSourcesBar(
      BuildContext context, List<WebSource> sources, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.link2,
                  size: 12, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 6),
            Text('Sources',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: const Color(0xFF3B82F6))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${sources.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3B82F6))),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sources.map((src) {
              return InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(src.url);
                  if (uri != null) {
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          src.faviconUrl,
                          width: 14,
                          height: 14,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Icon(LucideIcons.globe,
                                size: 8, color: Color(0xFF3B82F6)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(src.domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Dt.textPrimary)),
                            if (src.title.isNotEmpty && src.title != src.domain)
                              Text(src.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Theme.of(context).hintColor)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.externalLink,
                          size: 10, color: Theme.of(context).hintColor),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
