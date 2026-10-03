import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Shared app-list formatting (exact copies of the original AppsTab
/// helpers). Lives here so the row and the detail sheet import one
/// source instead of duplicating logic.
String formatAppSize(int bytes) {
  if (bytes < 1000) return '$bytes B';
  String t(double v) =>
      v.truncateToDouble() == v ? '${v.toInt()}' : v.toStringAsFixed(2);
  if (bytes < 1000000) return '${t(bytes / 1000)} kB';
  if (bytes < 1000000000) {
    return '${t(bytes / 1000000)} MB';
  }
  return '${t(bytes / 1000000000)} GB';
}

String formatAppDate(int ms) {
  if (ms <= 0) return '—';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]} ${d.year}';
}

String installerLabel(String? pkg) {
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

/// One installed-package row: icon, label/package/version, APK size
/// badge. Tapping opens the detail sheet via [onTap].
class AppListRow extends StatelessWidget {
  final Map<String, dynamic> app;
  final VoidCallback onTap;

  const AppListRow({super.key, required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = app;
    final icon = a['icon'];
    final bytes = (a['apkBytes'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                Theme.of(context).dividerColor.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
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
                        color: Theme.of(context).hintColor)
                    : Image.memory(icon, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            color: Theme.of(context).hintColor)),
                    Text('Version : ${a['version'] ?? '—'}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Theme.of(context).hintColor)),
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
                child: Text(formatAppSize(bytes),
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
}
