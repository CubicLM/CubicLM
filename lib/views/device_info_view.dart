import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_extra_service.dart';
import 'device_info_apps.dart';
import 'device_info_camera.dart';
import 'device_info_tab_battery.dart';
import 'device_info_tab_connectivity.dart';
import 'device_info_tab_cpu.dart';
import 'device_info_tab_dashboard.dart';
import 'device_info_tab_device.dart';
import 'device_info_tab_display.dart';
import 'device_info_tab_memory.dart';
import 'device_info_tab_network.dart';
import 'device_info_tab_sensors.dart';
import 'device_info_tab_system.dart';
import 'device_info_thermal.dart';

/// CubicDevice Info — on-device hardware dashboard (Toolkit feature).
/// Thin shell: one tab widget per file under
/// views/device_info_tab_*.dart (Camera/Apps/Thermal already had
/// their own files). Every number is measured live; unknowns render
/// as '—', never as fake zeros.
class DeviceInfoView extends StatefulWidget {
  const DeviceInfoView({super.key});

  @override
  State<DeviceInfoView> createState() => _DeviceInfoViewState();
}

class _DeviceInfoViewState extends State<DeviceInfoView> {
  late final DeviceInfoController c;
  Future<AndroidDeviceInfo>? _androidInfo;
  Future<Map<String, dynamic>?>? _sysInfo;

  static const _tabs = [
    'Dashboard',
    'Device',
    'System',
    'CPU',
    'Battery',
    'Network',
    'Connectivity',
    'Display',
    'Memory',
    'Camera',
    'Sensors',
    'Thermal',
    'Apps'
  ];

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<DeviceInfoController>()
        ? Get.find<DeviceInfoController>()
        : Get.put(DeviceInfoController());
    _androidInfo = DeviceInfoPlugin().androidInfo;
    _sysInfo = DeviceExtraService.getSystemInfo();
  }

  @override
  void dispose() {
    try {
      Get.delete<DeviceInfoController>();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('CubicDevice Info',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: () => c.refreshAll(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Same pill language as Explore → Local filter chips.
          Obx(() => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++) ...[
                      InkWell(
                        onTap: () => c.tab.value = i,
                        borderRadius:
                            BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.tab.value == i
                                ? Theme.of(context)
                                    .primaryColor
                                    .withValues(alpha: 0.18)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                              color: c.tab.value == i
                                  ? Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.3)
                                  : Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (c.tab.value == i) ...[
                                Icon(Icons.check,
                                    size: 16,
                                    color: Theme.of(context)
                                        .primaryColor),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                _tabs[i],
                                style: GoogleFonts
                                    .plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: c.tab.value == i
                                      ? Theme.of(context)
                                          .primaryColor
                                      : Theme.of(context)
                                          .hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              switch (c.tab.value) {
                case 1:
                  return DeviceTab(
                      androidInfo: _androidInfo);
                case 2:
                  return SystemTab(
                      androidInfo: _androidInfo,
                      sysInfo: _sysInfo);
                case 3:
                  return CpuTab(
                      androidInfo: _androidInfo);
                case 4:
                  return const BatteryTab();
                case 5:
                  return const NetworkTab();
                case 6:
                  return const ConnectivityTab();
                case 7:
                  return const DisplayTab();
                case 8:
                  return const MemoryTab();
                case 9:
                  return const CameraTab();
                case 10:
                  return const SensorsTab();
                case 11:
                  return const ThermalTab();
                case 12:
                  return const AppsTab();
                case 0:
                default:
                  return const DashboardTab();
              }
            }),
          ),
        ],
      ),
    );
  }
}
