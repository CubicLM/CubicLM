import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/device_extra_service.dart';
import '../theme/design_tokens.dart';
import 'data_usage_view.dart';
import 'device_info_android.dart';
import 'device_info_apps_row.dart';

/// Storage-analysis dialog (exact copy of the original AppsTab
/// `_showAnalyze` content). Takes the static snapshot instead of
/// re-reading the controller so it never subscribes to ticking Rxs.
void showAppAnalyzeDialog(
    BuildContext context, List<Map<String, dynamic>> all) {
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
          Text('APKs total ${formatAppSize(total)}',
              style: GoogleFonts.plusJakartaSans()),
          if (biggest != null) ...[
            const SizedBox(height: 6),
            Text(
                'Biggest: ${biggest['label']} (${formatAppSize((biggest['apkBytes'] as num?)?.toInt() ?? 0)})',
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

/// App detail bottom sheet (exact copy of the original AppsTab
/// `_showDetail` content): SDK levels, dates, installer, component
/// chips, Play/Extract/Launch/Data-Usage actions.
Future<void> showAppDetailSheet(
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
    det = await DeviceExtraService.getAppDetail(pkg);
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
                        color: Theme.of(context).hintColor)
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
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    Text(pkg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color:
                                Theme.of(context).hintColor)),
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
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Dt.accent)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'App settings',
                onPressed: () =>
                    DeviceExtraService.openAppSettings(pkg),
                icon:
                    const Icon(LucideIcons.settings, size: 20),
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
              formatAppDate((a['firstInstall'] as num?)
                      ?.toInt() ??
                  0)),
          _dRow(
              'Last Updated',
              formatAppDate(
                  (a['lastUpdate'] as num?)?.toInt() ?? 0)),
          _dRow('Installer',
              installerLabel(a['installer']?.toString())),
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
              _actBtn(context, LucideIcons.play,
                  'Google Play', () => _openPlay(pkg)),
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
            padding:
                const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(short(items[i]),
                style:
                    GoogleFonts.firaCode(fontSize: 11.5)),
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

Widget _actBtn(BuildContext context, IconData icon,
    String label, VoidCallback onTap) {
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
    final market = Uri.parse('market://details?id=$pkg');
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

Future<void> _launch(
    BuildContext context, String pkg) async {
  final ok = await DeviceExtraService.launchApp(pkg);
  if (!ok) {
    Get.snackbar('Cannot launch',
        'This package has no launchable activity.',
        snackPosition: SnackPosition.BOTTOM);
  }
}
