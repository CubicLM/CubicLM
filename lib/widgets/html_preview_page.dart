import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/browser_controller.dart';
import '../core/colors.dart';
import '../services/app_log_service.dart';
import '../theme/design_tokens.dart';
import '../utils/export_file.dart';
import '../views/cubicweb/browser_view.dart';

/// Full-screen live preview for self-contained HTML documents ("build a
/// game in a single HTML file"). Opened as a new page from chat code
/// blocks and HTML artifacts. Renders the code in an InAppWebView with
/// JavaScript enabled, plus reload / save / open-externally / share.
class HtmlPreviewPage extends StatefulWidget {
  final String code;
  final String title;

  const HtmlPreviewPage({super.key, required this.code, this.title = ''});

  /// Filesystem-safe `.html` filename derived from a title.
  /// Pure — unit tested.
  static String fileNameFor(String title) {
    var slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) slug = 'preview';
    if (slug.length > 40) slug = slug.substring(0, 40);
    return '$slug.html';
  }

  @override
  State<HtmlPreviewPage> createState() => _HtmlPreviewPageState();
}

class _HtmlPreviewPageState extends State<HtmlPreviewPage> {
  InAppWebViewController? _webController;
  bool _loading = true;
  bool _showCode = false;
  bool _copiedCode = false;
  String? _loadError;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await _webController?.reload();
  }

  Future<File> _writeTempHtml() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/cubiclm_preview_$stamp.html');
    await file.writeAsString(widget.code, flush: true);
    return file;
  }

  Future<void> _saveHtml() async {
    try {
      await ExportFile.quickExport(
        text: widget.code,
        fileName: HtmlPreviewPage.fileNameFor(widget.title),
        mimeType: 'text/html',
        shareText: widget.title.isEmpty ? 'HTML file' : widget.title,
        category: 'chat',
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar('Save failed', '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _openInBrowser() async {
    // Second way: when the inline frame isn't enough, run the same file
    // in the full CubicWeb Browser engine (proper tab, full settings).
    try {
      final file = await _writeTempHtml();
      final url = 'file://${file.path}';
      final browser = Get.isRegistered<BrowserController>()
          ? Get.find<BrowserController>()
          : Get.put(BrowserController());
      final ok = browser.addTab(url: url);
      if (!ok) {
        if (mounted) {
          Get.snackbar('Tab limit',
              'Close a browser tab first (max ${BrowserController.maxTabs}).',
              snackPosition: SnackPosition.BOTTOM);
        }
        return;
      }
      Get.to(() => const BrowserView());
    } catch (e) {
      if (mounted) {
        Get.snackbar('Cannot open in browser', '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
      try {
        if (Get.isRegistered<AppLogService>()) {
          Get.find<AppLogService>().error('HTML preview → browser failed',
              details: e, category: LogCategory.chat);
        }
      } catch (_) {}
    }
  }

  Future<void> _openExternally() async {
    try {
      final file = await _writeTempHtml();
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && mounted) {
        Get.snackbar('Cannot open', result.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('Cannot open', '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copiedCode = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedCode = false);
    });
  }

  Future<void> _shareHtml() async {
    try {
      final file = await _writeTempHtml();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        subject: 'HTML preview',
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar('prompt_export_failed'.tr, '$e',
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF101014) : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text(
            widget.title.isEmpty ? 'preview_title'.tr : widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          if (_showCode)
            IconButton(
              tooltip: 'preview_copy_code'.tr,
              icon: Icon(
                _copiedCode ? Icons.check_rounded : Icons.copy_rounded,
                size: 22,
                color: _copiedCode ? AppColors.success : null,
              ),
              onPressed: _copyCode,
            )
          else ...[
            IconButton(
              tooltip: 'preview_reload'.tr,
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: _reload,
            ),
            IconButton(
              tooltip: 'Save .html file',
              icon: const Icon(Icons.save_outlined, size: 22),
              onPressed: _saveHtml,
            ),
            IconButton(
              tooltip: 'preview_open_external'.tr,
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: _openExternally,
            ),
            IconButton(
              tooltip: 'Open in Browser',
              icon: const Icon(Icons.language_rounded, size: 22),
              onPressed: _openInBrowser,
            ),
            IconButton(
              tooltip: 'preview_share'.tr,
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              onPressed: _shareHtml,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: Text('preview_tab_preview'.tr),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.code_rounded, size: 16),
                  label: Text('preview_tab_code'.tr),
                ),
              ],
              selected: {_showCode},
              onSelectionChanged: (s) =>
                  setState(() => _showCode = s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          if (_loadError != null && !_showCode)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _loadError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppColors.error),
              ),
            ),
          Expanded(
            child: _showCode ? _buildCodeTab(isDark) : _buildPreviewTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTab() {
    return Stack(
      children: [
        InAppWebView(
          initialData: InAppWebViewInitialData(
            // Real origin is required: without a baseUrl the document
            // loads with an opaque (about:blank) origin and ANY
            // localStorage/sessionStorage access throws
            // "SecurityError: Access is denied for this document"
            // (breaks AI games using high-scores, saves, settings).
            // https://localhost/ gives DOM storage a proper origin.
            baseUrl: WebUri('https://localhost/'),
            data: widget.code,
            mimeType: 'text/html',
            encoding: 'utf-8',
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            // Android WebViews disable DOM storage by default — without
            // this, localStorage is unavailable even with a valid origin.
            domStorageEnabled: true,
            supportZoom: true,
            transparentBackground: false,
          ),
          onWebViewCreated: (controller) => _webController = controller,
          onLoadStop: (_, __) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadError = null;
              });
            }
          },
          onReceivedError: (controller, request, error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadError =
                    '${'preview_load_failed'.tr}: ${error.description}';
              });
            }
            // No screenshots needed: page errors land in System Logs.
            try {
              if (Get.isRegistered<AppLogService>()) {
                Get.find<AppLogService>().error('HTML preview load failed',
                    details:
                        '${error.description} (${request.url})',
                    category: LogCategory.chat);
              }
            } catch (_) {}
          },
          onConsoleMessage: (_, consoleMessage) {
            // Surface JS errors without spamming: keep the latest one.
            final msg = consoleMessage.message;
            if (consoleMessage.messageLevel ==
                    ConsoleMessageLevel.ERROR &&
                msg.isNotEmpty &&
                mounted) {
              setState(() => _loadError = msg);
              try {
                if (Get.isRegistered<AppLogService>()) {
                  Get.find<AppLogService>().error('HTML preview JS error',
                      details: msg.length > 500
                          ? msg.substring(0, 500)
                          : msg,
                      category: LogCategory.chat);
                }
              } catch (_) {}
            }
          },
        ),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildCodeTab(bool isDark) {
    final chars = widget.code.length;
    final lines = widget.code.isEmpty ? 0 : '\n'.allMatches(widget.code).length + 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              '$lines lines · $chars chars',
              style: GoogleFonts.firaCode(
                fontSize: 10,
                color: isDark
                    ? const Color(0xFF6C7086)
                    : Dt.textSecondary,
              ),
            ),
          ),
          Expanded(
            // Vertical + horizontal scroll: minified single-line files
            // would otherwise clip or break text layout entirely
            // (blank code tab while preview renders fine).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.code,
                  style: GoogleFonts.firaCode(
                    fontSize: 12,
                    height: 1.6,
                    color: isDark ? const Color(0xFFCDD6F4) : Dt.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
