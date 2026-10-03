import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';

/// Shared camera parsing helpers (exact copies of the original
/// CameraTab statics). Defined once here; the detail section imports
/// them instead of duplicating pixel-array / list parsing.
List<int> cameraInts(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is num) e.toInt()
  ];
}

List<double> cameraDbls(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is num) e.toDouble()
  ];
}

List<String> cameraStrs(dynamic raw) {
  if (raw is! List) return const [];
  return [for (final e in raw) '$e'];
}

String formatCameraMp(dynamic v) {
  final d = (v as num?)?.toDouble() ?? -1;
  if (d < 0) return '—';
  return d.truncateToDouble() == d
      ? '${d.toInt()} MP'
      : '${d.toStringAsFixed(1)} MP';
}

/// True sensor megapixels prefer the pixel array (e.g. 8000x6000 =
/// 48 MP); third-party JPEG caps are often binned (12 MP) on
/// Quad-Bayer sensors, which understates the hardware.
String cameraMpFor(Map<String, dynamic> m) {
  final pa = '${m['pixelArray'] ?? ''}';
  final mm = RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(pa);
  if (mm != null) {
    final w = int.tryParse(mm.group(1)!) ?? 0;
    final h = int.tryParse(mm.group(2)!) ?? 0;
    if (w > 0 && h > 0) return formatCameraMp(w * h / 1000000.0);
  }
  return formatCameraMp(m['mp']);
}

String cameraFacingLabel(int f) {
  switch (f) {
    case 0:
      return 'Back';
    case 1:
      return 'Front';
    case 2:
      return 'External';
    default:
      return '—';
  }
}

/// Pre-parsed card view-model. Computed ONCE per camera-data change
/// by the parent (memoized), so per-build regex/double parsing over
/// pixel arrays and focal lists never repeats per tick/rebuild.
class CameraCardView {
  final String title;
  final String resolution;
  final String focalLabel;

  const CameraCardView({
    required this.title,
    required this.resolution,
    required this.focalLabel,
  });

  factory CameraCardView.fromCamera(Map<String, dynamic> m) {
    final mp = cameraMpFor(m);
    final facing = (m['facing'] as num?)?.toInt() ?? -1;
    final aux = m['physical'] == true ? ' · Aux' : '';
    final focals = cameraDbls(m['focals']);
    return CameraCardView(
      title: '$mp - ${cameraFacingLabel(facing)}$aux',
      resolution: '${m['maxW'] ?? '—'} x ${m['maxH'] ?? '—'}',
      focalLabel: focals.isEmpty
          ? '—'
          : '${focals.first.toStringAsFixed(2)}mm',
    );
  }
}

/// One camera selector card (exact copy of the original horizontal
/// list item). Purely presentational — all parsing is done upstream.
class CameraCardItem extends StatelessWidget {
  final CameraCardView card;
  final bool selected;
  final VoidCallback onTap;

  const CameraCardItem({
    super.key,
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 168,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? Dt.accent
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? Dt.accent
                      : Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color:
                            selected ? Colors.white : null)),
                const SizedBox(height: 2),
                Text(card.resolution,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                                .withValues(alpha: 0.9)
                            : Theme.of(context).hintColor)),
                Text(card.focalLabel,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                                .withValues(alpha: 0.9)
                            : Theme.of(context).hintColor)),
              ],
            ),
          ),
          if (selected)
            const Positioned(
              right: 10,
              bottom: 10,
              child: Icon(LucideIcons.checkCircle2,
                  size: 20, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
