/// Slide canvases (ppt/docs/pdf) plus image controls.
///
/// Split from `slide_deck_view.dart` - behavior is unchanged.
/// Contains: _slideCanvas(), _pptCanvas(), _docsCanvas(), _pdfCanvas(), _imageControls(), _toggleFreeLayout()
///   _addManualImage(), _miniBtn(), _chipButton()
part of 'slide_deck_view.dart';

extension _SlideDeckCanvas on _SlideDeckViewState {
  /// PowerPoint-like 4:3 stage: gradient backdrop, image banner or
  /// reserved placeholder, compact title + bullets. Overflow-safe by
  /// construction (fixed line budgets + ellipsis).
  /// [mode]: ppt (dark 4:3 stage) · docs (light paper flow) ·
  /// pdf (light A4 portrait page).
  Widget _slideCanvas(BuildContext context, int index, Slide s, String mode) {
    if (mode == 'docs') return _docsCanvas(context, index, s);
    if (mode == 'pdf') return _pdfCanvas(context, index, s);
    return _pptCanvas(context, index, s);
  }

  Widget _pptCanvas(BuildContext context, int index, Slide s) {
    // Touch the observable so one-click theme presets rebuild the canvas.
    final pal = SlidePalette.fromTheme(c.theme.value);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: SlideCanvas(
        key: ValueKey('slide-$index'),
        slide: s,
        index: index,
        pal: pal,
        logoBytes: c.theme.value.logoBytes,
      ),
    );
  }

  /// Pure-Flutter chart renderer: bar, donut, or line from chartData.

  /// Docs mode: light paper, continuous flow (all content visible).
  Widget _docsCanvas(BuildContext context, int index, Slide s) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.title.isEmpty ? 'Untitled' : s.title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: const Color(0xFF1A1A1A)),
            ),
            Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 3,
                width: 44,
                decoration: BoxDecoration(
                    color: Dt.accent, borderRadius: BorderRadius.circular(2))),
            ...layoutBodyWidgets(s, s.wantsImage),
            if (s.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(s.notes.trim(),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF8A8A8A))),
            ],
          ]),
        ),
      ),
    );
  }

  /// PDF mode: light A4 portrait page with margins + page number.
  Widget _pdfCanvas(BuildContext context, int index, Slide s) {
    final total = c.slides.length;
    return AspectRatio(
      aspectRatio: 1 / 1.4142,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.title.isEmpty ? 'Untitled' : s.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: const Color(0xFF111111)),
            ),
            const SizedBox(height: 4),
            Text('Slide ${index + 1} of $total',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A9A9A))),
            const Divider(height: 20),
            Expanded(
              child: s.freeLayout
                  ? LayoutBuilder(
                      builder: (_, cons) => SlideCanvas.freeStack(
                        context,
                        s,
                        cons.maxWidth,
                        cons.maxHeight,
                        titleColor: const Color(0xFF111111),
                        bodyColor: const Color(0xFF333333),
                        titleBase: 16,
                        bodyBase: 11,
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...layoutBodyWidgets(s, s.wantsImage,
                                fontSize: 12,
                                bulletColor: const Color(0xFF555555),
                                textColor: const Color(0xFF222222)),
                          ]),
                    ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text('${index + 1} / $total',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: const Color(0xFFAAAAAA))),
            ),
          ]),
        ),
      ),
    );
  }

  /// Image generate/retry row under the canvas (full editor lives here;
  /// the canvas only previews).
  Widget _imageControls(BuildContext context, int index, Slide s) {
    final hasImage = (s.imageBytes != null && s.imageBytes!.isNotEmpty) || (s.imageUrl != null && s.imageUrl!.isNotEmpty);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (s.wantsImage || hasImage) ...[
          _chipButton(
            context,
            icon: hasImage ? LucideIcons.refreshCw : LucideIcons.sparkles,
            label: hasImage
                ? 'Regenerate AI image'
                : (c.canGenerateImages
                    ? 'Generate AI image'
                    : 'No AI image engine'),
            busy: c.imageBusyIndex.value == index,
            onTap: c.imageBusyIndex.value == index
                ? null
                : () => c.generateSlideImage(index),
          ),
          _chipButton(
            context,
            icon: LucideIcons.search,
            label: 'Find Stock Photo',
            busy: c.stockImageBusyIndex.value == index,
            onTap: c.stockImageBusyIndex.value == index
                ? null
                : () => c.findStockImage(index),
          ),
        ],
        _chipButton(
          context,
          icon: LucideIcons.imagePlus,
          label: hasImage ? 'Replace photo' : 'Add photo',
          busy: false,
          onTap: () => _addManualImage(index, s),
        ),
      ],
    );
  }

  /// Toggle freehand layout. First enable seeds non-overlapping
  /// defaults; disabling keeps values (re-enable restores them).
  void _toggleFreeLayout(int index, Slide s) {
    if (!s.freeLayout &&
        s.tDx == 0 &&
        s.tDy == 0 &&
        s.bDx == 0 &&
        s.bDy == 0 &&
        s.iDx == 0 &&
        s.iDy == 0) {
      s.tDx = 0.07;
      s.tDy = 0.05;
      s.bDx = 0.07;
      s.bDy = 0.34;
      s.iDx = 0.07;
      s.iDy = 0.64;
    }
    s.freeLayout = !s.freeLayout;
    c.slides.refresh();
  }

  /// Manual image: gallery or camera into the slide (works even when the
  /// model couldn't generate one — the reserved box gets filled by hand).
  Future<void> _addManualImage(int index, Slide s) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(LucideIcons.image),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(LucideIcons.camera),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      s.imageBytes = bytes.toList();
      c.slides.refresh();
    } catch (_) {}
  }
  Widget _miniBtn(
      BuildContext context, IconData icon, String tip, VoidCallback? onTap,
      {Color? color}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon,
              size: 16,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : (color ?? Theme.of(context).hintColor)),
        ),
      ),
    );
  }

  Widget _chipButton(BuildContext context,
      {required IconData icon,
      required String label,
      required bool busy,
      required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 13, color: Dt.accent),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
