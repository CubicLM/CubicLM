/// Sorter, deck bar, carousel, and slide cards.
///
/// Split from `slide_deck_view.dart` - behavior is unchanged.
/// Contains: _showSlideSorter(), _showResizeDialog(), _themePresetCard(), _pickTemplate(), _errorBox()
///   _deckBar(), _carousel(), _slideCard()
part of 'slide_deck_view.dart';

extension _SlideDeckBrowser on _SlideDeckViewState {
  void _showSlideSorter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Slide Sorter',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: Obx(() => GridView.builder(
                      controller: scroll,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 4 / 3.5,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: c.slides.length,
                      itemBuilder: (_, i) {
                        final s = c.slides[i];
                        final active = i == _page;
                        final pal = SlidePalette.fromTheme(c.theme.value);
                        return GestureDetector(
                          onTap: () {
                            _refresh(() => _page = i);
                            _pageCtrl.jumpToPage(i);
                            Navigator.pop(ctx);
                          },
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: active ? Dt.accent : Dt.hairline,
                                      width: active ? 2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: AbsorbPointer(
                                    child: SlideCanvas(
                                      slide: s,
                                      index: i,
                                      pal: pal,
                                      logoBytes: c.theme.value.logoBytes,
                                      interactive: false,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('${i + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: active ? Dt.accent : Dt.textSecondary)),
                            ],
                          ),
                        );
                      },
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResizeDialog(BuildContext context) {
    final ctrl = TextEditingController(text: '${c.slides.length}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resize Deck'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter target slide count (AI will merge/split slides):'),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'e.g. 5'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(ctrl.text);
              if (count != null && count >= 3 && count <= 20) {
                c.resizeDeck(count);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Resize'),
          ),
        ],
      ),
    );
  }

  Widget _themePresetCard(
      BuildContext sheetCtx, SlideDeckTheme t, {required bool selected}) {
    final pal = SlidePalette.fromTheme(t);
    return InkWell(
      onTap: () {
        c.applyThemePreset(t.name);
        Navigator.pop(sheetCtx);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Dt.accent : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: pal.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: pal.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTemplate(String templateName) async {
    if (_topicCtrl.text.trim().isEmpty) {
      _topicCtrl.text =
          templateName.replaceFirst(RegExp(r'^[^\w\s]+\s*'), '').trim();
      c.topic.value = _topicCtrl.text;
    }
    await c.generateFromTemplate(templateName);
    _page = 0;
    if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(0);
    }
  }

  Widget _errorBox(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(c.lastError.value!,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5, color: AppColors.error, height: 1.4)),
    );
  }

  // ── Deck bar + carousel ──

  Widget _deckBar(BuildContext context, bool isDark) {
    return Row(children: [
      Text('${c.slides.length} slides',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).hintColor)),
      const Spacer(),
      IconButton(
        tooltip: 'Present fullscreen',
        icon: const Icon(LucideIcons.play, size: 18),
        onPressed: () => Get.to(() => SlidePresentView(
              slides: c.slides.toList(),
              theme: c.theme.value,
              initialIndex: _page.clamp(0, c.slides.length - 1),
            )),
      ),
      IconButton(
        tooltip: 'Add blank slide',
        icon: const Icon(LucideIcons.plus, size: 18),
        onPressed: () {
          c.addBlank();
          _page = c.slides.length - 1;
          if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_page);
        },
      ),
    ]);
  }

  Widget _carousel(BuildContext context, bool isDark) {
    return Column(children: [
      // Viewer mode switch (Docs / PowerPoint / PDF look).
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'docs',
              icon: Icon(LucideIcons.fileText, size: 14),
              label: Text('Docs'),
            ),
            ButtonSegment(
              value: 'ppt',
              icon: Icon(LucideIcons.presentation, size: 14),
              label: Text('Slides'),
            ),
            ButtonSegment(
              value: 'pdf',
              icon: Icon(LucideIcons.fileDown, size: 14),
              label: Text('PDF'),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (s) => _refresh(() => _viewMode = s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Thumbnail strip for quick navigation
      if (c.slides.length > 1)
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: c.slides.length,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemBuilder: (_, i) {
              final ts = c.slides[i];
              final active = i == _page;
              return GestureDetector(
                onTap: () {
                  _refresh(() => _page = i);
                  _pageCtrl.jumpToPage(i);
                },
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: active
                          ? Dt.accent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Dt.hairline),
                      width: active ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${i + 1}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: active ? Dt.accent : Dt.textSecondary)),
                      const SizedBox(height: 2),
                      Text(ts.layout.substring(0, 4),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 8, color: Dt.textPlaceholder)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        height: _viewMode == 'ppt' ? 470 : 560,
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: c.slides.length,
          onPageChanged: (i) => _refresh(() => _page = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _slideCard(context, isDark, i, c.slides[i]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('${(_page + 1).clamp(1, c.slides.length)} / ${c.slides.length}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).hintColor)),
    ]);
  }

  Widget _slideCard(BuildContext context, bool isDark, int index, Slide s) {
    final busy = c.generating.value && c.regenIndex.value == index;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline),
      ),
      // Scrollable: notes + image controls can exceed the fixed
      // PageView viewport on small screens — scroll instead of overflow.
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('SLIDE ${index + 1}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Dt.accent)),
            if (s.speakerNotes.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Has speaker notes',
                child: Icon(LucideIcons.mic, size: 12, color: Dt.accent),
              ),
            ],
            if (s.citations.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Has citations',
                child: Icon(LucideIcons.scroll, size: 12, color: Dt.accent),
              ),
            ],
            const Spacer(),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              _miniBtn(context, LucideIcons.pencil, 'Edit slide',
                  () => showEditDialog(context, isDark, index, s)),
              _miniBtn(context, LucideIcons.move, 'Free layout',
                  () => _toggleFreeLayout(index, s),
                  color: s.freeLayout ? Dt.accent : null),
              _miniBtn(context, LucideIcons.refreshCw, 'Regenerate this slide',
                  () => c.regenerateSlide(index)),
              PopupMenuButton<String>(
                tooltip: 'Transform layout',
                icon: const Icon(LucideIcons.layout, size: 16, color: Dt.textSecondary),
                onSelected: (v) => c.transformLayout(index, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'cards', child: Text('Feature Cards')),
                  const PopupMenuItem(value: 'gallery', child: Text('Image Gallery')),
                  const PopupMenuItem(value: 'stats', child: Text('Key Stats')),
                  const PopupMenuItem(value: 'timeline', child: Text('Timeline')),
                ],
              ),
              _miniBtn(context, LucideIcons.sparkles, 'AI refine',
                  () => showRefineDialog(context, isDark, index)),
              _miniBtn(
                  context,
                  LucideIcons.copy,
                  'Duplicate slide',
                  c.slides.length >= SlideDeckController.maxSlides
                      ? null
                      : () => c.duplicateSlide(index)),
              _miniBtn(context, LucideIcons.arrowUp, 'Move up',
                  index == 0 ? null : () => c.moveSlide(index, -1)),
              _miniBtn(
                  context,
                  LucideIcons.arrowDown,
                  'Move down',
                  index == c.slides.length - 1
                      ? null
                      : () => c.moveSlide(index, 1)),
              _miniBtn(context, LucideIcons.trash2, 'Delete slide',
                  () => c.deleteSlide(index),
                  color: AppColors.error.withValues(alpha: 0.8)),
            ],
          ]),
          const SizedBox(height: 10),
          // WYSIWYG canvas — how the slide actually looks (4:3 stage).
          _slideCanvas(context, index, s, _viewMode),
          if (s.citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: s.citations
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(c.source, style: const TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            onPressed: () {},
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (s.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Notes: ${s.notes.trim()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor)),
          ],
          const SizedBox(height: 8),
          _imageControls(context, index, s),
        ]),
      ),
    );
  }
}
