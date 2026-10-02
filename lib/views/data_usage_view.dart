import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/traffic_service.dart';
import '../theme/design_tokens.dart';

/// In-app Data Usage (Network tab → Usage). Reference layout: period
/// pills, total card with Wi-Fi/Mobile + Download/Upload split, and a
/// per-app list with icons. Exact system numbers via NetworkStatsManager
/// (needs Usage Access — granted in system Settings).
class DataUsageView extends StatefulWidget {
  const DataUsageView({super.key});

  @override
  State<DataUsageView> createState() => _DataUsageViewState();
}

class _PeriodData {
  final bool permitted;
  final TrafficSummary? summary;
  final List<TrafficApp> apps;
  const _PeriodData(
      {required this.permitted,
      required this.summary,
      required this.apps});
}

class _DataUsageViewState extends State<DataUsageView>
    with WidgetsBindingObserver {
  int _period = 0; // 0 today, 1 last-7, 2 last-30
  var _nonce = 0;
  var _searching = false;
  var _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Usage-Access settings → recheck + reload.
    if (state == AppLifecycleState.resumed) {
      setState(() => _nonce++);
    }
  }

  int _startMs() {
    final now = DateTime.now();
    switch (_period) {
      case 2:
        return now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      case 1:
        return now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      case 0:
      default:
        return DateTime(now.year, now.month, now.day)
            .millisecondsSinceEpoch;
    }
  }

  String _periodLabel() {
    final now = DateTime.now();
    String d(DateTime t) =>
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
    switch (_period) {
      case 2:
        return '${d(now.subtract(const Duration(days: 30)))} – ${d(now)}';
      case 1:
        return '${d(now.subtract(const Duration(days: 7)))} – ${d(now)}';
      case 0:
      default:
        return d(now);
    }
  }

  Future<_PeriodData> _load() async {
    final ok = await TrafficService.hasPermission();
    if (!ok) {
      final b = await TrafficService.boot();
      return _PeriodData(
          permitted: false, summary: b, apps: const []);
    }
    final end = DateTime.now().millisecondsSinceEpoch;
    final start = _startMs();
    final s = await TrafficService.summary(start, end);
    final apps = await TrafficService.apps(start, end);
    return _PeriodData(
        permitted: true, summary: s, apps: apps);
  }

  /// Reference style: 2 decimals, decimal GB/MB.
  String _fmt(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000000) {
      return '${(bytes / 1000).toStringAsFixed(0)} KB';
    }
    if (bytes < 1000000000) {
      return '${(bytes / 1000000).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('Data Usage',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            tooltip: 'Search apps',
            icon: Icon(_searching
                ? LucideIcons.x
                : LucideIcons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                _pill(context, 'Today', 0),
                const SizedBox(width: 8),
                _pill(context, 'Last 7 Days', 1),
                const SizedBox(width: 8),
                _pill(context, 'Last 30 Days', 2),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search apps…',
                  prefixIcon:
                      const Icon(LucideIcons.search, size: 17),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<_PeriodData>(
              // ignore: discarded_futures
              future: _load(),
              builder: (context, snap) {
                if (snap.connectionState !=
                    ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                final d = snap.data;
                if (d == null) {
                  return Center(
                      child: Text('Unavailable.',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  color: Theme.of(context)
                                      .hintColor)));
                }
                if (!d.permitted) {
                  return _grantBlock(context, d.summary);
                }
                return _content(context, d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String label, int idx) {
    final sel = _period == idx;
    return InkWell(
      onTap: () => setState(() => _period = idx),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
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
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  /// No Usage Access yet: since-boot totals + grant button.
  Widget _grantBlock(
      BuildContext context, TrafficSummary? boot) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exact per-app history needs Usage Access',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  'Allow “Usage access” for CubicLM in system Settings. Without it only since-boot totals show.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    TrafficService.openSettings(),
                style: FilledButton.styleFrom(
                    backgroundColor: Dt.accent,
                    foregroundColor: Colors.white),
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
        if (boot != null) ...[
          const SizedBox(height: 12),
          _totalCard(
              context,
              'Since boot',
              boot,
              showSplit: true),
        ],
      ],
    );
  }

  Widget _content(BuildContext context, _PeriodData d) {
    final s = d.summary;
    var apps = d.apps;
    if (_query.isNotEmpty) {
      apps = apps
          .where((a) =>
              a.label.toLowerCase().contains(_query) ||
              a.package.toLowerCase().contains(_query))
          .toList();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (s != null) _totalCard(context, _periodLabel(), s),
        const SizedBox(height: 18),
        Text('App usage',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No app traffic in this period.',
                style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).hintColor)),
          )
        else
          for (var i = 0; i < apps.length; i++) ...[
            _appRow(context, apps[i]),
            if (i < apps.length - 1)
              Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.5)),
          ],
      ],
    );
  }

  Widget _totalCard(BuildContext context, String date,
      TrafficSummary s,
      {bool showSplit = true}) {
    final wifi = s.wifiRx + s.wifiTx;
    final mob = s.mobileRx + s.mobileTx;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Theme.of(context).hintColor)),
          const SizedBox(height: 2),
          Text(_fmt(s.total),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Dt.accent)),
          Text('Total data usage',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: Theme.of(context).hintColor)),
          const Divider(height: 20),
          if (showSplit) ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _miniStat(context, LucideIcons.wifi,
                    'Wi-Fi', _fmt(wifi)),
                _miniStat(context, LucideIcons.signal,
                    'Mobile', _fmt(mob)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _miniStat(context, LucideIcons.download,
                  'Download', _fmt(s.rx)),
              _miniStat(context, LucideIcons.upload,
                  'Upload', _fmt(s.tx)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      BuildContext context, IconData icon, String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14, color: Theme.of(context).hintColor),
        const SizedBox(width: 5),
        Text('$k - $v',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor)),
      ],
    );
  }

  Widget _appRow(BuildContext context, TrafficApp a) {
    final wifi = a.wifiRx + a.wifiTx;
    final mob = a.mobileRx + a.mobileTx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.25),
            ),
            clipBehavior: Clip.antiAlias,
            child: a.icon == null
                ? Icon(LucideIcons.package,
                    size: 22,
                    color: Theme.of(context).hintColor)
                : Image.memory(a.icon!, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    'Wi-Fi ${_fmt(wifi)} · Mobile ${_fmt(mob)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_fmt(a.total),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Dt.accent)),
        ],
      ),
    );
  }
}
