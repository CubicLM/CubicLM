import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../services/memory_service.dart';
import '../theme/design_tokens.dart';

/// Full-page memory management screen — ChatGPT-style.
/// Lists all stored user facts with search, edit, delete, and toggle.
class MemoryView extends StatefulWidget {
  const MemoryView({super.key});

  @override
  State<MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<MemoryView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  MemoryService get _mem => Get.find<MemoryService>();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _confirmClearAll(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear all memories?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: const Text(
            'This will permanently delete all stored memories. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mem.clearMemories();
            },
            child: const Text('Clear All',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String key, bool isDark) {
    _mem.deleteMemory(key);
    HapticFeedback.lightImpact();
    Get.snackbar('Deleted', 'Memory removed',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
  }

  void _showEditDialog(String key, String currentFact, bool isDark) {
    final ctrl = TextEditingController(text: currentFact);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Memory',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Memory fact...',
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                _mem.updateMemory(key, ctrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(LucideIcons.brain, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Memory',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(width: 8),
            Obx(() => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_mem.memoryCount}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                )),
          ],
        ),
        actions: [
          // Enable / disable toggle.
          Obx(() => Switch(
                value: _mem.isEnabled.value,
                onChanged: (v) => _mem.toggleEnabled(v),
                activeThumbColor: AppColors.primary,
              )),
          // Clear all.
          Obx(() => _mem.memories.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  tooltip: 'Clear all memories',
                  onPressed: () => _confirmClearAll(isDark),
                )),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Info banner.
          Obx(() => !_mem.isEnabled.value
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Memory is disabled. CubicLM will not remember facts about you.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink()),

          // Search bar.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search memories...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Description banner.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'CubicLM learns from your conversations and stores helpful facts to personalize future responses.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: isDark ? Dt.textSecondary : Colors.black54,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Memory list.
          Expanded(child: Obx(() {
            final filtered = _mem.getMemoriesWithKeys().where((m) {
              if (_query.isEmpty) return true;
              return m.fact.toLowerCase().contains(_query);
            }).toList();

            if (filtered.isEmpty && _mem.memories.isEmpty) {
              return _emptyState(isDark);
            }
            if (filtered.isEmpty) {
              return Center(
                child: Text('No memories matching "$_query"',
                    style: GoogleFonts.plusJakartaSans(
                        color: Dt.textSecondary, fontSize: 14)),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final m = filtered[i];
                return _memoryCard(m.key, m.fact, m.createdAt, isDark);
              },
            );
          })),
        ],
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.brain,
              size: 56,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('No memories yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            width: 280,
            child: Text(
              'As you chat, CubicLM will automatically learn and remember important facts about you.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: Dt.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memoryCard(String key, String fact, DateTime createdAt, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fact text.
          SelectableText(
            fact,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.5,
              color: isDark ? AppColors.textPrimary : Dt.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // Bottom row: timestamp + actions.
          Row(
            children: [
              const Icon(LucideIcons.clock, size: 12, color: Dt.textSecondary),
              const SizedBox(width: 4),
              Text(
                _relativeTime(createdAt),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: Dt.textSecondary),
              ),
              const Spacer(),
              // Copy.
              _actionBtn(LucideIcons.copy, 'Copy', () {
                Clipboard.setData(ClipboardData(text: fact));
                HapticFeedback.lightImpact();
                Get.snackbar('Copied', 'Memory copied',
                    snackPosition: SnackPosition.BOTTOM,
                    duration: const Duration(seconds: 1));
              }),
              const SizedBox(width: 4),
              // Edit.
              _actionBtn(LucideIcons.edit3, 'Edit', () {
                _showEditDialog(key, fact, isDark);
              }),
              const SizedBox(width: 4),
              // Delete.
              _actionBtn(LucideIcons.trash2, 'Delete', () {
                _confirmDelete(key, isDark);
              }, color: AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, VoidCallback onTap,
      {Color? color}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: color ?? Dt.textSecondary),
      ),
    );
  }
}
