import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_log_service.dart';
import '../theme/design_tokens.dart';

/// Android version table + asset matching for the System tab header.
///
/// Images live in assets/android_version/ as
/// `Android_<version>_<Codename>.png` (e.g. Android_11_Red_Velvet_Cake).
/// Matching is done by READING file names (prefix + version tokens),
/// so future drops work without code changes.
class AndroidVersionMeta {
  final String label; // "Android 11"
  final String codename; // "Red Velvet Cake"
  final String released; // "September 8, 2020"
  const AndroidVersionMeta(this.label, this.codename, this.released);
}

const _androidTable = <int, AndroidVersionMeta>{
  21: AndroidVersionMeta('Android 5.0', 'Lollipop', 'November 12, 2014'),
  22: AndroidVersionMeta('Android 5.1', 'Lollipop', 'March 9, 2015'),
  23: AndroidVersionMeta('Android 6.0', 'Marshmallow', 'October 5, 2015'),
  24: AndroidVersionMeta('Android 7.0', 'Nougat', 'August 22, 2016'),
  25: AndroidVersionMeta('Android 7.1', 'Nougat', 'October 4, 2016'),
  26: AndroidVersionMeta('Android 8.0', 'Oreo', 'August 21, 2017'),
  27: AndroidVersionMeta('Android 8.1', 'Oreo', 'December 5, 2017'),
  28: AndroidVersionMeta('Android 9', 'Pie', 'August 6, 2018'),
  29: AndroidVersionMeta('Android 10', 'Q', 'September 3, 2019'),
  30: AndroidVersionMeta(
      'Android 11', 'Red Velvet Cake', 'September 8, 2020'),
  31: AndroidVersionMeta('Android 12', 'Snow Cone', 'October 4, 2021'),
  32: AndroidVersionMeta('Android 12L', 'Snow Cone', 'March 7, 2022'),
  33: AndroidVersionMeta('Android 13', 'Tiramisu', 'August 15, 2022'),
  34: AndroidVersionMeta(
      'Android 14', 'Upside Down Cake', 'October 4, 2023'),
  35: AndroidVersionMeta(
      'Android 15', 'Vanilla Ice Cream', 'September 3, 2024'),
  36: AndroidVersionMeta('Android 16', 'Baklava', 'June 10, 2025'),
  37: AndroidVersionMeta('Android 17', 'Quince Tart', '—'),
};

AndroidVersionMeta androidMetaFor(int sdk) =>
    _androidTable[sdk] ??
    const AndroidVersionMeta('Android', '—', '—');

/// Candidate bundled paths for a release, in priority order, following
/// the shipped naming convention `Android_<version>_<Codename>.png`
/// (e.g. Android_11_Red_Velvet_Cake.png). The image widget tries each
/// in turn — no manifest read, no code change for future drops as long
/// as the convention holds.
List<String> androidVersionAssets(String release, String codename) {
  final rel = release.trim();
  final parts = rel.split('.');
  final code = codename.trim().replaceAll(' ', '_');
  final vers = <String>[rel];
  if (parts.length >= 2) vers.add('${parts[0]}.${parts[1]}');
  vers.add(parts[0]);
  vers.add('${parts[0]}.0');
  final out = <String>[];
  for (final v in vers) {
    final p = 'assets/android_version/Android_${v}_$code.png';
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

/// Tries each candidate artwork in order, falling back to the robot
/// icon when none is bundled.
class VersionArtwork extends StatefulWidget {
  final List<String> candidates;
  const VersionArtwork({super.key, required this.candidates});

  @override
  State<VersionArtwork> createState() => _VersionArtworkState();
}

class _VersionArtworkState extends State<VersionArtwork> {
  var _i = 0;
  final _logged = <String>{};

  void _logMiss(String asset, Object error) {
    if (!_logged.add(asset)) return;
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().debug(
          '[VersionArt] miss $asset: $error',
          category: LogCategory.system,
        );
      }
    } catch (_) {}
    debugPrint('[VersionArt] miss $asset: $error');
  }

  @override
  Widget build(BuildContext context) {
    if (_i >= widget.candidates.length) {
      return const Icon(Icons.android, size: 40, color: Colors.white);
    }
    final asset = widget.candidates[_i];
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, err, __) {
        _logMiss(asset, err);
        // Missing file (e.g. hot-reload before a reinstall bundles
        // new assets): try the next candidate, then the icon.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _i++);
        });
        return const SizedBox.shrink();
      },
    );
  }
}

/// Brown header card: version artwork + label + codename + release date
/// + codename/API chips (reference layout, app fonts).
class AndroidVersionHeader extends StatelessWidget {
  final AndroidVersionMeta meta;
  final int sdk;
  final String release;
  const AndroidVersionHeader(
      {super.key,
      required this.meta,
      required this.sdk,
      required this.release});

  @override
  Widget build(BuildContext context) {
    // App card language: paper surface + hairline border, accent only
    // on the artwork tile and chips (no solid brown slab).
    final onSurface =
        Theme.of(context).colorScheme.onSurface;
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
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  Dt.accent.withValues(alpha: 0.12),
            ),
            clipBehavior: Clip.antiAlias,
            child: VersionArtwork(
                candidates:
                    androidVersionAssets(release, meta.codename)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta.label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: onSurface)),
                Text(meta.codename,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: onSurface)),
                const SizedBox(height: 2),
                Text('Released : ${meta.released}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    _chip(context, meta.codename),
                    _chip(context, 'API $sdk'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String s) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Dt.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(s,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Dt.accent)),
    );
  }
}
