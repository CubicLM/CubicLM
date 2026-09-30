import 'package:flutter/material.dart';

import '../../chat/chat_widgets.dart';

/// CHAT animation: Shimmer name (the original Chat look, kept as an
/// option). Self-contained — not shared with the Boot animation.
/// Logo + looping shimmer app name, exactly as the Chat empty state
/// showed before this feature existed.
class ChatShimmerAnimation extends StatelessWidget {
  final bool isDark;
  const ChatShimmerAnimation({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icons/CubicLM.png',
          width: 64,
          height: 64,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        AnimatedAppName(isDark: isDark),
      ],
    );
  }
}
