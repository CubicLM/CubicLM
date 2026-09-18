import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../services/code_interpreter_service.dart';
import '../services/hive_service.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../utils/prompt_export.dart';
import 'html_preview_page.dart';

/// Claude-Canvas–style artifact renderer with split editor + live preview,
/// line numbers, "Ask AI" iteration, and persistent edits.
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
  bool _showDiff = false;
  bool _showChart = false;
  bool _showConsole = false;
  bool _ideMode = false;
  late TextEditingController _editController;
  String _consoleOutput = '';
  Timer? _debounce;
  InAppWebViewController? _webController;

  // For the "Ask AI" feature.
  bool _showAskAi = false;
  final _askAiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.versions.length - 1;
    _editController =
        TextEditingController(text: widget.versions[_currentIndex]['content']);
    _editController.addListener(() {
      if (mounted) setState(() {});
    });

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
    _askAiCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Save with Hive persistence ──────────────────────────

  void _save() async {
    final ctrl = Get.find<ChatController>();
    
    if (_ideMode && ctrl.activeProjectFile.value != null) {
      try {
        await File(ctrl.activeProjectFile.value!).writeAsString(_editController.text);
        setState(() => _isEditing = false);
        Get.snackbar('Saved', 'File updated on disk', snackPosition: SnackPosition.BOTTOM);
        return;
      } catch (e) {
        Get.snackbar('Save Error', e.toString());
      }
    }

    ctrl.updateArtifact(widget.id, _editController.text);

    setState(() => _isEditing = false);
    HapticFeedback.lightImpact();
    Get.snackbar('Saved', 'Artifact updated',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1));
  }

  // ── Ask AI to iterate ───────────────────────────────────

  void _submitAskAi() {
    final instruction = _askAiCtrl.text.trim();
    if (instruction.isEmpty) return;

    final type = widget.versions[_currentIndex]['type'] ?? 'code';
    final content = _editController.text;
    final prompt =
        'Here is the current artifact:\n```$type\n$content\n```\n\nPlease modify it: $instruction';

    // Insert into chat composer and send.
    final ctrl = Get.find<ChatController>();
    ctrl.textController.text = prompt;
    ctrl.inputText.value = prompt;
    ctrl.sendMessage();

    setState(() {
      _showAskAi = false;
      _askAiCtrl.clear();
    });
  }

  // ── JS execution ────────────────────────────────────────

  void _runCode() async {
    final code = _editController.text;
    setState(() {
      _isRunning = true;
      _consoleOutput = '';
      _showConsole = true;
    });

    try {
      final interpreter = Get.find<CodeInterpreterService>();
      final result = await interpreter.executeJs(code);
      setState(() => _consoleOutput = result);
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  // ── Debounced live preview update ───────────────────────

  void _onCodeChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !_isEditing) return;
      _refreshPreview(value);
    });
  }

  void _syncToDisk() async {
    final ctrl = Get.find<ChatController>();
    final current = widget.versions[_currentIndex];
    final title = current['title'] ?? 'artifact.txt';
    final content = _editController.text;

    final projectId = ctrl.currentProjectId.value;
    if (projectId == null) {
      Get.snackbar('Project Required', 'Please select or create a project first.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final project = ctrl.projects.firstWhereOrNull((p) => p.id == projectId);
    if (project == null) return;

    String? root = project.rootPath;

    if (root == null || root.isEmpty) {
      // Pick folder if not set
      final selected = await Get.find<ChatController>().pickProjectRoot(project);
      if (selected == null) return;
      root = selected;
    }

    try {
      final fileName = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final file = File('$root${Platform.pathSeparator}$fileName');
      await file.writeAsString(content);
      
      Get.snackbar('Synced', 'Saved to $root',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.success.withValues(alpha: 0.9),
          colorText: Colors.white);
      
      // Update project file list if new
      if (!project.filePaths.contains(file.path)) {
         final updated = project.copyWith(filePaths: [...project.filePaths, file.path]);
         ctrl.projects[ctrl.projects.indexOf(project)] = updated;
         Get.find<HiveService>().saveProject(project.id, updated.toMap());
         ctrl.invalidateProjectCache(project.id);
      }
    } catch (e) {
      Get.snackbar('Sync Failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.error.withValues(alpha: 0.9));
    }
  }

  void _refreshPreview(String content) {
    if (_webController == null) return;
    final type = widget.versions[_currentIndex]['type'];
    if (type == 'html') {
      _webController!.loadData(
          data: content,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: WebUri('https://localhost/'));
    } else if (type == 'mermaid') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      _webController!
          .loadData(data: _mermaidHtml(content, isDark), mimeType: 'text/html');
    }
  }

  // ── Build ───────────────────────────────────────────────

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
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _header(context, isDark, title, type),
          if (!_isEditing) _tabBar(isDark, type),
          if (widget.versions.length > 1) _historyBar(isDark),
          // Main content area.
          Expanded(
            child: _ideMode 
                ? _ideLayout(context, isDark)
                : (_isEditing
                    ? _editingLayout(
                        context, isDark, current['content'] ?? '', type)
                    : _body(context, isDark, current['content'] ?? '', type)),
          ),
          // Console panel.
          if (_showConsole && _consoleOutput.isNotEmpty) _consolePanel(isDark),
          // Ask AI overlay.
          if (_showAskAi) _askAiBar(isDark),
        ],
      ),
    );
  }

  Widget _ideLayout(BuildContext context, bool isDark) {
    final ctrl = Get.find<ChatController>();
    final projectId = ctrl.currentProjectId.value;
    final project = ctrl.projects.firstWhereOrNull((p) => p.id == projectId);
    
    return Row(
      children: [
        // File Tree Sidebar
        Container(
          width: 200,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1))),
          ),
          child: project == null || project.filePaths.isEmpty
              ? const Center(child: Text('No files', style: TextStyle(fontSize: 10)))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: project.filePaths.map((path) {
                    final name = path.split(Platform.pathSeparator).last;
                    final active = ctrl.activeProjectFile.value == path;
                    return ListTile(
                      dense: true,
                      selected: active,
                      selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                      leading: Icon(LucideIcons.fileCode, size: 14, color: active ? AppColors.primary : Dt.textSecondary),
                      title: Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                      onTap: () async {
                        try {
                          final content = await File(path).readAsString();
                          setState(() {
                            ctrl.activeProjectFile.value = path;
                            _editController.text = content;
                            _isEditing = false;
                            _showPreview = false;
                          });
                        } catch (e) {
                          Get.snackbar('Error', 'Could not read file: $e');
                        }
                      },
                    );
                  }).toList(),
                ),
        ),
        // Editor/Preview Area
        Expanded(
          child: Column(
            children: [
              if (ctrl.activeProjectFile.value == null)
                const Expanded(child: Center(child: Text('Select a file to edit')))
              else ...[
                _tabBar(isDark, ctrl.activeProjectFile.value?.split('.').last),
                Expanded(
                  child: _isEditing
                      ? _editingLayout(context, isDark, _editController.text, ctrl.activeProjectFile.value?.split('.').last)
                      : _body(context, isDark, _editController.text, ctrl.activeProjectFile.value?.split('.').last),
                ),
              ]
            ],
          ),
        ),
      ],
    );
  }

  // ── Split Editor + Live Preview Layout ──────────────────

  Widget _editingLayout(
      BuildContext context, bool isDark, String content, String? type) {
    final canPreview = type == 'html' || type == 'mermaid';
    String editorPref = 'split';
    try {
      if (Get.isRegistered<SettingsController>()) {
        editorPref = Get.find<SettingsController>().codeEditorType.value;
      }
    } catch (_) {}

    return LayoutBuilder(builder: (ctx, constraints) {
      // Wide screens: side-by-side editor + preview if preferred and previewable.
      if (editorPref == 'split' && canPreview && constraints.maxWidth > 600) {
        return Row(
          children: [
            Expanded(child: _editorWithLineNumbers(isDark)),
            VerticalDivider(
                width: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
            Expanded(child: _livePreview(isDark, type)),
          ],
        );
      }
      // Narrow, plain preference, or non-previewable: editor only.
      return _editorWithLineNumbers(isDark);
    });
  }

  Widget _livePreview(bool isDark, String? type) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.02),
            border: Border(
              bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.eye, size: 13, color: Dt.textSecondary),
              const SizedBox(width: 6),
              Text('Live Preview',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Dt.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialData: InAppWebViewInitialData(
              data: type == 'mermaid'
                  ? _mermaidHtml(_editController.text, isDark)
                  : _editController.text,
              mimeType: 'text/html',
              encoding: 'utf-8',
            ),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              supportZoom: true,
              javaScriptEnabled: true,
            ),
            onWebViewCreated: (ctrl) => _webController = ctrl,
            onConsoleMessage: (ctrl, msg) {
              if (mounted) {
                setState(() {
                  _consoleOutput += '${msg.message}\n';
                  _showConsole = true;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Editor with Line Numbers ────────────────────────────

  Widget _editorWithLineNumbers(bool isDark) {
    return Column(
      children: [
        // Editor toolbar.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.02),
            border: Border(
              bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.code2, size: 13, color: Dt.textSecondary),
              const SizedBox(width: 6),
              Text('Editor',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Dt.textSecondary)),
              const Spacer(),
              // Bracket auto-close hint.
              Text('Auto-close: () {} [] <>',
                  style: GoogleFonts.firaCode(
                      fontSize: 9, color: Dt.textSecondary)),
            ],
          ),
        ),
        // Editor body with line numbers.
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line number gutter.
              _LineNumberGutter(
                controller: _editController,
                isDark: isDark,
              ),
              // Vertical separator.
              Container(
                width: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
              ),
              // Code editor.
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    controller: _editController,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    onChanged: _onCodeChanged,
                    style: GoogleFonts.firaCode(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Edit your code here...',
                      isCollapsed: true,
                    ),
                    inputFormatters: [_BracketAutoCloseFormatter()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Console Panel ───────────────────────────────────────

  Widget _consolePanel(bool isDark) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.black.withValues(alpha: 0.03),
        border: Border(
          top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal,
                    size: 13, color: Dt.textSecondary),
                const SizedBox(width: 6),
                Text('Console',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Dt.textSecondary)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showConsole = false),
                  child: const Icon(LucideIcons.x,
                      size: 14, color: Dt.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SelectableText(
                _consoleOutput,
                style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ask AI Bar ──────────────────────────────────────────

  Widget _askAiBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _askAiCtrl,
              autofocus: true,
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'What should I change?',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: Dt.textSecondary),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (_) => _submitAskAi(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _showAskAi = false;
              _askAiCtrl.clear();
            }),
          ),
          IconButton(
            icon: const Icon(LucideIcons.send,
                size: 16, color: AppColors.primary),
            visualDensity: VisualDensity.compact,
            onPressed: _submitAskAi,
          ),
        ],
      ),
    );
  }

  /// Opens the current HTML artifact in a full page (same renderer as
  /// chat code-block previews, with reload / save / share).
  void _openFullPreview(String title) {
    try {
      final code = _editController.text;
      if (code.trim().isEmpty) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => HtmlPreviewPage(code: code, title: title),
        ),
      );
    } catch (e) {
      Get.snackbar('Preview unavailable', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _tabBar(bool isDark, String? type) {
    final canPreview = type == 'html' ||
        type == 'mermaid' ||
        type == 'csv' ||
        type == 'table' ||
        type == 'javascript' ||
        type == 'js';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [
              if (canPreview)
                const ButtonSegment(
                    value: 'preview',
                    label: Text('Preview'),
                    icon: Icon(LucideIcons.eye, size: 14)),
              const ButtonSegment(
                  value: 'code',
                  label: Text('Code'),
                  icon: Icon(LucideIcons.code, size: 14)),
              if (widget.versions.length > 1)
                const ButtonSegment(
                    value: 'diff',
                    label: Text('Diff'),
                    icon: Icon(LucideIcons.diff, size: 14)),
              if (type == 'csv' || type == 'table')
                const ButtonSegment(
                    value: 'chart',
                    label: Text('Chart'),
                    icon: Icon(LucideIcons.barChart, size: 14)),
            ],
            selected: {
              _showChart
                  ? 'chart'
                  : (_showDiff ? 'diff' : (_showPreview ? 'preview' : 'code'))
            },
            onSelectionChanged: (s) => setState(() {
              final val = s.first;
              _showDiff = val == 'diff';
              _showChart = val == 'chart';
              _showPreview = val == 'preview';
            }),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, bool isDark, String content, String? type) {
    if (_showChart) return _chartPreview(content, isDark);
    if (_showDiff) return _diffView(isDark);
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

  Widget _chartPreview(String content, bool isDark) {
    final chartHtml = '''
      <!DOCTYPE html>
      <html>
      <head>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <style>
          body { background: transparent; padding: 20px; font-family: sans-serif; }
          #container { width: 100%; height: 400px; }
        </style>
      </head>
      <body>
        <div id="container"><canvas id="canvas"></canvas></div>
        <script>
          try {
            const raw = `${content.replaceAll('`', '\\`')}`;
            const lines = raw.trim().split('\\n');
            const labels = lines[0].split(/[|,]/).map(s => s.trim());
            const dataPoints = lines.slice(1).map(l => l.split(/[|,]/).map(s => s.trim()));
            
            const datasets = labels.slice(1).map((label, i) => ({
              label: label,
              data: dataPoints.map(row => parseFloat(row[i+1]) || 0),
              borderColor: ['#3B82F6', '#10B981', '#F59E0B', '#EF4444'][i % 4],
              backgroundColor: ['#3B82F622', '#10B98122', '#F59E0B22', '#EF444422'][i % 4],
              tension: 0.3
            }));

            new Chart(document.getElementById('canvas'), {
              type: 'line',
              data: {
                labels: dataPoints.map(row => row[0]),
                datasets: datasets
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                  legend: { labels: { color: '${isDark ? "#ffffff" : "#000000"}' } }
                },
                scales: {
                  y: { grid: { color: '${isDark ? "#ffffff11" : "#00000011"}' }, ticks: { color: '${isDark ? "#ffffff88" : "#00000088"}' } },
                  x: { grid: { color: '${isDark ? "#ffffff11" : "#00000011"}' }, ticks: { color: '${isDark ? "#ffffff88" : "#00000088"}' } }
                }
              }
            });
          } catch(e) {
            document.body.innerHTML = '<div style="color:red">Error parsing data for chart: ' + e.message + '</div>';
          }
        </script>
      </body>
      </html>
    ''';

    return InAppWebView(
      initialData: InAppWebViewInitialData(data: chartHtml),
      initialSettings: InAppWebViewSettings(transparentBackground: true),
    );
  }

  Widget _diffView(bool isDark) {
    if (_currentIndex == 0) {
      return const Center(child: Text('No previous version to compare.'));
    }
    final oldText = widget.versions[_currentIndex - 1]['content'] ?? '';
    final newText = widget.versions[_currentIndex]['content'] ?? '';

    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');

    return Container(
      color: isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF9F9F9),
      child: ListView.builder(
        itemCount: max(oldLines.length, newLines.length),
        itemBuilder: (context, i) {
          final o = i < oldLines.length ? oldLines[i] : null;
          final n = i < newLines.length ? newLines[i] : null;

          if (o == n) {
            return _diffLine(i + 1, n ?? '', Colors.transparent, isDark);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (o != null)
                _diffLine(i + 1, o, Colors.red.withValues(alpha: 0.15), isDark,
                    prefix: '-'),
              if (n != null)
                _diffLine(i + 1, n, Colors.green.withValues(alpha: 0.15), isDark,
                    prefix: '+'),
            ],
          );
        },
      ),
    );
  }

  Widget _diffLine(int num, String text, Color bg, bool isDark,
      {String prefix = ' '}) {
    final clr = prefix == '+'
        ? Colors.green
        : (prefix == '-' ? Colors.red : Dt.textSecondary);
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text('$num',
                textAlign: TextAlign.right,
                style: GoogleFonts.firaCode(fontSize: 10, color: Dt.textMuted)),
          ),
          const SizedBox(width: 8),
          Text(prefix,
              style: GoogleFonts.firaCode(
                  fontSize: 13, color: clr, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.firaCode(
                fontSize: 13,
                height: 1.5,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _htmlPreview(String content) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        // Same real-origin requirement as the full page: games using
        // localStorage break on an opaque origin.
        baseUrl: WebUri('https://localhost/'),
        data: content,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: true,
        javaScriptEnabled: true,
        domStorageEnabled: true,
      ),
      onWebViewCreated: (ctrl) => _webController = ctrl,
      onConsoleMessage: (ctrl, msg) {
        if (mounted) {
          setState(() {
            _consoleOutput += '${msg.message}\n';
          });
        }
      },
    );
  }

  Widget _mermaidPreview(String content, bool isDark) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(data: _mermaidHtml(content, isDark)),
      initialSettings:
          InAppWebViewSettings(transparentBackground: true, supportZoom: true),
      onWebViewCreated: (ctrl) => _webController = ctrl,
    );
  }

  String _mermaidHtml(String content, bool isDark) {
    final themeName = isDark ? 'dark' : 'default';
    return '''<!DOCTYPE html>
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
    mermaid.initialize({ startOnLoad: true, theme: '$themeName' });
    window.addEventListener('load', function() {
      document.querySelector('.mermaid').style.visibility = 'visible';
    });
  </script>
</body>
</html>''';
  }

  Widget _tablePreview(String content, bool isDark) {
    final lines = content.trim().split('\n');
    if (lines.isEmpty) return const Center(child: Text('Empty Table'));

    final rows = lines
        .map((l) => l.split(RegExp(r',|\|')).map((e) => e.trim()).toList())
        .toList();
    final header = rows.first;
    final data = rows.skip(1).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05)),
          columns: header
              .map((h) => DataColumn(
                  label: Text(h,
                      style: const TextStyle(fontWeight: FontWeight.bold))))
              .toList(),
          rows: data
              .map((r) =>
                  DataRow(cells: r.map((c) => DataCell(Text(c))).toList()))
              .toList(),
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
              const Icon(LucideIcons.terminal,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Interactive Console',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isRunning ? null : _runCode,
                icon: _isRunning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.play, size: 14),
                label: const Text('Run'),
                style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.02),
            child: SelectableText(
              _consoleOutput.isEmpty
                  ? '// Click "Run" to see output'
                  : _consoleOutput,
              style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  /// Compact header icon button (40px targets instead of Material's
  /// 48px) so the 6-7 action buttons + title fit 360dp chat bubbles
  /// without a RenderFlex overflow.
  Widget _hbtn({
    required Widget icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _header(
      BuildContext context, bool isDark, String title, String? type) {
    final ctrl = Get.find<ChatController>();
    final hasProject = ctrl.currentProjectId.value != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          if (hasProject)
            _hbtn(
              icon: Icon(_ideMode ? LucideIcons.layout : LucideIcons.folderTree,
                  size: 18,
                  color: _ideMode ? AppColors.primary : Dt.textSecondary),
              onPressed: () => setState(() => _ideMode = !_ideMode),
              tooltip: _ideMode ? 'Artifact Mode' : 'Project IDE Mode',
            ),
          Icon(_getIcon(type), size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _ideMode 
                ? (ctrl.activeProjectFile.value?.split(Platform.pathSeparator).last ?? 'Project Explorer')
                : title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? AppColors.textPrimary : Dt.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isEditing) ...[
            if (_editController.selection.isValid &&
                !_editController.selection.isCollapsed)
              _hbtn(
                icon: const Icon(LucideIcons.scissors,
                    size: 18, color: AppColors.primary),
                onPressed: () {
                  final sel = _editController.selection;
                  final text = _editController.text.substring(sel.start, sel.end);
                  setState(() {
                    _showAskAi = true;
                    _askAiCtrl.text = 'Regarding this selection: "$text"\n\n';
                    _askAiCtrl.selection = TextSelection.collapsed(
                        offset: _askAiCtrl.text.length);
                  });
                },
                tooltip: 'Ask about selection',
              ),
            // Ask AI button.
            _hbtn(
              icon: const Icon(LucideIcons.sparkles,
                  size: 18, color: AppColors.primary),
              onPressed: () => setState(() => _showAskAi = !_showAskAi),
              tooltip: 'Ask AI to iterate',
            ),
            _hbtn(
              icon: const Icon(LucideIcons.save,
                  size: 20, color: AppColors.success),
              onPressed: _save,
              tooltip: 'Save changes',
            ),
          ] else ...[
            // HTML artifacts open in a full page (games need the space).
            if (type == 'html')
              _hbtn(
                icon: const Icon(LucideIcons.maximize2,
                    size: 18, color: AppColors.primary),
                onPressed: () => _openFullPreview(title),
                tooltip: 'Open full page',
              ),
            _hbtn(
              icon: const Icon(LucideIcons.save,
                  size: 18, color: AppColors.primary),
              onPressed: _syncToDisk,
              tooltip: 'Save to Project Disk',
            ),
            _hbtn(
              icon: const Icon(LucideIcons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editController.text));
                Get.snackbar('Copied', 'Artifact content copied to clipboard',
                    snackPosition: SnackPosition.BOTTOM);
              },
              tooltip: 'Copy content',
            ),
            _hbtn(
              icon: const Icon(LucideIcons.download, size: 18),
              onPressed: () => PromptExport.shareAsMarkdown(
                  _editController.text,
                  baseName: title),
              tooltip: 'Download as Markdown',
            ),
            // Ask AI (also available in view mode).
            _hbtn(
              icon: const Icon(LucideIcons.sparkles,
                  size: 18, color: AppColors.primary),
              onPressed: () => setState(() => _showAskAi = !_showAskAi),
              tooltip: 'Ask AI to iterate',
            ),
            _hbtn(
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
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
      ),
      child: Row(
        children: [
          Text(
            'Version ${_currentIndex + 1} of ${widget.versions.length}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Dt.textSecondary),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            onPressed: _currentIndex > 0
                ? () => setState(() {
                      _currentIndex--;
                      _editController.text =
                          widget.versions[_currentIndex]['content'] ?? '';
                    })
                : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, size: 16),
            onPressed: _currentIndex < widget.versions.length - 1
                ? () => setState(() {
                      _currentIndex++;
                      _editController.text =
                          widget.versions[_currentIndex]['content'] ?? '';
                    })
                : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _content(
      BuildContext context, bool isDark, String content, String? type) {
    if (type == 'html') {
      return InAppWebView(
        initialData: InAppWebViewInitialData(
          baseUrl: WebUri('https://localhost/'),
          data: content,
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: true,
          javaScriptEnabled: true,
          domStorageEnabled: true,
        ),
      );
    }

    return Markdown(
      data: '```${type ?? ""}\n$content\n```',
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        codeblockDecoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.black.withValues(alpha: 0.02),
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

// ── Line Number Gutter ─────────────────────────────────────

class _LineNumberGutter extends StatefulWidget {
  final TextEditingController controller;
  final bool isDark;

  const _LineNumberGutter({required this.controller, required this.isDark});

  @override
  State<_LineNumberGutter> createState() => _LineNumberGutterState();
}

class _LineNumberGutterState extends State<_LineNumberGutter> {
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _lineCount = _countLines();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final count = _countLines();
    if (count != _lineCount) {
      setState(() => _lineCount = count);
    }
  }

  int _countLines() {
    final text = widget.controller.text;
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      color: widget.isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02),
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _lineCount.clamp(1, 500),
          (i) => SizedBox(
            height: 19.5, // Match FiraCode fontSize:13 * lineHeight:1.5
            child: Text(
              '${i + 1}',
              style: GoogleFonts.firaCode(
                fontSize: 11,
                color: Dt.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bracket Auto-Close Formatter ───────────────────────────

class _BracketAutoCloseFormatter extends TextInputFormatter {
  static const _pairs = {
    '(': ')',
    '{': '}',
    '[': ']',
    '<': '>',
    '"': '"',
    "'": "'",
  };

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length != oldValue.text.length + 1) return newValue;

    final inserted = newValue.text[newValue.selection.baseOffset - 1];
    final closing = _pairs[inserted];

    if (closing != null) {
      final before = newValue.text.substring(0, newValue.selection.baseOffset);
      final after = newValue.text.substring(newValue.selection.baseOffset);
      return TextEditingValue(
        text: '$before$closing$after',
        selection:
            TextSelection.collapsed(offset: newValue.selection.baseOffset),
      );
    }

    return newValue;
  }
}
