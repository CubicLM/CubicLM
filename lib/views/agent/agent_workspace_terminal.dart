/// Agent Workspace — Terminal tab: project-jailed shell pane.
///
/// Runs commands through the same [RunCommandTool] the agent uses, so the
/// sandbox routing (PRoot Ubuntu when installed, host shell otherwise),
/// command risk classification and approval gating all apply. Safe reads
/// (ls, git status, cat) auto-run; side effects ask once / always.
part of 'agent_workspace_view.dart';

extension _AgentWorkspaceTerminal on _AgentWorkspaceViewState {
  void _clearTerm() {
    controller.termLines.clear();
    controller.termAppend(
        'CubicLM agent shell — commands run '
        '${controller.projectId.value == null ? 'in the host sandbox' : 'inside the project workspace'}.',
        muted: true);
  }

  /// Seed the welcome line (never called during an Obx build).
  void _ensureTermWelcome() {
    if (controller.termLines.isEmpty) {
      controller.termAppend(
          'CubicLM agent shell — commands run '
          '${controller.projectId.value == null ? 'in the host sandbox' : 'inside the project workspace'}.',
          muted: true);
    }
  }

  Widget _terminalPane(BuildContext context, bool isDark) {
    _ensureTermWelcome();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Obx(() {
            final lines = controller.termLines.toList();
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final l = lines[i];
                return SelectableText(
                  l.text,
                  style: GoogleFonts.firaCode(
                    fontSize: 11.5,
                    height: 1.5,
                    color: l.muted
                        ? Theme.of(context).hintColor
                        : l.ok
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.9)
                                : const Color(0xFF1F2430))
                            : AppColors.error,
                  ),
                );
              },
            );
          }),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16161E) : const Color(0xFFF7F7FA),
            border: Border(
              top: BorderSide(color: isDark ? Colors.white10 : Dt.hairline),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final cmd in const [
                    'ls -la',
                    'git status',
                    'node -v',
                    'python3 --version',
                    'gcc --version',
                    'php -v',
                  ])
                    ActionChip(
                      label: Text(cmd,
                          style: GoogleFonts.firaCode(fontSize: 10.5)),
                      onPressed: () => _submitTerm(cmd),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(LucideIcons.terminal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _termCtrl,
                      enabled: !controller.termRunning.value,
                      style: GoogleFonts.firaCode(fontSize: 12),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitTerm(_termCtrl.text),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: controller.termRunning.value
                            ? 'Running…'
                            : 'Shell command (Enter to run)',
                        hintStyle: GoogleFonts.firaCode(
                            fontSize: 11.5,
                            color: Theme.of(context).hintColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(() => controller.termRunning.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'Run',
                          icon: const Icon(Icons.play_arrow_rounded,
                              color: Dt.accent, size: 20),
                          onPressed: () => _submitTerm(_termCtrl.text),
                        )),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    onPressed: _clearTerm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _submitTerm(String text) {
    final cmd = text.trim();
    if (cmd.isEmpty) return;
    _termCtrl.clear();
    FocusScope.of(context).unfocus();
    controller.runTermCommand(cmd);
  }
}
