import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/design_tokens.dart';
import '../../splash_view.dart';

/// BOOT animation: 3D Tech Cube (picker frame size).
/// Self-contained loop — not shared with the Chat animation.
/// Phase-continuous rotation, so the loop has no visible cut.
class BootCubeAnimation extends StatefulWidget {
  const BootCubeAnimation({super.key});

  @override
  State<BootCubeAnimation> createState() => _BootCubeAnimationState();
}

class _BootCubeAnimationState extends State<BootCubeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
        final rotY = v * math.pi * 2.0 + (math.pi / 5.0);
        final rotX = (math.pi / 6.0) + math.sin(v * math.pi * 2.0) * 0.25;
        final rotZ = math.sin(v * math.pi * 2.0) * 0.1;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CustomPaint(
                        painter: Real3DCubePainter(
                          angleX: rotX,
                          angleY: rotY,
                          angleZ: rotZ,
                          cubeSize: 18.0,
                          primaryColor: const Color(0xFFFFD950),
                          darkColor: const Color(0xFFB8860B),
                          accentColor: const Color(0xFFFF7A00),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ShimmerBrandText(
                        shimmerProgress: v, textColor: textColor),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
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
