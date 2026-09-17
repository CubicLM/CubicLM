import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/settings_controller.dart';
import '../controllers/agent_runner_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import '../services/app_log_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import '../utils/web_download.dart';
import 'agent/agent_workspace_view.dart';
import 'package:lucide_icons/lucide_icons.dart';

class LogView extends StatefulWidget {
  const LogView({super.key});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final showHealth = true.obs;
  final TextEditingController _searchCtrl = TextEditingController();
  // Cached so the AppBar path row doesn't re-query the platform on rebuilds.
  late final Future<String> _exportDirFuture =
      ExportFile.getExportDirPath();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color levelColor(String level) {
    switch (level) {
      case 'ERROR':
        return AppColors.error;
      case 'WARNING':
        return const Color(0xFFFBBF24);
      case 'INFO':
        return const Color(0xFF10B981);
      case 'DEBUG':
        return const Color(0xFF3B82F6);
      default:
        return Dt.accent;
    }
  }

  IconData levelIcon(String level) {
    switch (level) {
      case 'ERROR':
        return LucideIcons.alertOctagon;
      case 'WARNING':
        return LucideIcons.alertTriangle;
      case 'INFO':
        return LucideIcons.info;
      case 'DEBUG':
        return LucideIcons.bug;
      default:
        return LucideIcons.terminal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = Get.find<AppLogService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor:
            (isDark ? AppColors.bg : AppColors.bgLight).withValues(alpha: 0.8),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Logs',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 18)),
            Obx(() => Text(
                '${logs.filteredEntries.length} entries matching filters',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor))),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(78),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => logs.searchQuery.value = v,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Search across logs, messages, stack traces…',
                    hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Theme.of(context).hintColor.withValues(alpha: 0.7)),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 18, color: Theme.of(context).hintColor),
                    suffixIcon: Obx(() => logs.searchQuery.value.isNotEmpty
                        ? IconButton(
                            icon: Icon(LucideIcons.x,
                                size: 16, color: Theme.of(context).hintColor),
                            onPressed: () {
                              _searchCtrl.clear();
                              logs.searchQuery.value = '';
                            },
                          )
                        : const SizedBox.shrink()),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
              FutureBuilder<String>(
                future: _exportDirFuture,
                builder: (ctx, snap) {
                  final path = snap.data ?? '…';
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    child: Row(
                      children: [
                        Icon(LucideIcons.folderOpen,
                            size: 12, color: Theme.of(ctx).hintColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                                fontSize: 10,
                                color: Theme.of(ctx).hintColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Health Report',
            icon: Obx(() => Icon(
                  LucideIcons.heartPulse,
                  size: 20,
                  color: logs.detectedPatterns.isNotEmpty
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFF10B981),
                )),
            onPressed: () => showHealth.value = !showHealth.value,
          ),
          IconButton(
            tooltip: 'Export Logs',
            icon: const Icon(LucideIcons.share2,
                size: 20, color: AppColors.primary),
            onPressed: () => _showExportSheet(context, logs, isDark),
          ),
          IconButton(
            tooltip: 'Clear All',
            icon: Icon(LucideIcons.trash2,
                size: 20,
                color: AppColors.error.withValues(alpha: 0.7)),
            onPressed: logs.clear,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: isDark ? AppColors.bg : AppColors.bgLight,
              child: TabBar(
                labelColor: Dt.accent,
                unselectedLabelColor: Theme.of(context).hintColor,
                indicatorColor: Dt.accent,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13),
                tabs: const [
                  Tab(text: 'Live Logs'),
                  Tab(text: 'Saved Files'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Obx(() {
                        if (!showHealth.value) return const SizedBox.shrink();
                        final patterns = logs.detectedPatterns;
                        final errCount = logs.errorCount;
                        final warnCount = logs.warningCount;

                        Widget content;
                        if (patterns.isEmpty && errCount == 0) {
                          content = Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(LucideIcons.checkCircle2, size: 18, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('System Healthy',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF10B981))),
                                    const SizedBox(height: 2),
                                    Text('No patterns detected in current stream.',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: Theme.of(context).hintColor)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          content = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(LucideIcons.heartPulse, size: 16, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 8),
                                  Text('Diagnostics',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFFBBF24))),
                                  const Spacer(),
                                  Text('$errCount errors · $warnCount warnings',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: Theme.of(context).hintColor)),
                                ],
                              ),
                              if (patterns.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                ...patterns.map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppColors.error.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(LucideIcons.bug, size: 12, color: AppColors.error),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${p.title} (${p.occurrences}x)',
                                                    style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700)),
                                                const SizedBox(height: 2),
                                                Text(p.fix,
                                                    style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 11,
                                                        color: Theme.of(context).hintColor)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                              Builder(builder: (_) {
                                final untracked = logs.untrackedErrors;
                                if (untracked.isEmpty) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 10),
                                    Text('Untracked Errors (${untracked.length})',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFFBBF24))),
                                    const SizedBox(height: 6),
                                    for (final u in untracked.take(5))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () {
                                            final first = u.message.split('\n').first.trim();
                                            logs.searchQuery.value = first.length > 60 ? first.substring(0, 60) : first;
                                            _searchCtrl.text = logs.searchQuery.value;
                                          },
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Icon(LucideIcons.helpCircle, size: 12, color: Color(0xFFFBBF24)),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                    u.message.split('\n').first.trim() + (u.count > 1 ? ' (×${u.count})' : ''),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ],
                          );
                        }

                        return Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surface : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: content,
                          ),
                        );
                      }),

                      SizedBox(
                        height: 44,
                        child: Obx(() {
                          final current = logs.selectedCategory.value;
                          return ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              _catChip(
                                context,
                                isDark,
                                label: 'All Categories',
                                selected: current == null,
                                color: Dt.accent,
                                onTap: () => logs.selectedCategory.value = null,
                              ),
                              for (final cat in LogCategory.values)
                                _catChip(
                                  context,
                                  isDark,
                                  label: cat.label,
                                  selected: current == cat,
                                  color: _catColor(cat),
                                  onTap: () => logs.selectedCategory.value =
                                      current == cat ? null : cat,
                                ),
                            ],
                          );
                        }),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: SizedBox(
                          height: 44,
                          child: Obx(() {
                            final current = logs.selectedLevel.value;
                            final filters = ['ALL', 'ERROR', 'WARNING', 'INFO', 'DEBUG'];
                            return ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: filters.length,
                              itemBuilder: (context, index) {
                                final filter = filters[index];
                                final isSelected = current == filter;
                                final color = filter == 'ALL' ? Dt.accent : levelColor(filter);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                  child: InkWell(
                                    onTap: () => logs.selectedLevel.value = filter,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? color.withValues(alpha: 0.15)
                                            : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02)),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected ? color.withValues(alpha: 0.4) : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (filter != 'ALL') ...[
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(filter,
                                              style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11.5,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected ? color : Theme.of(context).hintColor)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      ),

                      Obx(() {
                        final un = logs.unresolvedError.value;
                        if (un == null) return const SizedBox.shrink();
                        final color = un.level == 'ERROR' ? AppColors.error : const Color(0xFFFBBF24);
                        final head = un.message.split('\n').first.trim();
                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: color.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                un.level == 'ERROR' ? LucideIcons.alertOctagon : LucideIcons.alertTriangle,
                                size: 20,
                                color: color,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Unresolved ${un.level.toLowerCase()} · ${logs.crashHistory.length} in history',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: color),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${head.length > 110 ? '${head.substring(0, 110)}…' : head} · ${logs.unresolvedErrorMeta}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: Theme.of(context).hintColor),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Mark as fixed & clear',
                                icon: const Icon(LucideIcons.checkCircle2, size: 20),
                                color: color,
                                onPressed: () => logs.resolveCrashState(),
                              ),
                            ],
                          ),
                        );
                      }),

                      Expanded(
                        child: Obx(() {
                          final filtered = logs.filteredEntries;

                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Icon(LucideIcons.checkCircle, size: 32, color: Color(0xFF10B981)),
                                    ),
                                    const SizedBox(height: 20),
                                    Text('System Nominal',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? Colors.white : Colors.black)),
                                    const SizedBox(height: 8),
                                    Text('No ${logs.selectedLevel.value == 'ALL' ? '' : '${logs.selectedLevel.value.toLowerCase()} '}logs recorded.',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            color: Theme.of(context).hintColor,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              final color = levelColor(entry.level);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.surface : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                                  border: Border.all(
                                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  // Accent stripe via left border — no
                                  // IntrinsicHeight + stretch Row (that pair
                                  // mis-measures unbounded SelectableText and
                                  // overflows ~14px on device).
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                          left: BorderSide(
                                              width: 4, color: color)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                                  Row(children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                      decoration: BoxDecoration(
                                                          color: color.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6)),
                                                      child: Row(children: [
                                                        Icon(levelIcon(entry.level), color: color, size: 11),
                                                        const SizedBox(width: 5),
                                                        Text(entry.level,
                                                            style: GoogleFonts.plusJakartaSans(
                                                                fontSize: 9,
                                                                fontWeight: FontWeight.w800,
                                                                color: color)),
                                                      ]),
                                                    ),
                                                    if (entry.count > 1) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.primary.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text('×${entry.count}',
                                                            style: GoogleFonts.plusJakartaSans(
                                                                fontSize: 9,
                                                                fontWeight: FontWeight.w800,
                                                                color: AppColors.primary)),
                                                      ),
                                                    ],
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _catColor(entry.category).withValues(alpha: 0.08),
                                                          borderRadius: BorderRadius.circular(5),
                                                        ),
                                                        child: Text(entry.category.label,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: GoogleFonts.plusJakartaSans(
                                                                fontSize: 9,
                                                                fontWeight: FontWeight.w700,
                                                                color: _catColor(entry.category))),
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(_formatTime(entry.timestamp),
                                                        style: GoogleFonts.plusJakartaSans(
                                                            fontSize: 11,
                                                            color: Theme.of(context).hintColor,
                                                            fontWeight: FontWeight.w500)),
                                                  ]),
                                                  const SizedBox(height: 10),
                                                  SelectableText(entry.message,
                                                      style: GoogleFonts.plusJakartaSans(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                                          height: 1.4)),
                                                  if (entry.count > 1)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 6),
                                                      child: Text(
                                                          '×${entry.count} · first ${_formatDateTime(entry.timestamp)} · last ${_formatDateTime(entry.lastAt)}',
                                                          style: GoogleFonts.plusJakartaSans(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.w600,
                                                              color: AppColors.primary)),
                                                    ),
                                                  if (entry.details != null && entry.details!.isNotEmpty) ...[
                                                    const SizedBox(height: 10),
                                                    Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.all(10),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0F172A),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: SelectableText(entry.details!,
                                                          style: GoogleFonts.firaCode(
                                                              fontSize: 10.5,
                                                              color: const Color(0xFFE2E8F0),
                                                              height: 1.4)),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 10),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: [
                                                      _rowAction(
                                                        context,
                                                        icon: LucideIcons.clipboardList,
                                                        label: 'Copy diagnosis',
                                                        onTap: () async {
                                                          final text = logs
                                                              .diagnosisFor(
                                                                  entry);
                                                          await Clipboard.setData(
                                                              ClipboardData(
                                                                  text: text));
                                                          AppSnackbar.showTop(
                                                            'Diagnosis copied',
                                                            'Paste it to chat or the agent.',
                                                            icon: LucideIcons
                                                                .clipboardCheck,
                                                            iconName:
                                                                'clipboard_check',
                                                            duration:
                                                                const Duration(
                                                                    seconds: 2),
                                                            logHistory: false,
                                                          );
                                                        },
                                                      ),
                                                      if (entry.level ==
                                                              'ERROR' ||
                                                          entry.level ==
                                                              'WARNING')
                                                        _rowAction(
                                                          context,
                                                          icon: LucideIcons
                                                              .bot,
                                                          label:
                                                              'Fix with Agent',
                                                          accent: true,
                                                          onTap: () =>
                                                              _fixWithAgent(
                                                                  context,
                                                                  logs,
                                                                  entry),
                                                        ),
                                                    ],
                                                  ),
                                                ]),
                                      ),
                                  ),
                              ),
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                  _SavedFilesTab(isDark: isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final color =
        accent ? Dt.accent : Theme.of(context).hintColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// Prefill the agent with this row's diagnosis and open the workspace.
  /// The composer picks up `prompt` on build, so the task is visible and
  /// runnable with one tap.
  void _fixWithAgent(
      BuildContext context, AppLogService logs, AppLogEntry entry) {
    try {
      final c = Get.isRegistered<AgentRunnerController>()
          ? Get.find<AgentRunnerController>()
          : Get.put(AgentRunnerController());
      c.prompt.value = logs.diagnosisFor(entry, forAgent: true);
      Get.to(() => const AgentWorkspaceView());
    } catch (e) {
      AppSnackbar.showTop('Cannot open agent', '$e');
    }
  }

  Future<void> _showExportSheet(
      BuildContext context, AppLogService logs, bool isDark) async {    final action = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Export logs',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.copy, size: 20),
              title: Text('Copy to clipboard',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'copy'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.fileText, size: 20),
              title: Text('Save as .txt file',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'file'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.share2, size: 20),
              title: Text('Share .txt file',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
              contentPadding: EdgeInsets.zero,
              onTap: () => Get.back(result: 'share'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: null),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans()),
          ),
        ],
      ),
    );
    if (action == null) return;
    try {
      final text = await logs.exportFullLogs();
      if (!context.mounted) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: text));
        AppSnackbar.showTop(
          'Logs Copied',
          'Deduplicated diagnostic report copied to clipboard.',
          icon: LucideIcons.copyCheck,
          iconName: 'copyCheck',
          duration: const Duration(seconds: 2),
          logHistory: false,
        );
        return;
      }
      if (action == 'share') {
        await _shareLogsFile(logs, text);
        return;
      }
      await _saveLogsFile(context, logs, text);
    } catch (e) {
      AppSnackbar.showTop('Export failed', '$e',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<void> _saveLogsFile(
      BuildContext context, AppLogService logs, String text) async {
    var version = '';
    try {
      if (Get.isRegistered<SettingsController>()) {
        version = Get.find<SettingsController>().appVersion.value;
      }
    } catch (_) {}
    final fileName = logs.exportFileName(version);
    if (kIsWeb) {
      try {
        final bytes = utf8.encode(text);
        if (await downloadWebFile(bytes, fileName, 'text/plain')) {
          AppSnackbar.showTop('Logs saved', fileName,
              icon: LucideIcons.checkCircle2,
              type: 'success',
              iconName: 'check',
              duration: const Duration(seconds: 3),
              logHistory: false);
          return;
        }
      } catch (_) {}
      await Clipboard.setData(ClipboardData(text: text));
      AppSnackbar.showTop(
        'Logs Copied',
        'File save is not available on web — copied instead.',
        icon: LucideIcons.copyCheck,
        iconName: 'copyCheck',
        duration: const Duration(seconds: 3),
        logHistory: false,
      );
      return;
    }
    await ExportFile.quickExport(
      text: text,
      fileName: fileName,
      mimeType: 'text/plain',
    );
  }

  Future<void> _shareLogsFile(AppLogService logs, String text) async {
    var version = '';
    try {
      if (Get.isRegistered<SettingsController>()) {
        version = Get.find<SettingsController>().appVersion.value;
      }
    } catch (_) {}
    final fileName = logs.exportFileName(version);
    final bytes = Uint8List.fromList(utf8.encode(text));
    final ok = await ExportFile.shareBytes(
      bytes: bytes,
      fileName: fileName,
    );
    if (!ok) {
      AppSnackbar.showTop('Share failed', 'Could not share $fileName',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Widget _catChip(BuildContext context, bool isDark,
      {required String label,
      required bool selected,
      required Color color,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? color : Theme.of(context).hintColor)),
            ],
          ),
        ),
      ),
    );
  }

  Color _catColor(LogCategory cat) {
    switch (cat) {
      case LogCategory.system:
        return const Color(0xFF6366F1);
      case LogCategory.model:
        return const Color(0xFFF59E0B);
      case LogCategory.cloud:
        return const Color(0xFF3B82F6);
      case LogCategory.chat:
        return const Color(0xFF10B981);
      case LogCategory.server:
        return const Color(0xFF8B5CF6);
      case LogCategory.image:
        return const Color(0xFFEC4899);
      case LogCategory.agent:
        return const Color(0xFF14B8A6);
      case LogCategory.runtime:
        return const Color(0xFFF97316);
      case LogCategory.terminal:
        return const Color(0xFF64748B);
      case LogCategory.update:
        return const Color(0xFFA855F7);
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDateTime(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${_formatTime(time)}';
}

class _SavedFilesTab extends StatefulWidget {
  final bool isDark;
  const _SavedFilesTab({required this.isDark});

  @override
  State<_SavedFilesTab> createState() => _SavedFilesTabState();
}

class _SavedFilesTabState extends State<_SavedFilesTab> {
  List<ExportedFile> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    ExportFile.savedVersion.addListener(_onSaved);
  }

  @override
  void dispose() {
    ExportFile.savedVersion.removeListener(_onSaved);
    super.dispose();
  }

  void _onSaved() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await ExportFile.listSavedLogFiles();
    if (mounted) setState(() { _files = files; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.fileText,
                size: 40, color: Theme.of(context).hintColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No saved log files',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Text('Export logs from the menu above',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: Theme.of(context).hintColor.withValues(alpha: 0.7))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final f = _files[index];
          return Dismissible(
            key: ValueKey(f.path),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.trash2,
                  color: AppColors.error, size: 20),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete file?',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800)),
                  content: Text(f.name,
                      style: GoogleFonts.firaCode(fontSize: 11)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel', style: GoogleFonts.plusJakartaSans())),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Delete',
                            style: GoogleFonts.plusJakartaSans(color: AppColors.error, fontWeight: FontWeight.bold))),
                  ],
                ),
              );
            },
            onDismissed: (_) async {
              await ExportFile.deleteFile(f.path);
              setState(() => _files.removeAt(index));
              AppSnackbar.showTop('Deleted', f.name,
                  icon: LucideIcons.trash2,
                  duration: const Duration(seconds: 2),
                  logHistory: false);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: widget.isDark ? 0.15 : 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
                border: Border.all(
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Dt.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(LucideIcons.fileText,
                            size: 18, color: Dt.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.firaCode(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${f.sizeLabel}  ·  ${f.dateLabel}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Theme.of(context).hintColor,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'View',
                        icon: Icon(LucideIcons.eye,
                            size: 16, color: Theme.of(context).hintColor),
                        onPressed: () => _viewFile(f),
                      ),
                      IconButton(
                        tooltip: 'Share',
                        icon: Icon(LucideIcons.share2,
                            size: 16, color: Theme.of(context).hintColor),
                        onPressed: () => _shareFile(f),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _viewFile(ExportedFile f) async {
    try {
      String? text;
      if (f.path.startsWith('content://')) {
        final bytes = await ExportFile.readExportFile(f.path);
        if (bytes != null) text = String.fromCharCodes(bytes);
      } else {
        text = await File(f.path).readAsString();
      }
      if (!mounted || text == null) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.fileText,
                        size: 16, color: Dt.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(text ?? '',
                          style: GoogleFonts.firaCode(
                              fontSize: 11, height: 1.5, color: const Color(0xFFE2E8F0))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      AppSnackbar.showTop('Open failed', '$e',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }

  Future<void> _shareFile(ExportedFile f) async {
    try {
      Uint8List bytes;
      if (f.path.startsWith('content://')) {
        final b = await ExportFile.readExportFile(f.path);
        if (b == null) {
          AppSnackbar.showTop('Share failed', 'Could not read file',
              icon: LucideIcons.alertTriangle, type: 'error', iconName: 'alert');
          return;
        }
        bytes = b;
      } else {
        bytes = await File(f.path).readAsBytes();
      }
      await ExportFile.shareBytes(bytes: bytes, fileName: f.name);
    } catch (e) {
      AppSnackbar.showTop('Share failed', '$e',
          icon: LucideIcons.alertTriangle,
          type: 'error',
          iconName: 'alert');
    }
  }
}
