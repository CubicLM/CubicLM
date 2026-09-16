/// Shared slide renderer: the exact canvas the editor previews,
/// reused by Present mode. Pure params in (slide, palette, logo) — no
/// controllers, so it stays widget-testable.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme/design_tokens.dart';
import '../../utils/slide_deck.dart';
import '../../utils/slide_palette.dart';
import '../../widgets/typing_text.dart';
import 'slide_charts.dart';
import 'slide_painters.dart';

class SlideCanvas extends StatelessWidget {
  final Slide slide;
  final int index;
  final SlidePalette pal;
  final List<int>? logoBytes;
  final double aspect;
  final bool interactive;

  const SlideCanvas({
    super.key,
    required this.slide,
    required this.index,
    required this.pal,
    this.logoBytes,
    this.aspect = 4 / 3,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final Slide s = slide;
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    final hasUrl = s.imageUrl != null && s.imageUrl!.isNotEmpty;
    final hasBanner = hasImage || hasUrl || s.wantsImage || (s.embedUrl != null && s.embedUrl!.isNotEmpty);
    
    // Adaptive content: show more points if no banner
    final maxPoints = hasBanner ? 4 : 8;
    final showPoints = s.points.take(maxPoints).toList();
    final hidden = s.points.length - showPoints.length;
    final logo = logoBytes;
    // Chart/diagram lay out with Expanded bars/canvas: they need bounded
    // loose constraints (plain Center) and self-fit. Every other layout
    // is fixed-size content: scale it down to fit instead of overflowing
    // (66px bottom overflow on phones). FittedBox is incompatible with
    // flex descendants, hence the split.
    final flexLayout = s.layout == 'chart' || s.layout == 'diagram';

    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [pal.bg, pal.bgDeep],
          ),
          border: Border.all(color: pal.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: s.freeLayout
            ? LayoutBuilder(
                builder: (_, cons) => freeStack(
                  context,
                  s,
                  cons.maxWidth,
                  cons.maxHeight,
                  titleColor: pal.title,
                  bodyColor: pal.body,
                  titleBase: 17,
                  bodyBase: 11.5,
                  accent: pal.accent,
                  interactive: interactive,
                ),
              )
            : Stack(
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (hasImage)
                      SizedBox(
                        height: 110,
                        child: _applyMask(s, Image.memory(
                          Uint8List.fromList(s.imageBytes!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                        )),
                      )
                    else if (hasUrl)
                      SizedBox(
                        height: 110,
                        child: _applyMask(s, Image.network(
                          s.imageUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                        )),
                      )
                      else if (s.wantsImage)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: pal.accent.withValues(alpha: 0.12),
                          border: Border(
                            bottom: BorderSide(color: pal.accent, width: 1),
                          ),
                        ),
                        child: Row(children: [
                          Icon(LucideIcons.imagePlus,
                              size: 13, color: pal.accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.imagePrompt.trim().isEmpty
                                  ? 'IMAGE SPACE'
                                  : s.imagePrompt.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _st(pal, false,
                                  size: 10.5,
                                  weight: FontWeight.w600,
                                  color: pal.body),
                            ),
                          ),
                        ]),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Stack(
                          children: [
                            if (flexLayout)
                              // Center content vertically if it's sparse
                              Center(
                                child: _pptContentByLayout(s, index,
                                    showPoints, hidden, pal, !hasBanner),
                              )
                            else
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (_, cons) => FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: cons.maxWidth,
                                      child: _pptContentByLayout(
                                          s,
                                          index,
                                          showPoints,
                                          hidden,
                                          pal,
                                          !hasBanner),
                                    ),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text('${index + 1}',
                                  style: _st(pal, true,
                                      size: 10,
                                      weight: FontWeight.w800,
                                      color: pal.muted)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  if (logo != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Image.memory(
                        Uint8List.fromList(logo),
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
  /// Theme-aware slide text: heading/body family from the active preset,
  /// whitelisted + guarded so model-invented or offline-missing families
  /// fall back instead of breaking the canvas.
  TextStyle _st(SlidePalette pal, bool heading,
      {double? size,
      FontWeight? weight,
      double? height,
      Color? color,
      FontStyle? style}) {
    final fam = heading ? pal.headingFont : pal.bodyFont;
    try {
      return GoogleFonts.getFont(fam,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          fontStyle: style);
    } catch (_) {
      return GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          fontStyle: style);
    }
  }

  Widget _pptContentByLayout(
      Slide s, int index, List<String> showPoints, int hidden, SlidePalette pal, bool expanded) {
    // Dynamic font scaling
    final titleSize = expanded ? 24.0 : 19.0;
    final bodySize = expanded ? 14.5 : 12.0;
    final bulletSize = expanded ? 13.5 : 11.0;

    switch (s.layout) {
      case 'title':
        return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TypingText(
                text: s.title.isEmpty ? 'Untitled' : s.title,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _st(pal, true,
                    size: titleSize + 4,
                    weight: FontWeight.w800,
                    height: 1.2,
                    color: pal.title),
              ),
              if (s.subtitle.isNotEmpty || showPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                    width: 48,
                    height: 3.0,
                    decoration: BoxDecoration(
                        color: pal.accent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                TypingText(
                  text: s.subtitle.isNotEmpty ? s.subtitle : showPoints.first,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: _st(pal, false,
                      size: bodySize + 2,
                      weight: FontWeight.w500,
                      color: pal.body),
                ),
              ],
            ],
          );

      case 'quote':
        final quoteText = s.points.isNotEmpty ? s.points.first : s.title;
        final author = s.quoteAuthor.isNotEmpty
            ? s.quoteAuthor
            : (s.points.length > 1 ? s.points[1] : '');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(LucideIcons.quote, size: 24, color: pal.accent),
              const SizedBox(height: 8),
              TypingText(
                text: '"$quoteText"',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _st(pal, true,
                    size: 14.5,
                    style: FontStyle.italic,
                    weight: FontWeight.w600,
                    height: 1.35,
                    color: pal.title),
              ),
              if (author.isNotEmpty) ...[
                const SizedBox(height: 6),
                TypingText(
                  text: '- $author',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: _st(pal, false,
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: pal.accent),
                ),
              ],
            ],
          ),
        );

      case 'stats':
        final statsItems = s.stats.isNotEmpty
            ? s.stats
            : s.points.take(3).map((p) {
                final match =
                    RegExp(r'^([\d%+\$\.\s\w]+)[:\-–]\s*(.+)$').firstMatch(p);
                if (match != null) {
                  return {
                    'value': match.group(1)!.trim(),
                    'label': match.group(2)!.trim()
                  };
                }
                return {'value': '•', 'label': p};
              }).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingText(
              text: s.title.isEmpty ? 'Key Statistics' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: titleSize, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final item in statsItems.take(3))
                  Expanded(
                    child: Container(
                      height: expanded ? 140 : 100,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: pal.accentBorder),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TypingText(
                            text: item['value'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _st(pal, true,
                                size: expanded ? 24 : 18,
                                weight: FontWeight.w900,
                                color: pal.accent),
                          ),
                          const SizedBox(height: 4),
                          TypingText(
                            text: item['label'] ?? '',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: _st(pal, false,
                                size: expanded ? 11 : 9.5, color: pal.body),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );

      case 'comparison':
        final col1 = s.columns.isNotEmpty
            ? s.columns[0]
            : s.points.take((s.points.length / 2).ceil()).toList();
        final col2 = s.columns.length > 1
            ? s.columns[1]
            : s.points.skip((s.points.length / 2).ceil()).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingText(
              text: s.title.isEmpty ? 'Comparison' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: titleSize, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    height: expanded ? 180 : 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: pal.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: pal.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      // Min sizing: fixed-height card never errors; the
                      // outer FittedBox scales down instead.
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in col1.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TypingText(text: '• $p',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _st(pal, false,
                                    size: bodySize, color: pal.body)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: expanded ? 180 : 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: pal.accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: pal.accentBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in col2.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TypingText(text: '✓ $p',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _st(pal, false,
                                    size: bodySize, color: pal.body)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'timeline':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingText(
              text: s.title.isEmpty ? 'Timeline' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: titleSize, weight: FontWeight.w800, color: pal.title),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < showPoints.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: expanded ? 22 : 16,
                      height: expanded ? 22 : 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: pal.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: _st(pal, true,
                            size: expanded ? 12 : 9.5,
                            weight: FontWeight.w800,
                            color: pal.onAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TypingText(
                        text: showPoints[i],
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _st(pal, false,
                            size: expanded ? 14 : 10.5, color: pal.body),
                      ),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more steps',
                  style: _st(pal, false,
                      size: expanded ? 11 : 9.5,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );

      case 'summary':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.checkCircle2,
                    size: expanded ? 20 : 15, color: pal.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: TypingText(
                    text: s.title.isEmpty ? 'Key Takeaways' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _st(pal, true,
                        size: titleSize,
                        weight: FontWeight.w800,
                        color: pal.title),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in showPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✓ ',
                        style: TextStyle(
                            color: pal.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: expanded ? 16 : 10.5)),
                    Expanded(
                      child: TypingText(
                        text: p,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _st(pal, false,
                            size: expanded ? 14 : 10.5,
                            height: 1.35,
                            color: pal.body),
                      ),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: _st(pal, false,
                      size: expanded ? 11 : 9.5,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );

      case 'chart':
        return chartContent(s, pal);

      case 'table':
        return _tableContent(s, pal, expanded);

      case 'diagram':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                s.title.isEmpty ? 'Process Flow' : s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _st(pal, true,
                    size: 15,
                    weight: FontWeight.w800,
                    color: pal.title),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CustomPaint(
                  painter: DiagramPainter(s.diagram ?? '', pal.isDark),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingText(
              text: s.title.isEmpty ? 'Untitled' : s.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _st(pal, true,
                  size: titleSize,
                  weight: FontWeight.w800,
                  height: 1.2,
                  color: pal.title),
            ),
            const SizedBox(height: 10),
            for (var j = 0; j < showPoints.length; j++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.icons != null && j < s.icons!.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(_getIcon(s.icons![j]), size: bulletSize + 2, color: pal.accent),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Text('▸',
                            style: TextStyle(
                                color: pal.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: bulletSize + 2)),
                      ),
                    Expanded(
                      child: TypingText(
                        text: showPoints[j],
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _st(pal, false,
                            size: bulletSize,
                            height: 1.4,
                            color: pal.body),
                      ),
                    ),
                  ],
                ),
              ),
            if (hidden > 0)
              Text('+$hidden more',
                  style: _st(pal, false,
                      size: bulletSize - 2,
                      weight: FontWeight.w700,
                      color: pal.muted)),
          ],
        );
    }
  }
  Widget _applyMask(Slide s, Widget child) {
    if (s.imageMask == 'circle') {
      return ClipOval(child: child);
    } else if (s.imageMask == 'hexagon') {
      return ClipPath(
        clipper: _HexagonClipper(),
        child: child,
      );
    } else if (s.imageMask == 'squircle') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: child,
      );
    }
    return child;
  }

  Widget _tableContent(Slide s, SlidePalette pal, bool expanded) {
    if (s.tableData.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TypingText(
          text: s.title.isEmpty ? 'Data Table' : s.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _st(pal, true,
              size: expanded ? 24.0 : 19.0, weight: FontWeight.w800, color: pal.title),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: pal.cardBorder),
          ),
          child: Table(
            border: TableBorder.symmetric(inside: BorderSide(color: pal.cardBorder)),
            children: [
              for (var i = 0; i < s.tableData.length; i++)
                TableRow(
                  children: [
                    for (final cell in s.tableData[i])
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TypingText(
                          text: cell,
                          style: _st(pal, i == 0,
                              size: 11,
                              weight: i == 0 ? FontWeight.bold : FontWeight.normal,
                              color: i == 0 ? pal.accent : pal.body),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
  /// Free-layout stack shared by PPT canvas, PDF canvas and Present mode:
  /// title / body / image boxes positioned by fractional offsets.
  /// [interactive] false renders statically (Present mode).
  static Widget freeStack(
    BuildContext context,
    Slide s,
    double w,
    double h, {
    required Color titleColor,
    required Color bodyColor,
    required double titleBase,
    required double bodyBase,
    Color? accent,
    bool interactive = true,
  }) {
    final ac = accent ?? Dt.accent;
    final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;
    return Stack(children: [
      FreeBox(enabled: interactive,
        dx: s.tDx,
        dy: s.tDy,
        scale: s.tS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.tDx = dx;
          s.tDy = dy;
          s.tS = sc;
        },
        builder: (_, sc) => TypingText(
          text: s.title.isEmpty ? 'Untitled' : s.title,
          style: GoogleFonts.plusJakartaSans(
              fontSize: titleBase * sc,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: titleColor),
        ),
      ),
      FreeBox(enabled: interactive,
        dx: s.bDx,
        dy: s.bDy,
        scale: s.bS,
        canvasW: w,
        canvasH: h,
        onCommit: (dx, dy, sc) {
          s.bDx = dx;
          s.bDy = dy;
          s.bS = sc;
        },
        builder: (_, sc) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in s.points.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: TypingText(text: '▸ $p',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: bodyBase * sc,
                          height: 1.35,
                          color: bodyColor)),
                ),
            ]),
      ),
      if (hasImage || s.wantsImage)
        FreeBox(enabled: interactive,
          dx: s.iDx,
          dy: s.iDy,
          scale: s.iS,
          canvasW: w,
          canvasH: h,
          boxH: 84,
          onCommit: (dx, dy, sc) {
            s.iDx = dx;
            s.iDy = dy;
            s.iS = sc;
          },
          builder: (_, sc) => hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    Uint8List.fromList(s.imageBytes!),
                    height: 84 * sc,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                )
              : Container(
                  height: 52 * sc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ac, width: 1),
                    color: ac.withValues(alpha: 0.1),
                  ),
                  child: Text('IMAGE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10 * sc,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: ac)),
                ),
        ),
    ]);
  }
}

/// Maps semantic icon name strings to Lucide IconData.
IconData _getIcon(String name) {
  switch (name.toLowerCase()) {
    case 'check':
      return LucideIcons.check;
    case 'star':
      return LucideIcons.star;
    case 'bolt':
      return LucideIcons.zap;
    case 'heart':
      return LucideIcons.heart;
    case 'lightbulb':
      return LucideIcons.lightbulb;
    case 'target':
      return LucideIcons.target;
    case 'rocket':
      return LucideIcons.rocket;
    case 'shield':
      return LucideIcons.shield;
    case 'chart':
      return LucideIcons.barChart;
    case 'clock':
      return LucideIcons.clock;
    case 'flag':
      return LucideIcons.flag;
    case 'globe':
      return LucideIcons.globe;
    case 'key':
      return LucideIcons.key;
    case 'lock':
      return LucideIcons.lock;
    case 'users':
      return LucideIcons.users;
    case 'zap':
      return LucideIcons.zap;
    case 'code':
      return LucideIcons.code2;
    case 'file':
      return LucideIcons.fileText;
    case 'image':
      return LucideIcons.image;
    case 'link':
      return LucideIcons.link;
    case 'play':
      return LucideIcons.play;
    case 'settings':
      return LucideIcons.settings;
    case 'thumbs up':
      return LucideIcons.thumbsUp;
    case 'trending':
      return LucideIcons.trendingUp;
    case 'award':
      return LucideIcons.award;
    case 'bookmark':
      return LucideIcons.bookmark;
    case 'calendar':
      return LucideIcons.calendar;
    case 'layers':
      return LucideIcons.layers;
    case 'layout':
      return LucideIcons.layout;
    case 'list':
      return LucideIcons.list;
    case 'map':
      return LucideIcons.map;
    case 'phone':
      return LucideIcons.phone;
    case 'pie chart':
      return LucideIcons.pieChart;
    case 'search':
      return LucideIcons.search;
    case 'send':
      return LucideIcons.send;
    case 'tag':
      return LucideIcons.tag;
    case 'tool':
      return LucideIcons.wrench;
    case 'wifi':
      return LucideIcons.wifi;
    default:
      return LucideIcons.circle;
  }
}

class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.5, 0);
    path.lineTo(size.width, size.height * 0.25);
    path.lineTo(size.width, size.height * 0.75);
    path.lineTo(size.width * 0.5, size.height);
    path.lineTo(0, size.height * 0.75);
    path.lineTo(0, size.height * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
