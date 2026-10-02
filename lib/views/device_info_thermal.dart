import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';

/// Thermal tab: live thermal-zone thermometer. Every
/// /sys/class/thermal/thermal_zone* the kernel exposes is read —
/// beyond the screenshots, any extra device sensor is detected too.
/// Groups: CPU / GPU / Memory / Battery / Camera / Other, each with
/// show more/less. Header shows the hottest zone + status chips.
class ThermalTab extends StatelessWidget {
  const ThermalTab({super.key});

  static String _statusLabel(int s) {
    switch (s) {
      case 0:
        return 'Normal';
      case 1:
        return 'Light';
      case 2:
        return 'Moderate';
      case 3:
        return 'Severe';
      case 4:
        return 'Critical';
      case 5:
        return 'Emergency';
      case 6:
        return 'Shutdown';
      default:
        return '—';
    }
  }

  static String _groupOf(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('cpu-') || n.startsWith('cpuss-')) {
      return 'CPU';
    }
    if (n.startsWith('gpu')) return 'GPU';
    if (n.startsWith('ddr-')) return 'Memory';
    if (n == 'battery') return 'Battery';
    if (n.startsWith('camera-')) return 'Camera';
    return 'Other';
  }

  static String _temp(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return '—';
    return '${d.toStringAsFixed(1)} °C';
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      final raw = c.thermal.value;
      final sensors = <Map<String, dynamic>>[];
      if (raw != null && raw['sensors'] is List) {
        for (final e in (raw['sensors'] as List)) {
          if (e is Map) {
            sensors.add(Map<String, dynamic>.from(e));
          }
        }
      }
      sensors.sort((a, b) {
        final ta = (a['tempC'] as num?)?.toDouble() ?? -999;
        final tb = (b['tempC'] as num?)?.toDouble() ?? -999;
        return tb.compareTo(ta);
      });
      final status = (raw?['status'] as num?)?.toInt() ?? -1;
      var hot = 0.0;
      var hotGroup = '—';
      for (final s in sensors) {
        final t = (s['tempC'] as num?)?.toDouble() ?? -999;
        if (t > hot) {
          hot = t;
          hotGroup = _groupOf('${s['name'] ?? ''}');
        }
      }
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final s in sensors) {
        final g = _groupOf('${s['name'] ?? ''}');
        groups.putIfAbsent(g, () => []).add(s);
      }
      const order = ['CPU', 'GPU', 'Memory', 'Battery', 'Camera'];
      final ordered = [
        for (final g in order)
          if (groups.containsKey(g)) g,
        for (final g in groups.keys)
          if (!order.contains(g)) g,
      ];

      Widget chip(String s) {
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

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('Thermal Status',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight:
                                      FontWeight.w700,
                                  color: Theme.of(
                                          context)
                                      .hintColor)),
                      const SizedBox(height: 2),
                      Text(
                          sensors.isEmpty
                              ? '—'
                              : '${hot.toStringAsFixed(1)} °C',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 30,
                                  fontWeight:
                                      FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          chip(_statusLabel(status)),
                          chip(hotGroup),
                          chip(
                              '${sensors.length} Sensors'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                    LucideIcons.thermometerSun,
                    size: 44,
                    color: Dt.accent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (sensors.isEmpty)
            Text('No thermal zones reported on this device.',
                style: GoogleFonts.plusJakartaSans(
                    color: Theme.of(context).hintColor))
          else
            for (final g in ordered)
              _ThermalGroupCard(
                title: g,
                sensors: groups[g]!,
              ),
        ],
      );
    });
  }
}

/// One group card with show more/less (first 5 + "Show all · N more").
class _ThermalGroupCard extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> sensors;
  const _ThermalGroupCard(
      {required this.title, required this.sensors});

  @override
  State<_ThermalGroupCard> createState() =>
      _ThermalGroupCardState();
}

class _ThermalGroupCardState extends State<_ThermalGroupCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.sensors;
    final shown =
        _expanded ? list : list.take(5).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              Text('${list.length} Sensors',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context).hintColor)),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in shown)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${s['name'] ?? '—'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .hintColor)),
                  ),
                  Text(
                      ThermalTab._temp(s['tempC']),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          if (list.length > 5)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _expanded = !_expanded),
                child: Text(
                    _expanded
                        ? 'Show less'
                        : 'Show all · ${list.length - 5} more',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Dt.accent)),
              ),
            ),
        ],
      ),
    );
  }
}
