/// Explore MCP tab: server list, approval, enable flow.
///
/// Split from `explore_skills_mcp_tabs.dart` - behavior is unchanged.
/// Contains: ExploreMcpTab(), createState(), _openSheet(), _confirmDelete(), _approvalRow(), _toggleEnable()
///   build(), _serverTile(), _statusDot(), _statusBanner(), _confirmEnable()
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../services/mcp/mcp_config.dart';
import '../services/mcp/mcp_connection.dart';
import '../services/mcp/mcp_registry_service.dart';
import '../services/hive_service.dart';
import '../theme/design_tokens.dart';

import 'mcp_server_sheet.dart';

// â”€â”€ Explore MCP Tab â”€â”€

class ExploreMcpTab extends StatefulWidget {
  const ExploreMcpTab({super.key});
  @override
  State<ExploreMcpTab> createState() => _ExploreMcpTabState();
}

class _ExploreMcpTabState extends State<ExploreMcpTab> {
  McpRegistryService get _reg => Get.find<McpRegistryService>();

  Future<void> _openSheet({McpConfig? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => McpServerSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, bool isDark, McpConfig cfg) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Remove server?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text('This deletes "${cfg.name}" and its token.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Get.back(result: true),
            child: const Text('Remove')),
      ],
    ));
    if (ok == true) await _reg.removeConfig(cfg.id);
  }

  /// Ask-before-run toggle for MCP tool calls (Deny / Allow once / Always).
  /// Same Hive key the cloud provider's approval gate reads.
  Widget _approvalRow(BuildContext context) {
    final hive = Get.find<HiveService>();
    final require =
        hive.getSetting<bool>('mcp_require_approval', defaultValue: true) ??
            true;
    return Row(children: [
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ask before running tools',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w700)),
        Text('Model shows Deny / Allow once / Always',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: Theme.of(context).hintColor)),
      ])),
      Switch.adaptive(
        value: require,
        activeThumbColor: Dt.accent,
        onChanged: (v) async {
          await hive.setSetting('mcp_require_approval', v);
          if (mounted) setState(() {});
        },
      ),
    ]);
  }

  Future<void> _toggleEnable(
      BuildContext context, bool isDark, McpConfig cfg, bool v) async {    if (!v) {
      await _reg.setEnabled(cfg.id, false);
      return;
    }
    // Enable first (connects), then confirm with the real tool list â€”
    // matches the old single-server flow.
    await _reg.setEnabled(cfg.id, true);
    final mine = _reg.toolsFor(cfg.id);
    if (mine.isNotEmpty && context.mounted) {
      final ok = await _confirmEnable(context, isDark, mine);
      if (ok != true) await _reg.setEnabled(cfg.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final servers = _reg.configs.toList();
      final status = _reg.status.value;
      final tools = _reg.tools.toList();
      final err = _reg.lastError.value;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: isDark ? AppColors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Dt.hairline)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(color: Dt.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(LucideIcons.plug, size: 18, color: Dt.accent)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('MCP Servers',
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                    servers.isEmpty
                        ? 'Connect remote HTTP/SSE servers â€” no marketplace'
                        : '${servers.length} server${servers.length == 1 ? '' : 's'} Â· ${tools.length} tools',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
              ])),
              _statusDot(status),
            ]),
            const SizedBox(height: 12),
            _statusBanner(status, err, tools, isDark),
            const SizedBox(height: 12),
            _approvalRow(context),
          ]),
        ),
        const SizedBox(height: 12),
        for (final cfg in servers) _serverTile(context, isDark, cfg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openSheet(),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text('Add server',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Dt.accent,
              side: BorderSide(color: Dt.accent.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        if (tools.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Dt.pillMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Exposed tools â€” model will see these',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
              const SizedBox(height: 8),
              for (final t in tools)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: Dt.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(LucideIcons.wrench, size: 14, color: Dt.accent)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                        if (t.description.isNotEmpty)
                          Text(t.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                      ])),
                    ])),
            ]),
          ),
        ],
      ]);
    });
  }

  Widget _serverTile(BuildContext context, bool isDark, McpConfig cfg) {
    final st = _reg.statusOf(cfg.id);
    final err = _reg.errors[cfg.id] ?? '';
    final toolCount = _reg.toolsFor(cfg.id).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: isDark ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Dt.hairline)),
      child: Row(children: [
        _statusDot(st),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Flexible(
                  child: Text(cfg.name.isEmpty ? 'MCP Server' : cfg.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                if (toolCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('$toolCount tools',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success))),
                ],
              ]),
              const SizedBox(height: 2),
              Text(cfg.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Theme.of(context).hintColor)),
              if (st == McpStatus.error && err.isNotEmpty)
                Text(err,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: AppColors.error)),
            ])),
        Switch(
          value: cfg.enabled,
          activeThumbColor: Dt.accent,
          onChanged: (v) => _toggleEnable(context, isDark, cfg, v),
        ),
        IconButton(
          tooltip: 'Edit server',
          icon: const Icon(LucideIcons.pencil, size: 18),
          onPressed: () => _openSheet(existing: cfg),
        ),
        IconButton(
          tooltip: 'Remove server',
          icon: const Icon(LucideIcons.trash2,
              size: 18, color: AppColors.error),
          onPressed: () => _confirmDelete(context, isDark, cfg),
        ),
      ]),
    );
  }
  Widget _statusDot(McpStatus s) {    final color = switch (s) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Colors.grey,
    };
    return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: s == McpStatus.connected
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
                : null));
  }

  Widget _statusBanner(McpStatus status, String err, List<McpTool> tools, bool isDark) {
    final text = switch (status) {
      McpStatus.connected => tools.isEmpty ? 'Connected â€” no tools exposed' : 'Connected â€” ${tools.length} tool(s) ready',
      McpStatus.connecting => 'Connectingâ€¦',
      McpStatus.error => err.isNotEmpty ? err : 'Connection error',
      McpStatus.disconnected => 'Not connected â€” save and test your server',
    };
    final color = switch (status) {
      McpStatus.connected => AppColors.success,
      McpStatus.connecting => AppColors.warning,
      McpStatus.error => AppColors.error,
      McpStatus.disconnected => Theme.of(Get.context!).hintColor,
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(children: [
          Icon(
              switch (status) {
                McpStatus.connected => LucideIcons.checkCircle,
                McpStatus.connecting => LucideIcons.loader2,
                McpStatus.error => LucideIcons.alertTriangle,
                McpStatus.disconnected => LucideIcons.info,
              },
              size: 16,
              color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
        ]));
  }

  Future<bool?> _confirmEnable(BuildContext context, bool isDark, List<McpTool> tools) {
    return Get.dialog<bool>(AlertDialog(
      backgroundColor: isDark ? Dt.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Enable MCP tools?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('The model will be able to call these tools. Review them before enabling.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
        const SizedBox(height: 12),
        for (final t in tools)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(LucideIcons.wrench, size: 14, color: Dt.accent),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
                  if (t.description.isNotEmpty)
                    Text(t.description,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Theme.of(context).hintColor)),
                ])),
              ])),
      ])),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Dt.accent),
            onPressed: () => Get.back(result: true),
            child: const Text('Enable')),
      ],
    ));
  }
}
