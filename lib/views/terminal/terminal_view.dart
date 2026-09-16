/// CubicLM Terminal — sandboxed shell screen.
///
/// One session per scope (default + per agent project), each with its own
/// transcript, history, and working directory. Every command passes
/// through [SandboxService] before spawning. Full PRoot/Ubuntu isolation
/// is deferred native work (roadmap Phase 6).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
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

  /// -1 = fresh line; otherwise an index into [TerminalService.history]
  /// (0 = newest). The ↑ ↓ helper keys walk it.
  int _histIndex = -1;

  @override
  void initState() {
    super.initState();
    term = Get.isRegistered<TerminalService>()
        ? Get.find<TerminalService>()
        : Get.put(TerminalService());
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void run() {
    final cmd = input.text.trim();
    if (cmd.isEmpty || term.isRunning.value) return;
    input.clear();
    _histIndex = -1;
    term.runCommand(cmd).then((_) {
      try {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      } catch (_) {}
    });
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
          Obx(() => Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.grey.withValues(alpha: 0.08),
                child: Text(
                  term.workingDir.value.isEmpty
                      ? 'sandboxed shell — destructive commands blocked'
                      : term.workingDir.value,
                  style: GoogleFonts.firaCode(
                      fontSize: 10.5,
                      color: Theme.of(context).hintColor),
                  overflow: TextOverflow.ellipsis,
                ),
              )),
          Expanded(
            child: Obx(() => ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: term.lines.length,
                  itemBuilder: (context, i) {
                    final line = term.lines[i];
                    return SelectableText(
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
                                : null,
                      ),
                    );
                  },
                )),
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
                  child: TextField(
                    controller: input,
                    style: GoogleFonts.firaCode(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'whoami / git status / npm test…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      prefixText: '\$ ',
                    ),
                    onSubmitted: (_) => run(),
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

  /// One-tap keys: ESC/TAB/CTRL-C, history ↑ ↓, cursor ← →, and common
  /// shell metacharacters.
  Widget _keyRow() {
    final keys = <({String label, String? insert, VoidCallback? action})>[
      (label: 'ESC', insert: '\x1B', action: null),
      (label: 'TAB', insert: '\t', action: null),
      (
        label: '^C',
        insert: null,
        action: () {
          if (term.isRunning.value) term.kill();
        }
      ),
      (label: '↑', insert: null, action: () => _walkHistory(true)),
      (label: '↓', insert: null, action: () => _walkHistory(false)),
      (label: '|', insert: '|', action: null),
      (label: '~', insert: '~', action: null),
      (label: '&&', insert: ' && ', action: null),
      (label: '/', insert: '/', action: null),
      (label: '-', insert: '-', action: null),
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
          final enabled = k.action != null || k.insert != null;
          // ^C only does something while a command runs.
          final active = k.label != '^C' || term.isRunning.value;
          return Obx(() {
            final running = term.isRunning.value;
            final on = k.label == '^C' ? running : enabled && active;
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: !on
                  ? null
                  : () {
                      if (k.insert != null) {
                        _insert(k.insert!);
                      } else {
                        k.action?.call();
                      }
                    },
              child: Text(
                k.label,
                style: GoogleFonts.firaCode(fontSize: 12),
              ),
            );
          });
        },
      ),
    );
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
