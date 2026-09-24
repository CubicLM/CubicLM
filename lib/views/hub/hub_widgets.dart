/// Shared Hub/Explore widgets: HubRing (circular percent indicator),
/// HubSectionTitle, HubStatTile.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Circular percent indicator: background track + progress arc + center
/// label. Hand-rolled (no chart dependency) for the advanced-feel rings.
class HubRing extends StatelessWidget {
  final double fraction; // 0..1
  final String center;
  final String label;
  final Color color;

  const HubRing({
    super.key,
    required this.fraction,
    required this.center,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: CustomPaint(
            painter: _RingPainter(
                fraction: fraction.clamp(0.0, 1.0),
                color: color,
                track: track),
            child: Center(
              child: Text(center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;

  _RingPainter(
      {required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (fraction <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      fraction * 2 * 3.141592653589793,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track;
}

/// Small caps section header used across Hub tabs.
class HubSectionTitle extends StatelessWidget {
  final String text;
  const HubSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(text.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: Theme.of(context).primaryColor)),
    );
  }
}

/// Single stat tile: big value + caption.
class HubStatTile extends StatelessWidget {
  final String value;
  final String caption;
  final IconData icon;

  const HubStatTile(
      {super.key,
      required this.value,
      required this.caption,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(caption,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).hintColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
