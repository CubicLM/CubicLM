import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../controllers/slide_deck_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../theme/design_tokens.dart';
import '../utils/slide_deck.dart';
import '../utils/slide_palette.dart';
import '../services/app_log_service.dart';
import 'slides/slide_charts.dart';
import 'slides/slide_canvas.dart';
import 'slides/slide_dialogs.dart';
import 'slides/slide_outline_view.dart';
import 'slides/slide_present_view.dart';
import '../widgets/app_ui.dart';
import '../widgets/model_switcher_sheet.dart';

/// Slide Maker (chat ⋮ menu): AI builds a structured deck from a topic.
/// Text-only models reserve proper image boxes; image-capable setups can
/// render them. Any slide can be regenerated solo or edited by hand.
/// Exports: Markdown, PDF, standalone HTML.
part 'slide_deck_sheets.dart';
part 'slide_deck_browser.dart';
part 'slide_deck_canvas.dart';
class SlideDeckView extends StatefulWidget {
  const SlideDeckView({super.key});

  @override
  State<SlideDeckView> createState() => _SlideDeckViewState();
}

class _SlideDeckViewState extends State<SlideDeckView> {
  /// setState bridge for `part` extensions (extensions cannot call the
  /// protected [State.setState] directly).
  void _refresh(VoidCallback fn) => setState(fn);

  late final SlideDeckController c;
  final _topicCtrl = TextEditingController();
  final _pageCtrl = PageController();
  int _page = 0;

  final _stt = stt.SpeechToText();
  bool _isListening = false;

  /// Viewer mode: ppt (dark 4:3 stage) · docs (light paper flow) ·
  /// pdf (light A4 portrait page). View-only; exports unchanged.
  String _viewMode = 'ppt';

  @override
  void initState() {
    super.initState();
    AppLogService.trackScreen('Slide Maker');
    c = Get.isRegistered<SlideDeckController>()
        ? Get.find<SlideDeckController>()
        : Get.put(SlideDeckController());
    _topicCtrl.text = c.topic.value;
  }

  @override
  void dispose() {
    AppLogService.untrackScreen('Slide Maker');
    _pageCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Slide Maker',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        actions: [
          Obx(() => c.hasDeck
              ? Row(
                  children: [
                    // Slide Sorter
                    _miniBtn(context, LucideIcons.layoutGrid, 'Slide sorter',
                        () => _showSlideSorter(context)),
                    const SizedBox(width: 4),
                    // Adaptive Content: Resize
                    _miniBtn(context, LucideIcons.scaling, 'Resize deck',
                        () => _showResizeDialog(context)),
                    const SizedBox(width: 4),
                    // TOC generation
                    _miniBtn(context, LucideIcons.list, 'Generate TOC',
                        c.generateTOC),
                    const SizedBox(width: 4),
                    // One-click restyle button
                    PopupMenuButton<String>(
                      tooltip: 'Restyle deck',
                      enabled: !c.generating.value,
                      onSelected: (v) => c.restyleDeck(v),
                      icon: const Icon(LucideIcons.palette, size: 20),
                      itemBuilder: (_) => [
                        for (final s in SlideDeckController.styles)
                          PopupMenuItem(
                            value: s,
                            child: Text(s,
                                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Theme settings',
                      icon: const Icon(LucideIcons.settings2, size: 20),
                      onPressed: () => _showThemePicker(context),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'AI Tools',
                      icon: const Icon(LucideIcons.sparkles, size: 20),
                      onSelected: (v) {
                        if (v == 'polish') c.polishDesign();
                        if (v == 'translate') _showTranslateDialog(context);
                        if (v == 'live') _showLiveDataDialog(context);
                        if (v == 'url') _showUrlDialog(context);
                        if (v == 'audit') c.auditDeck();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'polish', child: Text('Polish Design')),
                        const PopupMenuItem(
                            value: 'translate', child: Text('Translate Deck')),
                        const PopupMenuItem(
                            value: 'live', child: Text('Inject Live Data')),
                        const PopupMenuItem(
                            value: 'url', child: Text('Generate from URL')),
                        const PopupMenuItem(
                            value: 'audit', child: Text('Audit Deck')),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Clear deck',
                      icon: Icon(LucideIcons.trash2,
                          size: 20,
                          color: AppColors.error.withValues(alpha: 0.8)),
                      onPressed: c.clearDeck,
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'Export deck',
                      icon: Icon(LucideIcons.share2,
                          color: isDark ? AppColors.textPrimary : Dt.iconDefault),
                      onSelected: (v) {
                        if (v == 'md') c.exportMarkdown();
                        if (v == 'pdf') c.exportPdf();
                        if (v == 'html') c.exportHtml();
                        if (v == 'pptx') c.exportPptx();
                        if (v == 'preview') c.previewInBrowser();
                      },
                      itemBuilder: (_) => [
                        _exportItem('preview', 'Preview in browser'),
                        _exportItem('pptx', 'PowerPoint (.pptx)'),
                        _exportItem('pdf', 'PDF document'),
                        _exportItem('html', 'Web slides (.html)'),
                        _exportItem('md', 'Markdown (.md)'),
                      ],
                    ),
                  ],
                )
              : const SizedBox.shrink()),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (c.lastError.value != null) ...[
                    _errorBox(context, isDark),
                    const SizedBox(height: 10),
                  ],
                  if (c.hasDeck) ...[
                    const SizedBox(height: 12),
                    _deckBar(context, isDark),
                    if (c.generating.value)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(
                          backgroundColor: Dt.pillMuted,
                          color: Dt.accent,
                          minHeight: 2,
                        ),
                      ),
                    const SizedBox(height: 10),
                    _carousel(context, isDark),
                  ] else if (c.generating.value) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('Designing your slides…',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Theme.of(context).hintColor)),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Describe a topic below — the AI designs every slide.\n'
                        'Visual slides always reserve an image box, even when '
                        'the model can only write text.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Or start with a structured template:',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tName in SlideDeckController.templates.keys)
                          ActionChip(
                            backgroundColor:
                                isDark ? AppColors.surface : Dt.pillMuted,
                            side: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Dt.hairline),
                            label: Text(
                              tName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isDark ? Colors.white : Dt.textPrimary),
                            ),
                            onPressed: () => _pickTemplate(tName),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // ── Composer pinned at the bottom (chat-style) ──
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 4, 16, 16 + MediaQuery.of(context).padding.bottom),
              child: _composerCard(context, isDark),
            ),
          ],
        );
      }),
      // Outline Sheet
      bottomSheet: Obx(() => c.showingOutline.value
          ? SlideOutlineView()
          : const SizedBox.shrink()),
    );
  }

  PopupMenuItem<String> _exportItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
    );
  }

  // ── Composer ──

  /// Chat-style composer: borderless field on top, controls row below
  /// (model pill → style → slide count … generate CTA).
  Widget _composerCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Dt.card,
        borderRadius: BorderRadius.circular(Dt.rComposer),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicCtrl,
                    enabled: !c.generating.value,
                    maxLines: 4,
                    minLines: 1,
                    onChanged: (v) => c.topic.value = v,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, height: 1.35, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'e.g. How photosynthesis works (class 8)',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 16, color: Dt.textPlaceholder),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      isDense: true,
                      fillColor: Colors.transparent,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_isListening ? LucideIcons.mic : LucideIcons.micOff,
                      color: _isListening ? Dt.accent : Dt.textSecondary),
                  onPressed: _toggleSpeech,
                ),
              ],
            ),
          ),
          // (Sources + research live under the + sheet.)
          const SizedBox(height: 4),
          // Row 1: + sheet . model pill . style/audience . count . generate CTA.
          ClipRect(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Add source, AI research or vision sketch',
                  icon: Obx(() => Icon(
                        (c.sourceFile.value != null || c.useResearch.value || c.inputImage.value != null)
                            ? LucideIcons.plusCircle
                            : LucideIcons.plus,
                        size: 20,
                        color: (c.sourceFile.value != null ||
                                c.useResearch.value ||
                                c.inputImage.value != null)
                            ? Dt.accent
                            : Dt.textSecondary,
                      )),
                  onPressed: c.generating.value
                      ? null
                      : () => _showPlusSheet(context),
                ),
                SizedBox(
                  width: 125,
                  child: Obx(() => AppModelPill(
                        label: _engineLabel(),
                        onTap: () => showModelSwitcherSheet(context),
                      )),
                ),
                const SizedBox(width: 6),
                // Expanded (not Flexible): tight width forces the inner
                // ellipsis text to engage. Flexible passes loose width,
                // so a slightly-long "Style · Audience" label sized to
                // its intrinsic width and overflowed 0.56px on device.
                Expanded(child: Obx(() => _styleAudiencePill(context, isDark))),
                const SizedBox(width: 6),
                // Fixed-size stepper: never flex it — squeezing below its
                // ~54px intrinsic width overflowed 4.3px on 360px phones
                // (the pill's ellipsis text absorbs slack instead).
                Obx(() => _countStepper(context, isDark)),
                const Spacer(),
                AppCtaButton(
                  icon: c.generating.value
                      ? Icons.hourglass_top_rounded
                      : LucideIcons.presentation,
                  onTap: c.generating.value ||
                          (_topicCtrl.text.trim().isEmpty &&
                              c.sourceFile.value == null)
                      ? null
                      : () async {
                          c.topic.value = _topicCtrl.text;
                          await c.generate();
                          _page = 0;
                          if (_pageCtrl.hasClients) {
                            _pageCtrl.jumpToPage(0);
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Engine label for the model pill (same rules as chat).
  String _engineLabel() {
    final s = Get.find<SettingsController>();
    if (s.inferenceMode.value == 'cloud') {
      final m = s.selectedCloudModelName;
      if (m.isEmpty) return 'Cloud';
      final short = m.contains('/') ? m.split('/').last : m;
      return short.length > 14 ? '${short.substring(0, 14)}…' : short;
    }
    String name = '';
    try {
      final inf = Get.find<InferenceService>();
      if (inf.isModelLoaded.value) name = inf.loadedModelName.value;
    } catch (_) {}
    if (name.isEmpty) {
      try {
        final img = Get.find<LocalImageService>();
        if (img.isModelLoaded.value) name = img.loadedModelName.value;
      } catch (_) {}
    }
    if (name.isEmpty) return 'Local';
    final stripped = name.replaceAll(
        RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
    return stripped.length > 14 ? '${stripped.substring(0, 14)}…' : stripped;
  }

  /// Single style+audience pill (sits next to the model switcher).
  /// Opens one sheet with two tabs — Slide Style | Target Audience —
  /// mirroring the CubicWeb Builder setup sheet.
  Widget _styleAudiencePill(BuildContext context, bool isDark) {
    final audience = c.audience.value;
    final label = audience.isEmpty
        ? c.style.value
        : '${c.style.value} · $audience';
    final highlighted = audience.isNotEmpty;
    return InkWell(
      onTap: c.generating.value ? null : () => _showStyleAudienceSheet(context),
      borderRadius: BorderRadius.circular(Dt.pillHeight),
      child: Container(
        height: Dt.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: highlighted
              ? Dt.accent.withValues(alpha: 0.12)
              : Dt.pillMuted,
          borderRadius: BorderRadius.circular(Dt.pillHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.slidersHorizontal,
                size: 13,
                color: highlighted ? Dt.accent : Dt.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: highlighted ? Dt.accent : Dt.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  static const _audiences = [
    'General',
    'Investors',
    'Students',
    'Executives',
    'Engineers',
    'Marketing',
    'Clients',
    'Team',
  ];
}
