/// CubicLM Agentic Workspace — main agent screen.
///
/// Prompt → general agent loop (cloud or on-device) with a live execution
/// trace, per-file undo/accept, and checkpoint rollback. File tools are
/// jailed to the selected project; pick none to run Q&A without files.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/agent_runner_controller.dart';
import '../../core/colors.dart';
import '../../services/agent_workspace.dart';
import '../../theme/design_tokens.dart';
import 'agent_trace_view.dart';

/// Main agent workspace screen (reached from Toolkit → Agent Workspace).
class AgentWorkspaceView extends StatelessWidget {
  const AgentWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<AgentRunnerController>()
        ? Get.find<AgentRunnerController>()
        : Get.put(AgentRunnerController());
    final input = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agent Workspace',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        actions: [
          Obx(() => Row(
                children: [
                  Text('Local',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                  Switch(
                    value: controller.useLocal.value,
                    activeThumbColor: Dt.accent,
                    onChanged: controller.running.value
                        ? null
                        : (v) => controller.useLocal.value = v,
                  ),
                ],
              )),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _projectPicker(controller),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Obx(() => OutlinedButton.icon(
                        icon: controller.importing.value
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_rounded,
                                size: 16),
                        label: const Text('Import folder'),
                        onPressed: controller.importing.value ||
                                controller.running.value
                            ? null
                            : () => controller.importFolder(),
                      )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Obx(() => Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Plan first',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12)),
                          Switch(
                            value: controller.planMode.value,
                            activeThumbColor: Dt.accent,
                            onChanged: controller.running.value
                                ? null
                                : (v) =>
                                    controller.planMode.value = v,
                          ),
                        ],
                      )),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              minLines: 2,
              maxLines: 5,
              onChanged: (v) => controller.prompt.value = v,
              decoration: InputDecoration(
                hintText:
                    'Describe a task — e.g. "add a settings screen with dark mode toggle"…',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Obx(() => FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: controller.running.value
                        ? AppColors.error
                        : Dt.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(controller.running.value
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(
                    controller.running.value ? 'Stop' : 'Run agent',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    if (controller.running.value) {
                      controller.cancel();
                    } else {
                      controller.prompt.value = input.text;
                      controller.run();
                    }
                  },
                )),
            Obx(() => controller.error.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      controller.error.value!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: AppColors.error),
                    ),
                  )),
            const SizedBox(height: 16),
            Obx(() => controller.todos.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle(context, 'Plan'),
                      const SizedBox(height: 8),
                      _todoList(context, controller, isDark),
                      const SizedBox(height: 16),
                    ],
                  )),
            _sectionTitle(context, 'Trace'),
            const SizedBox(height: 8),
            Obx(() => AgentTraceView(events: controller.events.toList())),
            const SizedBox(height: 16),
            _sectionTitle(context, 'Changed files'),
            const SizedBox(height: 8),
            Obx(() => _changedFiles(context, controller, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 14, fontWeight: FontWeight.w800),
    );
  }

  Widget _projectPicker(AgentRunnerController controller) {
    if (!Get.isRegistered<AgentWorkspaceService>()) {
      return const SizedBox.shrink();
    }
    final ws = Get.find<AgentWorkspaceService>();
    return Obx(() {
      final projects = ws.projects.toList();
      return DropdownButtonFormField<String?>(
        initialValue: controller.projectId.value,
        decoration: InputDecoration(
          labelText: 'Project (optional — file tools jail here)',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(
              value: null, child: Text('No project (Q&A only)')),
          for (final p in projects)
            DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
        ],
        onChanged: controller.running.value
            ? null
            : (v) => controller.projectId.value = v,
      );
    });
  }

  Widget _todoList(BuildContext context,
      AgentRunnerController controller, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          for (final t in controller.todos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    t.status == 'completed'
                        ? Icons.check_circle_rounded
                        : t.status == 'in_progress'
                            ? Icons.play_circle_rounded
                            : Icons.circle_outlined,
                    size: 16,
                    color: t.status == 'completed'
                        ? Colors.green
                        : t.status == 'in_progress'
                            ? Dt.accent
                            : Theme.of(context).hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.content,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.4,
                        decoration: t.status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _changedFiles(BuildContext context,
      AgentRunnerController controller, bool isDark) {
    final files = controller.changedFiles.toList();
    final cpId = controller.checkpointId.value;
    if (files.isEmpty && cpId == null) {
      return Text(
        'No changes yet.',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12, color: Theme.of(context).hintColor),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in files)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(f,
                      style:
                          GoogleFonts.firaCode(fontSize: 12)),
                ),
                TextButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.acceptFile(f),
                  child: const Text('Accept'),
                ),
                TextButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.undoFile(f),
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
        if (files.isNotEmpty || cpId != null)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.undoAll(),
                child: const Text('Undo all'),
              ),
              OutlinedButton(
                onPressed: controller.running.value
                    ? null
                    : () => controller.acceptAll(),
                child: const Text('Accept all'),
              ),
              if (cpId != null)
                OutlinedButton(
                  onPressed: controller.running.value
                      ? null
                      : () => controller.rollbackCheckpoint(),
                  child: const Text('Rollback checkpoint'),
                ),
            ],
          ),
      ],
    );
  }
}
