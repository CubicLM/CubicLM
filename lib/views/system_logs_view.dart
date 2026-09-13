/// CubicWeb System Logs — developer diagnostics console (§19).
///
/// Lists structured RUNTIME/PLATFORM events (never user-code errors —
/// those stay on the AI path). Severity filters, text search, detail
/// sheets with evidence + contextual actions, clear-all.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/agent_controller.dart';
import '../core/colors.dart';
import '../services/cubicweb/cubicweb_event.dart';
import '../services/cubicweb/cubicweb_logger.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';

class SystemLogsView extends StatefulWidget {
  const SystemLogsView({super.key});

  @override
  State<SystemLogsView> createState() => _SystemLogsViewState();
}

class _SystemLogsViewState extends State<SystemLogsView> {
  CwSeverity? _sevFilter;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      Get.find<CubicWebLogger>().markAllRead();
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _getSeverityColor(CwSeverity? severity) {
    switch (severity) {
      case CwSeverity.error:
        return AppColors.error;
      case CwSeverity.warning:
        return const Color(0xFFFBBF24);
      case CwSeverity.info:
        return const Color(0xFF3B82F6);
      default:
        return Dt.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    CubicWebLogger logger;
    try {
      logger = Get.find<CubicWebLogger>();
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('CubicWeb System Logs')),
        body: const Center(child: Text('Logger unavailable.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CubicWeb System Logs',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 18)),
            Obx(() {
              final n = logger.events.length;
              return Text(
                  n == 0
                      ? 'No system events'
                      : '$n event${n == 1 ? '' : 's'} (newest first)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor));
            }),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search code, message, project, command…',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: Theme.of(context).hintColor.withValues(alpha: 0.7)),
                prefixIcon: Icon(LucideIcons.search, size: 18, color: Theme.of(context).hintColor),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Dt.accent, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            icon: const Icon(LucideIcons.trash2, size: 20),
            onPressed: () async {
              final ok = await Get.dialog<bool>(AlertDialog(
                title: Text('Clear System Logs?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                content: Text(
                    'Removes all stored diagnostics (in-memory + persisted).',
                    style: GoogleFonts.plusJakartaSans()),
                actions: [
                  TextButton(
                      onPressed: () => Get.back(result: false),
                      child: Text('Cancel', style: GoogleFonts.plusJakartaSans())),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error),
                    onPressed: () => Get.back(result: true),
                    child: Text('Clear', style: GoogleFonts.plusJakartaSans()),
                  ),
                ],
              ));
              if (ok == true) {
                await logger.clear();
                if (context.mounted) setState(() {});
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip(context, 'All', null),
              const SizedBox(width: 8),
              _filterChip(context, 'Errors', CwSeverity.error),
              const SizedBox(width: 8),
              _filterChip(context, 'Warnings', CwSeverity.warning),
              const SizedBox(width: 8),
              _filterChip(context, 'Info', CwSeverity.info),
            ]),
          ),
        ),
        Expanded(
          child: Obx(() {
            final items = logger.events.reversed.where((e) {
              if (_sevFilter != null && e.severity != _sevFilter) {
                return false;
              }
              final q = _query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return e.errorCode.toLowerCase().contains(q) ||
                  e.title.toLowerCase().contains(q) ||
                  e.message.toLowerCase().contains(q) ||
                  e.projectId.toLowerCase().contains(q) ||
                  e.component.toLowerCase().contains(q) ||
                  e.command.toLowerCase().contains(q) ||
                  e.traceId.toLowerCase().contains(q);
            }).toList();
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.terminal, size: 40, color: Theme.of(context).hintColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        logger.events.isEmpty
                            ? 'No system events yet.\nRuntime and platform failures will appear here — code errors stay with the AI debugger.'
                            : 'No events match this filter.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              itemBuilder: (_, i) => _eventCard(context, isDark, items[i]),
            );
          }),
        ),
      ]),
    );
  }

  Widget _filterChip(BuildContext context, String label, CwSeverity? sev) {
    final selected = _sevFilter == sev;
    final chipColor = _getSeverityColor(sev);
    return InkWell(
      onTap: () => setState(() => _sevFilter = sev),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withValues(alpha: 0.15)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? chipColor.withValues(alpha: 0.4)
                  : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sev != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: chipColor),
              ),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected ? chipColor : Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(BuildContext context, bool isDark, SystemLogEvent e) {
    final accentColor = _getSeverityColor(e.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        // Accent stripe via left border — avoids the IntrinsicHeight +
        // stretch Row pair that mis-measures unbounded text (~14px
        // bottom overflow on device).
        child: Container(
          decoration: BoxDecoration(
            border:
                Border(left: BorderSide(width: 4, color: accentColor)),
          ),
          child: InkWell(
            onTap: () => _showDetail(context, e),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                          Row(
                            children: [
                              if (e.errorCode.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(e.errorCode,
                                      style: GoogleFonts.firaCode(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: accentColor)),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF1E293B))),
                              ),
                              if (e.occurrenceCount > 1)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('×${e.occurrenceCount}',
                                      style: GoogleFonts.firaCode(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: accentColor)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                    '${e.component} · ${e.category.name.toUpperCase()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).hintColor)),
                              ),
                              Text(_fmtTime(e.lastAtMs),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).hintColor)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(e.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: isDark ? Colors.white70 : const Color(0xFF475569))),
                          if (!e.aiCanFix) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.alertTriangle, size: 12, color: AppColors.error),
                                  const SizedBox(width: 4),
                                  Text("Environment Issue — AI can't fix automatically",
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.error)),
                                ],
                              ),
                            ),
                          ],
                        ]),
                  ),
                ),
        ),
      ),
    );
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final t = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
      return t;
    }
    return '$t · ${d.month}/${d.day}';
  }

  void _showDetail(BuildContext context, SystemLogEvent e) {
    final c = Get.isRegistered<AgentController>() ? Get.find<AgentController>() : null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetCtx).hintColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Text(e.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).hintColor.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).hintColor.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    _kv('Error code', e.errorCode.isEmpty ? '—' : e.errorCode, mono: true),
                    _kv('Severity', e.severity.name.toUpperCase()),
                    _kv('Category', e.category.name.toUpperCase()),
                    _kv('Component', e.component),
                    _kv('Time', _fmtTime(e.timestampMs)),
                    _kv('Trace ID', e.traceId, mono: true),
                    if (e.projectId.isNotEmpty) _kv('Project', e.projectId, mono: true),
                    if (e.operation.isNotEmpty) _kv('Operation', e.operation, mono: true),
                    if (e.command.isNotEmpty) _kv('Command', e.command, mono: true),
                    if (e.exitCode != null) _kv('Exit code', '${e.exitCode}'),
                    if (e.platform.isNotEmpty) _kv('Platform', e.platform, mono: true),
                    if (e.runtime.isNotEmpty) _kv('Runtime', e.runtime, mono: true),
                    _kv('AI can fix', e.aiCanFix ? 'Yes — route to AI debugger' : 'No — environment issue'),
                    if (e.fallbackAvailable.isNotEmpty) _kv('Fallback', e.fallbackAvailable, mono: true),
                    if (e.fallbackUsed.isNotEmpty) _kv('Fallback used', e.fallbackUsed, mono: true),
                    if (e.occurrenceCount > 1)
                      _kv('Occurrences', '×${e.occurrenceCount} (first ${_fmtTime(e.firstAtMs)}, last ${_fmtTime(e.lastAtMs)})'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Log Message', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SelectableText(e.message,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5, color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.85))),
              if (e.technicalDetails.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Technical details & evidence',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(e.technicalDetails,
                          style: GoogleFonts.firaCode(
                              fontSize: 11,
                              height: 1.5,
                              color: const Color(0xFFE2E8F0))),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: '${e.errorCode.isEmpty ? e.title : '${e.errorCode} — ${e.title}'}\n${e.message}'));
                    Get.back();
                    AppSnackbar.showTop('Copied', 'Error summary copied.', logHistory: false);
                  },
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: const Text('Copy Error'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _fullExport(e)));
                    Get.back();
                    AppSnackbar.showTop('Copied', 'Full details copied.', logHistory: false);
                  },
                  icon: const Icon(LucideIcons.clipboardList, size: 16),
                  label: const Text('Copy Details'),
                ),
                if (e.fallbackAvailable == 'USE_CLOUD_RUNTIME' && c != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Dt.accent),
                    onPressed: () {
                      Get.back();
                      c.useCloudFallback();
                    },
                    icon: const Icon(LucideIcons.cloud, size: 16),
                    label: const Text('Use Cloud'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Get.back(),
                  icon: const Icon(LucideIcons.cornerUpLeft, size: 16),
                  label: const Text('Close'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 115,
          child: Text(k,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Dt.textSecondary, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: SelectableText(v,
              style: mono
                  ? GoogleFonts.firaCode(fontSize: 11.5, color: Dt.accent)
                  : GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  String _fullExport(SystemLogEvent e) {
    final b = StringBuffer()
      ..writeln('${e.errorCode.isEmpty ? '' : '${e.errorCode} — '}${e.title}')
      ..writeln('Severity: ${e.severity.name} · Category: ${e.category.name} · Component: ${e.component}')
      ..writeln('Trace: ${e.traceId} · Occurrences: ${e.occurrenceCount}')
      ..writeln(e.message);
    if (e.command.isNotEmpty) b.writeln('Command: ${e.command}');
    if (e.exitCode != null) b.writeln('Exit: ${e.exitCode}');
    if (e.technicalDetails.isNotEmpty) {
      b.writeln('--- evidence ---');
      b.writeln(e.technicalDetails);
    }
    return b.toString();
  }
}
