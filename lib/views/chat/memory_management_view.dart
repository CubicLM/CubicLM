import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/memory_service.dart';
import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

class MemoryManagementView extends StatelessWidget {
  const MemoryManagementView({super.key});

  MemoryService get _svc => Get.find<MemoryService>();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : Colors.white,
      appBar: AppBar(
        title: Text('AI Memory', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surface : Dt.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
              ),
              child: Obx(() => SwitchListTile(
                title: Text('Enable Long-term Memory', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text('Allows the AI to store and recall personal facts, preferences, and context from previous chats.', 
                  style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                value: _svc.isEnabled.value,
                activeThumbColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => _svc.toggleEnabled(v),
              )),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                Icon(LucideIcons.list, size: 14, color: AppColors.textMuted),
                SizedBox(width: 8),
                Text('STORED FACTS', 
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.8)),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              final list = _svc.getMemoriesWithKeys();
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.brain, size: 64, color: Theme.of(context).hintColor.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text('No facts remembered yet.', 
                        style: GoogleFonts.plusJakartaSans(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text('AI automatically extracts key info from your conversations when this feature is enabled.', 
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Theme.of(context).hintColor)),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = list[i];
                  return Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceLight : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(m.fact, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('Learned on ${_formatDate(m.createdAt)}', style: const TextStyle(fontSize: 10)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.pencil,
                                size: 16, color: Dt.textSecondary),
                            tooltip: 'Edit fact',
                            onPressed: () => _editFact(context, m.key, m.fact),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.trash2,
                                size: 16, color: AppColors.error),
                            tooltip: 'Delete fact',
                            onPressed: () => _svc.deleteMemory(m.key),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
          if (_svc.memories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton.icon(
                onPressed: () => _showClearConfirmation(context),
                icon: const Icon(LucideIcons.eraser, size: 16, color: AppColors.error),
                label: const Text('Clear all memory', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  void _editFact(BuildContext context, String key, String fact) {
    final ctrl = TextEditingController(text: fact);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit fact'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _svc.updateMemory(key, ctrl.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all memory?'),
        content: const Text('This will permanently delete everything the AI has learned about you. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _svc.clearMemories();
              Navigator.pop(ctx);
            }, 
            child: const Text('Clear All', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800))
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }
}
