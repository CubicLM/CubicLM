import 'dart:async';
import 'package:flutter/material.dart';

/// A widget that displays text with a "typewriter" effect when the text changes.
/// Useful for streaming AI responses.
class TypingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration speed;

  const TypingText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.speed = const Duration(milliseconds: 20),
  });

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText> {
  String _displayedText = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _displayedText = widget.text;
  }

  @override
  void didUpdateWidget(TypingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      if (widget.text.startsWith(oldWidget.text)) {
        // Text is being appended (streaming)
        _startTyping(oldWidget.text.length);
      } else {
        // Text changed completely
        _timer?.cancel();
        setState(() {
          _displayedText = widget.text;
        });
      }
    }
  }

  void _startTyping(int startFrom) {
    _timer?.cancel();
    _timer = Timer.periodic(widget.speed, (timer) {
      if (_displayedText.length < widget.text.length) {
        setState(() {
          _displayedText = widget.text.substring(0, _displayedText.length + 1);
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
