import 'package:flutter/material.dart';

import '../../splash_view.dart';

/// BOOT animation: CubicLM Shimmer (picker frame size).
/// Self-contained loop — not shared with the Chat animation.
/// Logo + sweeping shimmer brand text.
class BootShimmerAnimation extends StatefulWidget {
  const BootShimmerAnimation({super.key});

  @override
  State<BootShimmerAnimation> createState() =>
      _BootShimmerAnimationState();
}

class _BootShimmerAnimationState extends State<BootShimmerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
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
    final textColor =
        isDark ? Colors.white : const Color(0xFF1C1C1E);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icons/CubicLM.png',
            width: 52,
            height: 52,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 190,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ShimmerBrandText(
                  shimmerProgress: _ctrl.value,
                  textColor: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
