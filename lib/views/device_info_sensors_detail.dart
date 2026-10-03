import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import 'device_info_sensors_row.dart';
import 'device_info_widgets.dart';

/// Sensors tab: detail dialog (Vendor, Type, Wake-up, Version, Max
/// range, Resolution, Power, delays, FIFOs, Reporting mode).
/// Static — plain params only.
class SensorDetailDialog extends StatelessWidget {
  final Map<String, dynamic> sensor;
  const SensorDetailDialog(
      {super.key, required this.sensor});

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

  @override
  Widget build(BuildContext context) {
    final s = sensor;
    final name = '${s['name'] ?? 'Unknown sensor'}';
    final wakeup = s['wakeup'] == true;
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(sensorIconFor(s),
              size: 20, color: Dt.accent),
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
                sensorTypeLabelFor(s)),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Shows the sensor detail dialog.
void showSensorDetail(
    BuildContext context, Map<String, dynamic> s) {
  showDialog(
    context: context,
    builder: (ctx) =>
        SensorDetailDialog(sensor: s),
  );
}
