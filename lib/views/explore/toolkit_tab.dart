import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../agent/agent_workspace_view.dart';
import '../agent_ide_view.dart';
import '../battle_arena_view.dart';
import '../cubicapp_builder_view.dart';
import '../cubicdata/datasheet_home_view.dart';
import '../cubicweb/browser_view.dart';
import '../runtime/runtime_setup_view.dart';
import '../slide_deck_view.dart';
import '../terminal/terminal_view.dart';

/// Explore Toolkit tab cards.
/// Extracted from views/model_view.dart (one responsibility per file).

class _ToolSpec {
  final IconData icon;
  final String title;
  final String description;
  final Widget Function() open;

  const _ToolSpec({
    required this.icon,
    required this.title,
    required this.description,
    required this.open,
  });
}

List<_ToolSpec> _toolSpecs() => [
      _ToolSpec(
        icon: LucideIcons.bot,
        title: 'Agent Workspace',
        description:
            'General coding agent: describe any task — explore, edit, test, commit — with tool approvals, per-file undo and checkpoint rollback. Cloud or on-device.',
        open: () => const AgentWorkspaceView(),
      ),
      _ToolSpec(
        icon: LucideIcons.terminal,
        title: 'Terminal',
        description:
            'Sandboxed on-device shell with streaming output and history. Destructive commands are blocked automatically.',
        open: () => const TerminalView(),
      ),
      _ToolSpec(
        icon: LucideIcons.package,
        title: 'Runtime & Toolchains',
        description:
            'One core Ubuntu runtime, then only the stacks you need — Node, Python, Android, C++, PHP. Isolated agent + terminal execution, on-device.',
        open: () => const RuntimeSetupView(),
      ),
      _ToolSpec(
        icon: LucideIcons.swords,
        title: 'Battle Arena',
        description:
            'Race up to 4 cloud models on one prompt — same-time or one-by-one (on-device allowed). Live monitor ranks finish, speed and length, then declares an overall winner.',
        open: () => const BattleArenaView(),
      ),
      _ToolSpec(
        icon: LucideIcons.presentation,
        title: 'Slide Maker',
        description:
            'AI designs every slide from a topic — Docs / Slides / PDF views, freehand move + resize, manual photos, per-slide regen. Exports Markdown, PDF and web slides.',
        open: () => const SlideDeckView(),
      ),
      _ToolSpec(
        icon: LucideIcons.terminalSquare,
        title: 'CubicWeb Builder',
        description:
            'Agent IDE: tell AI what to build — websites in any framework, live preview, console-error auto-fix, file explorer. Static + ESM runs on-device.',
        open: () => const AgentIdeView(),
      ),
      _ToolSpec(
        icon: LucideIcons.smartphone,
        title: 'CubicApp Builder',
        description:
            'Build Android apps with AI — pick a template, describe your app, export ZIP with GitHub Actions workflow. Push to GitHub for automatic APK build.',
        open: () => const CubicAppBuilderView(),
      ),
      _ToolSpec(
        icon: LucideIcons.tableProperties,
        title: 'CubicDataSheet',
        description:
            'Personal sheets + docs workspace: formulas, cell locks with unlock mode, per-cell copy, notes and history. Stored on this device only.',
        open: () => const DataSheetHomeView(),
      ),
      _ToolSpec(
        icon: LucideIcons.globe,
        title: 'CubicWeb Browser',
        description:
            'Private in-app browser: ads and trackers blocked from a built-in list, no history saved. Extract any page into chat for the local model.',
        open: () => const BrowserView(),
      ),
    ];

Widget buildToolkitTab(BuildContext context, {String query = ''}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final q = query.trim().toLowerCase();
  final specs = _toolSpecs();
  final shown = q.isEmpty
      ? specs
      : specs
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q))
          .toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        q.isEmpty
            ? 'AI power tools — same engine as chat, focused workspaces.'
            : '${shown.length} result${shown.length == 1 ? '' : 's'} for "$query"',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12.5,
          color: Theme.of(context).hintColor,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 12),
      for (int i = 0; i < shown.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _toolkitCard(
          context,
          isDark,
          icon: shown[i].icon,
          title: shown[i].title,
          experimental: true,
          description: shown[i].description,
          onTap: () => Get.to(shown[i].open),
        ),
      ],
      if (shown.isEmpty) ...[
        const SizedBox(height: 32),
        Center(
          child: Text(
            'No tools match your search.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      ],
    ],
  );
}

Widget _toolkitCard(
  BuildContext context,
  bool isDark, {
  required IconData icon,
  required String title,
  required String description,
  required VoidCallback onTap,
  bool experimental = false,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Dt.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: Dt.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    if (experimental) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'EXPERIMENTAL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(LucideIcons.chevronRight,
              size: 18, color: Theme.of(context).hintColor),
        ],
      ),
    ),
  );
}
