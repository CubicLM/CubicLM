import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_thermal_curve.dart';
import 'device_info_thermal_group.dart';
import 'device_info_thermal_header.dart';
import 'device_info_thermal_utils.dart';

/// Thermal tab: live thermal-zone thermometer. Every
/// /sys/class/thermal/thermal_zone* the kernel exposes is read —
/// beyond the screenshots, any extra device sensor is detected too.
/// Groups: CPU / GPU / Memory / Battery / Camera / Other, each with
/// show more/less. Header shows the hottest zone + status chips.
///
/// Thin shell: the outer Obx ONLY gates `loading`. Sorting, grouping
/// and hottest-zone math are memoized by value in [_ThermalBody], so
/// the ~5s thermal ticks that change nothing never rebuild the list.
class ThermalTab extends StatelessWidget {
  const ThermalTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      if (c.loading.value) {
        return const Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ));
      }
      return _ThermalBody(thermal: c.thermal.value);
    });
  }
}

class _ThermalBody extends StatefulWidget {
  final Map<String, dynamic>? thermal;

  const _ThermalBody({required this.thermal});

  @override
  State<_ThermalBody> createState() => _ThermalBodyState();
}

class _ThermalBodyState extends State<_ThermalBody> {
  var _lastKey = '';
  var _sensors = const <Map<String, dynamic>>[];
  var _ordered = const <String>[];
  var _groups = const <String, List<Map<String, dynamic>>>{};
  var _hot = 0.0;
  var _hotGroup = '—';
  var _status = -1;

  void _ensure() {
    final raw = widget.thermal;
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
    final key = StringBuffer()..write(status)..write('|');
    for (final s in sensors) {
      key
        ..write(s['name'])
        ..write('=')
        ..write(s['tempC'])
        ..write(';');
    }
    final k = key.toString();
    if (k == _lastKey) return;
    _lastKey = k;
    _sensors = sensors;
    _status = status;
    var hot = 0.0;
    var hotGroup = '—';
    for (final s in sensors) {
      final t = (s['tempC'] as num?)?.toDouble() ?? -999;
      if (t > hot) {
        hot = t;
        hotGroup = thermalGroupOf('${s['name'] ?? ''}');
      }
    }
    _hot = hot;
    _hotGroup = hotGroup;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in sensors) {
      final g = thermalGroupOf('${s['name'] ?? ''}');
      groups.putIfAbsent(g, () => []).add(s);
    }
    const order = ['CPU', 'GPU', 'Memory', 'Battery', 'Camera'];
    _ordered = [
      for (final g in order)
        if (groups.containsKey(g)) g,
      for (final g in groups.keys)
        if (!order.contains(g)) g,
    ];
    _groups = groups;
  }

  @override
  Widget build(BuildContext context) {
    _ensure();
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        ThermalHeaderCard(
          sensorCount: _sensors.length,
          hot: _hot,
          hotGroup: _hotGroup,
          status: _status,
        ),
        const SizedBox(height: 14),
        // ── Realtime Thermal Throttling Curve (60s) ──
        ThermalCurveCard(hot: _hot),
        const SizedBox(height: 14),
        if (_sensors.isEmpty)
          Text('No thermal zones reported on this device.',
              style: GoogleFonts.plusJakartaSans(
                  color: Theme.of(context).hintColor))
        else
          for (final g in _ordered)
            ThermalGroupCard(
              key: ValueKey(g),
              title: g,
              sensors: _groups[g]!,
            ),
      ],
    );
  }
}
