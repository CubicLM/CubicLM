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

import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../services/terminal/terminal_service.dart';
import '../../theme/design_tokens.dart';

/// Terminal screen (reached from Toolkit → Terminal).
class TerminalView extends StatelessWidget {
  const TerminalView({super.key});

  @override
  Widget build(BuildContext context) {
    final term = Get.isRegistered<TerminalService>()
        ? Get.find<TerminalService>()
        : Get.put(TerminalService());
    final input = TextEditingController();
    final scroll = ScrollController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void run() {
      final cmd = input.text.trim();
      if (cmd.isEmpty || term.isRunning.value) return;
      input.clear();
      term.runCommand(cmd).then((_) {
        try {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        } catch (_) {}
      });
    }

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
          Padding(
            padding: const EdgeInsets.all(12),
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
