import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/chat_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
import '../services/usage_tracker_service.dart';
import '../theme/design_tokens.dart';
import '../views/hub/hub_widgets.dart';

/// Full Context Window page (opens from the chat context bar/ring and
/// from the Dashboard). OpenCode-desktop style details — session,
/// token stats, visual breakdown, raw messages — plus an Online tab
/// for cloud sessions. Every label has an ⓘ explainer.
class ContextWindowView extends StatefulWidget {
  /// 0 = Local, 1 = Online. Defaults to the current inference mode.
  final int initialTab;
  const ContextWindowView({super.key, this.initialTab = -1});

  @override
  State<ContextWindowView> createState() =>
      _ContextWindowViewState();
}

class _ContextWindowViewState extends State<ContextWindowView> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    var t = widget.initialTab;
    if (t < 0) {
      try {
        t = Get.find<SettingsController>().inferenceMode.value ==
                'local'
            ? 0
            : 1;
      } catch (_) {
        t = 0;
      }
    }
    _tab = t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('Context Window',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                _tabPill(context, 'Local', 0),
                const SizedBox(width: 8),
                _tabPill(context, 'Online', 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              // Rebuild live on new messages / token updates.
              try {
                Get.find<ChatController>().messages.length;
                Get.find<InferenceService>()
                    .contextTokensUsed
                    .value;
                Get.find<UsageTrackerService>().version.value;
              } catch (_) {}
              return _tab == 0
                  ? _localTab(context)
                  : _onlineTab(context);
            }),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(BuildContext context, String s, int i) {
    final sel = _tab == i;
    return InkWell(
      onTap: () => setState(() => _tab = i),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: sel
              ? Theme.of(context)
                  .primaryColor
                  .withValues(alpha: 0.15)
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel
                ? Theme.of(context)
                    .primaryColor
                    .withValues(alpha: 0.3)
                : Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.5),
          ),
        ),
        child: Text(s,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  // ── shared bits ──────────────────────────────────────────

  static String fmtInt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (n < 0 ? '-' : '') + buf.toString();
  }

  static String fmtK(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = n / 1000;
      return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}k';
    }
    final v = n / 1000000;
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}M';
  }

  static String fmtTime(DateTime t) {
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    var h = t.hour;
    final ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '${mo[t.month - 1]} ${t.day}, ${t.year}, $h:${t.minute.toString().padLeft(2, '0')} $ap';
  }

  void _info(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800)),
        content: Text(body,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, height: 1.55)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value,
      String info,
      {bool wide = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context).hintColor)),
            ),
            InkWell(
              onTap: () => _info(context, label, info),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(LucideIcons.info,
                    size: 12,
                    color: Theme.of(context)
                        .hintColor
                        .withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            maxLines: wide ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  // ── Local tab ────────────────────────────────────────────

  Map<String, int> _localBreakdown(List<ChatMessage> msgs) {
    var user = 0, asst = 0, tool = 0;
    for (final m in msgs) {
      if (m.role == 'user') {
        user += m.content.length;
      } else if (m.role == 'assistant') {
        asst += m.content.length;
        try {
          for (final s in m.toolSteps ?? const []) {
            tool += '${s['output'] ?? ''}'.length;
          }
        } catch (_) {}
      }
    }
    return {'user': user, 'asst': asst, 'tool': tool};
  }

  Widget _localTab(BuildContext context) {
    ChatController cc;
    InferenceService inf;
    SettingsController settings;
    try {
      cc = Get.find<ChatController>();
      inf = Get.find<InferenceService>();
      settings = Get.find<SettingsController>();
    } catch (_) {
      return const Center(child: Text('—'));
    }
    final msgs = cc.messages.toList();
    if (cc.currentSessionId.value.isEmpty || msgs.isEmpty) {
      return Center(
          child: Text('No active session — start chatting first.',
              style: GoogleFonts.plusJakartaSans(
                  color: Theme.of(context).hintColor)));
    }
    final total = inf.contextTokensTotal.value > 0
        ? inf.contextTokensTotal.value
        : settings.contextSize.value;
    final estChars =
        msgs.fold<int>(0, (s, m) => s + m.content.length);
    final used = (inf.contextTokensUsed.value > 0
            ? inf.contextTokensUsed.value
            : (estChars / 4).ceil())
        .clamp(0, total);
    final pct = total > 0 ? used / total : 0.0;
    final userMsgs = msgs.where((m) => m.role == 'user').length;
    final asstMsgs =
        msgs.where((m) => m.role == 'assistant').length;
    final parts = _localBreakdown(msgs);
    final userTok = parts['user']! ~/ 4;
    final asstTok = parts['asst']! ~/ 4;
    final toolTok = parts['tool']! ~/ 4;
    final otherTok = (used - userTok - asstTok - toolTok)
        .clamp(0, used);
    final model = inf.loadedModelName.value.isEmpty
        ? 'No model loaded'
        : inf.loadedModelName.value;
    final first = msgs.first.timestamp.toLocal();
    final last = msgs.last.timestamp.toLocal();
    final title = _chatTitle(cc);

    double share(int t) =>
        used > 0 ? (t / used).clamp(0.0, 1.0) : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Header: ring + model + session.
        _card(context,
            child: Row(
              children: [
                HubRing(
                  fraction: pct,
                  center: '${(pct * 100).round()}%',
                  label: '',
                  color: pct >= 0.8
                      ? AppColors.warning
                      : Dt.accent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(model,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .hintColor)),
                      Text('${msgs.length} messages',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .hintColor)),
                    ],
                  ),
                ),
              ],
            )),
        const SizedBox(height: 12),
        // Visual breakdown bar (OpenCode style, more precise).
        _card(context,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text('Context Breakdown',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        _seg(share(userTok),
                            const Color(0xFF4ADE80)),
                        _seg(share(asstTok),
                            const Color(0xFF22D3EE)),
                        _seg(share(toolTok),
                            const Color(0xFFFBBF24)),
                        _seg(share(otherTok),
                            Theme.of(context)
                                .hintColor
                                .withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _legend(context, 'User',
                        '${(share(userTok) * 100).toStringAsFixed(1)}%',
                        const Color(0xFF4ADE80)),
                    _legend(context, 'Assistant',
                        '${(share(asstTok) * 100).toStringAsFixed(1)}%',
                        const Color(0xFF22D3EE)),
                    _legend(context, 'Tool Calls',
                        '${(share(toolTok) * 100).toStringAsFixed(1)}%',
                        const Color(0xFFFBBF24)),
                    _legend(context, 'Other',
                        '${(share(otherTok) * 100).toStringAsFixed(1)}%',
                        Theme.of(context).hintColor),
                  ],
                ),
              ],
            )),
        const SizedBox(height: 12),
        // Stat grid.
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: [
            _card(context,
                child: _stat(
                    context,
                    'Session',
                    _shortId(cc.currentSessionId.value),
                    'This chat thread. A new chat starts a new session with a fresh context window.')),
            _card(context,
                child: _stat(
                    context,
                    'Model',
                    model,
                    'The loaded on-device model. Its context limit caps how much fits.')),
            _card(context,
                child: _stat(
                    context,
                    'Context Limit',
                    fmtInt(total),
                    'Maximum tokens the model holds: prompt + reply + tools. Beyond this the oldest turns are trimmed.')),
            _card(context,
                child: _stat(
                    context,
                    'Usage',
                    '${(pct * 100).toStringAsFixed(1)}%',
                    'Share of the context limit currently filled. Above 80% answers may degrade — start a new chat.')),
            _card(context,
                child: _stat(
                    context,
                    'Total Tokens',
                    fmtInt(used),
                    'Estimated tokens now occupying context (chars ÷ 4, or the engine counter when available).')),
            _card(context,
                child: _stat(
                    context,
                    'Messages',
                    '${msgs.length}',
                    'All turns kept in this session, both sides.')),
            _card(context,
                child: _stat(
                    context,
                    'Input Tokens',
                    fmtInt(userTok),
                    'Estimate from everything you sent (chars ÷ 4).')),
            _card(context,
                child: _stat(
                    context,
                    'Output Tokens',
                    fmtInt(asstTok),
                    'Estimate from everything the model wrote (chars ÷ 4).')),
            _card(context,
                child: _stat(
                    context,
                    'User Messages',
                    '$userMsgs',
                    'Your turns in this session.')),
            _card(context,
                child: _stat(
                    context,
                    'Assistant Messages',
                    '$asstMsgs',
                    'Model replies in this session.')),
            _card(context,
                child: _stat(
                    context,
                    'Session Created',
                    fmtTime(first),
                    'Time of the first message in this session.')),
            _card(context,
                child: _stat(
                    context,
                    'Last Activity',
                    fmtTime(last),
                    'Time of the latest message in this session.')),
          ],
        ),
        const SizedBox(height: 12),
        // Raw messages.
        _card(context,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text('Raw messages',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (var i = 0; i < msgs.length; i++)
                  Theme(
                    data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      dense: true,
                      title: Row(
                        children: [
                          _roleChip(context, msgs[i].role),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                msgs[i]
                                    .content
                                    .replaceAll('\n', ' '),
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12)),
                          ),
                        ],
                      ),
                      subtitle: Text(
                          '${fmtTime(msgs[i].timestamp.toLocal())} · ${fmtK(msgs[i].content.length ~/ 4)} tok',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .hintColor)),
                      children: [
                        SelectableText(msgs[i].content,
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12.5,
                                    height: 1.5)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
              ],
            )),
      ],
    );
  }

  Widget _seg(double f, Color c) {
    if (f <= 0) return const SizedBox.shrink();
    return Expanded(flex: (f * 1000).round().clamp(1, 1000), child: Container(color: c));
  }

  Widget _legend(
      BuildContext context, String s, String v, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$s $v',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: Theme.of(context).hintColor)),
      ],
    );
  }

  Widget _roleChip(BuildContext context, String role) {
    final user = role == 'user';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (user ? Dt.accent : AppColors.success)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(role,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: user ? Dt.accent : AppColors.success)),
    );
  }

  String _shortId(String id) {
    final s = id.trim();
    if (s.length <= 18) return s;
    return '${s.substring(0, 10)}…${s.substring(s.length - 6)}';
  }

  String _chatTitle(ChatController cc) {
    try {
      final sid = cc.currentSessionId.value;
      for (final s in cc.sessions) {
        try {
          if (s.id == sid && s.title.trim().isNotEmpty) {
            return s.title.trim();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return 'Chat';
  }

  // ── Online tab ───────────────────────────────────────────

  Widget _onlineTab(BuildContext context) {
    SettingsController settings;
    try {
      settings = Get.find<SettingsController>();
    } catch (_) {
      return const Center(child: Text('—'));
    }
    final providerId = settings.cloudProvider.value;
    String providerLabel = providerId;
    try {
      providerLabel = providerId == 'custom'
          ? settings.customCloudName.value
          : providerId.capitalizeFirst ?? providerId;
    } catch (_) {}
    final model = _cloudModel(settings);
    UsageTrackerService? tracker;
    try {
      tracker = Get.find<UsageTrackerService>();
    } catch (_) {}
    final totals = tracker?.totals() ??
        const {'in': 0, 'out': 0, 'calls': 0};
    final providers = tracker?.byProvider() ?? const [];
    ChatController? cc;
    try {
      cc = Get.find<ChatController>();
    } catch (_) {}
    final msgs = cc?.messages.toList() ?? const [];
    final sessChars =
        msgs.fold<int>(0, (s, m) => s + m.content.length);
    final sessTok = sessChars ~/ 4;
    final userMsgs =
        msgs.where((m) => m.role == 'user').length;
    final asstMsgs =
        msgs.where((m) => m.role == 'assistant').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _card(context,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.cloud,
                      size: 22, color: Dt.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(providerLabel,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      Text(model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .hintColor)),
                      Text(
                          '${fmtK(sessTok)} session tokens · ${msgs.length} messages',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .hintColor)),
                    ],
                  ),
                ),
              ],
            )),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: [
            _card(context,
                child: _stat(
                    context,
                    'Provider',
                    providerLabel,
                    'The cloud account answering right now. Switch it in Explore → Online.')),
            _card(context,
                child: _stat(context, 'Model', model,
                    'The cloud model answering. Context limits differ per model — check the provider docs.')),
            _card(context,
                child: _stat(
                    context,
                    'Session Tokens',
                    fmtInt(sessTok),
                    'Estimate for this chat only (chars ÷ 4). Cloud billing uses the provider counter, not this.')),
            _card(context,
                child: _stat(
                    context,
                    'Messages',
                    '${msgs.length}',
                    'All turns in this cloud session.')),
            _card(context,
                child: _stat(
                    context,
                    'Input Tokens',
                    fmtInt(totals['in'] ?? 0),
                    'All-time input estimate across providers (chars ÷ 4).')),
            _card(context,
                child: _stat(
                    context,
                    'Output Tokens',
                    fmtInt(totals['out'] ?? 0),
                    'All-time output estimate across providers (chars ÷ 4).')),
            _card(context,
                child: _stat(
                    context,
                    'User Messages',
                    '$userMsgs',
                    'Your turns in this session.')),
            _card(context,
                child: _stat(
                    context,
                    'Assistant Messages',
                    '$asstMsgs',
                    'Model replies in this session.')),
            _card(context,
                child: _stat(
                    context,
                    'Total Calls',
                    fmtInt(totals['calls'] ?? 0),
                    'All-time cloud API calls across providers.')),
            _card(context,
                child: _stat(
                    context,
                    'Total Cost',
                    '\$0.00',
                    'CubicLM never bills — check your provider dashboard for real spend.')),
          ],
        ),
        const SizedBox(height: 12),
        _card(context,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text('Usage by provider',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (providers.isEmpty)
                  Text('No cloud calls yet.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color:
                              Theme.of(context).hintColor))
                else
                  for (final p in providers)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                              vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                '${p['provider']}',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12.5,
                                        fontWeight:
                                            FontWeight
                                                .w700)),
                          ),
                          Text(
                              '▲${fmtK((p['in'] as int? ?? 0))} ▼${fmtK((p['out'] as int? ?? 0))} · ${p['calls']} calls',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 11.5,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                        ],
                      ),
                    ),
              ],
            )),
      ],
    );
  }

  String _cloudModel(SettingsController settings) {
    try {
      final m = settings.selectedCloudModelName.trim();
      if (m.isNotEmpty) return m;
    } catch (_) {}
    return '—';
  }
}
