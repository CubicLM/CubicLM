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

/// Typewriter greeting with fade in/out:
/// - Fades in and types out character by character slowly.
/// - Once the sentence completes, pauses briefly, then fades out.
/// - When a new sentence arrives, fades in and starts typing again.
/// - Text size remains consistent across all greetings (no auto-scaling down).
class TypedGreeting extends StatefulWidget {
  final List<String> lines;
  final TextStyle? style;
  final String debugLabel;

  const TypedGreeting(
      {super.key, required this.lines, this.style, this.debugLabel = ''});

  @override
  State<TypedGreeting> createState() => _TypedGreetingState();
}

class _TypedGreetingState extends State<TypedGreeting> {
  late final List<String> _frozen;
  int _lineIndex = 0;
  int _charIndex = 0;
  double _opacity = 0.0;
  Timer? _typingTimer;
  Timer? _delayTimer;
  int _fadeToken = 0;

  @override
  void initState() {
    super.initState();
    _frozen = List<String>.of(widget.lines);
    // ignore: avoid_print
    print(
        '[TypedGreeting] start segment=${widget.debugLabel} lines=${_frozen.length}');
    if (_frozen.isNotEmpty) {
      _startLine();
    }
  }

  void _startLine() {
    if (!mounted || _frozen.isEmpty) return;
    setState(() {
      _charIndex = 0;
      _opacity = 0.0;
    });

    final token = ++_fadeToken;
    _cancelAllTimers();

    // Fade in
    _delayTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || token != _fadeToken) return;
      setState(() {
        _opacity = 1.0;
      });

      // Start typing after fade-in initiates
      final text = _frozen[_lineIndex % _frozen.length];
      const typingSpeed = Duration(milliseconds: 75); // Slower typing speed

      _typingTimer = Timer.periodic(typingSpeed, (timer) {
        if (!mounted || token != _fadeToken) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_charIndex < text.length) {
            _charIndex++;
          } else {
            timer.cancel();
            _scheduleFadeOut(token);
          }
        });
      });
    });
  }

  void _scheduleFadeOut(int token) {
    // Hold fully visible for 2.2 seconds after typing completes
    _delayTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || token != _fadeToken) return;
      setState(() {
        _opacity = 0.0; // Fade out
      });

      // Wait for fade out duration (400ms) before switching to next line
      _delayTimer = Timer(const Duration(milliseconds: 420), () {
        if (!mounted || token != _fadeToken) return;
        setState(() {
          _lineIndex = (_lineIndex + 1) % _frozen.length;
        });
        _startLine();
      });
    });
  }

  void _cancelAllTimers() {
    _typingTimer?.cancel();
    _delayTimer?.cancel();
    _typingTimer = null;
    _delayTimer = null;
  }

  @override
  void dispose() {
    _fadeToken++;
    _cancelAllTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frozen.isEmpty) {
      return const SizedBox.shrink();
    }
    final text = _frozen[_lineIndex % _frozen.length];
    final displayedText =
        _charIndex <= text.length ? text.substring(0, _charIndex) : text;
    final color = Theme.of(context).colorScheme.onSurface;
    final style = (widget.style ?? GoogleFonts.plusJakartaSans(
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400), // Smooth fade in and out
      opacity: _opacity,
      child: Text(
        displayedText,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: color),
      ),
    );
  }
}
