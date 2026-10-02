import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';

/// Camera tab: one card per camera id (Back/Front/External) + the full
/// Camera2 characteristics of the selected one. Everything is measured
/// live — no permission needed (characteristics are never opened).
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  var _sel = 0;

  static const _ae = {
    0: 'Off',
    1: 'On',
    2: 'Auto Flash',
    3: 'Always Flash',
    4: 'Auto Flash Red-eye',
  };
  static const _af = {
    0: 'Off',
    1: 'Auto',
    2: 'Macro',
    3: 'Continuous Video',
    4: 'Continuous Picture',
    5: 'Extended DOF',
  };
  static const _awb = {
    0: 'Auto',
    1: 'Incandescent',
    2: 'Fluorescent',
    3: 'Warm Fluorescent',
    4: 'Daylight',
    5: 'Cloudy Daylight',
    6: 'Twilight',
    7: 'Shade',
    8: 'Off',
  };
  static const _edge = {
    0: 'Off',
    1: 'Fast',
    2: 'High Quality',
    3: 'Zero Shutter Lag',
  };
  static const _noise = {
    0: 'Off',
    1: 'Fast',
    2: 'High Quality',
    3: 'Minimal',
    4: 'Zero Shutter Lag',
  };
  static const _hotPixel = {0: 'Off', 1: 'Fast', 2: 'High Quality'};
  static const _effects = {
    0: 'Off',
    1: 'Mono',
    2: 'Negative',
    3: 'Solarize',
    4: 'Sepia',
    5: 'Posterize',
    6: 'Whiteboard',
    7: 'Blackboard',
    8: 'Aqua',
  };
  static const _scenes = {
    0: 'Disabled',
    1: 'Face Priority',
    2: 'Action',
    3: 'Portrait',
    4: 'Landscape',
    5: 'Night',
    6: 'Night Portrait',
    7: 'Theatre',
    8: 'Beach',
    9: 'Snow',
    10: 'Sunset',
    11: 'Steady Photo',
    12: 'Fireworks',
    13: 'Sports',
    14: 'Party',
    15: 'Candlelight',
    16: 'Barcode',
    17: 'High Speed Video',
    18: 'HDR',
  };
  static const _stab = {
    0: 'Off',
    1: 'On',
    2: 'Preview Stabilization',
  };
  static const _face = {0: 'Off', 1: 'Simple', 2: 'Full'};
  static const _testPat = {
    0: 'Off',
    1: 'Solid Color',
    2: 'Color Bars',
    3: 'Fade To Gray',
    4: 'PN9',
    5: 'Custom 1',
  };
  static const _cfa = {
    0: 'RGGB',
    1: 'GRBG',
    2: 'GBGR',
    3: 'BGGR',
    4: 'RGB',
  };
  static const _caps = {
    0: 'Backward Compatible',
    1: 'Manual Sensor',
    2: 'Manual Post Processing',
    3: 'RAW',
    4: 'Private Reprocessing',
    5: 'Read Sensor Settings',
    6: 'Burst Capture',
    7: 'YUV Reprocessing',
    8: 'Depth Output',
    9: 'Constrained High Speed Video',
    10: 'Motion Tracking',
    11: 'Logical Multi Camera',
    12: 'Monochrome',
    13: 'Secure Image Data',
    14: 'System Camera',
    15: 'Offline Processing',
    16: 'Ultra High Resolution',
  };

  static String _facing(int f) {
    switch (f) {
      case 0:
        return 'Back';
      case 1:
        return 'Front';
      case 2:
        return 'External';
      default:
        return '—';
    }
  }

  static String _hwLevel(dynamic v) {
    switch (v) {
      case 0:
        return 'Limited';
      case 1:
        return 'Full';
      case 2:
        return 'Legacy';
      case 3:
        return 'Level 3';
      case 4:
        return 'External';
      default:
        return '—';
    }
  }

  /// Short lists read as "a, b, c"; long ones as bullet lines.
  static String _modes(dynamic raw, Map<int, String> table) {
    final items = <String>[];
    if (raw is List) {
      for (final e in raw) {
        final i = (e as num?)?.toInt();
        if (i == null) continue;
        items.add(table[i] ?? 'Mode $i');
      }
    }
    if (items.isEmpty) return '—';
    if (items.length <= 3) return items.join(', ');
    return items.map((s) => '• $s').join('\n');
  }

  static List<int> _ints(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is num) e.toInt()
    ];
  }

  static List<double> _dbls(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is num) e.toDouble()
    ];
  }

  static List<String> _strs(dynamic raw) {
    if (raw is! List) return const [];
    return [for (final e in raw) '$e'];
  }

  static String _mp(dynamic v) {
    final d = (v as num?)?.toDouble() ?? -1;
    if (d < 0) return '—';
    return d.truncateToDouble() == d
        ? '${d.toInt()} MP'
        : '${d.toStringAsFixed(1)} MP';
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      final cams = (c.cameras.value ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort((a, b) => ((a['facing'] as num?)?.toInt() ?? 9)
            .compareTo((b['facing'] as num?)?.toInt() ?? 9));
      if (cams.isEmpty) {
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text('No cameras reported on this device.',
                style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).hintColor)),
          ],
        );
      }
      if (_sel >= cams.length) _sel = 0;
      final sel = cams[_sel];
      int facingOf(Map<String, dynamic> m) =>
          (m['facing'] as num?)?.toInt() ?? -1;
      String cardTitle(Map<String, dynamic> m) {
        final mp = _mp(m['mp']);
        return '$mp - ${_facing(facingOf(m))}';
      }

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cams.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final m = cams[i];
                final selected = i == _sel;
                final focals = _dbls(m['focals']);
                return GestureDetector(
                  onTap: () => setState(() => _sel = i),
                  child: Stack(
                    children: [
                      Container(
                        width: 168,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? Dt.accent
                              : Theme.of(context)
                                  .cardColor,
                          borderRadius:
                              BorderRadius.circular(16),
                          border: Border.all(
                              color: selected
                                  ? Dt.accent
                                  : Theme.of(context)
                                      .dividerColor
                                      .withValues(
                                          alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Text(cardTitle(m),
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight
                                                .w800,
                                        color: selected
                                            ? Colors.white
                                            : null)),
                            const SizedBox(height: 2),
                            Text(
                                '${m['maxW'] ?? '—'} x ${m['maxH'] ?? '—'}',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12.5,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: selected
                                            ? Colors.white
                                                .withValues(
                                                    alpha:
                                                        0.9)
                                            : Theme.of(
                                                    context)
                                                .hintColor)),
                            Text(
                                focals.isEmpty
                                    ? '—'
                                    : '${focals.first.toStringAsFixed(2)}mm',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12.5,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: selected
                                            ? Colors.white
                                                .withValues(
                                                    alpha:
                                                        0.9)
                                            : Theme.of(
                                                    context)
                                                .hintColor)),
                          ],
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          right: 10,
                          bottom: 10,
                          child: Icon(
                              LucideIcons.checkCircle2,
                              size: 20,
                              color: Colors.white),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _note(context),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: _rows(context, sel),
            ),
          ),
        ],
      );
    });
  }

  Widget _note(BuildContext context) {
    return Text(
      'Please Read This: if the MegaPixel count shown is wrong, that means your device manufacturer has limited the access to the camera for third-party apps.',
      style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          height: 1.5,
          color: Theme.of(context).hintColor),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool last = false}) {
    var v = value.trim();
    if (v.isEmpty) v = '—';
    final multi = v.contains('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        multi
            ? Text(v,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Dt.accent))
            : SelectableText(v,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5, color: Dt.accent)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(
              height: 1,
              thickness: 0.5,
              color: last
                  ? Colors.transparent
                  : Theme.of(context)
                      .dividerColor
                      .withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  List<MapEntry<String, String>> _entries(
      Map<String, dynamic> m) {
    final focals = _dbls(m['focals']);
    final apertures = _dbls(m['apertures']);
    final nd = _dbls(m['ndDensities']);
    final thumbs = _strs(m['thumbs']);
    final sizes = _strs(m['sizes']);
    final streams = _ints(m['streams']);
    final ois = _ints(m['ois']);
    final facing = (m['facing'] as num?)?.toInt() ?? -1;
    String focusCalib() {
      switch (m['focusCalib']) {
        case 0:
          return 'Uncalibrated';
        case 1:
          return 'Approximate';
        case 2:
          return 'Calibrated';
        default:
          return '—';
      }
    }

    String cfa() =>
        _cfa[(m['cfa'] as num?)?.toInt()] ?? '—';

    String tsSrc() {
      switch (m['timestampSrc']) {
        case 0:
          return 'Unknown';
        case 1:
          return 'Realtime';
        default:
          return '—';
      }
    }

    return [
      MapEntry(
          'Aberration Modes', _modes(m['aberrModes'], _edge)),
      const MapEntry(
          'Antibanding Modes', 'Off, 50Hz, 60Hz, Auto'),
      MapEntry(
          'Auto Exposure Modes', _modes(m['aeModes'], _ae)),
      MapEntry('Compensation Step',
          (m['aeStep']?.toString() ?? '—')),
      MapEntry(
          'AutoFocus Modes', _modes(m['afModes'], _af)),
      MapEntry('Effects', _modes(m['effects'], _effects)),
      MapEntry(
          'Scene Modes', _modes(m['scenes'], _scenes)),
      MapEntry('Video Stabilization Modes',
          _modes(m['stabModes'], _stab)),
      MapEntry('Auto White Balance Modes',
          _modes(m['awbModes'], _awb)),
      MapEntry('Maximum Auto Exposure Regions',
          '${m['aeRegions'] ?? '—'}'),
      MapEntry('Maximum Auto Focus Regions',
          '${m['afRegions'] ?? '—'}'),
      MapEntry('Maximum Auto White Balance Regions',
          '${m['awbRegions'] ?? '—'}'),
      MapEntry(
          'Edge Modes', _modes(m['edgeModes'], _edge)),
      MapEntry('Noise Reduction Modes',
          _modes(m['noiseModes'], _noise)),
      MapEntry('Flash Available',
          (m['flash'] == true) ? 'Yes' : 'No'),
      MapEntry('Hot Pixel Modes',
          _modes(m['hotPixelModes'], _hotPixel)),
      MapEntry(
          'Hardware Level', _hwLevel(m['hwLevel'])),
      MapEntry(
          'Thumbnail Sizes',
          thumbs.isEmpty
              ? '—'
              : thumbs.map((s) => '• $s').join('\n')),
      MapEntry('Lens Placement', _facing(facing)),
      MapEntry(
          'Apertures',
          apertures.isEmpty
              ? '—'
              : apertures
                  .map((a) => 'f/${a.toStringAsFixed(2)}')
                  .join(', ')),
      MapEntry('Filter Densities',
          nd.isEmpty ? '—' : nd.map((a) => '$a').join(', ')),
      MapEntry(
          'Focal Lengths',
          focals.isEmpty
              ? '—'
              : focals
                  .map((a) => '${a.toStringAsFixed(2)}mm')
                  .join(', ')),
      MapEntry(
          'Optical Stabilization',
          ois.isEmpty
              ? '—'
              : ois
                  .map((o) => o == 1 ? 'On' : 'Off')
                  .join(', ')),
      MapEntry('Focus Distance Calibration', focusCalib()),
      MapEntry(
          'Camera Capabilities', _modes(m['caps'], _caps)),
      MapEntry('Maximum Output Streams',
          streams.isNotEmpty ? '${streams[0]}' : '—'),
      MapEntry('Maximum Output Streams Stalling',
          streams.length > 2 ? '${streams[2]}' : '—'),
      MapEntry('Maximum RAW Output Streams',
          streams.length > 1 ? '${streams[1]}' : '—'),
      MapEntry(
          'Partial Results', '${m['partialResults'] ?? '—'}'),
      MapEntry('Maximum Digital Zoom',
          (m['maxZoom'] as num?)?.toString() ?? '—'),
      MapEntry(
          'Cropping Type',
          (m['cropType'] as num?)?.toInt() == 1
              ? 'Freeform'
              : 'Center Only'),
      MapEntry(
          'Supported Resolutions',
          sizes.isEmpty
              ? '—'
              : sizes.map((s) => '• $s').join('\n')),
      MapEntry('Test Pattern Modes',
          _modes(m['testPatterns'], _testPat)),
      MapEntry('Color Filter Arrangement', cfa()),
      MapEntry(
          'Sensor Size',
          (m['sensorSize']?.toString().isNotEmpty ?? false)
              ? m['sensorSize'].toString()
              : '—'),
      MapEntry(
          'Pixel Array Size',
          (m['pixelArray']?.toString().isNotEmpty ?? false)
              ? m['pixelArray'].toString()
              : '—'),
      MapEntry('Timestamp Source', tsSrc()),
      MapEntry(
          'Orientation',
          m['orientation'] != null
              ? '${m['orientation']} deg'
              : '—'),
      MapEntry(
          'Face Detection Modes', _modes(m['faceModes'], _face)),
    ];
  }

  List<Widget> _rows(
      BuildContext context, Map<String, dynamic> m) {
    final entries = _entries(m);
    return [
      for (var i = 0; i < entries.length; i++)
        _row(context, entries[i].key, entries[i].value,
            last: i == entries.length - 1),
    ];
  }
}
