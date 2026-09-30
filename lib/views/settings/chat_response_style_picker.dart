import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/settings_controller.dart';
import '../../core/constants.dart';
import '../../utils/sentence_splitter.dart';
import '../chat/chat_widgets.dart';

class ChatResponseStylePickerView extends StatelessWidget {
  const ChatResponseStylePickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final styles = [
      _StyleOption(
        id: AppConstants.responseStyleDefault,
        title: 'chat_resp_default'.tr,
        subtitle: 'chat_resp_default_desc'.tr,
        icon: LucideIcons.sparkles,
        isPrimary: true,
      ),
      _StyleOption(
        id: AppConstants.responseStyleBlurry,
        title: 'chat_resp_blurry'.tr,
        subtitle: 'chat_resp_blurry_desc'.tr,
        icon: LucideIcons.wand2,
      ),
      _StyleOption(
        id: AppConstants.responseStyleBlurryWord,
        title: 'chat_resp_blurry_word'.tr,
        subtitle: 'chat_resp_blurry_word_desc'.tr,
        icon: LucideIcons.type,
      ),
      _StyleOption(
        id: AppConstants.responseStyleInstant,
        title: 'chat_resp_instant'.tr,
        subtitle: 'chat_resp_instant_desc'.tr,
        icon: LucideIcons.zap,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('chat_response_style'.tr,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
      ),
      body: Obx(() {
        final currentStyle = controller.chatResponseStyle.value;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'chat_response_style_desc'.tr,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            ...styles.map((option) {
              final isSelected = currentStyle == option.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08)),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => controller.setChatResponseStyle(option.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha: 0.15)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.05)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                option.icon,
                                size: 20,
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Theme.of(context).iconTheme.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          option.title,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (option.isPrimary)
                                        Container(
                                          margin: const EdgeInsets.only(left: 6),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .primaryColor
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Primary',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    option.subtitle,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Active',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _LoopingResponsePreview(
                          styleId: option.id,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }
}

class _StyleOption {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPrimary;

  const _StyleOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isPrimary = false,
  });
}

/// Live looping animation preview box for a response style
class _LoopingResponsePreview extends StatefulWidget {
  final String styleId;
  final bool isDark;

  const _LoopingResponsePreview({
    required this.styleId,
    required this.isDark,
  });

  @override
  State<_LoopingResponsePreview> createState() =>
      _LoopingResponsePreviewState();
}

class _LoopingResponsePreviewState extends State<_LoopingResponsePreview> {
  static const String _sampleText =
      'CubicLM AI is generating your response. Each sentence is crafted with high intelligence. Experience seamless chat performance!';

  Timer? _timer;
  int _charIndex = 0;
  bool _isInstantThinking = true;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant _LoopingResponsePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.styleId != widget.styleId) {
      _restartAnimation();
    }
  }

  void _restartAnimation() {
    _timer?.cancel();
    _charIndex = 0;
    _isInstantThinking = true;
    _startAnimation();
  }

  void _startAnimation() {
    if (widget.styleId == AppConstants.responseStyleInstant) {
      _runInstantLoop();
    } else {
      _runStreamingLoop();
    }
  }

  void _runStreamingLoop() {
    _timer = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (!mounted) return;
      setState(() {
        if (_charIndex < _sampleText.length) {
          _charIndex++;
        } else {
          t.cancel();
          // Pause at full text, then restart
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _charIndex = 0;
              });
              _runStreamingLoop();
            }
          });
        }
      });
    });
  }

  void _runInstantLoop() {
    setState(() {
      _isInstantThinking = true;
    });
    // Show thinking indicator for 1.5 seconds, then full response for 2.5s
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _isInstantThinking = false;
      });
      _timer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        _runInstantLoop();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final bgBubble = widget.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgBubble,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.bot,
                  size: 13,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'CubicLM AI',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildContent(context, primaryColor),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color primaryColor) {
    if (widget.styleId == AppConstants.responseStyleInstant) {
      if (_isInstantThinking) {
        return Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Generating response...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        );
      }
      return Text(
        _sampleText,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          height: 1.45,
        ),
      );
    }

    final currentTyped = _sampleText.substring(0, _charIndex);

    if (widget.styleId == AppConstants.responseStyleBlurry) {
      final split = splitSentences(currentTyped);
      final completed = split.completedText;
      final inProgress = split.inProgressText;

      return RichText(
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.45,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          children: [
            if (completed.isNotEmpty) TextSpan(text: completed),
            if (inProgress.isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Text(
                    inProgress,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.45,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: BlinkingCursor(color: primaryColor),
            ),
          ],
        ),
      );
    }

    if (widget.styleId == AppConstants.responseStyleBlurryWord) {
      final split = splitWords(currentTyped);
      final completed = split.completedText;
      final inProgress = split.inProgressText;

      return RichText(
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.45,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          children: [
            if (completed.isNotEmpty) TextSpan(text: completed),
            if (inProgress.isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Text(
                    inProgress,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.45,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: BlinkingCursor(color: primaryColor),
            ),
          ],
        ),
      );
    }

    // Default Real-time stream
    return RichText(
      text: TextSpan(
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          height: 1.45,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
        children: [
          TextSpan(text: currentTyped),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: BlinkingCursor(color: primaryColor),
          ),
        ],
      ),
    );
  }
}
