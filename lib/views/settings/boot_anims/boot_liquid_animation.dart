import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/design_tokens.dart';
import '../../splash_view.dart';

/// BOOT animation: Liquid Wave Dot (picker frame size).
/// Self-contained loop — not shared with the Chat animation.
/// Bounce + sloshing waves run in phase, so the loop has no cut.
class BootLiquidAnimation extends StatefulWidget {
  const BootLiquidAnimation({super.key});

  @override
  State<BootLiquidAnimation> createState() =>
      _BootLiquidAnimationState();
}

class _BootLiquidAnimationState extends State<BootLiquidAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Dt.textPrimary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        final phase = v * math.pi * 2.0;
        final bounce = -math.sin(phase);
        const ty = 0.0; // centered stack; bounce via offset below
        final dy = bounce * 26.0 - 12.0;
        final nearBottom = (math.cos(phase) * 0.5 + 0.5);
        final squash =
            1.0 - 0.35 * math.pow(nearBottom, 6.0).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'CubicLM',
                    style: GoogleFonts.heebo(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      height: 1.0,
                      color: textColor,
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(ty, dy),
                    child: Transform(
                      transform: Matrix4.diagonal3Values(
                          2.0 - squash, squash, 1.0),
                      alignment: Alignment.center,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD950)
                                  .withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: CustomPaint(
                            painter: LiquidWavePainter(
                              waveProgress: 1.0,
                              animValue: v,
                              foregroundColor:
                                  const Color(0xFFFFD950),
                              backgroundColor:
                                  const Color(0xFF977A12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Think • Create • Explore',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Dt.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        );
      },
    );
  }
}
