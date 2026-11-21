/// Dedicated CubicAi Helper chat page / split pane.
///
/// The conversation is independent of the main Chat tab and always carries
/// the active browser tab as context. Engine (Local / API) can be switched
/// right here and reuses the app-wide inference settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/cubic_ai_helper_controller.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/model_switcher_sheet.dart';
import '../../widgets/site_favicon.dart';

/// Full-screen route opened from the CubicWeb menu (and AI entry points).
class CubicAiHelperView extends StatelessWidget {
  const CubicAiHelperView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = CubicAiHelperController.ensure();

    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? Dt.cardDark : Dt.card,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back to browser',
          onPressed: () => Get.back(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.sparkles, size: 16, color: Dt.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CubicAi Helper',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Chat with your current browser tab',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Refresh page context',
            onPressed: () => c.refreshContext(),
          ),
          Obx(() => IconButton(
                icon: Icon(c.isBusy.value ? LucideIcons.square : LucideIcons.trash2,
                    size: 18),
                tooltip: c.isBusy.value ? 'Stop generating' : 'New conversation',
                onPressed: () => c.isBusy.value ? c.stop() : c.clear(),
              )),
        ],
      ),
      body: const SafeArea(child: CubicAiHelperPanel()),
    );
  }
}

/// Reusable body — also used inside CubicWeb's split AI pane.
class CubicAiHelperPanel extends StatefulWidget {
  final bool compact;

  const CubicAiHelperPanel({super.key, this.compact = false});

  @override
  State<CubicAiHelperPanel> createState() => _CubicAiHelperPanelState();
}

class _CubicAiHelperPanelState extends State<CubicAiHelperPanel> {
  final c = CubicAiHelperController.ensure();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final Worker _msgWorker;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final pos = _scrollCtrl.position;
      _atBottom = pos.pixels >= pos.maxScrollExtent - 120;
    });
    _msgWorker = ever(c.messages, (_) {
      if (_atBottom) unawaited(_scrollToBottom());
    });
    unawaited(c.refreshContext());
    _consumePending();
  }

  void _consumePending() {
    final pending = c.consumePending();
    if (pending == null) return;
    unawaited(c.send(
      pending['prompt'] as String,
      extraContext: pending['extraContext'] as String?,
    ));
  }

  Future<void> _scrollToBottom() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _msgWorker.dispose();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final prompt = (text ?? _inputCtrl.text).trim();
    if (prompt.isEmpty || c.isBusy.value) return;
    _inputCtrl.clear();
    _atBottom = true;
    unawaited(c.send(prompt));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Dt.cardDark : Dt.card;

    return Column(
      children: [
        _buildContextCard(isDark, cardBg),
        _buildEngineBar(isDark),
        Expanded(
          child: Obx(() {
            if (c.messages.isEmpty) return _buildEmpty(isDark);
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: c.messages.length,
              itemBuilder: (context, i) => _buildMessage(c.messages[i], isDark),
            );
          }),
        ),
        _buildSuggestions(isDark),
        _buildComposer(isDark, cardBg),
      ],
    );
  }

  Widget _buildContextCard(bool isDark, Color cardBg) {
    return Obx(() {
      final title = c.pageTitle.value;
      final url = c.pageUrl.value;
      final attached = c.hasPage.value;
      final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Dt.borderColor(isDark)),
        ),
        child: Row(
          children: [
            if (attached)
              SiteFavicon(url: url, size: 28)
            else
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.globe, size: 16, color: Dt.accent),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attached && title.isNotEmpty ? title : 'No page attached',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attached
                        ? (host.isNotEmpty ? host : url)
                        : 'Open a website in CubicWeb to give CubicAi context.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            if (attached)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('READING',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.green)),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildEngineBar(bool isDark) {
    return Obx(() {
      final isCloud = c.isCloud;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _engineChip('Local', !isCloud, LucideIcons.cpu, () => c.setEngine('local')),
                  _engineChip('API', isCloud, LucideIcons.cloud, () => c.setEngine('cloud')),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => showModelSwitcherSheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Icon(isCloud ? LucideIcons.zap : LucideIcons.database,
                          size: 13, color: Dt.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.modelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(LucideIcons.chevronDown, size: 13),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _engineChip(String label, bool active, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Dt.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: active ? Colors.white : null),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Dt.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.sparkles, size: 30, color: Dt.accent),
            ),
            const SizedBox(height: 16),
            Text(
              'Ask anything about this page',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'CubicAi Helper reads the tab you are browsing and answers using '
              'its content — powered by your chosen local model or API.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(CubicAiMessage m, bool isDark) {
    final isUser = m.role == 'user';
    final bubbleBg = m.isError
        ? Colors.red.withValues(alpha: 0.12)
        : isUser
            ? Dt.accent
            : (isDark ? Dt.cardDark : Dt.card);
    final fg = isUser && !m.isError ? Colors.white : null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        constraints: BoxConstraints(maxWidth: Get.width * (widget.compact ? 0.92 : 0.82)),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: isUser && !m.isError
              ? null
              : Border.all(color: m.isError ? Colors.red.withValues(alpha: 0.3) : Dt.borderColor(isDark)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && m.pageTitle != null && m.pageTitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.globe,
                        size: 11,
                        color: fg ?? Dt.accent.withValues(alpha: 0.8)),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: Get.width * 0.35,
                      child: Text(
                        m.pageTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: fg ?? Dt.accent),
                      ),
                    ),
                  ],
                ),
              ),
            if (m.content.isNotEmpty)
              SelectableText(
                m.content + (m.streaming ? '▍' : ''),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.45,
                  color: fg ?? (m.isError ? Colors.red : null),
                ),
              )
            else if (m.streaming)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Dt.accent),
                  ),
                  const SizedBox(width: 8),
                  Text('Thinking…',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Theme.of(context).hintColor)),
                ],
              ),
            if (!isUser && !m.streaming && m.modelLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${m.modelLabel} · ${_time(m.at)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9, color: Theme.of(context).hintColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  Widget _buildSuggestions(bool isDark) {
    if (widget.compact) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _suggestion('Summarize page', CubicAiHelperController.suggestions['summarize']!),
          _suggestion('Explain', CubicAiHelperController.suggestions['explain']!),
          _suggestion('Key points', CubicAiHelperController.suggestions['keyPoints']!),
          _suggestion('About this page', CubicAiHelperController.suggestions['askPage']!),
        ],
      ),
    );
  }

  Widget _suggestion(String label, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(LucideIcons.sparkles, size: 12, color: Dt.accent),
        label: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, fontWeight: FontWeight.w600)),
        onPressed: c.isBusy.value ? null : () => _submit(prompt),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildComposer(bool isDark, Color cardBg) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(top: BorderSide(color: Dt.borderColor(isDark))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ask about this page…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: Theme.of(context).hintColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Dt.borderColor(isDark)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Obx(() => IconButton(
                onPressed: c.isBusy.value ? c.stop : () => _submit(),
                icon: Icon(
                  c.isBusy.value ? LucideIcons.square : LucideIcons.send,
                  color: Dt.accent,
                  size: 20,
                ),
                tooltip: c.isBusy.value ? 'Stop' : 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: Dt.accent.withValues(alpha: 0.12),
                ),
              )),
        ],
      ),
    );
  }
}
