/// Config-page sections mirroring the reference app's Settings —
/// "Developer tools" (per-stack Add / % / Installed with progress) and
/// "Linux runtime" (info rows, clear terminal history, reliability help).
///
/// Same behavior, Apple-grouped styling to match this screen. Installs
/// route through [RuntimeInstaller] (preflight blocks where unsupported),
/// terminal clearing through [TerminalService], developer options through
/// the `com.cubiclm.app/power` channel.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/runtime/runtime_installer.dart';
import '../../services/runtime/toolchain_catalog.dart';
import '../../services/setup_checklist_service.dart';
import '../../services/terminal/terminal_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import 'apple_widgets.dart';

RuntimeInstaller? _installer() =>
    Get.isRegistered<RuntimeInstaller>()
        ? Get.find<RuntimeInstaller>()
        : null;

// ── Developer tools ──────────────────────────────────────────────

/// "Developer tools" section: core note + one row per toolchain stack.
/// Reference parity: live `Core tools + N optional toolchain(s)`
/// caption, per-row Add / NN% / Installed trailing, progress bar +
/// message line while installing.
Widget buildDeveloperToolsSection(BuildContext context, bool isDark) {
  return Obx(() {
    final installer = _installer();
    final stacks = ToolchainCatalog.stacks();
    final installedCount = stacks
        .where((s) =>
            installer?.statuses[s.id]?.state == ToolchainState.ready)
        .length;
    final repo = installedCount == 1 ? 'toolchain' : 'toolchains';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionLabel(context, 'Developer tools'),
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 8),
          child: Text(
            'Core tools + $installedCount optional $repo',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).hintColor),
          ),
        ),
        appleGroupedCard(context, isDark, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              'Core Ubuntu ships the shell; stacks add Node, Python, Android, C++ and PHP.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Theme.of(context).hintColor),
            ),
          ),
          if (installer == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text('Runtime service starting…'),
            )
          else ...[
            for (var i = 0; i < stacks.length; i++) ...[
              _stackRow(context, isDark, installer, stacks[i],
                  i < stacks.length - 1),
            ],
            if (!SetupChecklist.supportsRuntimeInstall)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Text(
                  'Isolated installs need Android — on this platform the agent uses your native shell.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).hintColor),
                ),
              ),
          ],
        ]),
      ],
    );
  });
}

Widget _stackRow(BuildContext context, bool isDark,
    RuntimeInstaller installer, ToolchainStack s, bool showDivider) {
  final st = installer.statuses[s.id] ?? const StackStatus();
  final busy = installer.busy.value;
  final installing = st.state == ToolchainState.downloading ||
      st.state == ToolchainState.verifying ||
      st.state == ToolchainState.extracting;
  final installed = st.state == ToolchainState.ready;
  return Column(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(s.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Theme.of(context).hintColor)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (installing)
          Text(
            '${(st.fraction.clamp(0.0, 1.0) * 100).toInt()}%',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, color: Dt.accent),
          )
        else if (installed)
          Text('Installed',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Theme.of(context).hintColor))
        else if (!s.available)
          Text('Coming soon',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).hintColor))
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: !SetupChecklist.supportsRuntimeInstall || busy
                ? null
                : () async {
                    final err = await installer.install(s.id);
                    if (err != null) {
                      AppSnackbar.showTop('Install failed', err);
                    }
                  },
            child: const Text('Add'),
          ),
      ]),
    ),
    if (installing) ...[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: LinearProgressIndicator(
          value: st.fraction > 0 ? st.fraction.clamp(0.0, 1.0) : null,
          minHeight: 4,
          backgroundColor:
              Theme.of(context).hintColor.withValues(alpha: 0.15),
          valueColor: const AlwaysStoppedAnimation(Dt.accent),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            st.line.isEmpty ? 'Installing…' : st.line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: Theme.of(context).hintColor),
          ),
        ),
      ),
    ],
    if (showDivider)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03)),
      ),
  ]);
}

// ── Linux runtime ────────────────────────────────────────────────

/// "Linux runtime" section: info rows, clear-terminal-history,
/// reliability help. Reference parity including the post-tap label flip.
class LinuxRuntimeSection extends StatefulWidget {
  final bool isDark;
  const LinuxRuntimeSection({super.key, required this.isDark});

  @override
  State<LinuxRuntimeSection> createState() => _LinuxRuntimeSectionState();
}

class _LinuxRuntimeSectionState extends State<LinuxRuntimeSection> {
  bool _cleared = false;
  bool _showHelp = false;

  String _archLabel() {
    if (kIsWeb) return 'Web (cloud-only)';
    if (Platform.isAndroid) return 'ARM64 (aarch64)';
    return '${Platform.operatingSystem} (host shell)';
  }

  Future<void> _clearHistory() async {
    try {
      if (Get.isRegistered<TerminalService>()) {
        Get.find<TerminalService>().clearAll();
      }
    } catch (_) {}
    if (mounted) setState(() => _cleared = true);
  }

  Future<void> _openDevOptions() async {
    final ok = await SetupChecklist.openDeveloperOptions();
    if (!mounted) return;
    if (!ok) {
      AppSnackbar.showTop(
        'Could not open settings',
        'Open Developer options manually.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Obx(() {
      final installer = _installer();
      final coreReady =
          installer?.statuses[ToolchainId.core]?.state ==
              ToolchainState.ready;
      final nodeReady =
          installer?.statuses[ToolchainId.node]?.state ==
              ToolchainState.ready;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionLabel(context, 'Linux runtime'),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text(
              'Ubuntu 20.04 PRoot · ARM64',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).hintColor),
            ),
          ),
          appleGroupedCard(context, isDark, children: [
            _infoRow(context, 'Architecture', _archLabel()),
            _infoRow(
              context,
              'Environment',
              coreReady
                  ? 'Ubuntu 20.04 PRoot'
                  : 'Ubuntu 20.04 PRoot · not installed',
            ),
            _infoRow(
              context,
              'Agent',
              nodeReady
                  ? 'CubicLM agent + Node.js 24'
                  : 'CubicLM agent',
              last: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(LucideIcons.trash2, size: 17),
                  label: Text(_cleared
                      ? 'Terminal history cleared'
                      : 'Clear terminal history'),
                  onPressed: _clearHistory,
                ),
              ),
            ),
            if (SetupChecklist.isAndroid)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => setState(
                            () => _showHelp = !_showHelp),
                        child: const Text(
                            'Advanced runtime reliability'),
                      ),
                    ),
                    if (_showHelp) ...[
                      const SizedBox(height: 8),
                      Text(
                        'If large builds stop unexpectedly, Android Developer options may provide a child-process restriction toggle.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Theme.of(context).hintColor),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Dt.accent),
                          onPressed: _openDevOptions,
                          child: const Text('Open Developer options'),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else
              const SizedBox(height: 14),
          ]),
        ],
      );
    });
  }

  Widget _infoRow(BuildContext context, String label, String value,
      {bool last = false}) {
    return Column(children: [
      Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Theme.of(context).hintColor)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      if (!last)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
              height: 1,
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03)),
        ),
    ]);
  }
}
