import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/design_tokens.dart';
import '../../splash_view.dart';

/// CHAT animation: Liquid Wave Dot (compact, Chat page size).
/// Self-contained loop — not shared with the Boot animation.
/// Bounce + sloshing waves run in phase, so the loop has no cut.
class ChatLiquidAnimation extends StatefulWidget {
  const ChatLiquidAnimation({super.key});

  @override
  State<ChatLiquidAnimation> createState() =>
      _ChatLiquidAnimationState();
}

class _ChatLiquidAnimationState extends State<ChatLiquidAnimation>
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
        final dy = bounce * 22.0 - 10.0;
        final nearBottom = (math.cos(phase) * 0.5 + 0.5);
        final squash =
            1.0 - 0.35 * math.pow(nearBottom, 6.0).toDouble();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 104,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'CubicLM',
                    style: GoogleFonts.heebo(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      height: 1.0,
                      color: textColor,
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      transform: Matrix4.diagonal3Values(
                          2.0 - squash, squash, 1.0),
                      alignment: Alignment.center,
                      child: Container(
                        width: 20,
                        height: 20,
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
          ],
        );
      },
    );
  }
}
