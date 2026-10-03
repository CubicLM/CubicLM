import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_sensors_detail.dart';

/// Sensors tab: one card per sensor (icon by kind,
/// "name  Wakeup/Non-wakeup", Vendor, Type) + detail dialog.
/// Every sensor the OS reports is listed — nothing is filtered out.
/// Static — plain params only.

String _sensorTypeKey(Map<String, dynamic> s) {
  var t = '${s['type'] ?? ''}'.trim().toLowerCase();
  const prefix = 'android.sensor.';
  if (t.startsWith(prefix)) t = t.substring(prefix.length);
  return t;
}

/// Icon for a sensor by kind (shared with the detail dialog title).
IconData sensorIconFor(Map<String, dynamic> s) {
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

/// Upper-case type label (shared with the detail dialog rows).
String sensorTypeLabelFor(Map<String, dynamic> s) {
  var t = '${s['type'] ?? ''}'.trim();
  const prefix = 'android.sensor.';
  if (t.toLowerCase().startsWith(prefix)) {
    t = t.substring(prefix.length);
  }
  t = t.replaceAll('_', ' ').trim().toUpperCase();
  return t.isEmpty ? 'UNKNOWN SENSOR' : t;
}

class SensorRow extends StatelessWidget {
  final Map<String, dynamic> sensor;
  const SensorRow({super.key, required this.sensor});

  @override
  Widget build(BuildContext context) {
    final s = sensor;
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
        onTap: () => showSensorDetail(
            context, Map<String, dynamic>.from(s)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                  sensorIconFor(
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
                                    FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        'Vendor : ${s['vendor'] ?? '—'}',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .hintColor)),
                    Text(
                        'Type : ${sensorTypeLabelFor(Map<String, dynamic>.from(s))}',
                        style: GoogleFonts
                            .plusJakartaSans(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .hintColor)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight,
                  size: 18,
                  color: Theme.of(context).hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
