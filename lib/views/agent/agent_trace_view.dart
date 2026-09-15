/// CubicLM Agentic Workspace — execution trace timeline widget.
///
/// Renders the [AgentEvent] stream as a compact, readable feed.
/// Stateless + dependency-free (takes events as a parameter).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/agent/agent_types.dart';
import '../../theme/design_tokens.dart';

/// Scrollable trace feed for an agent run.
class AgentTraceView extends StatelessWidget {
  final List<AgentEvent> events;

  const AgentTraceView({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No activity yet — describe a task and press Run.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _eventCard(context, events[i]),
    );
  }

  Widget _eventCard(BuildContext context, AgentEvent e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    IconData icon;
    Color color;
    String label;
    switch (e.kind) {
      case AgentEventKind.text:
        icon = Icons.chat_bubble_outline;
        color = Dt.accent;
        label = e.text;
        break;
      case AgentEventKind.reasoning:
        icon = Icons.psychology_outlined;
        color = Colors.purple;
        label = e.text;
        break;
      case AgentEventKind.toolStarted:
        icon = Icons.play_arrow_rounded;
        color = Colors.blue;
        label = 'Running ${e.toolName}…';
        break;
      case AgentEventKind.toolCompleted:
        icon = e.success ? Icons.check_circle_outline : Icons.error_outline;
        color = e.success ? Colors.green : Colors.red;
        label = e.success
            ? '${e.toolName} done (${e.outputChars} chars)'
            : '${e.toolName} failed';
        break;
      case AgentEventKind.checkpoint:
        icon = Icons.save_outlined;
        color = Colors.orange;
        label = 'Checkpoint saved';
        break;
      case AgentEventKind.complete:
        icon = Icons.flag_outlined;
        color = Colors.green;
        label = e.maxIterations
            ? 'Stopped: iteration limit reached'
            : 'Done';
        break;
      case AgentEventKind.error:
        icon = Icons.warning_amber_rounded;
        color = Colors.red;
        label = e.text;
        break;
      case AgentEventKind.cancelled:
        icon = Icons.stop_circle_outlined;
        color = Colors.grey;
        label = 'Cancelled';
        break;
    }

    final isText = e.kind == AgentEventKind.text;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              label.length > 2000 ? '${label.substring(0, 2000)}…' : label,
              style: isText
                  ? GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5)
                  : GoogleFonts.firaCode(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
