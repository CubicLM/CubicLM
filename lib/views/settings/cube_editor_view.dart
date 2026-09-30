import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/colors.dart';

class CubeEditorView extends GetView<SettingsController> {
  const CubeEditorView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Customize 3D Cube & Text',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: isDark ? AppColors.textPrimary : Dt.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              controller.resetCubeColors();
              Get.snackbar('Reset', '3D Cube style restored to defaults',
                  snackPosition: SnackPosition.BOTTOM);
            },
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── LIVE PREVIEW CARD ──
          // Flat outer card; the preview itself sits in a fixed dark
          // well — white (or any) branding text stays visible, which
          // was impossible on the old white background.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Live Preview',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 12),
                // Frosted theme well (blurred, reduced corners): any
                // text color stays readable — fixed black hid black
                // text, fixed white hid white text. The preview text
                // also gets a contrast halo (see _haloFor).
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: 14, sigmaY: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .cardColor
                            .withValues(alpha: 0.55),
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Live Rotating 3D Cube
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: Obx(() {
                                  // Indexed reads register the
                                  // observables — passing the RxList
                                  // itself registers zero and GetX
                                  // throws improper-use. NOTE:
                                  // RxList.value is @protected.
                                  final faces = [
                                    controller.cubeFaceColors[0],
                                    controller.cubeFaceColors[1],
                                    controller.cubeFaceColors[2],
                                    controller.cubeFaceColors[3],
                                    controller.cubeFaceColors[4],
                                    controller.cubeFaceColors[5],
                                  ];
                                  return CustomPaint(
                                    painter: _Real3DCubePainter(
                                      angleX: math.pi / 6,
                                      angleY: math.pi / 4,
                                      angleZ: 0.0,
                                      cubeSize: 22.0,
                                      faceColors: faces,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(width: 16),
                              // Live Custom Text (+ contrast halo)
                              Obx(() {
                                final tc = controller
                                    .cubeTextColor.value;
                                return Text(
                                  'CubicLM',
                                  style: GoogleFonts.getFont(
                                    controller.cubeTextFont.value,
                                    fontSize: 42,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.5,
                                    height: 1.0,
                                    color: tc,
                                    shadows: [
                                      Shadow(
                                        color: _haloFor(tc),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Think • Create • Explore',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.0,
                              color:
                                  Theme.of(context).hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── PRESETS SECTION ──
          Text(
            'Quick Presets',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            // Obx: indexed reads keep it subscribed; the matching
            // preset gets tick + accent ring, so the current
            // selection is always visible.
            child: Obx(() {
              final cur = [
                controller.cubeFaceColors[0],
                controller.cubeFaceColors[1],
                controller.cubeFaceColors[2],
                controller.cubeFaceColors[3],
                controller.cubeFaceColors[4],
                controller.cubeFaceColors[5],
              ];
              final curText = controller.cubeTextColor.value;
              final defs = _presetDefs;
              var selected = -1;
              for (var i = 0; i < defs.length; i++) {
                if (curText == defs[i].textColor &&
                    _sameFaces(cur, defs[i].faces)) {
                  selected = i;
                  break;
                }
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: defs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 10),
                itemBuilder: (_, i) => _presetButton(
                  defs[i].label,
                  defs[i].faces,
                  defs[i].textColor,
                  i == selected,
                ),
              );
            }),
          ),
          const SizedBox(height: 28),

          // ── CUBE FACE COLORS ──
          Text(
            '3D Cube Face Colors',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 12),
          // Indexed reads keep this Obx subscribed (RxList.value
          // is @protected — [] is the legal tracked read).
          Obx(() => Column(
                children: [
                  _faceColorTile(0, 'Front Face', controller.cubeFaceColors[0]),
                  _faceColorTile(1, 'Back Face', controller.cubeFaceColors[1]),
                  _faceColorTile(2, 'Top Face', controller.cubeFaceColors[2]),
                  _faceColorTile(3, 'Bottom Face', controller.cubeFaceColors[3]),
                  _faceColorTile(4, 'Right Face', controller.cubeFaceColors[4]),
                  _faceColorTile(5, 'Left Face', controller.cubeFaceColors[5]),
                ],
              )),
          const SizedBox(height: 28),

          // ── TYPOGRAPHY & TEXT COLOR ──
          Text(
            'Branding Text Style',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              children: [
                // Text Color Picker Tile (Obx: the dot must update live)
                Obx(() => Row(
                      children: [
                        Text('Text Color',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _pickColor(
                              context,
                              controller.cubeTextColor.value,
                              (c) =>
                                  controller.setCubeTextColor(c)),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  controller.cubeTextColor.value,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.2),
                                    blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )),
                const Divider(height: 24),
                // Font Family Dropdown
                Row(
                  children: [
                    const Text('Font Style', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Obx(() => DropdownButton<String>(
                          value: controller.cubeTextFont.value,
                          dropdownColor: isDark ? const Color(0xFF262624) : Colors.white,
                          items: [
                            'Plus Jakarta Sans',
                            'Inter',
                            'Roboto',
                            'Outfit',
                            'Work Sans',
                            'Lexend',
                            'Montserrat',
                            'Poppins',
                          ].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                          onChanged: (val) {
                            if (val != null) controller.setCubeTextFont(val);
                          },
                        )),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Preset catalog (faces + text). A preset counts as selected only
  /// when all 6 faces AND the text color match the current state.
  List<_CubePreset> get _presetDefs => const [
        _CubePreset('CubicLM Original', [
          Color(0xFFFF7A00),
          Color(0xFFB8860B),
          Color(0xFFFFD950),
          Color(0xFF664A00),
          Color(0xFFE8A317),
          Color(0xFF7A5900),
        ], Colors.white),
        _CubePreset('Real 3D Cube', [
          Color(0xFFE63946),
          Color(0xFF1D3557),
          Color(0xFFFFB703),
          Color(0xFFF1FAEE),
          Color(0xFF2A9D8F),
          Color(0xFFFB8500),
        ], Color(0xFFFFB703)),
        _CubePreset('Rubik Classic', [
          Colors.red,
          Colors.blue,
          Colors.yellow,
          Colors.white,
          Colors.green,
          Colors.orange,
        ], Colors.yellow),
        _CubePreset('Cyberpunk Neon', [
          Color(0xFF00F0FF),
          Color(0xFFFF007F),
          Color(0xFF7000FF),
          Color(0xFF00FF66),
          Color(0xFFFF0055),
          Color(0xFF00FFFF),
        ], Color(0xFF00F0FF)),
        _CubePreset('Emerald Matrix', [
          Color(0xFF00FF87),
          Color(0xFF00853E),
          Color(0xFF60FFA0),
          Color(0xFF004D25),
          Color(0xFF10B981),
          Color(0xFF059669),
        ], Color(0xFF00FF87)),
      ];

  bool _sameFaces(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _presetButton(
      String label, List<Color> faces, Color textColor, bool selected) {
    final ctx = Get.context;
    final card = ctx != null ? Theme.of(ctx).cardColor : Colors.white;
    final onCard =
        ctx != null ? Theme.of(ctx).colorScheme.onSurface : Colors.black;
    final hairline = ctx != null
        ? Theme.of(ctx).dividerColor.withValues(alpha: 0.6)
        : Colors.grey;
    return ActionChip(
      avatar: selected
          ? const Icon(LucideIcons.check, size: 14, color: Dt.accent)
          : null,
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Dt.accent : onCard)),
      backgroundColor:
          selected ? Dt.accent.withValues(alpha: 0.12) : card,
      side: BorderSide(
          color: selected ? Dt.accent : hairline,
          width: selected ? 1.5 : 1),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: () {
        for (int i = 0; i < faces.length; i++) {
          controller.setCubeFaceColor(i, faces[i]);
        }
        controller.setCubeTextColor(textColor);
      },
    );
  }

  Widget _faceColorTile(int index, String title, Color color) {
    final ctx = Get.context;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ctx != null
            ? Theme.of(ctx).cardColor
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ctx != null
              ? Theme.of(ctx).dividerColor.withValues(alpha: 0.6)
              : Colors.grey,
        ),
      ),
      child: Row(
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const Spacer(),
          GestureDetector(
            onTap: () => _pickColor(Get.context!, color, (c) => controller.setCubeFaceColor(index, c)),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Contrast halo for the preview text: light text gets a dark halo,
  /// dark text a light one — readable on any frosted background.
  Color _haloFor(Color text) => text.computeLuminance() > 0.5
      ? Colors.black.withValues(alpha: 0.55)
      : Colors.white.withValues(alpha: 0.75);

  void _pickColor(BuildContext context, Color initialColor, ValueChanged<Color> onSelected) {
    final colors = [
      const Color(0xFFFFD950),
      const Color(0xFFFF7A00),
      const Color(0xFFB8860B),
      const Color(0xFFE8A317),
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.white,
      Colors.black,
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) => GestureDetector(
                onTap: () {
                  onSelected(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c,
                    border: Border.all(
                      color: initialColor == c ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                    ],
                  ),
                ),
              )).toList(),
        ),
      ),
    );
  }
}

/// Quick-preset definition: 6 face colors + branding text color.
class _CubePreset {
  final String label;
  final List<Color> faces;
  final Color textColor;
  const _CubePreset(this.label, this.faces, this.textColor);
}

/// Real 3D Cube Painter used in Editor and Splash View
class _Real3DCubePainter extends CustomPainter {
  final double angleX;
  final double angleY;
  final double angleZ;
  final double cubeSize;
  final List<Color> faceColors;

  _Real3DCubePainter({
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
      _CubeFace(indices: [4, 5, 6, 7], color1: c0, color2: c0.withValues(alpha: 0.7)), // Front
      _CubeFace(indices: [1, 0, 3, 2], color1: c1, color2: c1.withValues(alpha: 0.7)), // Back
      _CubeFace(indices: [0, 1, 5, 4], color1: c2, color2: c2.withValues(alpha: 0.7)), // Top
      _CubeFace(indices: [7, 6, 2, 3], color1: c3, color2: c3.withValues(alpha: 0.7)), // Bottom
      _CubeFace(indices: [5, 1, 2, 6], color1: c4, color2: c4.withValues(alpha: 0.7)), // Right
      _CubeFace(indices: [0, 4, 7, 3], color1: c5, color2: c5.withValues(alpha: 0.7)), // Left
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
  bool shouldRepaint(covariant _Real3DCubePainter oldDelegate) {
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
