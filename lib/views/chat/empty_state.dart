import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../../utils/greetings.dart';
import 'chat_widgets.dart';

/// Empty state + suggestion cards.
/// Extracted from views/chat_view.dart.

ChatController get _c => Get.find<ChatController>();

Widget emptyState(BuildContext context, bool isDark) {
  final suggestions = [
    {
      'text': 'Explain quantum computing simply',
      'icon': Icons.auto_awesome_rounded,
      'color': Dt.chipAccent,
    },
    {
      'text': 'Write a short poem about time',
      'icon': Icons.edit_note_rounded,
      'color': Dt.chipLink,
    },
    {
      'text': 'What makes the Northern Lights happen?',
      'icon': Icons.light_mode_rounded,
      'color': Dt.chipSuccess,
    },
    {
      'text': 'Give me a 5-minute healthy breakfast recipe',
      'icon': Icons.restaurant_rounded,
      'color': Dt.chipWarm,
    },
  ];
  return Center(
      child: SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset(
        'assets/icons/CubicLM.png',
        width: 64,
        height: 64,
        fit: BoxFit.contain,
      ),
      const SizedBox(height: 16),
      AnimatedAppName(isDark: isDark),
      const SizedBox(height: 20),
      Obx(() {
        String name = '';
        try {
          name = Get.find<ProfileController>().name.value;
        } catch (_) {}
        final now = DateTime.now();
        final seg = segmentFor(now);
        final lines = greetingsNow(name, now);
        final label = seg.name;
        // Stable key per (name, segment): parent rebuilds must never
        // recreate this state, or the typewriter restarts every frame.
        final greetingStyle = GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: isDark ? AppColors.textPrimary : Dt.textPrimary);
        return TypedGreeting(
          key: ValueKey('$name-$label'),
          lines: lines,
          debugLabel: label,
          style: greetingStyle,
        );
      }),
      const SizedBox(height: 8),
      Text('chat_empty_subtitle'.tr,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: isDark ? AppColors.textSecondary : Dt.textSecondary,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 28),
      Obx(() {
        final settings = Get.find<SettingsController>();
        final models = Get.find<ModelController>();
        final isLocal = settings.inferenceMode.value == 'local';
        if (isLocal && models.downloadedCount == 0) {
          // Compact banner — same card language as suggestionCard
          // (paper surface, hairline border, icon chip) so it sits
          // quietly in the empty state instead of dominating it.
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.cloud_download_rounded,
                      color: AppColors.warning, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('chat_no_local_models_title'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface)),
                      const SizedBox(height: 4),
                      Text('chat_no_local_models_desc'.tr,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: Theme.of(context).hintColor,
                              height: 1.45)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () =>
                            Get.find<HomeController>().changeTab(1),
                        icon: const Icon(Icons.arrow_right_alt_rounded,
                            size: 16),
                        label: Text('chat_go_to_hub'.tr,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 600 ? (w >= 900 ? 4 : 3) : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                // Fixed dp height (not width-derived) so wrapped text on
                // narrow screens can never overflow the tile.
                mainAxisExtent: 136,
              ),
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) {
                final s = suggestions[i];
                return suggestionCard(context, s['text'] as String,
                    s['icon'] as IconData, s['color'] as Color, isDark);
              },
            );
          },
        );
      }),
    ]),
  ));
}

Widget suggestionCard(BuildContext context, String text, IconData icon,
    Color color, bool isDark) {
  return InkWell(
    onTap: () {
      _c.createNewChat();
      _c.textController.text = text;
      _c.inputText.value = text;
      _c.sendMessage();
    },
    borderRadius: BorderRadius.circular(24),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Text(text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}

/// Shine-sweep greeting (CodePen "CSS Text Animation" style): a bright
/// band sweeps across dim uppercase text on loop, and the greeting swaps
/// every few seconds with a fade. Single line only, no cursor. Lines are
/// frozen in initState so a mid-session rebuild can never mix segments.
class TypedGreeting extends StatefulWidget {
  final List<String> lines;
  final TextStyle? style;

  /// Forensic tag printed on init + each line switch (proves on-device
  /// which segment/lines are actually rendering).
  final String debugLabel;

  const TypedGreeting(
      {super.key, required this.lines, this.style, this.debugLabel = ''});

  @override
  State<TypedGreeting> createState() => _TypedGreetingState();
}

class _TypedGreetingState extends State<TypedGreeting>
    with SingleTickerProviderStateMixin {
  /// Matches the pen: 3s linear infinite sweep.
  static const _shineMs = 3000;

  /// How long each greeting stays before the fade-swap.
  static const _showMs = 4200;
  static const _fadeMs = 300;

  /// Band half-width as a fraction of the text width (pen: 80% size).
  static const _band = 0.28;

  late final List<String> _frozen;
  late final AnimationController _shine;
  Timer? _switchTimer;
  int _line = 0;
  double _opacity = 1.0;
  int _fadeToken = 0;

  @override
  void initState() {
    super.initState();
    _frozen = List<String>.of(widget.lines);
    // ignore: avoid_print
    print(
        '[GreetingV3] shine start segment=${widget.debugLabel} lines=${_frozen.length}');
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _shineMs),
    )..repeat();
    _switchTimer =
        Timer.periodic(const Duration(milliseconds: _showMs), (_) => _swap());
  }

  void _swap() {
    if (!mounted || _frozen.isEmpty) return;
    setState(() => _opacity = 0.0);
    final token = ++_fadeToken;
    Future.delayed(const Duration(milliseconds: _fadeMs), () {
      if (!mounted || token != _fadeToken) return;
      setState(() {
        _line = (_line + 1) % _frozen.length;
        _opacity = 1.0;
      });
      // ignore: avoid_print
      print('[GreetingV3] line=$_line: ${_frozen[_line]}');
    });
  }

  @override
  void dispose() {
    _fadeToken++; // invalidate pending fade callback
    _switchTimer?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final base = onSurface.withValues(alpha: 0.35);
    final shine = Theme.of(context).primaryColor;
    final raw = _frozen.isEmpty ? '' : _frozen[_line % _frozen.length];
    final style = (widget.style ?? const TextStyle())
        .copyWith(letterSpacing: 2.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: _fadeMs),
      opacity: _opacity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedBuilder(
          animation: _shine,
          builder: (_, __) {
            // Sweep position -0.4 → 1.4 (band fully off-screen at both
            // ends, like background-position -500% → 500%).
            final p = -0.4 + 1.8 * _shine.value;
            var s0 = (p - _band).clamp(0.0, 1.0);
            var s1 = p.clamp(0.0, 1.0);
            var s2 = (p + _band).clamp(0.0, 1.0);
            // Keep stops strictly increasing (clamping can equalize).
            if (s1 <= s0) s1 = (s0 + 0.002).clamp(0.0, 1.0);
            if (s2 <= s1) s2 = (s1 + 0.002).clamp(0.0, 1.0);
            if (s1 >= s2) s1 = (s2 - 0.002).clamp(0.0, 1.0);
            if (s0 >= s1) s0 = (s1 - 0.002).clamp(0.0, 1.0);
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, shine, base],
                stops: [s0, s1, s2],
              ).createShader(bounds),
              child: Text(
                raw.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );
          },
        ),
      ),
    );
  }
}
