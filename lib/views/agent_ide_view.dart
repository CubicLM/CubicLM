import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/assets_data.dart';
import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/cubicweb/cubicweb_logger.dart';
import '../services/runtime/cli_manager.dart';
import '../services/runtime/project_detector.dart';
import 'system_logs_view.dart';
import '../services/app_log_service.dart';
import 'cubicweb/agent_preview.dart';
import 'cubicweb/chat_cards.dart';
import 'cubicweb/file_cards.dart';
import 'cubicweb/project_sheets.dart';
import 'cubicweb/version_timeline.dart';
import 'cubicweb/diff_view.dart';
import 'cubicweb/responsive_grid_view.dart';
import 'cubicweb/knowledge_graph_view.dart';
import '../widgets/cli_sheets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/agent_workspace.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import '../widgets/app_ui.dart';
import '../widgets/model_switcher_sheet.dart';
import 'agent_ide_markdown.dart';

/// CubicWeb Builder — agentic website studio (Toolkit): prompt → project
/// → live localhost preview → console-error auto-fix loop.
part 'agent_ide_mentions.dart';
part 'agent_ide_sheets.dart';
part 'agent_ide_command.dart';
part 'agent_ide_panes.dart';
part 'agent_ide_chat.dart';
part 'agent_ide_dialogs.dart';
part 'agent_ide_files.dart';
class AgentIdeView extends StatefulWidget {
  const AgentIdeView({super.key});

  @override
  State<AgentIdeView> createState() => _AgentIdeViewState();
}

class _AgentIdeViewState extends State<AgentIdeView> {
  /// setState bridge for `part` extensions (extensions cannot call the
  /// protected [State.setState] directly).
  void _refresh(VoidCallback fn) => setState(fn);

  late final AgentController c;
  final _promptCtrl = TextEditingController();
  final _askCtrl = TextEditingController();
  final _askFocus = FocusNode();
  final _termCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  final _expandedFolders = <String>{}.obs;
  final _openTabs = <String>[].obs;
  String _tab = 'preview'; // preview | files | terminal
  String? _openFile;
  OverlayEntry? _mentionOverlay;
  final _askLayer = LayerLink();
  String _devTab = 'console'; // console | terminal
  final _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    AppLogService.trackScreen('CubicWeb Builder');
    c = Get.isRegistered<AgentController>()
        ? Get.find<AgentController>()
        : Get.put(AgentController());

    _askCtrl.addListener(() {
      if (mounted) {
        setState(() {});
        _checkMentions();
      }
    });

    ever(c.generating, (_) {
      if (mounted) setState(() {});
    });
    ever(c.fixing, (_) {
      if (mounted) setState(() {});
    });
    ever(c.project, (_) {
      if (mounted) setState(() {});
    });

    ever(c.transcript, (_) {
      if (!mounted) return;
      _scrollToBottom();
    });
    ever(c.buildSteps, (_) {
      if (!mounted) return;
      _scrollToBottom();
    });

    ever(c.streamingFiles, (_) {
      if (!mounted) return;
      if (_openFile == null && c.streamingFiles.isNotEmpty && _tab == 'files') {
        final path = c.streamingFiles.keys.first;
        if (!_openTabs.contains(path)) _openTabs.add(path);
        setState(() => _openFile = path);
      }
    });

    _termCtrl.addListener(() {
      if (mounted) setState(() {});
    });

    ever(c.requestAskFocus, (_) {
      if (mounted) _askFocus.requestFocus();
    });

    // Success celebration
    ever(c.generating, (busy) {
      if (!busy && c.lastError.value == null && c.project.value != null) {
        AppSnackbar.showTop('Project Live', 'Your changes have been deployed successfully! ✨', logHistory: false);
      }
    });

    unawaited(c.ensureTerminalWelcome());

    ever(c.detectedCliId, (_) {
      if (!mounted) return;
      final id = c.detectedCliId.value;
      if (id == null || id.isEmpty) return;
      c.detectedCliId.value = null;
      try {
        final m = Get.find<CliManagerService>().manifestById(id);
        if (m == null) return;
        showCliDetectedDialog(m, c.detectedCliVersion.value ?? '');
      } catch (_) {}
    });
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final isMod = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isMod && event.logicalKey == LogicalKeyboardKey.enter) {
          _sendFromAskBar();
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.keyK) {
          _showCommandPalette(context, isDark);
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit1) {
          setState(() => _tab = 'preview');
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit2) {
          setState(() => _tab = 'files');
          return KeyEventResult.handled;
        }
        if (isMod && event.logicalKey == LogicalKeyboardKey.digit3) {
          setState(() => _tab = 'chat');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final p = c.project.value;
            if (p == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('CubicWeb Builder',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800)),
                  Text('Agent IDE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).hintColor)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800)),
                Text('${p.framework} · ${c.files.length} files',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor)),
              ],
            );
          }),
          actions: [
            Obx(() {
              final hasP = c.project.value != null;
              final dim = Theme.of(context).hintColor.withValues(alpha: 0.45);
              return Row(mainAxisSize: MainAxisSize.min, children: [
                // 1. Project Management Group
                IconButton(
                  tooltip: 'New project',
                  icon: const Icon(LucideIcons.plusCircle, size: 20, color: Dt.accent),
                  onPressed: _newProjectReset,
                ),
                
                // 2. AI Magic Tools Menu
                PopupMenuButton<String>(
                  tooltip: 'AI Tools',
                  icon: Icon(LucideIcons.sparkles, color: hasP ? Dt.accent : dim),
                  onSelected: (v) {
                    if (v == 'polish') c.autoPolish();
                    if (v == 'autofix') c.autoFix.value = !c.autoFix.value;
                    if (v == 'pick') c.toggleElementPick();
                    if (v == 'test') c.runAutoTest();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'polish',
                      enabled: hasP,
                      child: const Row(children: [
                        Icon(LucideIcons.wand2, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Magic Polish UI', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'autofix',
                      enabled: hasP,
                      child: Row(children: [
                        Icon(c.autoFix.value ? Icons.bolt_rounded : Icons.bolt_outlined, size: 16, color: Dt.accent),
                        const SizedBox(width: 12),
                        Text('Auto-fix: ${c.autoFix.value ? 'ON' : 'OFF'}', style: const TextStyle(fontSize: 14)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'pick',
                      enabled: hasP,
                      child: const Row(children: [
                        Icon(LucideIcons.crosshair, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Inspect Element', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'test',
                      enabled: hasP,
                      child: const Row(children: [
                        Icon(LucideIcons.shieldCheck, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Run Auto-Test', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                  ],
                ),

                // 3. Configuration Menu
                PopupMenuButton<String>(
                  tooltip: 'Configuration',
                  icon: const Icon(LucideIcons.settings2, size: 20, color: Dt.accent),
                  onSelected: (v) {
                    if (v == 'instructions') _showSystemPromptSheet(context);
                    if (v == 'brand') _showBrandIdentitySheet(context);
                    if (v == 'settings') showBuilderSettingsSheet(context);
                    if (v == 'history') showHistorySheet(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'instructions',
                      child: Row(children: [
                        Icon(LucideIcons.binary, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('System Instructions', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'brand',
                      child: Row(children: [
                        Icon(LucideIcons.palette, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Brand Identity', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Row(children: [
                        Icon(LucideIcons.history, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Snapshot History', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(children: [
                        Icon(LucideIcons.sliders, size: 16, color: Dt.accent),
                        SizedBox(width: 12),
                        Text('Builder Settings', style: TextStyle(fontSize: 14)),
                      ]),
                    ),
                  ],
                ),
              ]);
            }),
            
            // 4. System Status & Logs
            Obx(() {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              int n = 0;
              try {
                n = Get.find<CubicWebLogger>().unreadErrors.value;
              } catch (_) {}
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'CubicWeb System Logs',
                    icon: Icon(LucideIcons.activity,
                        size: 20,
                        color: n > 0
                            ? AppColors.error
                            : (isDark
                                ? AppColors.textPrimary
                                : Dt.iconDefault)),
                    onPressed: () => Get.to(() => const SystemLogsView(),
                        transition: Transition.rightToLeft,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic),
                  ),
                  if (n > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            n > 99 ? '99+' : '$n',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),

            // 5. Context Menu
            Obx(() {
              final hasP = c.project.value != null;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return PopupMenuButton<String>(
                tooltip: 'Project',
                icon: Icon(LucideIcons.folderGit2,
                    color: hasP
                        ? (isDark ? AppColors.textPrimary : Dt.iconDefault)
                        : Theme.of(context).hintColor.withValues(alpha: 0.45)),
                onSelected: (v) =>
                    onProjectMenu(context, v, promptCtrl: _promptCtrl),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'switch',
                    child: Text('Switch project (${c.projectsOf().length})',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    enabled: hasP,
                    child: const Text('Export ZIP',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    enabled: hasP,
                    child: const Text('Rename project',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'fork',
                    enabled: hasP,
                    child: const Text('Fork project',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'deploy',
                    enabled: hasP,
                    child: const Text('Deploy to web',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    enabled: hasP,
                    child: const Text('Share project link',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'github',
                    enabled: hasP,
                    child: const Text('Export to GitHub',
                        style: TextStyle(fontSize: 14)),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: hasP,
                    child: Text('Delete project',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: AppColors.error)),
                  ),
                ],
              );
            }),
            const SizedBox(width: 4),
          ],
        ),
        body: Obx(() {
          final hasProject = c.project.value != null;
          final wide = MediaQuery.of(context).size.width >= 900 && hasProject;
          if (wide) {
            return Row(children: [
              VersionTimeline(isDark: isDark),
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        flex: 2,
                        child: Column(children: [
                          _paneHeader(context, isDark, 'CHAT', null),
                          Expanded(child: _chatPane(context, isDark)),
                        ]),
                      ),
                      Container(
                        width: 1,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Dt.hairline,
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(children: [
                          _paneHeader(
                              context,
                              isDark,
                              _tab == 'files'
                                  ? 'FILES'
                                  : _tab == 'console'
                                      ? 'CONSOLE'
                                      : _tab == 'grid'
                                          ? 'GRID'
                                          : _tab == 'graph'
                                              ? 'MIND MAP'
                                              : 'LIVE PREVIEW',
                              _workspaceTabs(context, isDark)),
                          Expanded(
                            child: _tab == 'files'
                                ? _filesPane(context, isDark)
                                : _tab == 'console'
                                    ? _consolePane(context, isDark)
                                    : _tab == 'grid'
                                        ? ResponsiveGridView(url: c.previewUrl.value ?? '', isDark: isDark)
                                        : _tab == 'graph'
                                            ? KnowledgeGraphView(isDark: isDark, onFileClick: (f) => _openFileTab(f))
                                            : _previewPane(context, isDark, c.revision.value),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  if (c.lastError.value != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(_friendlyError(c.lastError.value ?? 'Unknown error'),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5, color: AppColors.error, height: 1.4)),
                    ),
                  _bottomMeter(context, isDark),
                  _smartSuggestions(context, isDark),
                  _askBar(context, isDark),
                ]),
              ),
            ]);
          }
          return Column(children: [
            _tabSwitch(context, isDark),
            Expanded(
              child: _tab == 'preview' && hasProject
                  ? _splitOrPreview(context, isDark)
                  : _tab == 'preview'
                      ? _previewPane(context, isDark, c.revision.value)
                      : _tab == 'files'
                          ? _filesPane(context, isDark)
                          : _tab == 'console'
                              ? _consolePane(context, isDark)
                              : _tab == 'grid'
                                  ? ResponsiveGridView(url: c.previewUrl.value ?? '', isDark: isDark)
                                  : _tab == 'graph'
                                      ? KnowledgeGraphView(isDark: isDark, onFileClick: (f) => _openFileTab(f))
                                      : _chatPane(context, isDark),
            ),
            if (c.lastError.value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(_friendlyError(c.lastError.value ?? 'Unknown error'),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5, color: AppColors.error, height: 1.4)),
              ),
            _bottomMeter(context, isDark),
            _smartSuggestions(context, isDark),
            _askBar(context, isDark),
          ]);
        }),
      ),
    );
  }


  Widget _paneHeader(
      BuildContext context, bool isDark, String label, Widget? trailing) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
          ),
        ),
      ),
      child: Row(children: [
        if (label == 'LIVE PREVIEW')
          Obx(() => Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      c.livePreviewReady.value ? AppColors.success : Dt.accent,
                ),
              )),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: Theme.of(context).hintColor)),
        if (label == 'CHAT') ...[
          const Spacer(),
          Obx(() {
            if (c.pendingChanges.isEmpty) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => c.pendingChanges.clear(),
                  child: const Text('Discard', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
                TextButton(
                  onPressed: () => Get.to(() => DiffView(isDark: isDark, fullPage: true)),
                  child: const Text('View', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => c.applyPendingChanges(),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Dt.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Apply Changes', style: TextStyle(fontSize: 11)),
                ),
              ],
            );
          }),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Expanded(child: trailing),
        ],
      ]),
    );
  }

  Widget _tabSwitch(BuildContext context, bool isDark) {
    return _workspaceTabs(context, isDark, fullWidth: true);
  }

  Widget _workspaceTabs(BuildContext context, bool isDark, {bool fullWidth = false}) {
    final tabs = [
      {'id': 'preview', 'label': 'Preview', 'icon': LucideIcons.eye},
      {'id': 'files', 'label': 'Files', 'icon': LucideIcons.folderOpen},
      {'id': 'chat', 'label': 'Chat', 'icon': LucideIcons.messageCircle},
      {'id': 'console', 'label': 'Console', 'icon': LucideIcons.terminal},
      {'id': 'grid', 'label': 'Grid', 'icon': LucideIcons.layoutGrid},
      {'id': 'graph', 'label': 'Mind Map', 'icon': LucideIcons.gitBranch},
    ];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: fullWidth ? (isDark ? AppColors.surface : Colors.white) : Colors.transparent,
        border: fullWidth ? Border(bottom: BorderSide(color: isDark ? Colors.white10 : Dt.hairline)) : null,
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final t = tabs[i];
          final active = _tab == t['id'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => setState(() => _tab = t['id'] as String),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active ? Dt.accent.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(t['icon'] as IconData, size: 14, color: active ? Dt.accent : Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      t['label'] as String,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.bold : FontWeight.w700,
                        color: active ? Dt.accent : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _smartSuggestions(BuildContext context, bool isDark) {
    return Obx(() {
      if (c.suggestions.isEmpty) return const SizedBox.shrink();
      
      return Container(
        height: 36,
        margin: const EdgeInsets.only(bottom: 4),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: c.suggestions.length,
          itemBuilder: (context, i) {
            final s = c.suggestions[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600)),
                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                onPressed: () {
                  _askCtrl.text = s;
                  _askFocus.requestFocus();
                },
              ),
            );
          },
        ),
      );
    });
  }

  Widget _askBar(BuildContext context, bool isDark) {
    final hasProject = c.project.value != null;
    final busy = c.generating.value || c.fixing.value;
    final hasContent =
        _askCtrl.text.trim().isNotEmpty || c.attachedImage.value != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.consoleError.value != null && c.consoleError.value!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(c.consoleError.value!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5, color: AppColors.error)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: c.fixing.value ? null : () => c.repairFromError(),
                  child: Text(c.fixing.value ? 'Fixing…' : 'Fix'),
                ),
              ]),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Dt.card,
              borderRadius: BorderRadius.circular(Dt.rComposer),
              border: isDark
                  ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                    child: CompositedTransformTarget(
                      link: _askLayer,
                      child: TextField(
                        controller: _askCtrl,
                        focusNode: _askFocus,
                        minLines: 1,
                        maxLines: 6,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            height: 1.35,
                            color:
                                isDark ? AppColors.textPrimary : Dt.textPrimary,
                            fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: hasProject
                              ? 'Ask AI to change anything… (@ for files)'
                              : 'Describe what to build…',
                          hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              color: Dt.textPlaceholder,
                              fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 10),
                          isDense: true,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                  Obx(() => c.attachedImage.value != null
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Dt.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(LucideIcons.image,
                                size: 13, color: Dt.accent),
                            const SizedBox(width: 6),
                            Text('Screenshot attached',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Dt.accent)),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => c.clearAttachment(),
                              child: const Icon(LucideIcons.x,
                                  size: 12, color: Dt.accent),
                            ),
                          ]),
                        )
                      : const SizedBox.shrink()),
                  Obx(() => c.pickedElement.value != null
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Dt.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Dt.accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(LucideIcons.crosshair,
                                size: 13, color: Dt.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _pickedLabel(c.pickedElement.value!),
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Dt.accent),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => c.clearPickedElement(),
                              child: const Icon(LucideIcons.x,
                                  size: 12, color: Dt.accent),
                            ),
                          ]),
                        )
                      : const SizedBox.shrink()),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    AppCircleButton(
                      icon: _isListening ? LucideIcons.mic : LucideIcons.micOff,
                      tooltip: _isListening ? 'builder_voice_listening'.tr : 'builder_voice_hint'.tr,
                      iconColor: _isListening ? AppColors.error : null,
                      onTap: _toggleVoice,
                    ),
                    const SizedBox(width: 8),
                    AppCircleButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Builder tools',
                      onTap: () => showBuilderToolsSheet(
                          context, isDark, hasProject,
                          askCtrl: _askCtrl,
                          onInserted: () => _askFocus.requestFocus()),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 125,
                      child: Obx(() => AppModelPill(
                            label: builderModelLabel(),
                            onTap: () => showModelSwitcherSheet(context),
                          )),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!hasProject)
                            Obx(() => GestureDetector(
                                  onTap: () => showFrameworkSheet(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 7),
                                    decoration: BoxDecoration(
                                      color:
                                          Dt.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Dt.accent
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      '${frameworkShort(c.framework.value)} · ${c.selectedLibrary.value} · ${c.selectedDesignSystem.value}',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: Dt.accent),
                                    ),
                                  ),
                                )),
                          if (!hasProject && c.planMode.value)
                            const SizedBox(width: 6),
                          if (!hasProject && c.planMode.value)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.map,
                                        size: 12, color: Color(0xFFF59E0B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Plan',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFF59E0B)),
                                    ),
                                  ]),
                            ),
                          if (!hasProject) const SizedBox(width: 6),
                          AppCircleButton(
                            icon: LucideIcons.brain,
                            tooltip: 'Extended thinking',
                            iconColor: c.extendedThinking.value
                                ? const Color(0xFF8B5CF6)
                                : null,
                            onTap: () => c.extendedThinking.value =
                                !c.extendedThinking.value,
                          ),
                          const SizedBox(width: 6),
                          AppCircleButton(
                            icon: LucideIcons.globe,
                            tooltip: 'Web search',
                            iconColor: c.webSearch.value
                                ? const Color(0xFF10B981)
                                : null,
                            onTap: () => c.webSearch.value = !c.webSearch.value,
                          ),
                          const SizedBox(width: 6),
                          Opacity(
                            opacity: hasProject ? 1.0 : 0.35,
                            child: AppCircleButton(
                              icon: LucideIcons.shieldCheck,
                              tooltip: hasProject
                                  ? 'Auto-test project'
                                  : 'Auto-test (needs a project)',
                              onTap: (!hasProject || busy)
                                  ? null
                                  : () => c.runAutoTest(),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    Tooltip(
                      message: busy
                          ? 'Stop'
                          : (hasProject ? 'Apply change' : 'Build project'),
                      child: AppCtaButton(
                        icon: busy ? LucideIcons.square : LucideIcons.arrowUp,
                        onTap: busy
                            ? c.cancelWork
                            : (hasContent ? _sendFromAskBar : null),
                      ),
                    ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _liveProgressPill(BuildContext context, bool isDark, String? status) {
    return Obx(() {
      final n = c.streamingFiles.length;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Dt.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                status ??
                    (n > 0
                        ? 'Writing $n file${n == 1 ? '' : 's'}… preview updating live'
                        : 'AI is writing…'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Dt.accent)),
          ),
        ]),
      );
    });
  }

  Widget _previewDiagnosisCard(BuildContext context, bool isDark) {
    return Obx(() {
      final steps = c.previewSteps.toList();
      final kind = c.previewKind.value;
      final blockers = c.previewIssues.where((i) => i.blocksPreview).toList();
      if (kind == ProjectKind.staticSite || steps.isEmpty) {
        return const SizedBox.shrink();
      }
      final decision = c.previewDecision.value;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: blockers.isNotEmpty
                  ? AppColors.error.withValues(alpha: 0.35)
                  : Dt.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(
                    blockers.isNotEmpty
                        ? LucideIcons.alertTriangle
                        : LucideIcons.info,
                    size: 14,
                    color: blockers.isNotEmpty ? AppColors.error : Dt.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${projectKindLabel(kind)} detected',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                if (c.devServerStarting.value)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              // Cap visible steps: the card lives above an Expanded preview,
              // an unbounded step list can squeeze it into overflow.
              for (final s in steps.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Text(
                        s.state == 'ok'
                            ? '✓'
                            : s.state == 'fail'
                                ? '✗'
                                : '…',
                        style: GoogleFonts.firaCode(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: s.state == 'ok'
                                ? const Color(0xFF4ADE80)
                                : s.state == 'fail'
                                    ? AppColors.error
                                    : Theme.of(context).hintColor)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          s.detail.isEmpty
                              ? s.label
                              : '${s.label} — ${s.detail}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              color: Theme.of(context).hintColor)),
                    ),
                  ]),
                ),
              if (steps.length > 6)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 20),
                  child: Text('+${steps.length - 6} more steps',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: Theme.of(context).hintColor)),
                ),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final b in blockers.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• ${b.message}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: AppColors.error,
                            height: 1.35)),
                  ),
              ],
              if (decision != null && decision.actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in decision.actions)
                    _diagnosisAction(context, a),
                  ActionChip(
                    label: Text('System Logs',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5, fontWeight: FontWeight.w700)),
                    avatar: const Icon(LucideIcons.activity, size: 14),
                    onPressed: () => Get.to(() => const SystemLogsView(),
                        transition: Transition.rightToLeft,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
              ],
            ]),
      );
    });
  }

  Widget _diagnosisAction(BuildContext context, String action) {
    String label;
    IconData icon;
    VoidCallback? onTap;
    switch (action) {
      case 'start-dev-server':
        label = c.devServerUrl.value != null
            ? 'Restart dev server'
            : 'Start dev server';
        icon = LucideIcons.play;
        onTap = c.devServerStarting.value
            ? null
            : () => c.devServerUrl.value != null
                ? c.restartDevServer()
                : c.startDevServer();
      case 'validate-build':
        label = 'Validate build';
        icon = LucideIcons.wrench;
        onTap = c.validatingBuild.value ? null : () => c.validateBuild();
      case 'recheck-runtime':
        label = 'Recheck runtime';
        icon = LucideIcons.rotateCw;
        onTap = () => c.recheckRuntimeAndServe();
      case 'use-cloud':
        label = 'Run in cloud';
        icon = LucideIcons.cloud;
        onTap = () => c.useCloudFallback();
      case 'export-zip':
        label = 'Export ZIP';
        icon = LucideIcons.packageOpen;
        onTap = () => c.exportZip();
      case 'fix-issues':
        label = 'Ask AI to Fix';
        icon = LucideIcons.wand2;
        onTap = () => c.fixPreviewIssues();
      case 'open-terminal':
        label = 'Terminal';
        icon = LucideIcons.terminal;
        onTap = () => setState(() => _tab = 'preview');
      default:
        return const SizedBox.shrink();
    }
    return ActionChip(
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5, fontWeight: FontWeight.w700)),
      avatar: Icon(icon, size: 14),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }





  @override
  void dispose() {
    AppLogService.untrackScreen('CubicWeb Builder');
    _promptCtrl.dispose();
    _askCtrl.dispose();
    _askFocus.dispose();
    _termCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

}
