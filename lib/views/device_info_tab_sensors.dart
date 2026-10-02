import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Sensors tab: count banner + one card per sensor (icon by kind,
/// "name  Wakeup/Non-wakeup", Vendor, Type) + detail dialog.
/// Every sensor the OS reports is listed — nothing is filtered out.
class SensorsTab extends StatelessWidget {
  const SensorsTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  static String _sensorTypeKey(Map<String, dynamic> s) {
    var t = '${s['type'] ?? ''}'.trim().toLowerCase();
    const prefix = 'android.sensor.';
    if (t.startsWith(prefix)) t = t.substring(prefix.length);
    return t;
  }

  static IconData _sensorIcon(Map<String, dynamic> s) {
    final t = _sensorTypeKey(s);
    final n = '${s['name'] ?? ''}'.toLowerCase();
    bool has(List<String> ks) =>
        ks.any((k) => t.contains(k) || n.contains(k));
    if (t.contains('private') || t.isEmpty) {
      return LucideIcons.lock;
    }
    if (has(['magnet', 'compass', 'geomag'])) {
      return LucideIcons.magnet;
    }
    if (has(['gyroscope', 'gyro'])) return LucideIcons.orbit;
    if (has(['accelerometer'])) return LucideIcons.gauge;
    if (has(['gravity'])) return LucideIcons.globe;
    if (has(['linear'])) return LucideIcons.trendingUp;
    if (has(['rotation', 'orientation', 'pose', 'game'])) {
      return LucideIcons.compass;
    }
    if (has(['light'])) return LucideIcons.sun;
    if (has(['proximity'])) return LucideIcons.radar;
    if (has(['pressure', 'barometer'])) return LucideIcons.cloud;
    if (has(['humidity'])) return LucideIcons.droplets;
    if (has(['temperature', 'ambient'])) {
      return LucideIcons.thermometer;
    }
    if (has(['heart', 'hrm'])) return LucideIcons.heartPulse;
    if (has([
      'step',
      'motion',
      'tilt',
      'pickup',
      'stationary',
      'pedometer',
      'significant',
      'har',
      'stow',
      'wrist'
    ])) {
      return LucideIcons.footprints;
    }
    return LucideIcons.activity;
  }

  static String _sensorTypeLabel(Map<String, dynamic> s) {
    var t = '${s['type'] ?? ''}'.trim();
    const prefix = 'android.sensor.';
    if (t.toLowerCase().startsWith(prefix)) {
      t = t.substring(prefix.length);
    }
    t = t.replaceAll('_', ' ').trim().toUpperCase();
    return t.isEmpty ? 'UNKNOWN SENSOR' : t;
  }

  static String _reportMode(dynamic v) {
    switch ((v as num?)?.toInt()) {
      case 0:
        return 'Continuous';
      case 1:
        return 'On change';
      case 2:
        return 'One shot';
      case 3:
        return 'Special trigger';
      default:
        return '—';
    }
  }

  static String _delay(dynamic us) {
    final u = (us as num?)?.toInt() ?? -1;
    if (u < 0) return '—';
    if (u == 0) return 'Fastest';
    if (u >= 1000) {
      final ms = u / 1000.0;
      return ms.truncateToDouble() == ms
          ? '${ms.toInt()} ms'
          : '${ms.toStringAsFixed(1)} ms';
    }
    return '$u µs';
  }

  void _showSensorDetail(
      BuildContext context, Map<String, dynamic> s) {
    final name = '${s['name'] ?? 'Unknown sensor'}';
    final wakeup = s['wakeup'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(_sensorIcon(s), size: 20, color: Dt.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              devRow(context, 'Vendor',
                  '${s['vendor'] ?? '—'}'),
              devRow(context, 'Type',
                  _sensorTypeLabel(s)),
              devRow(context, 'Wake-up',
                  wakeup ? 'Wakeup' : 'Non-wakeup'),
              devRow(context, 'Version',
                  '${s['version'] ?? '—'}'),
              devRow(context, 'Max range',
                  '${s['range'] ?? '—'}'),
              devRow(context, 'Resolution',
                  '${s['resolution'] ?? '—'}'),
              devRow(context, 'Power',
                  '${s['power'] ?? '—'} mA'),
              devRow(context, 'Min delay',
                  _delay(s['minDelayUs'])),
              devRow(context, 'Max delay',
                  _delay(s['maxDelayUs'])),
              devRow(context, 'FIFO reserved',
                  '${s['fifoReserved'] ?? '—'}'),
              devRow(context, 'FIFO max',
                  '${s['fifoMax'] ?? '—'}'),
              devRow(context, 'Reporting mode',
                  _reportMode(s['reportingMode']),
                  last: true),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = c.sensors.value ?? const [];
      // Lazy rows: same freeze fix as the Apps tab.
      return Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: 0.6)),
              ),
              child: Center(
                child: Text(
                    list.isEmpty
                        ? 'No sensors reported on this device.'
                        : '${list.length} Sensors are available on your device',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const SizedBox.shrink()
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    16, 0, 16, 32),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  return Container(
                    margin:
                        const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: 0.6)),
              ),
              child: InkWell(
                onTap: () => _showSensorDetail(
                    context,
                    Map<String, dynamic>.from(s)),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(_sensorIcon(
                          Map<String, dynamic>.from(s)),
                          size: 30,
                          color: Dt.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${s['name'] ?? 'Unknown sensor'}  ${s['wakeup'] == true ? 'Wakeup' : 'Non-wakeup'}',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight:
                                            FontWeight
                                                .w800)),
                            const SizedBox(height: 2),
                            Text(
                                'Vendor : ${s['vendor'] ?? '—'}',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12,
                                        color: Theme.of(
                                                context)
                                            .hintColor)),
                            Text(
                                'Type : ${_sensorTypeLabel(Map<String, dynamic>.from(s))}',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12,
                                        color: Theme.of(
                                                context)
                                            .hintColor)),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronRight,
                          size: 18,
                          color:
                              Theme.of(context).hintColor),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
        ],
      );
    });
  }
}
