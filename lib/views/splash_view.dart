import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/routes.dart';
import '../core/constants.dart';
import '../services/hive_service.dart';
import '../controllers/settings_controller.dart';
import '../theme/design_tokens.dart';

/// Boot Animation Splash View supporting 'cube3d', 'liquid_wave'
/// and 'shimmer' selections.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  bool _isNavigating = false;
  String _bootAnimType = 'cube3d';

  @override
  void initState() {
    super.initState();
    try {
      if (Get.isRegistered<HiveService>()) {
        final hive = Get.find<HiveService>();
        _bootAnimType =
            hive.getSetting<String>(AppConstants.keyBootAnimation) ?? 'cube3d';
      }
    } catch (_) {}

    final durationMs = _bootAnimType == 'liquid_wave' ? 5800 : 2500;

    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _animCtrl.forward();

    _animCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNext();
      }
    });
  }

  void _navigateToNext() async {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;

    String next = AppRoutes.home;
    try {
      if (Get.isRegistered<HiveService>()) {
        final hive = Get.find<HiveService>();
        final done =
            hive.getSetting<bool>(AppConstants.keyOnboardingDone) ?? false;
        if (!done) next = AppRoutes.onboarding;
      }
    } catch (_) {}

    Get.offAllNamed(next);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F12) : Dt.canvas;

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _navigateToNext();
        },
        child: Center(
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, child) {
              final p = _animCtrl.value;

              if (_bootAnimType == 'liquid_wave') {
                return _LiquidWaveSplash(progress: p, isDark: isDark);
              } else if (_bootAnimType == 'shimmer') {
                return _ShimmerSplash(progress: p, isDark: isDark);
              } else {
                return _Cube3DSplash(progress: p, isDark: isDark);
              }
            },
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ANIMATION 1: 3D TECH CUBE (Default)
// ==========================================
class _Cube3DSplash extends StatelessWidget {
  final double progress;
  final bool isDark;

  const _Cube3DSplash({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final settings = Get.isRegistered<SettingsController>()
        ? Get.find<SettingsController>()
        : null;

    return Obx(() {
      final faceColors = settings?.cubeFaceColors ??
          [
            const Color(0xFFFF7A00),
            const Color(0xFFB8860B),
            const Color(0xFFFFD950),
            const Color(0xFF664A00),
            const Color(0xFFE8A317),
            const Color(0xFF7A5900),
          ];
      final textColor =
          settings?.cubeTextColor.value ?? (isDark ? Colors.white : Dt.textPrimary);
      final textFont = settings?.cubeTextFont.value ?? 'Plus Jakarta Sans';

      final rotY = (1.0 -
                  Curves.easeOutCubic.transform(
                      (progress / 0.75).clamp(0.0, 1.0))) *
              math.pi *
              2.0 +
          (math.pi / 5.0);
      final rotX = math.sin(progress * math.pi) * 0.35 + (math.pi / 6.0);
      final rotZ = math.sin(progress * math.pi * 0.5) * 0.15;

      final textP = ((progress - 0.25) / 0.40).clamp(0.0, 1.0);
      final textOpacity = Curves.easeOut.transform(textP);
      final textTx = _lerp(-20.0, 0.0, Curves.easeOutCubic.transform(textP));

      final shimmerP = ((progress - 0.45) / 0.50).clamp(0.0, 1.0);
      final subOpacity =
          Curves.easeOut.transform(((progress - 0.55) / 0.30).clamp(0.0, 1.0));

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(
                  painter: Real3DCubePainter(
                    angleX: rotX,
                    angleY: rotY,
                    angleZ: rotZ,
                    cubeSize: 22.0,
                    faceColors: faceColors,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Opacity(
                opacity: textOpacity,
                child: Transform.translate(
                  offset: Offset(textTx, 0),
                  child: CustomShimmerBrandText(
                    shimmerProgress: shimmerP,
                    textColor: textColor,
                    fontFamily: textFont,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: subOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Think • Create • Explore',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.2,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.5)
                        : Dt.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 44 *
                      Curves.easeOut.transform(
                          ((progress - 0.60) / 0.30).clamp(0.0, 1.0)),
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xFFFFD950),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);
}

class Real3DCubePainter extends CustomPainter {
  final double angleX;
  final double angleY;
  final double angleZ;
  final double cubeSize;
  final List<Color> faceColors;

  Real3DCubePainter({
    required this.angleX,
    required this.angleY,
    required this.angleZ,
    required this.cubeSize,
    required this.faceColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = cubeSize;

    final rawVertices = [
      [-s, -s, -s],
      [s, -s, -s],
      [s, s, -s],
      [-s, s, -s],
      [-s, -s, s],
      [s, -s, s],
      [s, s, s],
      [-s, s, s],
    ];

    final cosX = math.cos(angleX);
    final sinX = math.sin(angleX);
    final cosY = math.cos(angleY);
    final sinY = math.sin(angleY);
    final cosZ = math.cos(angleZ);
    final sinZ = math.sin(angleZ);

    final List<List<double>> rotated = [];
    final List<Offset> projected = [];

    for (final v in rawVertices) {
      final x = v[0];
      final y = v[1];
      final z = v[2];

      final x1 = x * cosY + z * sinY;
      final y1 = y;
      final z1 = -x * sinY + z * cosY;

      final x2 = x1;
      final y2 = y1 * cosX - z1 * sinX;
      final z2 = y1 * sinX + z1 * cosX;

      final x3 = x2 * cosZ - y2 * sinZ;
      final y3 = x2 * sinZ + y2 * cosZ;
      final z3 = z2;

      rotated.add([x3, y3, z3]);
      projected.add(Offset(cx + x3, cy + y3));
    }

    final c0 = faceColors.isNotEmpty ? faceColors[0] : const Color(0xFFFF7A00);
    final c1 = faceColors.length > 1 ? faceColors[1] : const Color(0xFFB8860B);
    final c2 = faceColors.length > 2 ? faceColors[2] : const Color(0xFFFFD950);
    final c3 = faceColors.length > 3 ? faceColors[3] : const Color(0xFF664A00);
    final c4 = faceColors.length > 4 ? faceColors[4] : const Color(0xFFE8A317);
    final c5 = faceColors.length > 5 ? faceColors[5] : const Color(0xFF7A5900);

    final faces = [
      _CubeFace(indices: [4, 5, 6, 7], color1: c0, color2: c0.withValues(alpha: 0.7)),
      _CubeFace(indices: [1, 0, 3, 2], color1: c1, color2: c1.withValues(alpha: 0.7)),
      _CubeFace(indices: [0, 1, 5, 4], color1: c2, color2: c2.withValues(alpha: 0.7)),
      _CubeFace(indices: [7, 6, 2, 3], color1: c3, color2: c3.withValues(alpha: 0.7)),
      _CubeFace(indices: [5, 1, 2, 6], color1: c4, color2: c4.withValues(alpha: 0.7)),
      _CubeFace(indices: [0, 4, 7, 3], color1: c5, color2: c5.withValues(alpha: 0.7)),
    ];

    for (final face in faces) {
      double sumZ = 0;
      for (final idx in face.indices) {
        sumZ += rotated[idx][2];
      }
      face.avgZ = sumZ / 4;
    }

    faces.sort((a, b) => a.avgZ.compareTo(b.avgZ));

    final strokePaint = Paint()
      ..color = const Color(0xFFFFF5CC).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final gridPaint = Paint()
      ..color = const Color(0xFFFFF5CC).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final auraPaint = Paint()
      ..color = c2.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(Offset(cx, cy), s * 1.4, auraPaint);

    for (final face in faces) {
      if (face.avgZ < -s * 0.1) continue;

      final p0 = projected[face.indices[0]];
      final p1 = projected[face.indices[1]];
      final p2 = projected[face.indices[2]];
      final p3 = projected[face.indices[3]];

      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [face.color1, face.color2],
        ).createShader(Rect.fromPoints(p0, p2));

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      for (int i = 1; i < 3; i++) {
        final frac = i / 3.0;
        final g1a = Offset.lerp(p0, p3, frac)!;
        final g1b = Offset.lerp(p1, p2, frac)!;
        canvas.drawLine(g1a, g1b, gridPaint);

        final g2a = Offset.lerp(p0, p1, frac)!;
        final g2b = Offset.lerp(p3, p2, frac)!;
        canvas.drawLine(g2a, g2b, gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant Real3DCubePainter oldDelegate) {
    return oldDelegate.angleX != angleX ||
        oldDelegate.angleY != angleY ||
        oldDelegate.angleZ != angleZ ||
        oldDelegate.cubeSize != cubeSize ||
        oldDelegate.faceColors != faceColors;
  }
}

class _CubeFace {
  final List<int> indices;
  final Color color1;
  final Color color2;
  double avgZ = 0.0;

  _CubeFace(
      {required this.indices, required this.color1, required this.color2});
}

class CustomShimmerBrandText extends StatelessWidget {
  final double shimmerProgress;
  final Color textColor;
  final String fontFamily;

  const CustomShimmerBrandText({
    super.key,
    required this.shimmerProgress,
    required this.textColor,
    this.fontFamily = 'Plus Jakarta Sans',
  });

  @override
  Widget build(BuildContext context) {
    final dx = -1.5 + 3.0 * shimmerProgress;

    return ShaderMask(
      shaderCallback: (bounds) {
        final base = textColor;
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            base,
            base,
            const Color(0xFFFFD950),
            Colors.white,
            const Color(0xFFFFD950),
            base,
            base,
          ],
          stops: [
            (dx - 0.35).clamp(0.0, 1.0),
            (dx - 0.20).clamp(0.0, 1.0),
            (dx - 0.08).clamp(0.0, 1.0),
            dx.clamp(0.0, 1.0),
            (dx + 0.08).clamp(0.0, 1.0),
            (dx + 0.20).clamp(0.0, 1.0),
            (dx + 0.28).clamp(0.0, 1.0),
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: Text(
        'CubicLM',
        style: GoogleFonts.getFont(
          fontFamily,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          height: 1.0,
          color: Colors.white,
        ),
      ),
    );
  }
}

// Backwards compatibility alias
typedef ShimmerBrandText = CustomShimmerBrandText;

// ==========================================
// ANIMATION 3: CUBICLM SHIMMER (logo + sweeping shimmer text)
// ==========================================
class _ShimmerSplash extends StatelessWidget {
  final double progress;
  final bool isDark;

  const _ShimmerSplash({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final logoIn =
        Curves.easeOutCubic.transform((progress / 0.25).clamp(0.0, 1.0));
    final tagIn = Curves.easeOut
        .transform(((progress - 0.70) / 0.20).clamp(0.0, 1.0));
    final textColor = isDark ? Colors.white : Dt.textPrimary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: logoIn,
          child: Transform.scale(
            scale: 0.8 + 0.2 * logoIn,
            child: Image.asset(
              'assets/icons/CubicLM.png',
              width: 96,
              height: 96,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ShimmerBrandText(
            shimmerProgress: progress, textColor: textColor),
        const SizedBox(height: 28),
        Opacity(
          opacity: tagIn,
          child: Text(
            'Think • Create • Explore',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.0,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : Dt.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// ANIMATION 2: LIQUID WAVE DOT
// ==========================================
class _LiquidWaveSplash extends StatelessWidget {
  final double progress;
  final bool isDark;

  const _LiquidWaveSplash({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Dt.textPrimary;
    const textStr = 'CubicLM';
    const charCount = textStr.length;

    final dotState = _calculateDotState(progress);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFFD950)
                          .withValues(alpha: isDark ? 0.08 : 0.12),
                      Colors.transparent,
                    ],
                    radius: 1.2,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: List.generate(charCount, (index) {
                final char = textStr[index];
                final distPercent = 1.0 - (index / (charCount - 1));

                final textInDelay = 0.20 + (0.12 * (1.0 - distPercent));
                const textInDuration = 0.12;

                double charOpacity = 0.0;
                double charScale = 0.0;
                double translateX = 0.0;
                double translateY = 0.0;
                double scaleY = 1.0;

                if (progress >= textInDelay) {
                  final rawCp = ((progress - textInDelay) / textInDuration)
                      .clamp(0.0, 1.0);
                  final cp = Curves.easeOutCubic.transform(rawCp);
                  charOpacity = cp;
                  if (rawCp < 0.85) {
                    charScale = _lerp(0.0, 1.12, rawCp / 0.85);
                  } else {
                    charScale = _lerp(1.12, 1.0, (rawCp - 0.85) / 0.15);
                  }
                  translateX = _lerp(-20.0, 0.0, cp);
                }

                if (char.toLowerCase() == 'i' &&
                    progress >= 0.46 &&
                    progress <= 0.54) {
                  final sp = ((progress - 0.46) / 0.08).clamp(0.0, 1.0);
                  if (sp <= 0.5) {
                    final t = Curves.easeOutQuad.transform(sp / 0.5);
                    scaleY = _lerp(1.0, 0.55, t);
                    translateY = _lerp(0.0, 5.0, t);
                  } else {
                    final t = Curves.easeInQuad.transform((sp - 0.5) / 0.5);
                    scaleY = _lerp(0.55, 1.0, t);
                    translateY = _lerp(5.0, 0.0, t);
                  }
                }

                if (index == charCount - 1 &&
                    progress >= 0.80 &&
                    progress <= 0.88) {
                  final bp = ((progress - 0.80) / 0.08).clamp(0.0, 1.0);
                  if (bp <= 0.35) {
                    final t = Curves.easeOutQuad.transform(bp / 0.35);
                    translateX += _lerp(0.0, -12.0, t);
                  } else {
                    final t = Curves.elasticOut.transform((bp - 0.35) / 0.65);
                    translateX += _lerp(-12.0, 0.0, t);
                  }
                }

                return Opacity(
                  opacity: charOpacity,
                  child: Transform.translate(
                    offset: Offset(translateX, translateY),
                    child: Transform.scale(
                      scale: charScale,
                      child: Transform(
                        transform: Matrix4.diagonal3Values(1.0, scaleY, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          char,
                          style: GoogleFonts.heebo(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            height: 1.0,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned(
              child: Transform.translate(
                offset: Offset(dotState.translateX, dotState.translateY),
                child: Opacity(
                  opacity: dotState.opacity,
                  child: Transform.scale(
                    scale: dotState.scale,
                    child: Transform(
                      transform: Matrix4.diagonal3Values(
                        dotState.scaleX,
                        dotState.scaleY,
                        1.0,
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 26,
                        height: 26,
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
                              waveProgress: dotState.waveProgress,
                              animValue: progress,
                              foregroundColor: const Color(0xFFFFD950),
                              backgroundColor: const Color(0xFF977A12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Opacity(
          opacity: Curves.easeOut.transform(
            ((progress - 0.70) / 0.20).clamp(0.0, 1.0),
          ),
          child: Text(
            'Think • Create • Explore',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.0,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : Dt.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }

  _DotState _calculateDotState(double p) {
    double opacity = 1.0;
    double scale = 1.0;
    double scaleX = 1.0;
    double scaleY = 1.0;
    double translateY = 0.0;
    double translateX = 0.0;

    if (p < 0.10) {
      opacity = Curves.easeOut.transform((p / 0.10).clamp(0.0, 1.0));
      scale = 3.0;
    }

    final waveProgress = (p / 0.28).clamp(0.0, 1.0);

    if (p < 0.50) {
      translateX = 0.0;
    } else if (p < 0.78) {
      final t = Curves.easeInOutCubic.transform((p - 0.50) / 0.28);
      translateX = _lerp(0.0, 118.0, t);
    } else if (p < 0.85) {
      final t = Curves.easeOutQuad.transform((p - 0.78) / 0.07);
      translateX = _lerp(118.0, 92.0, t);
    } else if (p < 0.90) {
      final t = Curves.easeInOut.transform((p - 0.85) / 0.05);
      translateX = _lerp(92.0, 96.0, t);
    } else {
      translateX = 96.0;
    }

    if (p < 0.10) {
      translateY = 0.0;
      scale = 3.0;
    } else if (p < 0.16) {
      final t = Curves.easeOut.transform((p - 0.10) / 0.06);
      scale = _lerp(3.0, 1.0, t);
      translateY = _lerp(0.0, 12.0, t);
      scaleY = _lerp(1.0, 0.60, t);
      scaleX = _lerp(1.0, 1.45, t);
    } else if (p < 0.25) {
      final t = Curves.easeOutCubic.transform((p - 0.16) / 0.09);
      translateY = _lerp(12.0, -75.0, t);
      scaleY = _lerp(0.60, 1.30, t);
      scaleX = _lerp(1.45, 0.80, t);
    } else if (p < 0.35) {
      final t = Curves.easeInCubic.transform((p - 0.25) / 0.10);
      translateY = _lerp(-75.0, 18.0, t);
      scaleY = _lerp(1.30, 0.60, t);
      scaleX = _lerp(0.80, 1.40, t);
    } else if (p < 0.46) {
      final t = Curves.easeOutCubic.transform((p - 0.35) / 0.11);
      translateY = _lerp(18.0, -95.0, t);
      scaleY = _lerp(0.60, 1.25, t);
      scaleX = _lerp(1.40, 0.85, t);
    } else if (p < 0.58) {
      final t = Curves.easeInCubic.transform((p - 0.46) / 0.12);
      translateY = _lerp(-95.0, 18.0, t);
      scaleY = _lerp(1.25, 0.70, t);
      scaleX = _lerp(0.85, 1.30, t);
    } else if (p < 0.68) {
      final t = Curves.easeOutCubic.transform((p - 0.58) / 0.10);
      translateY = _lerp(18.0, -45.0, t);
      scaleY = _lerp(0.70, 1.10, t);
      scaleX = _lerp(1.30, 0.95, t);
    } else if (p < 0.76) {
      final t = Curves.easeInCubic.transform((p - 0.68) / 0.08);
      translateY = _lerp(-45.0, 18.0, t);
      scaleY = _lerp(1.10, 0.85, t);
      scaleX = _lerp(0.95, 1.15, t);
    } else {
      translateY = 18.0;
      scaleY = 1.0;
      scaleX = 1.0;
    }

    return _DotState(
      opacity: opacity,
      scale: scale,
      scaleX: scaleX,
      scaleY: scaleY,
      translateY: translateY,
      translateX: translateX,
      waveProgress: waveProgress,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);
}

class _DotState {
  final double opacity;
  final double scale;
  final double scaleX;
  final double scaleY;
  final double translateY;
  final double translateX;
  final double waveProgress;

  _DotState({
    required this.opacity,
    required this.scale,
    required this.scaleX,
    required this.scaleY,
    required this.translateY,
    required this.translateX,
    required this.waveProgress,
  });
}

class LiquidWavePainter extends CustomPainter {
  final double waveProgress;
  final double animValue;
  final Color foregroundColor;
  final Color backgroundColor;

  LiquidWavePainter({
    required this.waveProgress,
    required this.animValue,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = backgroundColor.withValues(alpha: 0.25),
    );

    final liquidLevel = h - (h * 0.72 * waveProgress.clamp(0.0, 1.0));
    final amplitude = h * 0.10;

    final bgPath = Path();
    bgPath.moveTo(0, liquidLevel);
    final bgPhase = animValue * 2 * math.pi * 2.5 + math.pi;

    for (double x = 0; x <= w; x += 2.0) {
      final y = liquidLevel +
          math.sin((x / w) * 2 * math.pi + bgPhase) * amplitude;
      bgPath.lineTo(x, y);
    }
    bgPath.lineTo(w, h);
    bgPath.lineTo(0, h);
    bgPath.close();

    canvas.drawPath(bgPath, Paint()..color = backgroundColor);

    final fgPath = Path();
    fgPath.moveTo(0, liquidLevel);
    final fgPhase = animValue * 2 * math.pi * 3.5;

    for (double x = 0; x <= w; x += 2.0) {
      final y = liquidLevel +
          math.sin((x / w) * 2 * math.pi + fgPhase) * amplitude;
      fgPath.lineTo(x, y);
    }
    fgPath.lineTo(w, h);
    fgPath.lineTo(0, h);
    fgPath.close();

    canvas.drawPath(fgPath, Paint()..color = foregroundColor);
  }

  @override
  bool shouldRepaint(covariant LiquidWavePainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
        oldDelegate.animValue != animValue ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
