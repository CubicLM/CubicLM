import 'package:flutter/material.dart';

import 'device_info_dash_battery.dart';
import 'device_info_dash_cpu.dart';
import 'device_info_dash_overview.dart';
import 'device_info_dash_ram.dart';
import 'device_info_dash_storage.dart';

/// Dashboard tab: RAM card, CPU grid, storage bar, battery card,
/// display/sensors row.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: const [
        DashRamCard(),
        SizedBox(height: 12),
        DashCpuCard(),
        SizedBox(height: 12),
        DashStorageCard(),
        SizedBox(height: 12),
        DashBatteryCard(),
        SizedBox(height: 12),
        DashDisplaySensorsRow(),
      ],
    );
  }
}
