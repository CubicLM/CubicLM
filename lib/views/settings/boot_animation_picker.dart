import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../../core/routes.dart';
import 'boot_anims/boot_cube_animation.dart';
import 'boot_anims/boot_liquid_animation.dart';
import 'boot_anims/boot_shimmer_animation.dart';
import 'chat_anims/chat_cube_animation.dart';
import 'chat_anims/chat_liquid_animation.dart';
import 'chat_anims/chat_shimmer_animation.dart';

/// Animation picker — wallpaper-picker style gallery.
///
/// Both animations render live in phone frames and loop forever, so the
/// user can watch and judge which is more beautiful.
/// [mode] 'boot' picks the app boot animation (cube + liquid);
/// [mode] 'chat' picks the Chat empty-state branding (same two, plus
/// the current Shimmer name which stays available).
class BootAnimationPickerView extends StatelessWidget {
  final String mode;
  const BootAnimationPickerView({super.key, this.mode = 'boot'});

  bool get _isChat => mode == 'chat';

  String _name(String id) {
    switch (id) {
      case 'cube3d':
        return '3D Tech Cube';
      case 'liquid_wave':
        return 'Liquid Wave Dot';
      case 'shimmer':
      default:
        return 'CubicLM Shimmer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsController>();
    final ids = _isChat
        ? const ['shimmer', 'cube3d', 'liquid_wave']
        : const ['shimmer', 'cube3d', 'liquid_wave'];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isChat ? 'Chat animation' : 'Boot animation',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Obx(() {
            // Touch first: boot-mode text reads no observable otherwise
            // → GetX empty-scope error. Chat mode reads chatAnimation.
            final _ = _isChat
                ? settings.chatAnimation.value
                : settings.bootAnimation.value;
            return Text(
              _isChat
                  ? 'Changes the CubicLM animation on the Chat page (boot stays ${_name(settings.bootAnimation.value)}).'
                  : 'Watch them loop, then tap your favourite.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Theme.of(context).hintColor),
            );
          }),
          const SizedBox(height: 16),
          // Vertical 2-per-row grid (no more left-right swipe).
          // shrinkWrap + never-scroll: the outer ListView scrolls.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ids.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
              // Cell ≈ 173 wide → ~360 tall (frame + labels + btn).
              childAspectRatio: 0.48,
            ),
            itemBuilder: (context, i) {
              final id = ids[i];
              return _AnimFrame(
                id: id,
                title: _name(id),
                subtitle: _subtitle(id),
                preview:
                    _previewFor(context, id, _isChat),
              );
            },
          ),
        ],
      ),
    );
  }

  String _subtitle(String id) {
    switch (id) {
      case 'cube3d':
        return 'Holographic cube + glowing core';
      case 'liquid_wave':
        return 'Bouncing dot, sloshing liquid';
      case 'shimmer':
      default:
        return 'Logo + sweeping shimmer';
    }
  }

  /// Boot mode uses boot_* widgets, chat mode uses chat_* widgets —
  /// never shared across features, even though they look the same.
  Widget _previewFor(BuildContext context, String id, bool isChat) {
    if (isChat) {
      switch (id) {
        case 'cube3d':
          return const ChatCubeAnimation();
        case 'liquid_wave':
          return const ChatLiquidAnimation();
        case 'shimmer':
        default:
          // Frame is narrow; full shimmer is 44px text — scale to fit.
          return Builder(builder: (ctx) {
            final isDark =
                Theme.of(ctx).brightness == Brightness.dark;
            return Center(
              child: SizedBox(
                width: 190,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ChatShimmerAnimation(isDark: isDark),
                ),
              ),
            );
          });
      }
    }
    switch (id) {
      case 'liquid_wave':
        return const BootLiquidAnimation();
      case 'shimmer':
        return const BootShimmerAnimation();
      case 'cube3d':
      default:
        return const BootCubeAnimation();
    }
  }

}

/// One phone-frame card: looping preview + name + selected ring.
class _AnimFrame extends StatelessWidget {
  final String id;
  final String title;
  final String subtitle;
  final Widget preview;

  const _AnimFrame({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsController>();
    // Selection source depends on which picker opened this frame.
    final isChatPicker = _isChatPicker(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final frameBg = isDark ? const Color(0xFF0F0F12) : Dt.canvas;
    return Obx(() {
      final current = isChatPicker
          ? settings.chatAnimation.value
          : settings.bootAnimation.value;
      final selected = current == id;
      return GestureDetector(
        onTap: () {
          if (isChatPicker) {
            settings.setChatAnimation(id);
          } else {
            settings.setBootAnimation(id);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 280,
                  decoration: BoxDecoration(
                    color: frameBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected
                          ? Dt.accent
                          : Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.7),
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: preview,
                ),
                if (selected)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Dt.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.check,
                          size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w800)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: Theme.of(context).hintColor)),
            if (id == 'cube3d') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.cubeEditor),
                  icon: const Icon(LucideIcons.sliders, size: 13),
                  label: const Text('Customize 3D Cube'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// Finds the enclosing picker's mode via the ancestor widget.
  bool _isChatPicker(BuildContext context) {
    final picker =
        context.findAncestorWidgetOfExactType<BootAnimationPickerView>();
    return picker != null && picker.mode == 'chat';
  }
}
