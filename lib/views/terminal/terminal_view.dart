/// CubicLM Terminal — sandboxed shell screen.
///
/// One session per scope (default + per agent project), each with its own
/// transcript, history, and working directory. Every command passes
/// through [SandboxService] before spawning (isolated PRoot Ubuntu when
/// the runtime is installed, screened host shell otherwise).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../services/sandbox/sandbox_manager.dart';
import '../../services/security/sandbox_service.dart';
import '../../services/terminal/terminal_service.dart';
import '../../theme/design_tokens.dart';

/// Terminal screen (reached from Toolkit → Terminal).
class TerminalView extends StatefulWidget {
  const TerminalView({super.key});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  late final TerminalService term;
  final input = TextEditingController();
  final scroll = ScrollController();
  late final Worker _scrollWorker;

  /// -1 = fresh line; otherwise an index into [TerminalService.history]
  /// (0 = newest). The ↑ ↓ helper keys walk it.
  int _histIndex = -1;

  /// CTRL modifier armed (reference-app parity): the next `c` typed or
  /// tapped interrupts a running process, or clears the line when idle.
  bool _ctrlActive = false;

  @override
  void initState() {
    super.initState();
    term = Get.isRegistered<TerminalService>()
        ? Get.find<TerminalService>()
        : Get.put(TerminalService());
    // Auto-scroll on every new line (reference-app parity) — posted
    // post-frame so layout has settled.
    _scrollWorker = ever<List<TerminalLine>>(term.lines, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          if (scroll.hasClients) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        } catch (_) {}
      });
    });
  }

  @override
  void dispose() {
    _scrollWorker.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// Shared CTRL+C handling (key button, CTRL-armed `c` keypress):
  /// interrupt the foreground process, or clear the line when idle.
  void _ctrlC() {
    _ctrlActive = false;
    if (term.isRunning.value) {
      term.interrupt();
    } else {
      input.clear();
    }
  }

  /// Feed a typed key through the CTRL modifier (reference-app parity):
  /// with CTRL armed, `c`/`C` interrupts (running) or clears (idle) and
  /// disarms; any other key just disarms.
  void _onInputChanged(String next) {
    final prev = _lastInputText;
    _lastInputText = next;
    if (!_ctrlActive) return;
    // Diff for the inserted segment (handles mid-line typing/paste).
    var i = 0;
    while (i < prev.length &&
        i < next.length &&
        prev.codeUnitAt(i) == next.codeUnitAt(i)) {
      i++;
    }
    var j = 0;
    while (j < prev.length - i &&
        j < next.length - i &&
        prev.codeUnitAt(prev.length - 1 - j) ==
            next.codeUnitAt(next.length - 1 - j)) {
      j++;
    }
    final inserted = next.substring(i, next.length - j);
    if (inserted.contains(RegExp(r'[cC]'))) {
      _ctrlActive = false;
      // Drop the trigger character, keep the rest.
      final kept =
          '${next.substring(0, i)}${inserted.replaceAll(RegExp(r'[cC]'), '')}${next.substring(next.length - j)}';
      input.value = TextEditingValue(
        text: kept,
        selection: TextSelection.collapsed(
            offset: (i + inserted.replaceAll(RegExp(r'[cC]'), '').length)
                .clamp(0, kept.length)),
      );
      _lastInputText = kept;
      _ctrlC();
    } else {
      _ctrlActive = false;
    }
    setState(() {});
  }

  String _lastInputText = '';

  void run() {
    final cmd = input.text.trim();
    if (cmd.isEmpty) return;
    // Live stdin (reference-app parity): typing while a host process runs
    // sends to it instead of starting a second command.
    if (term.isRunning.value) {
      term.sendInput(cmd);
      input.clear();
      _histIndex = -1;
      return;
    }
    // Destructive commands need one explicit tap (reference-app confirm
    // dialog parity — the service still hard-blocks the catastrophic set).
    final verdict = SandboxService.classifyCommand(cmd);
    if (verdict.risk == CommandRisk.high) {
      _confirmRun(cmd);
      return;
    }
    _launch(cmd);
  }

  void _launch(String cmd) {
    input.clear();
    _histIndex = -1;
    term.runCommand(cmd).then((_) {
      try {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      } catch (_) {}
    });
  }

  /// Explicit go-ahead for high-risk commands. Shows the exact command
  /// (ellipsized) with Run/Cancel — nothing executes on dismiss.
  void _confirmRun(String cmd) {
    final preview = cmd.length > 300 ? '${cmd.substring(0, 300)}…' : cmd;
    Get.dialog(
      AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Run this command?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                preview,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'High-risk commands always ask first. Catastrophic ones stay blocked.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(context).hintColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Get.back();
              _launch(cmd);
            },
            child: const Text('Run'),
          ),
        ],
      ),
      name: 'terminal-confirm-run',
    );
  }

  /// Backend label for the status bar (`Host shell` / `PRoot`).
  String _backendLabel() {
    try {
      if (!Get.isRegistered<SandboxManager>()) return '';
      final n = Get.find<SandboxManager>().activeBackendName.value;
      if (n.isEmpty) return '';
      return ' · $n';
    } catch (_) {
      return '';
    }
  }

  /// Insert [text] at the cursor (helper keys below the transcript).
  void _insert(String text) {
    final value = input.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end =
        value.selection.end < 0 ? value.text.length : value.selection.end;
    final next = value.text.replaceRange(start, end, text);
    input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Walk command history: [older]=true moves toward older entries.
  void _walkHistory(bool older) {
    final h = term.history;
    if (h.isEmpty) return;
    if (older) {
      if (_histIndex < h.length - 1) _histIndex++;
    } else {
      if (_histIndex > 0) {
        _histIndex--;
      } else {
        _histIndex = -1;
        input.clear();
        return;
      }
    }
    if (_histIndex >= 0) {
      input.text = h[_histIndex];
      input.selection =
          TextSelection.collapsed(offset: input.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Terminal',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Export transcript',
            icon: const Icon(Icons.save_alt_rounded, size: 20),
            onPressed: () async {
              final text = term.exportTranscript();
              if (!context.mounted) return;
              // Copy to clipboard as simple export
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transcript copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_all_rounded),
            onPressed: term.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          _sessionBar(context, term),
          Obx(() {
            final cwd = term.workingDir.value;
            final label = cwd.isEmpty
                ? 'sandboxed shell — destructive commands blocked'
                : cwd;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.grey.withValues(alpha: 0.08),
              child: Text(
                '$label${_backendLabel()}',
                style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    color: Theme.of(context).hintColor),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          // Quick commands (reference-app parity): one tap runs.
          Obx(() => SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  children: [
                    for (final cmd in _quickCommands)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: term.isRunning.value
                              ? null
                              : () {
                                  input.text = cmd;
                                  run();
                                },
                          child: Text(
                            cmd,
                            style: GoogleFonts.firaCode(fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              )),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                // Terminal console (reference-app parity): bordered
                // rounded surface, near-black in dark mode.
                color: isDark
                    ? const Color(0xFF090D14)
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Obx(() {
                if (term.lines.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'CubicLM Terminal ready.\nType a shell command below or tap a quick command above.',
                      style: GoogleFonts.firaCode(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark
                            ? const Color(0xFF6E7681)
                            : Theme.of(context).hintColor,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: term.lines.length,
                  itemBuilder: (context, i) {
                    final line = term.lines[i];
                    final text = SelectableText(
                      line.text.isEmpty ? ' ' : line.text,
                      style: GoogleFonts.firaCode(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: line.isCommand
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: line.isCommand
                            ? Dt.accent
                            : line.isError
                                ? AppColors.error
                                : isDark
                                    ? const Color(0xFFC9D1D9)
                                    : null,
                      ),
                    );
                    // Output lines indent under their command
                    // (reference-app console parity).
                    if (line.isCommand) return text;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: text,
                    );
                  },
                );
              }),
            ),
          ),
          // Dev-server preview chip (Mobile-Harness parity): a loopback
          // URL in the output becomes an openable chip.
          Obx(() {
            final url = term.previewUrl.value;
            if (url == null || url.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Dt.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language_rounded,
                      size: 14, color: Dt.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 11, color: Dt.accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    child: Text(
                      'Open',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Dt.accent,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    onPressed: () => term.previewUrl.value = null,
                  ),
                ],
              ),
            );
          }),
          // Helper key row (Mobile-Harness parity): modifiers, history,
          // and shell metacharacters that soft keyboards hide.
          _keyRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).hintColor.withValues(
                              alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Inline cwd-aware prompt (reference-app parity:
                        // green `user@host`-style head instead of `$ `).
                        Obx(() {
                          final cwd = term.workingDir.value;
                          final short = cwd.isEmpty
                              ? '~'
                              : compactPromptPath(cwd);
                          return Flexible(
                            child: Text(
                              '\$ $short ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.firaCode(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Dt.accent,
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: TextField(
                            controller: input,
                            style:
                                GoogleFonts.firaCode(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'command…',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 10),
                            ),
                            onChanged: _onInputChanged,
                            onSubmitted: (_) => run(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() => term.isRunning.value
                    ? IconButton.filled(
                        tooltip: 'Kill',
                        style: IconButton.styleFrom(
                            backgroundColor: AppColors.error),
                        icon: const Icon(Icons.stop_rounded),
                        onPressed: term.kill,
                      )
                    : IconButton.filled(
                        tooltip: 'Run',
                        style: IconButton.styleFrom(
                            backgroundColor: Dt.accent),
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: run,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Quick commands (reference-app parity).
  static const _quickCommands = [
    'uname -a',
    'ls -la',
    'pwd',
    'whoami',
    'node -v',
    'python3 --version',
    'df -h',
    'free -m',
  ];

  /// One-tap keys: ESC/TAB/CTRL-C, history ↑ ↓, cursor ← →, and common
  /// shell metacharacters. ESC clears the line and idle ^C clears it too
  /// (reference-app parity); running ^C interrupts the process. CTRL arms
  /// the modifier so the next typed `c` behaves like ^C.
  Widget _keyRow() {
    final keys = <({
      String label,
      String? insert,
      VoidCallback? action,
      bool highlight
    })>[
      (label: 'ESC', insert: null, action: () => input.clear(), highlight: false),
      (label: 'TAB', insert: '\t', action: null, highlight: false),
      (
        label: '^C',
        insert: null,
        action: _ctrlC,
        highlight: false,
      ),
      (
        label: 'CTRL',
        insert: null,
        action: () {
          _ctrlActive = !_ctrlActive;
          setState(() {});
        },
        highlight: _ctrlActive,
      ),
      (label: '↑', insert: null, action: () => _walkHistory(true), highlight: false),
      (label: '↓', insert: null, action: () => _walkHistory(false), highlight: false),
      (label: '←', insert: null, action: () => _moveCursor(-1), highlight: false),
      (label: '→', insert: null, action: () => _moveCursor(1), highlight: false),
      (label: '|', insert: '|', action: null, highlight: false),
      (label: '~', insert: '~', action: null, highlight: false),
      (label: '&&', insert: ' && ', action: null, highlight: false),
      (label: '/', insert: '/', action: null, highlight: false),
      (label: '-', insert: '-', action: null, highlight: false),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final k = keys[i];
          return OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              backgroundColor: k.highlight
                  ? Dt.accent.withValues(alpha: 0.18)
                  : null,
              side: k.highlight
                  ? const BorderSide(color: Dt.accent)
                  : null,
            ),
            onPressed: () {
              if (k.insert != null) {
                _insert(k.insert!);
              } else {
                k.action?.call();
              }
            },
            child: Text(
              k.highlight ? '${k.label} ✓' : k.label,
              style: GoogleFonts.firaCode(
                fontSize: 12,
                color: k.highlight ? Dt.accent : null,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Move the text cursor by [delta] code units, clamped to the input.
  void _moveCursor(int delta) {
    final value = input.value;
    final pos = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final next = (pos + delta).clamp(0, value.text.length);
    input.selection = TextSelection.collapsed(offset: next);
  }

  /// Session picker: default shell plus one session per agent project.
  Widget _sessionBar(BuildContext context, TerminalService term) {
    final hasWs = Get.isRegistered<AgentWorkspaceService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Obx(() {
        final projects =
            hasWs ? Get.find<AgentWorkspaceService>().projects.toList() : const [];
        return DropdownButtonFormField<String>(
          initialValue: term.activeSessionId.value,
          decoration: InputDecoration(
            labelText: 'Session',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<String>(
                value: TerminalService.defaultSessionId,
                child: Text('Default shell')),
            for (final p in projects)
              DropdownMenuItem<String>(
                  value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) {
            if (v != null) term.switchSession(v);
          },
        );
      }),
    );
  }
}
