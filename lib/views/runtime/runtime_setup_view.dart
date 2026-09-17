/// CubicLM Runtime & Toolchains — guided setup (Toolkit).
///
/// Step 1 · System readiness → Step 2 · Toolchain picker (core Ubuntu +
/// opt-in Node/Python/Android/C++/PHP, same lineup as the reference app) →
/// Step 3 · Done (jump to Agent Workspace / Terminal).
///
/// Doubles as the manager: installed stacks show Remove, failed ones show
/// Retry, and the base URL (self-hosting) lives behind the overflow menu.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/runtime/runtime_installer.dart';
import '../../services/runtime/toolchain_catalog.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_snackbar.dart';
import '../agent/agent_workspace_view.dart';
import '../terminal/terminal_view.dart';

class RuntimeSetupView extends StatefulWidget {
  const RuntimeSetupView({super.key});

  @override
  State<RuntimeSetupView> createState() => _RuntimeSetupViewState();
}

class _RuntimeSetupViewState extends State<RuntimeSetupView> {
  int _step = 0;

  /// Isolated runtimes (PRoot + ARM64 rootfs) only exist on Android.
  /// Elsewhere the agent + terminal use the native host shell with the
  /// same approval gates — installs are disabled, never attempted.
  static bool get runtimeSupported => !kIsWeb && Platform.isAndroid;

  RuntimeInstaller get _installer {
    if (!Get.isRegistered<RuntimeInstaller>()) {
      Get.put(RuntimeInstaller());
    }
    return Get.find<RuntimeInstaller>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _installer.refresh();
      } catch (_) {}
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Runtime & Toolchains',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Bundle source (self-hosting)',
            icon: const Icon(LucideIcons.server, size: 18),
            onPressed: () => _editBaseUrl(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _stepper(context, isDark),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                0 => _readinessPane(context, isDark),
                1 => _toolchainsPane(context, isDark),
                _ => _donePane(context, isDark),
              },
            ),
          ),
          _navBar(context, isDark),
        ],
      ),
    );
  }

  // ── Stepper ────────────────────────────────────────────────────────

  Widget _stepper(BuildContext context, bool isDark) {
    const labels = ['Readiness', 'Toolchains', 'Done'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _dot(i, isDark, labels[i]),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i < _step
                      ? Dt.accent
                      : Theme.of(context).hintColor.withValues(alpha: 0.25),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i, bool isDark, String label) {
    final active = i == _step;
    final done = i < _step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? Dt.accent : Colors.transparent,
            border: Border.all(
              color: done || active
                  ? Dt.accent
                  : Theme.of(context).hintColor.withValues(alpha: 0.4),
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : Text(
                    '${i + 1}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : Theme.of(context).hintColor,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active ? null : Theme.of(context).hintColor,
          ),
        ),
      ],
    );
  }

  // ── Step 1: readiness ──────────────────────────────────────────────

  Widget _readinessPane(BuildContext context, bool isDark) {
    return Obx(() {
      final core = _installer.statuses[ToolchainId.core] ??
          const StackStatus();
      final rows = <({IconData icon, String title, String detail, bool ok})>[
        (
          icon: LucideIcons.smartphone,
          title: 'Platform',
          detail: Platform.isAndroid
              ? 'Android — full toolchain setup supported'
              : kIsWeb
                  ? 'Web — runtimes need Android or desktop'
                  : '${Platform.operatingSystem} — isolated runtimes are Android-only; the agent uses your native shell here',
          ok: true,
        ),
        (
          icon: LucideIcons.cpu,
          title: 'Architecture',
          detail: Platform.isAndroid
              ? 'ARM64 required for Core (checked before download)'
              : 'Host arch used for host-side tools',
          ok: true,
        ),
        (
          icon: LucideIcons.packageCheck,
          title: 'Core Ubuntu runtime',
          detail: core.state == ToolchainState.ready
              ? 'Installed — terminal + agent shell run isolated'
              : 'Not installed — install it in the next step (one-time download)',
          ok: core.state == ToolchainState.ready,
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mobile-Harness-style setup, CubicLM edition: one core Linux '
            'runtime, then pick only the stacks your projects need.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              height: 1.5,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 12),
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(r.icon, size: 18, color: Dt.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.detail,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            height: 1.4,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    r.ok
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: r.ok ? Colors.green : Theme.of(context).hintColor,
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  // ── Step 2: toolchain picker ───────────────────────────────────────

  Widget _toolchainsPane(BuildContext context, bool isDark) {
    return Obx(() {
      final stacks = ToolchainCatalog.stacks();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!runtimeSupported) _desktopNote(context, isDark),
          for (final s in stacks) _stackCard(context, isDark, s),
        ],
      );
    });
  }

  /// Honest non-Android banner (PLATFORM_DIFFERENCES §8.3): no dead
  /// install buttons, closest real alternative stated upfront.
  Widget _desktopNote(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Dt.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 16, color: Dt.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kIsWeb
                  ? 'Toolchain installs need Android or desktop — the web build is cloud-only.'
                  : 'Isolated Ubuntu runtimes need Android (PRoot). On desktop the agent workspace and terminal run in your native shell with the same approval gates — nothing to install here.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                height: 1.45,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stackCard(BuildContext context, bool isDark, ToolchainStack s) {
    final st =
        _installer.statuses[s.id] ?? const StackStatus();
    final busy = _installer.busy.value;
    final inFlight = st.state == ToolchainState.downloading ||
        st.state == ToolchainState.verifying ||
        st.state == ToolchainState.extracting;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: st.state == ToolchainState.ready
              ? Colors.green.withValues(alpha: 0.45)
              : isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      s.subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              _stateChip(st.state),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.downloadNote,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              height: 1.4,
              color: Theme.of(context).hintColor,
            ),
          ),
          if (inFlight || st.fraction > 0 && st.state != ToolchainState.ready) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: st.totalBytes > 0 ? st.fraction : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              st.line.isEmpty ? _stateLabel(st.state) : st.line,
              style: GoogleFonts.firaCode(
                fontSize: 10,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
          if (st.state == ToolchainState.failed && st.error != null) ...[
            const SizedBox(height: 6),
            Text(
              st.error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                height: 1.4,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!runtimeSupported)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                s.id == ToolchainId.core
                    ? 'Android-only runtime — install is disabled on this platform.'
                    : 'Needs the Core runtime (Android-only) — install is disabled on this platform.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          if (!s.available && runtimeSupported)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Bundle not published yet — coming soon.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          Row(
            children: [
              if (st.state == ToolchainState.ready)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label: const Text('Remove'),
                  onPressed: busy ? null : () => _installer.remove(s.id),
                )
              else if (inFlight)
                OutlinedButton.icon(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Cancel'),
                  onPressed: () => _installer.cancel(),
                )
              else if (!s.available && runtimeSupported)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .hintColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Coming soon',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: Text(st.state == ToolchainState.failed
                      ? 'Retry'
                      : 'Install'),
                  onPressed: busy || !runtimeSupported
                      ? null
                      : () => _installStack(s.id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stateChip(ToolchainState state) {
    final (label, color) = switch (state) {
      ToolchainState.ready => ('Ready', Colors.green),
      ToolchainState.downloading => ('Downloading', Dt.accent),
      ToolchainState.verifying => ('Verifying', Dt.accent),
      ToolchainState.extracting => ('Extracting', Dt.accent),
      ToolchainState.failed => ('Failed', Colors.red),
      _ => ('Not installed', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _stateLabel(ToolchainState s) => switch (s) {
        ToolchainState.downloading => 'Downloading…',
        ToolchainState.verifying => 'Verifying…',
        ToolchainState.extracting => 'Extracting…',
        _ => '',
      };

  Future<void> _installStack(ToolchainId id) async {
    final err = await _installer.install(id);
    if (!mounted) return;
    if (err != null && err != 'Cancelled.') {
      AppSnackbar.showTop('Install failed', err);
    } else if (err == null) {
      AppSnackbar.showTop(
        'Installed',
        '${ToolchainCatalog.stackOf(id).title} is ready.',
      );
      setState(() {});
    }
  }

  Future<void> _editBaseUrl(BuildContext context) async {
    final ctrl = TextEditingController(text: _installer.baseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bundle source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Where toolchain bundles download from. Point it at your own mirror to self-host.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _installer.setBaseUrl(ctrl.text);
      if (mounted) setState(() {});
    }
  }

  // ── Step 3: done ───────────────────────────────────────────────────

  Widget _donePane(BuildContext context, bool isDark) {
    return Obx(() {
      final ready = ToolchainCatalog.stacks()
          .where((s) =>
              (_installer.statuses[s.id]?.state ?? ToolchainState.unknown) ==
              ToolchainState.ready)
          .toList();
      final coreReady = ready.any((s) => s.id == ToolchainId.core);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            coreReady
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 48,
            color: coreReady ? Colors.green : Dt.accent,
          ),
          const SizedBox(height: 12),
          Text(
            coreReady
                ? 'Isolated runtime ready — agent + terminal run inside Ubuntu.'
                : 'Setup saved — install the Core runtime any time to unlock isolation.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w700, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            ready.isEmpty
                ? 'No stacks installed yet.'
                : 'Installed: ${ready.map((s) => s.title).join(', ')}',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(LucideIcons.bot, size: 16),
            label: const Text('Open Agent Workspace'),
            onPressed: () => Get.to(() => const AgentWorkspaceView()),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.terminal, size: 16),
            label: const Text('Open Terminal'),
            onPressed: () => Get.to(() => const TerminalView()),
          ),
        ],
      );
    });
  }

  // ── Nav ────────────────────────────────────────────────────────────

  Widget _navBar(BuildContext context, bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.grey.withValues(alpha: 0.25),
            ),
          ),
        ),
        child: Row(
          children: [
            if (_step > 0)
              TextButton(
                onPressed: _installer.busy.value
                    ? null
                    : () => setState(() => _step--),
                child: const Text('Back'),
              ),
            const Spacer(),
            if (_step < 2)
              FilledButton(
                onPressed: () => setState(() => _step++),
                child: Text(_step == 0 ? 'Choose toolchains' : 'Finish'),
              )
            else
              FilledButton(
                onPressed: () => Get.back(),
                child: const Text('Close'),
              ),
          ],
        ),
      ),
    );
  }
}
