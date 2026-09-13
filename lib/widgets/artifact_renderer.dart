import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../services/code_interpreter_service.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/prompt_export.dart';

class ArtifactRenderer extends StatefulWidget {
  final String id;
  final List<Map<String, String>> versions;
  final VoidCallback onClose;

  const ArtifactRenderer({
    super.key,
    required this.id,
    required this.versions,
    required this.onClose,
  });

  @override
  State<ArtifactRenderer> createState() => _ArtifactRendererState();
}

class _ArtifactRendererState extends State<ArtifactRenderer> {
  late int _currentIndex;
  bool _isEditing = false;
  bool _isRunning = false;
  bool _showPreview = true;
  late TextEditingController _editController;
  String _consoleOutput = '';

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.versions.length - 1;
    _editController = TextEditingController(text: widget.versions[_currentIndex]['content']);
    
    // Auto-switch to code for non-previewable types
    final type = widget.versions[_currentIndex]['type'];
    if (type == 'code' || type == 'text') {
      _showPreview = false;
    }
  }

  @override
  void didUpdateWidget(covariant ArtifactRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.versions.length != oldWidget.versions.length) {
      _currentIndex = widget.versions.length - 1;
      if (!_isEditing) {
        _editController.text = widget.versions[_currentIndex]['content'] ?? '';
      }
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _save() {
    Get.find<ChatController>().updateArtifact(widget.id, _editController.text);
    setState(() => _isEditing = false);
  }

  void _runCode() async {
    final code = _editController.text;
    setState(() {
      _isRunning = true;
      _consoleOutput = '';
    });

    try {
      final interpreter = Get.find<CodeInterpreterService>();
      final result = await interpreter.executeJs(code);
      setState(() => _consoleOutput = result);
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = widget.versions[_currentIndex];
    final type = current['type'];
    final title = current['title'] ?? 'Artifact';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Dt.canvasDark : Dt.canvas,
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _header(context, isDark, title, type),
          if (!_isEditing) _tabBar(isDark, type),
          if (widget.versions.length > 1) _historyBar(isDark),
          Expanded(child: _isEditing ? _editor(isDark) : _body(context, isDark, current['content'] ?? '', type)),
        ],
      ),
    );
  }

  Widget _tabBar(bool isDark, String? type) {
    final canPreview = type == 'html' || type == 'mermaid' || type == 'csv' || type == 'table' || type == 'javascript' || type == 'js';
    if (!canPreview) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Center(
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Preview'), icon: Icon(LucideIcons.eye, size: 14)),
            ButtonSegment(value: false, label: Text('Code'), icon: Icon(LucideIcons.code, size: 14)),
          ],
          selected: {_showPreview},
          onSelectionChanged: (s) => setState(() => _showPreview = s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool isDark, String content, String? type) {
    if (!_showPreview) return _content(context, isDark, content, type);

    switch (type) {
      case 'html':
        return _htmlPreview(content);
      case 'mermaid':
        return _mermaidPreview(content, isDark);
      case 'csv':
      case 'table':
        return _tablePreview(content, isDark);
      case 'javascript':
      case 'js':
        return _jsConsolePreview(content, isDark);
      default:
        return _content(context, isDark, content, type);
    }
  }

  Widget _htmlPreview(String content) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: content,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: true,
        javaScriptEnabled: true,
      ),
    );
  }

  Widget _mermaidPreview(String content, bool isDark) {
    final html = """
      <!DOCTYPE html>
      <html>
      <head>
        <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
        <style>
          body { background: transparent; display: flex; justify-content: center; padding: 20px; }
          .mermaid { visibility: hidden; }
        </style>
      </head>
      <body>
        <div class="mermaid">
          $content
        </div>
        <script>
          mermaid.initialize({ startOnLoad: true, theme: '${isDark ? 'dark' : 'default'}' });
          window.addEventListener('load', () => {
            document.querySelector('.mermaid').style.visibility = 'visible';
          });
        </script>
      </body>
      </html>
    """;
    return InAppWebView(
      initialData: InAppWebViewInitialData(data: html),
      initialSettings: InAppWebViewSettings(transparentBackground: true, supportZoom: true),
    );
  }

  Widget _tablePreview(String content, bool isDark) {
    final lines = content.trim().split('\n');
    if (lines.isEmpty) return const Center(child: Text('Empty Table'));

    final rows = lines.map((l) => l.split(RegExp(r',|\|')).map((e) => e.trim()).toList()).toList();
    final header = rows.first;
    final data = rows.skip(1).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          columns: header.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
          rows: data.map((r) => DataRow(cells: r.map((c) => DataCell(Text(c))).toList())).toList(),
        ),
      ),
    );
  }

  Widget _jsConsolePreview(String content, bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(LucideIcons.terminal, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Interactive Console', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isRunning ? null : _runCode,
                icon: _isRunning ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.play, size: 14),
                label: const Text('Run'),
                style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.02),
            child: SelectableText(
              _consoleOutput.isEmpty ? '// Click "Run" to see output' : _consoleOutput,
              style: GoogleFonts.firaCode(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, bool isDark, String title, String? type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getIcon(type),
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(LucideIcons.save, size: 20, color: AppColors.success),
              onPressed: _save,
              tooltip: 'Save changes',
            )
          else ...[
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editController.text));
                Get.snackbar('Copied', 'Artifact content copied to clipboard', snackPosition: SnackPosition.BOTTOM);
              },
              tooltip: 'Copy content',
            ),
            IconButton(
              icon: const Icon(LucideIcons.download, size: 18),
              onPressed: () => PromptExport.shareAsMarkdown(_editController.text, baseName: title),
              tooltip: 'Download as Markdown',
            ),
            IconButton(
              icon: const Icon(LucideIcons.edit3, size: 18),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit artifact',
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _historyBar(bool isDark) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
      ),
      child: Row(
        children: [
          Text(
            'Version ${_currentIndex + 1} of ${widget.versions.length}',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Dt.textSecondary),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            onPressed: _currentIndex > 0 ? () => setState(() {
              _currentIndex--;
              _editController.text = widget.versions[_currentIndex]['content'] ?? '';
            }) : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, size: 16),
            onPressed: _currentIndex < widget.versions.length - 1 ? () => setState(() {
              _currentIndex++;
              _editController.text = widget.versions[_currentIndex]['content'] ?? '';
            }) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _editor(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _editController,
        maxLines: null,
        expands: true,
        style: GoogleFonts.firaCode(
          fontSize: 13,
          color: isDark ? AppColors.textPrimary : Dt.textPrimary,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Edit your content here...',
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool isDark, String content, String? type) {
    if (type == 'html') {
      return InAppWebView(
        initialData: InAppWebViewInitialData(
          data: content,
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: true,
        ),
      );
    }

    // Default to Markdown/Code view
    return Markdown(
      data: '```${type ?? ""}\n$content\n```',
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'html':
        return LucideIcons.layout;
      case 'code':
      case 'javascript':
      case 'js':
        return LucideIcons.code2;
      case 'mermaid':
        return LucideIcons.gitBranch;
      case 'csv':
      case 'table':
        return LucideIcons.table;
      default:
        return LucideIcons.fileText;
    }
  }
}
