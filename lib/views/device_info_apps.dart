import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_extra_service.dart';
import '../theme/design_tokens.dart';
import 'data_usage_view.dart';
import 'device_info_android.dart';

/// Apps tab: visible installed packages with icons, versions, APK
/// sizes + a detail sheet (SDK levels, dates, installer, components,
/// Play/Extract/Launch/Data-Usage actions). No QUERY_ALL_PACKAGES —
/// only packages visible to the app are listed (count is honest).
class AppsTab extends StatefulWidget {
  const AppsTab({super.key});

  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  var _filter = 2; // 0 user, 1 system, 2 all

  static String _appSize(int bytes) {
    if (bytes < 1000) return '$bytes B';
    String t(double v) =>
        v.truncateToDouble() == v
            ? '${v.toInt()}'
            : v.toStringAsFixed(2);
    if (bytes < 1000000) return '${t(bytes / 1000)} kB';
    if (bytes < 1000000000) {
      return '${t(bytes / 1000000)} MB';
    }
    return '${t(bytes / 1000000000)} GB';
  }

  static String _date(int ms) {
    if (ms <= 0) return '—';
    const wd = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  static String _installerLabel(String? pkg) {
    switch (pkg) {
      case 'com.android.vending':
        return 'Google Play Store';
      case 'com.xiaomi.mipicks':
        return 'GetApps';
      case 'com.huawei.appmarket':
        return 'AppGallery';
      case 'com.sec.android.app.samsungapps':
        return 'Galaxy Store';
      case 'com.amazon.venezia':
        return 'Amazon Appstore';
      case 'com.oppo.market':
        return 'OPPO App Market';
      case 'com.vivo.appstore':
        return 'vivo App Store';
      case null:
      case '':
        return 'Unknown';
      default:
        return pkg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      final all = c.apps.value ?? const [];
      final users =
          all.where((a) => a['isSystem'] != true).toList();
      final systems =
          all.where((a) => a['isSystem'] == true).toList();
      final items = _filter == 0
          ? users
          : _filter == 1
              ? systems
              : all;
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _countChip(context, '${all.length}'),
                const SizedBox(width: 8),
                _filterChip(context, 'User', 0),
                const SizedBox(width: 8),
                _filterChip(context, 'System', 1),
                const SizedBox(width: 8),
                _filterChip(context, 'All', 2),
                const SizedBox(width: 8),
                _filterChip(context, 'Analyze', -1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text('No apps in this filter.',
                style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).hintColor))
          else
            for (final a in items)
              _appRow(context, Map<String, dynamic>.from(a)),
        ],
      );
    });
  }

  Widget _countChip(BuildContext context, String s) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(s,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).hintColor)),
    );
  }

  Widget _filterChip(BuildContext context, String s, int idx) {
    if (idx == -1) {
      return InkWell(
        onTap: () => _showAnalyze(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(s,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor)),
        ),
      );
    }
    final sel = _filter == idx;
    return InkWell(
      onTap: () => setState(() => _filter = idx),
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
                  .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel
                ? Theme.of(context)
                    .primaryColor
                    .withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Text(s,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).hintColor)),
      ),
    );
  }

  Widget _appRow(
      BuildContext context, Map<String, dynamic> a) {
    final icon = a['icon'];
    final bytes = (a['apkBytes'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: () => _showDetail(context, a),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.25),
                ),
                clipBehavior: Clip.antiAlias,
                child: icon == null
                    ? Icon(LucideIcons.package,
                        size: 22,
                        color:
                            Theme.of(context).hintColor)
                    : Image.memory(icon,
                        fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('${a['label'] ?? a['package'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text('${a['package'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .hintColor)),
                    Text('Version : ${a['version'] ?? '—'}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.8)),
                ),
                child: Text(_appSize(bytes),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnalyze(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    final all = c.apps.value ?? const [];
    var total = 0;
    Map<String, dynamic>? biggest;
    for (final a in all) {
      final b = (a['apkBytes'] as num?)?.toInt() ?? 0;
      total += b;
      final bb = (biggest?['apkBytes'] as num?)?.toInt() ?? -1;
      if (b > bb) biggest = a;
    }
    final users = all.where((a) => a['isSystem'] != true).length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Storage analyze'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${all.length} apps · $users user',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('APKs total ${_appSize(total)}',
                style: GoogleFonts.plusJakartaSans()),
            if (biggest != null) ...[
              const SizedBox(height: 6),
              Text(
                  'Biggest: ${biggest['label']} (${_appSize((biggest['apkBytes'] as num?)?.toInt() ?? 0)})',
                  style: GoogleFonts.plusJakartaSans(
                      color: Theme.of(context).hintColor)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetail(
      BuildContext context, Map<String, dynamic> a) async {
    final pkg = '${a['package'] ?? ''}';
    final target = (a['targetSdk'] as num?)?.toInt() ?? 0;
    final min = (a['minSdk'] as num?)?.toInt() ?? 0;
    String sdkLine(int sdk) {
      if (sdk <= 0) return '—';
      final m = androidMetaFor(sdk);
      return '${m.label} (${m.codename}, API $sdk)';
    }

    Map<String, dynamic>? det;
    try {
      det = await () async {
        // Lazy per-app component lists.
        return await DeviceExtraService.getAppDetail(pkg);
      }();
    } catch (_) {}
    det ??= const {};

    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return [for (final e in v) '$e'];
    }

    final perms = strList(det['permissions']);
    final acts = strList(det['activities']);
    final svcs = strList(det['services']);
    final recs = strList(det['receivers']);
    final provs = strList(det['providers']);

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding:
              const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: 0.25),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: a['icon'] == null
                      ? Icon(LucideIcons.package,
                          color:
                              Theme.of(context).hintColor)
                      : Image.memory(a['icon'],
                          fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('${a['label'] ?? pkg}',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight:
                                      FontWeight.w800)),
                      Text(pkg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 11.5,
                                  color: Theme.of(
                                          context)
                                      .hintColor)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Dt.accent
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text('API $target',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 10.5,
                                    fontWeight:
                                        FontWeight.w800,
                                    color: Dt.accent)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'App settings',
                  onPressed: () =>
                      DeviceExtraService.openAppSettings(
                          pkg),
                  icon: const Icon(LucideIcons.settings, size: 20),
                ),
              ],
            ),
            const Divider(height: 24),
            _dRow('Version',
                '${a['version'] ?? '—'} (${(a['versionCode'] as num?)?.toInt() ?? '—'})'),
            _dRow('Minimum', sdkLine(min)),
            _dRow('Target', sdkLine(target)),
            _dRow(
                'Installed',
                _date((a['firstInstall'] as num?)
                        ?.toInt() ??
                    0)),
            _dRow(
                'Last Updated',
                _date((a['lastUpdate'] as num?)?.toInt() ??
                    0)),
            _dRow('Installer',
                _installerLabel(a['installer']?.toString())),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _compChip(context, 'Permissions', perms,
                    (v) => v.split('.').last),
                _compChip(context, 'Activities', acts,
                    (v) => v.split('.').last),
                _compChip(context, 'Services', svcs,
                    (v) => v.split('.').last),
                _compChip(context, 'Receivers', recs,
                    (v) => v.split('.').last),
                _compChip(context, 'Providers', provs,
                    (v) => v.split('.').last),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actBtn(
                    context,
                    LucideIcons.play,
                    'Google Play',
                    () => _openPlay(pkg)),
                _actBtn(context, LucideIcons.download,
                    'Extract App', () => _extract(context, a)),
                _actBtn(context, LucideIcons.externalLink,
                    'Launch', () => _launch(context, pkg)),
                _actBtn(context, LucideIcons.refreshCw,
                    'Data Usage', () {
                  Navigator.pop(ctx);
                  Get.to(() => const DataUsageView());
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: Colors.grey[700])),
          ),
          Expanded(
            child: Text(v,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _compChip(BuildContext context, String label,
      List<String> items, String Function(String) short) {
    return InkWell(
      onTap: items.isEmpty
          ? null
          : () => _showCompList(context, label, items, short),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.8)),
        ),
        child: Text('$label (${items.length})',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _showCompList(BuildContext context, String label,
      List<String> items, String Function(String) short) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('$label (${items.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(short(items[i]),
                  style: GoogleFonts.firaCode(fontSize: 11.5)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _actBtn(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _openPlay(String pkg) async {
    try {
      final market =
          Uri.parse('market://details?id=$pkg');
      // ignore: deprecated_member_use
      if (await canLaunchUrl(market)) {
        await launchUrl(market,
            mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    try {
      await launchUrl(
          Uri.parse(
              'https://play.google.com/store/apps/details?id=$pkg'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _extract(
      BuildContext context, Map<String, dynamic> a) async {
    Get.snackbar('Extracting…', 'Copying APK, please wait.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
    final path = await DeviceExtraService.extractApk(
        '${a['package'] ?? ''}');
    if (path == null || path.isEmpty) {
      Get.snackbar('Extract failed',
          'Could not read this APK.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await Share.shareXFiles([XFile(path)],
          text: '${a['label'] ?? 'App'} APK');
    } catch (_) {
      Get.snackbar('Saved', path,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _launch(BuildContext context, String pkg) async {
    final ok = await DeviceExtraService.launchApp(pkg);
    if (!ok) {
      Get.snackbar('Cannot launch',
          'This package has no launchable activity.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }
}
