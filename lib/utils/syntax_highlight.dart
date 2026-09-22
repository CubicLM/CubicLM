/// Lightweight regex-based syntax highlighter for multiple languages.
/// Returns a list of [SyntaxToken]s for rendering with RichText.
library;

import 'package:flutter/material.dart';

class SyntaxToken {
  final String text;
  final Color color;
  const SyntaxToken(this.text, this.color);
}

/// Theme-aware color palettes for syntax tokens.
class SyntaxColors {
  // Dark (Catppuccin-inspired on warm dark surfaces)
  static const keyword = Color(0xFFCBA6F7);
  static const string = Color(0xFFA6E3A1);
  static const comment = Color(0xFF6C7086);
  static const tag = Color(0xFFF38BA8);
  static const attr = Color(0xFFFAB387);
  static const number = Color(0xFFF9E2AF);
  static const punct = Color(0xFF89DCEB);
  static const plain = Color(0xFFCDD6F4);
  static const ghost = Color(0x66CDD6F4);

  // Light (parchment/paper)
  static const keywordLight = Color(0xFF7C3AED);
  static const stringLight = Color(0xFF15803D);
  static const commentLight = Color(0xFF6B7280);
  static const tagLight = Color(0xFFBE123C);
  static const attrLight = Color(0xFFC2410C);
  static const numberLight = Color(0xFFA16207);
  static const punctLight = Color(0xFF0E7490);
  static const plainLight = Color(0xFF2D2520);
  static const ghostLight = Color(0x662D2520);

  static const surfaceDark = Color(0xFF1E1E2E);
  static const surfaceLight = Color(0xFFF8F9FA);
}

/// Resolve palette for current brightness.
class SyntaxPalette {
  final bool isDark;
  const SyntaxPalette(this.isDark);

  Color get keyword => isDark ? SyntaxColors.keyword : SyntaxColors.keywordLight;
  Color get string => isDark ? SyntaxColors.string : SyntaxColors.stringLight;
  Color get comment => isDark ? SyntaxColors.comment : SyntaxColors.commentLight;
  Color get tag => isDark ? SyntaxColors.tag : SyntaxColors.tagLight;
  Color get attr => isDark ? SyntaxColors.attr : SyntaxColors.attrLight;
  Color get number => isDark ? SyntaxColors.number : SyntaxColors.numberLight;
  Color get punct => isDark ? SyntaxColors.punct : SyntaxColors.punctLight;
  Color get plain => isDark ? SyntaxColors.plain : SyntaxColors.plainLight;
  Color get ghost => isDark ? SyntaxColors.ghost : SyntaxColors.ghostLight;
  Color get surface =>
      isDark ? SyntaxColors.surfaceDark : SyntaxColors.surfaceLight;
}

/// Detect file type from path.
String detectLangFromPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.html') || p.endsWith('.htm')) return 'html';
  if (p.endsWith('.css')) return 'css';
  if (p.endsWith('.js') ||
      p.endsWith('.jsx') ||
      p.endsWith('.mjs') ||
      p.endsWith('.ts') ||
      p.endsWith('.tsx')) {
    return 'js';
  }
  if (p.endsWith('.dart')) return 'dart';
  if (p.endsWith('.py')) return 'python';
  if (p.endsWith('.json')) return 'json';
  if (p.endsWith('.xml') || p.endsWith('.svg')) return 'xml';
  if (p.endsWith('.md') || p.endsWith('.markdown')) return 'md';
  return 'text';
}

/// Tokenize source code into colored spans (theme-aware).
List<SyntaxToken> highlight(String source, String path, {bool isDark = true}) {
  final pal = SyntaxPalette(isDark);
  final lang = detectLangFromPath(path);
  switch (lang) {
    case 'html':
    case 'xml':
      return _highlightHtml(source, pal);
    case 'css':
      return _highlightCss(source, pal);
    case 'js':
    case 'dart':
    case 'python':
      return _highlightCode(source, lang, pal);
    case 'json':
      return _highlightJson(source, pal);
    default:
      return [SyntaxToken(source, pal.plain)];
  }
}

List<SyntaxToken> _highlightHtml(String src, SyntaxPalette pal) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'(<!--[\s\S]*?-->)'
    r'|(<[a-zA-Z][\w-]*)'
    r'|(<\/?[a-zA-Z][\w-]*>)'
    r'|(\s+[a-zA-Z][\w-]*=)'
    r'|("([^"\\]|\\.)*")'
    r"|('([^'\\]|\\.)*')"
    r'|(\s+)',
    caseSensitive: false,
  );

  var lastIndex = 0;
  for (final m in re.allMatches(src)) {
    if (m.start > lastIndex) {
      tokens.add(SyntaxToken(src.substring(lastIndex, m.start), pal.plain));
    }
    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, pal.comment));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, pal.tag));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, pal.tag));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, pal.attr));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, pal.string));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, pal.string));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(m.group(7)!, pal.plain));
    }
    lastIndex = m.end;
  }

  if (lastIndex < src.length) {
    tokens.add(SyntaxToken(src.substring(lastIndex), pal.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightCss(String src, SyntaxPalette pal) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'(\/\*[\s\S]*?\*\/)'
    r'|("(\\.|[^"\\])*")'
    r"|('(\\.|[^'\\])*')"
    r'|(\#[0-9a-fA-F]{3,8})'
    r'|(\.[a-zA-Z][\w-]*)'
    r'|(\#[a-zA-Z][\w-]*)'
    r'|(@[a-zA-Z]+)'
    r'|(:{1,2}[a-zA-Z][\w-]*)'
    r'|\b(\d+\.?\d*(px|em|rem|%|vh|vw|s|ms)?)\b'
    r'|([{}();:,])'
    r'|(\s+)',
    caseSensitive: false,
  );
  for (final m in re.allMatches(src)) {
    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, pal.comment));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, pal.string));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, pal.string));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, pal.number));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, pal.attr));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, pal.attr));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(m.group(7)!, pal.keyword));
    } else if (m.group(8) != null) {
      tokens.add(SyntaxToken(m.group(8)!, pal.keyword));
    } else if (m.group(9) != null) {
      tokens.add(SyntaxToken(m.group(9)!, pal.number));
    } else if (m.group(10) != null) {
      tokens.add(SyntaxToken(m.group(10)!, pal.punct));
    } else if (m.group(11) != null) {
      tokens.add(SyntaxToken(m.group(11)!, pal.plain));
    }
  }
  if (tokens.isEmpty) {
    tokens.add(SyntaxToken(src, pal.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightCode(String src, String lang, SyntaxPalette pal) {
  final tokens = <SyntaxToken>[];
  final String kwPattern;
  if (lang == 'js') {
    kwPattern = r'\b(const|let|var|function|return|if|else|for|while|do|switch|case|'
        r'break|continue|new|this|class|extends|import|export|from|default|'
        r'try|catch|finally|throw|async|await|yield|typeof|instanceof|in|of|'
        r'true|false|null|undefined|void|delete|super|static|get|set|window|document|console)\b';
  } else if (lang == 'dart') {
    kwPattern = r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|'
        r'covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|'
        r'external|factory|false|final|finally|for|Function|get|hide|if|implements|'
        r'import|in|interface|is|late|library|mixin|new|null|on|operator|part|'
        r'required|rethrow|return|set|show|static|super|switch|sync|this|throw|'
        r'true|try|typedef|var|void|while|with|yield)\b';
  } else if (lang == 'python') {
    kwPattern = r'\b(False|None|True|and|as|assert|async|await|break|class|continue|'
        r'def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|'
        r'nonlocal|not|or|pass|raise|return|try|while|with|yield)\b';
  } else {
    kwPattern = r'\b(if|else|return)\b';
  }

  final kw = RegExp(kwPattern);
  final re = RegExp(
    r'(\/\/[^\n]*)'
    r'|(\/\*[\s\S]*?\*\/)'
    r'|(\#[^\n]*)'
    r'|("(\\.|[^"\\])*")'
    r"|('(\\.|[^'\\])*')"
    r'|(`(\\.|[^`])*`)'
    r'|(\b\d+\.?\d*([eE][+-]?\d+)?\b)'
    r'|(\s*[a-zA-Z_$][\w$]*\s*:)'
    r'|([{}();:,.\[\]=+\-<>&|!?])'
    r'|(\s+)',
    caseSensitive: false,
  );

  var lastIndex = 0;
  for (final m in re.allMatches(src)) {
    if (m.start > lastIndex) {
      tokens.add(SyntaxToken(src.substring(lastIndex, m.start), pal.plain));
    }

    final fullMatch = m.group(0)!;
    if (m.group(1) != null || m.group(2) != null || m.group(3) != null) {
      tokens.add(SyntaxToken(fullMatch, pal.comment));
    } else if (m.group(4) != null || m.group(5) != null || m.group(6) != null) {
      tokens.add(SyntaxToken(fullMatch, pal.string));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(fullMatch, pal.number));
    } else {
      if (kw.hasMatch(fullMatch.trim())) {
        tokens.add(SyntaxToken(fullMatch, pal.keyword));
      } else if (m.group(8) != null) {
        tokens.add(SyntaxToken(fullMatch, pal.attr));
      } else if (m.group(9) != null) {
        tokens.add(SyntaxToken(fullMatch, pal.punct));
      } else {
        tokens.add(SyntaxToken(fullMatch, pal.plain));
      }
    }
    lastIndex = m.end;
  }

  if (lastIndex < src.length) {
    tokens.add(SyntaxToken(src.substring(lastIndex), pal.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightJson(String src, SyntaxPalette pal) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'("(\\.|[^"\\])*")\s*:'
    r'|("(\\.|[^"\\])*")'
    r'|\b(true|false|null)\b'
    r'|(-?\d+\.?\d*([eE][+-]?\d+)?)'
    r'|([{}[\]:,])'
    r'|(\s+)',
  );

  var lastIndex = 0;
  for (final m in re.allMatches(src)) {
    if (m.start > lastIndex) {
      tokens.add(SyntaxToken(src.substring(lastIndex, m.start), pal.plain));
    }

    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, pal.attr));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, pal.string));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, pal.keyword));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, pal.number));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, pal.punct));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, pal.plain));
    }
    lastIndex = m.end;
  }

  if (lastIndex < src.length) {
    tokens.add(SyntaxToken(src.substring(lastIndex), pal.plain));
  }
  return tokens;
}

/// Build a TextSpan tree from tokens for use with RichText.
TextSpan buildHighlightedSpan(List<SyntaxToken> tokens,
    {double fontSize = 12}) {
  return TextSpan(
    children: tokens
        .map((t) => TextSpan(
              text: t.text,
              style: TextStyle(
                color: t.color,
                fontFamily: 'FiraCode',
                fontSize: fontSize,
                height: 1.5,
              ),
            ))
        .toList(),
  );
}

/// A specialized controller that applies syntax highlighting as you type.
class SyntaxHighlightingController extends TextEditingController {
  final String path;
  final bool isDark;
  String? ghostText;

  SyntaxHighlightingController({
    super.text,
    required this.path,
    this.isDark = true,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final dark =
        isDark && (Theme.of(context).brightness == Brightness.dark || isDark);
    final tokens = highlight(text, path, isDark: dark);
    final baseSpan =
        buildHighlightedSpan(tokens, fontSize: style?.fontSize ?? 12);
    final pal = SyntaxPalette(dark);

    if (ghostText != null &&
        selection.isCollapsed &&
        selection.baseOffset == text.length) {
      return TextSpan(
        children: [
          baseSpan,
          TextSpan(
            text: ghostText,
            style: TextStyle(
              color: pal.ghost,
              fontFamily: 'FiraCode',
              fontSize: style?.fontSize ?? 12,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    return baseSpan;
  }
}
