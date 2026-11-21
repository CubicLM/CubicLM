/// Agent Workspace — Chat tab: transcript + composer.
///
/// Chat-style rendering of the [AgentEvent] stream (OpenCode/Claude-Code
/// parity): user task bubble, assistant markdown, collapsed reasoning,
/// expandable tool cards with output, checkpoint chips, todo plan, and a
/// composer with @-file mentions, plan/local toggles and Run/Stop.
part of 'agent_workspace_view.dart';

extension _AgentWorkspaceChat on _AgentWorkspaceViewState {
  Widget _chatPane(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isWide) _projectBar(context, isDark),
        Expanded(
          child: Obx(() {
            // Touch an always-present observable first: the todos getter
            // returns without touching any Rx when ToolRegistry has not
            // registered yet, and an Obx with zero observables throws
            // GetX's "improper use" error (seen on first launch).
            controller.events.length;
            final todos = controller.todos;
            return ListView.builder(
              controller: _chatScroll,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              itemCount: todos.length + controller.events.length + 1,
              itemBuilder: (context, i) {
                if (i < todos.length) {
                  return _todoRow(context, todos[i], isDark);
                }
                final idx = i - todos.length;
                if (idx == controller.events.length) {
                  return controller.running.value
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Obx(() => Text(
                                    'Working… ${controller.elapsed.value}',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: Theme.of(context).hintColor),
                                  )),
                            ],
                          ),
                        )
                      : const SizedBox(height: 8);
                }
                return _eventBlock(context, idx, controller.events[idx],
                    todos.length, isDark);
              },
            );
          }),
        ),
        if (!isWide) _changedFilesStrip(context, isDark),
        _composer(context, isDark),
      ],
    );
  }

  // ── Transcript blocks ────────────────────────────────────────────

  /// One transcript block per meaningful event. toolStarted folds into
  /// its toolCompleted card; toolCompleted without a prior start (cloud
  /// mode surfaces both) still renders.
  Widget _eventBlock(BuildContext context, int index, AgentEvent e,
      int todoCount, bool isDark) {
    switch (e.kind) {
      case AgentEventKind.text:
        return _assistantCard(context, e.text, isDark);
      case AgentEventKind.reasoning:
        return _reasoningCard(context, index, e.text, isDark);
      case AgentEventKind.toolStarted:
        final next = index + 1 < controller.events.length
            ? controller.events[index + 1]
            : null;
        if (next != null && next.kind == AgentEventKind.toolCompleted) {
          return const SizedBox.shrink(); // folded into the completion card
        }
        return _toolCard(context, index, e.toolName, e.argsPreview,
            running: true, isDark: isDark);
      case AgentEventKind.toolCompleted:
        return _toolCard(context, index, e.toolName, e.argsPreview,
            running: false,
            success: e.success,
            output: e.output,
            outputChars: e.outputChars,
            isDark: isDark);
      case AgentEventKind.checkpoint:
        return _checkpointChip(context, isDark);
      case AgentEventKind.complete:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                e.maxIterations ? Icons.error_outline : Icons.check_circle,
                size: 14,
                color: e.maxIterations
                    ? AppColors.warning
                    : Colors.green.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                e.maxIterations
                    ? 'Stopped at the iteration limit — continue with a follow-up prompt.'
                    : 'Done.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5, color: Theme.of(context).hintColor),
              ),
            ],
          ),
        );
      case AgentEventKind.error:
        return _errorCard(context, e.text, isDark);
      case AgentEventKind.cancelled:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.stop_circle_outlined,
                  size: 14, color: Colors.red),
              const SizedBox(width: 8),
              Text('Cancelled.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, color: Theme.of(context).hintColor)),
            ],
          ),
        );
    }
  }

  Widget _assistantCard(BuildContext context, String text, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 860),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.25),
          ),
        ),
        child: MarkdownBody(
          data: text,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.5, color: _textColor(context, isDark)),
            h1: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _textColor(context, isDark)),
            h2: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _textColor(context, isDark)),
            h3: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _textColor(context, isDark)),
            code: GoogleFonts.firaCode(
                fontSize: 11.5,
                backgroundColor:
                    isDark ? Colors.white10 : Colors.grey.shade200),
            codeblockDecoration: BoxDecoration(
              color: isDark ? const Color(0xFF111116) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            listBullet: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: _textColor(context, isDark)),
          ),
        ),
      ),
    );
  }

  Color _textColor(BuildContext context, bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1F2430);

  Widget _reasoningCard(
      BuildContext context, int index, String text, bool isDark) {
    final open = _expandedReasoning.contains(index);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          onExpansionChanged: (v) => v
              ? _expandedReasoning.add(index)
              : _expandedReasoning.remove(index),
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Icon(Icons.psychology_outlined,
              size: 16, color: Colors.purple.withValues(alpha: 0.8)),
          title: Text('Thinking',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          children: [
            SelectableText(
              text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(
    BuildContext context,
    int index,
    String tool,
    String args, {
    required bool running,
    bool success = true,
    String output = '',
    int outputChars = 0,
    required bool isDark,
  }) {
    final open = _expandedTools.contains(index);
    final hasOutput = !running && output.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: running
              ? Dt.accent.withValues(alpha: 0.4)
              : (success
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.red.withValues(alpha: 0.35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: hasOutput
                ? () => open
                    ? _expandedTools.remove(index)
                    : _expandedTools.add(index)
                : null,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      success
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 15,
                      color: success ? Colors.green : Colors.red,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: tool,
                            style: GoogleFonts.firaCode(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Dt.accent),
                          ),
                          if (args.isNotEmpty)
                            TextSpan(
                              text: '  ${args.length > 60 ? '${args.substring(0, 60)}…' : args}',
                              style: GoogleFonts.firaCode(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (outputChars > 0 && !hasOutput)
                    Text('${outputChars}ch',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: Theme.of(context).hintColor)),
                  if (hasOutput)
                    Icon(
                      open
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 14,
                      color: Theme.of(context).hintColor,
                    ),
                ],
              ),
            ),
          ),
          if (hasOutput && open)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF111116)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                output,
                style: GoogleFonts.firaCode(
                    fontSize: 11,
                    height: 1.45,
                    color: _textColor(context, isDark)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _checkpointChip(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.save_outlined,
              size: 13, color: Colors.orange.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Text('Checkpoint saved — you can roll back from the sidebar.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todoRow(BuildContext context, TodoItem t, bool isDark) {
    final done = t.status == 'completed';
    final active = t.status == 'in_progress';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : active
                    ? Icons.play_circle_rounded
                    : Icons.circle_outlined,
            size: 15,
            color: done
                ? Colors.green
                : active
                    ? Dt.accent
                    : Theme.of(context).hintColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.content,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                height: 1.4,
                decoration:
                    done ? TextDecoration.lineThrough : null,
                color: active ? Dt.accent : _textColor(context, isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Changed files strip (narrow screens; full pane in Files tab) ──

  Widget _changedFilesStrip(BuildContext context, bool isDark) {
    return Obx(() {
      final files = controller.changedFiles.toList();
      if (files.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Dt.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.fileDiff, size: 14, color: Dt.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${files.length} changed file${files.length == 1 ? '' : 's'} — review in Files tab',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5, color: Dt.accent),
              ),
            ),
            TextButton(
              onPressed: controller.running.value
                  ? null
                  : () => controller.acceptAll(),
              child: const Text('Accept all'),
            ),
          ],
        ),
      );
    });
  }

  // ── Composer ─────────────────────────────────────────────────────

  Widget _composer(BuildContext context, bool isDark) {
    return Container(
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
          _mentionSuggestions(context, isDark),
          // Attachment preview (chat-composer parity).
          Obx(() {
            final name = controller.selectedFileName.value;
            if (name == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AttachmentPreview(
                fileName: name,
                fileType: controller.selectedFileType.value,
                fileSize: controller.selectedFileSize.value > 0
                    ? controller.selectedFileSize.value
                    : null,
                imagePath: controller.selectedImagePath.value,
                imageBase64: controller.selectedImageBase64.value,
                onRemove: () {
                  controller.clearImage();
                  controller.clearFile();
                },
              ),
            );
          }),
          // STT listening indicator (chat-composer parity).
          Obx(() {
            if (!controller.isListening.value) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Text('Listening… speak now',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w700)),
              ),
            );
          }),
          TextField(
            controller: _promptCtrl,
            focusNode: _promptFocus,
            minLines: 1,
            maxLines: 5,
            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.4),
            decoration: InputDecoration(
              hintText:
                  'Describe a task — e.g. "add a settings screen with dark mode toggle". @ to mention files…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: Theme.of(context).hintColor),
              filled: true,
              fillColor:
                  isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          // Controls row — same shape as the chat composer:
          // + (add) / model pill / plan chip … mic / run-stop.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppCircleButton(
                icon: LucideIcons.plus,
                tooltip: 'Add to prompt',
                onTap: () {
                  if (!controller.running.value) {
                    showAddToChatSheet(
                      context,
                      isDark: isDark,
                      onCamera: controller.takePhoto,
                      onImage: controller.pickImage,
                      onFile: controller.pickFile,
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Obx(() {
                  // Touch an always-present observable first: the label
                  // getter reads none when SettingsController is missing
                  // (fresh install/tests), and a zero-observable Obx
                  // throws GetX's improper-use error.
                  controller.running.value;
                  return AppModelPill(
                    label: _agentModelLabel(),
                    onTap: () {
                      if (!controller.running.value) {
                        showModelSwitcherSheet(context);
                      }
                    },
                  );
                }),
              ),
              const SizedBox(width: 4),
              Obx(() => _modeChip(
                    context,
                    icon: LucideIcons.listOrdered,
                    label: controller.planMode.value ? 'Plan' : 'Build',
                    active: controller.planMode.value,
                    onTap: controller.running.value
                        ? null
                        : () => controller.planMode.value =
                            !controller.planMode.value,
                  )),
              Obx(() {
                final micAvailable = controller.sttAvailable.value ||
                    controller.isListening.value;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  if (micAvailable && !controller.running.value)
                    AppCircleButton(
                      icon: LucideIcons.mic,
                      tooltip: 'Voice input',
                      iconColor: controller.isListening.value
                          ? AppColors.error
                          : null,
                      onTap: () => controller.toggleListening(),
                    ),
                  if (micAvailable && !controller.running.value)
                    const SizedBox(width: 8),
                ]);
              }),
              Obx(() => FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: controller.running.value
                          ? AppColors.error
                          : Dt.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: Icon(controller.running.value
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                        size: 18),
                    label: Text(
                      controller.running.value ? 'Stop' : 'Run agent',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    onPressed: () {
                      if (controller.running.value) {
                        controller.cancel();
                      } else {
                        controller.prompt.value = _promptCtrl.text;
                        controller.run();
                      }
                    },
                  )),
            ],
          ),
          Obx(() => controller.error.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.error.value!,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5, color: AppColors.error),
                  ),
                )),
        ],
      ),
    );
  }

  /// Label for the workspace model pill (same shape as the chat
  /// composer's label, without the chat-pin logic).
  String _agentModelLabel() {
    String mode = 'cloud';
    try {
      if (Get.isRegistered<SettingsController>()) {
        mode = Get.find<SettingsController>().inferenceMode.value;
      }
    } catch (_) {}
    if (mode == 'cloud') {
      String m = '';
      try {
        final s = Get.find<SettingsController>();
        m = s.selectedCloudModelName;
      } catch (_) {}
      if (m.isEmpty) return 'Cloud';
      final short = m.contains('/') ? m.split('/').last : m;
      return short.length > 18 ? '${short.substring(0, 18)}…' : short;
    }
    String name = '';
    try {
      final inf = Get.find<InferenceService>();
      name = inf.isModelLoaded.value ? inf.loadedModelName.value : '';
    } catch (_) {}
    if (name.isEmpty) return 'Local';
    final stripped = name.replaceAll(
        RegExp(r'\.(gguf|litertlm|safetensors)$', caseSensitive: false), '');
    return stripped.length > 14 ? '${stripped.substring(0, 14)}…' : stripped;
  }

  Widget _modeChip(BuildContext context,
      {required IconData icon,
      required String label,
      required bool active,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Dt.accent.withValues(alpha: 0.14)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? Dt.accent : Dt.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active ? Dt.accent : Theme.of(context).hintColor),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? Dt.accent
                        : Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  // ── @-mentions ───────────────────────────────────────────────────

  /// Suggestions shown while the token after the last `@` matches files.
  String? _mentionTokenFrom(String text) {
    final at = text.lastIndexOf('@');
    if (at < 0) return null;
    final token = text.substring(at + 1);
    if (token.contains(' ') || token.contains('\n')) return null;
    if (at > 0 && text[at - 1] != ' ' && text[at - 1] != '\n') return null;
    return token.toLowerCase();
  }

  Widget _mentionSuggestions(BuildContext context, bool isDark) {
    // TextEditingController is not reactive — listen to the editing value
    // so suggestions track typing; Obx handles the files list.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _promptCtrl,
      builder: (context, value, _) => Obx(() {
        // Read the observable unconditionally first: when there is no
        // `@` token yet the guard below would short-circuit before
        // touching any Rx, and GetX then throws its improper-use error.
        final hasFiles = controller.files.isNotEmpty;
        final token = _mentionTokenFrom(value.text);
        if (token == null || !hasFiles) {
          return const SizedBox.shrink();
        }
        final matches = controller.files
            .where((f) => f.toLowerCase().contains(token))
            .take(6)
            .toList();
        if (matches.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            for (final f in matches)
              InkWell(
                onTap: () {
                  final text = _promptCtrl.text;
                  final at = text.lastIndexOf('@');
                  final mention = AgentRunnerController.sanitizeForMention(f);
                  _promptCtrl.text =
                      '${text.substring(0, at)}@$mention ';
                  _promptFocus.requestFocus();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      Icon(_fileIconFor(f),
                          size: 13, color: Theme.of(context).hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      }),
    );
  }

  // ── Chat switcher ────────────────────────────────────────────────

  void _openChatSwitcher(BuildContext context, AgentRunnerController c,
      TextEditingController input) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Obx(() {
          final list = c.chats.toList();
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New chat'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  c.newChat();
                  input.clear();
                },
              ),
              const Divider(height: 8),
              if (list.isEmpty)
                const ListTile(title: Text('No chats yet.')),
              for (final chat in list)
                ListTile(
                  selected: chat.id == c.activeChatId.value,
                  leading:
                      const Icon(Icons.chat_bubble_outline_rounded),
                  title: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    _chatSubtitle(chat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete chat',
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18),
                    onPressed: () => c.deleteChat(chat.id),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    c.selectChat(chat.id);
                    input.text = c.prompt.value;
                  },
                ),
            ],
          );
        }),
      ),
    );
  }

  String _chatSubtitle(AgentChat chat) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
        chat.updatedMs == 0 ? 0 : chat.updatedMs);
    final when =
        '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final preview = chat.prompt.trim().split('\n').first.trim();
    return preview.isEmpty ? when : '$when · $preview';
  }
}
