/// CubicLM Live Preview — renders generated HTML/web content in a WebView.
///
/// Used in the agent workspace and CubicApp Builder to preview
/// generated web apps without leaving the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/preview_guard.dart';

/// Inline web preview panel for generated HTML/JS/CSS content.
///
/// Renders [htmlContent] inside a sandboxed InAppWebView.  Supports
/// hot-reload when [htmlContent] changes.
class LivePreview extends StatefulWidget {
  final String htmlContent;
  final String? title;
  final VoidCallback? onOpenExternal;

  const LivePreview({
    super.key,
    required this.htmlContent,
    this.title,
    this.onOpenExternal,
  });

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  InAppWebViewController? _controller;
  bool _loading = true;

  @override
  void didUpdateWidget(LivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.htmlContent != oldWidget.htmlContent) {
      _loadContent();
    }
  }

  void _loadContent() {
    if (_controller == null) return;
    _controller!.loadData(
      data: widget.htmlContent,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri('https://localhost'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.grey.withValues(alpha: 0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              // ignore: prefer_const_constructors — Dt.accent is runtime
              Icon(Icons.language_rounded,
                  size: 14, color: Dt.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title ?? 'Live Preview',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, size: 14),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _loadContent,
              ),
              if (widget.onOpenExternal != null)
                IconButton(
                  tooltip: 'Open in browser',
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onOpenExternal,
                ),
            ],
          ),
        ),
        // WebView
        Expanded(
          child: Stack(
            children: [
              InAppWebView(
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  supportZoom: false,
                  useWideViewPort: false,
                  loadWithOverviewMode: true,
                  transparentBackground: true,
                ),
                // Loopback-only navigation: external links open in the
                // system browser instead of inside the preview.
                shouldOverrideUrlLoading: (ctrl, action) async {
                  final url = action.request.url?.toString() ?? '';
                  if (isPreviewUrlAllowed(url)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  try {
                    widget.onOpenExternal?.call();
                  } catch (_) {}
                  AppSnackbar.showTop(
                    'External link blocked',
                    'Preview stays on localhost — opened externally.',
                  );
                  return NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (_, __) => setState(() => _loading = true),
                onLoadStop: (_, __) => setState(() => _loading = false),
                onWebViewCreated: (ctrl) {
                  _controller = ctrl;
                  _loadContent();
                },
              ),
              if (_loading)
                // ignore: prefer_const_constructors — Dt.accent is runtime
                Center(
                  // ignore: prefer_const_constructors — Dt.accent is runtime
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Dt.accent,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
