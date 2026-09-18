import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/chat_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';

/// Full-screen prompt library / explorer with categories, search, and custom prompts.
class PromptLibraryView extends StatefulWidget {
  const PromptLibraryView({super.key});

  @override
  State<PromptLibraryView> createState() => _PromptLibraryViewState();
}

class _PromptLibraryViewState extends State<PromptLibraryView> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  ChatController get _c => Get.find<ChatController>();

  static const _categories = [
    'All',
    'Coding',
    'Writing',
    'Analysis',
    'Creative',
    'Study',
    'Business',
    'Translation',
    'Productivity',
  ];

  static const _categoryIcons = <String, IconData>{
    'All': LucideIcons.layoutGrid,
    'Coding': LucideIcons.code2,
    'Writing': LucideIcons.penTool,
    'Analysis': LucideIcons.barChart3,
    'Creative': LucideIcons.palette,
    'Study': LucideIcons.graduationCap,
    'Business': LucideIcons.briefcase,
    'Translation': LucideIcons.languages,
    'Productivity': LucideIcons.listChecks,
  };

  @override
  void initState() {
    super.initState();
    _c.ensureTemplatesLoaded();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> _filtered() {
    final templates = _c.promptTemplates.toList();
    return templates.where((t) {
      final name = (t['name'] ?? '').toLowerCase();
      final body = (t['body'] ?? '').toLowerCase();
      final cat = t['category'] ?? '';
      final desc = (t['description'] ?? '').toLowerCase();

      // Category filter.
      if (_selectedCategory != 'All' && cat != _selectedCategory) return false;
      // Search filter.
      if (_query.isNotEmpty) {
        return name.contains(_query) ||
            body.contains(_query) ||
            desc.contains(_query);
      }
      return true;
    }).toList();
  }

  void _usePrompt(Map<String, String> t) {
    _c.insertTemplate(t['body'] ?? '');
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    Get.snackbar('Template inserted', t['name'] ?? '',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Prompt Library',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showCreateDialog(isDark),
        backgroundColor: AppColors.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white, size: 20),
      ),
      body: Column(
        children: [
          // Search bar.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search prompts...',
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

          // Category chips.
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final selected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_categoryIcons[cat] ?? LucideIcons.circle,
                          size: 14,
                          color: selected ? Colors.white : Dt.textSecondary),
                      const SizedBox(width: 4),
                      Text(cat,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  selected ? Colors.white : Dt.textSecondary)),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white,
                  side: BorderSide(
                    color: selected
                        ? Colors.transparent
                        : isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Grid.
          Expanded(
            child: Obx(() {
              final items = _filtered();
              if (items.isEmpty) {
                return Center(
                  child: Text('No prompts found',
                      style: GoogleFonts.plusJakartaSans(
                          color: Dt.textSecondary, fontSize: 14)),
                );
              }

              // Split into custom and built-in.
              final custom =
                  items.where((t) => (t['builtin'] ?? '').isEmpty).toList();
              final builtin =
                  items.where((t) => (t['builtin'] ?? '').isNotEmpty).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                children: [
                  if (custom.isNotEmpty) ...[
                    _sectionHeader('Your Custom Prompts', isDark),
                    const SizedBox(height: 8),
                    ..._buildCards(custom, isDark, canDelete: true),
                    const SizedBox(height: 20),
                  ],
                  if (builtin.isNotEmpty) ...[
                    _sectionHeader(
                        _selectedCategory == 'All'
                            ? 'Built-in Prompts'
                            : _selectedCategory,
                        isDark),
                    const SizedBox(height: 8),
                    ..._buildCards(builtin, isDark),
                  ],
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.textPrimary : Dt.textPrimary));
  }

  List<Widget> _buildCards(List<Map<String, String>> items, bool isDark,
      {bool canDelete = false}) {
    return items
        .map((t) => _promptCard(t, isDark, canDelete: canDelete))
        .toList();
  }

  Widget _promptCard(Map<String, String> t, bool isDark,
      {bool canDelete = false}) {
    final name = t['name'] ?? '';
    final body = t['body'] ?? '';
    final desc = t['description'] ?? '';
    final cat = t['category'] ?? '';
    final icon = _categoryIcons[cat] ?? LucideIcons.messageSquare;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _usePrompt(t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              // Text.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.textPrimary
                                : Dt.textPrimary)),
                    if (desc.isNotEmpty)
                      Text(desc,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: Dt.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)
                    else
                      Text(body,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: Dt.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    if (cat.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(cat,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                      ),
                  ],
                ),
              ),
              // Actions.
              Column(
                children: [
                  FilledButton.tonal(
                    onPressed: () => _usePrompt(t),
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text('Use',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  if (canDelete)
                    IconButton(
                      icon: const Icon(LucideIcons.trash2,
                          size: 14, color: AppColors.error),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _c.deletePromptTemplate(t['id'] ?? '');
                        HapticFeedback.lightImpact();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog(bool isDark) {
    final nameCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String selectedCat = 'Productivity';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text('Create Custom Prompt',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Debug React Error',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Prompt body',
                    hintText: 'Enter your prompt template...',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCat,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  items: _categories
                      .where((c) => c != 'All')
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedCat = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty &&
                    bodyCtrl.text.trim().isNotEmpty) {
                  _c.addPromptTemplate(nameCtrl.text, bodyCtrl.text,
                      category: selectedCat);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      }),
    );
  }
}
