import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';

/// Shared bits for the CubicDevice Info tabs (one widget per file
/// under views/device_info_tab_*.dart). App card language throughout.
Widget devCard(BuildContext context, {required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
          color: Theme.of(context)
              .dividerColor
              .withValues(alpha: 0.6)),
    ),
    child: child,
  );
}

Widget devRow(BuildContext context, String label, String value,
    {bool last = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      SelectableText(value,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5, color: Dt.accent)),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(
            height: 1,
            thickness: 0.5,
            color: last
                ? Colors.transparent
                : Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.5)),
      ),
    ],
  );
}

String freqFmt(int mhz) {
  if (mhz < 0) return '—';
  if (mhz >= 1000) {
    return '${(mhz / 1000).toStringAsFixed(1)} GHz';
  }
  return '$mhz MHz';
}

String clockFmt(int ms) {
  if (ms <= 0) return '—';
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
}

String langLabel(String tag) {
  const names = {
    'en': 'English', 'bn': 'Bengali', 'hi': 'Hindi', 'ur': 'Urdu',
    'ar': 'Arabic', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'pt': 'Portuguese', 'ru': 'Russian', 'zh': 'Chinese',
    'ja': 'Japanese', 'ko': 'Korean', 'tr': 'Turkish',
    'id': 'Indonesian', 'vi': 'Vietnamese', 'it': 'Italian',
    'nl': 'Dutch', 'th': 'Thai', 'ms': 'Malay',
  };
  final code = tag.split(RegExp(r'[_-]')).first.toLowerCase();
  final name = names[code] ?? code;
  final flat = tag.replaceAll('-', '_');
  return '$name ($flat)';
}

/// RAM history sparkline with soft fill and smooth auto-scaled cubic wave curve.
class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color line;
  const SparklinePainter({required this.values, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Auto-scale Y-axis relative to active min/max so small RAM fluctuations (65% -> 66%) map to a rich wave
    var minV = values[0];
    var maxV = values[0];
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final diff = maxV - minV;
    final pad = diff < 0.06 ? (0.06 - diff) / 2 : 0.01;
    final rangeMin = (minV - pad).clamp(0.0, 1.0);
    final rangeMax = (maxV + pad).clamp(0.0, 1.0);
    final rangeSpan = rangeMax > rangeMin ? (rangeMax - rangeMin) : 0.1;

    final pts = <Offset>[];
    final stepX = values.length > 1 ? size.width / (values.length - 1) : size.width;
    for (var i = 0; i < values.length; i++) {
      final x = values.length > 1 ? i * stepX : size.width / 2;
      final normY = ((values[i] - rangeMin) / rangeSpan).clamp(0.0, 1.0);
      final y = size.height - (normY * (size.height - 16) + 8);
      pts.add(Offset(x, y));
    }

    final path = Path();
    if (pts.length == 1) {
      path.moveTo(0, pts[0].dy);
      path.lineTo(size.width, pts[0].dy);
    } else {
      path.moveTo(pts[0].dx, pts[0].dy);
      for (var i = 0; i < pts.length - 1; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final ctrlX = (p0.dx + p1.dx) / 2;
        path.cubicTo(ctrlX, p0.dy, ctrlX, p1.dy, p1.dx, p1.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Subtle horizontal grid lines for oscilloscope/monitor wave effect
    final paintGrid = Paint()
      ..color = line.withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height * 0.25), Offset(size.width, size.height * 0.25), paintGrid);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paintGrid);
    canvas.drawLine(Offset(0, size.height * 0.75), Offset(size.width, size.height * 0.75), paintGrid);

    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.4), line.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);

    // Active glowing live dot on the latest sample
    if (pts.isNotEmpty) {
      final last = pts.last;
      canvas.drawCircle(
          last,
          5.0,
          Paint()
            ..color = line.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(
          last,
          2.8,
          Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) =>
      old.values != values || old.line != line;
}

/// Core history mini wave painter for individual CPU core boxes.
class CoreWavePainter extends CustomPainter {
  final List<double> values;
  final Color line;
  const CoreWavePainter({required this.values, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Auto-scale Y-axis relative to core history min/max for expressive wave
    var minV = values[0];
    var maxV = values[0];
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final diff = maxV - minV;
    final pad = diff < 0.12 ? (0.12 - diff) / 2 : 0.02;
    final rangeMin = (minV - pad).clamp(0.0, 1.0);
    final rangeMax = (maxV + pad).clamp(0.0, 1.0);
    final rangeSpan = rangeMax > rangeMin ? (rangeMax - rangeMin) : 0.1;

    final pts = <Offset>[];
    final stepX = values.length > 1 ? size.width / (values.length - 1) : size.width;
    for (var i = 0; i < values.length; i++) {
      final x = values.length > 1 ? i * stepX : size.width / 2;
      final normY = ((values[i] - rangeMin) / rangeSpan).clamp(0.0, 1.0);
      final y = size.height - (normY * (size.height - 10) + 5);
      pts.add(Offset(x, y));
    }

    final path = Path();
    if (pts.length == 1) {
      path.moveTo(0, pts[0].dy);
      path.lineTo(size.width, pts[0].dy);
    } else {
      path.moveTo(pts[0].dx, pts[0].dy);
      for (var i = 0; i < pts.length - 1; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final ctrlX = (p0.dx + p1.dx) / 2;
        path.cubicTo(ctrlX, p0.dy, ctrlX, p1.dy, p1.dx, p1.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Horizontal midpoint line
    canvas.drawLine(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.5),
        Paint()
          ..color = line.withValues(alpha: 0.12)
          ..strokeWidth = 0.8);

    // Gradient fill under wave
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.3), line.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Wave stroke
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);

    // Active live dot on the latest frequency sample
    if (pts.isNotEmpty) {
      final last = pts.last;
      canvas.drawCircle(
          last,
          4.0,
          Paint()
            ..color = line.withValues(alpha: 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(
          last,
          2.2,
          Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant CoreWavePainter old) =>
      old.values != values || old.line != line;
}
