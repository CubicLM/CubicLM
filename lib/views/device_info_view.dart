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
  late final PageController _pageCtrl;
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
    _pageCtrl = PageController(initialPage: c.tab.value);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    try {
      Get.delete<DeviceInfoController>();
    } catch (_) {}
    super.dispose();
  }

  void _goTab(int i) {
    c.tab.value = i;
    try {
      _pageCtrl.animateToPage(i,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    } catch (_) {}
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
          // Explore-style segmented tabs + swipeable pages.
          Obx(() => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < _tabs.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(_tabs[i],
                            style: const TextStyle(
                                fontSize: 12)),
                      ),
                  ],
                  selected: {c.tab.value},
                  onSelectionChanged: (s) =>
                      _goTab(s.first),
                  style: const ButtonStyle(
                    visualDensity:
                        VisualDensity.compact,
                    tapTargetSize:
                        MaterialTapTargetSize
                            .shrinkWrap,
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              onPageChanged: (i) {
                if (c.tab.value != i) {
                  c.tab.value = i;
                }
              },
              children: [
                const DashboardTab(),
                DeviceTab(androidInfo: _androidInfo),
                SystemTab(
                    androidInfo: _androidInfo,
                    sysInfo: _sysInfo),
                CpuTab(androidInfo: _androidInfo),
                const BatteryTab(),
                const NetworkTab(),
                const ConnectivityTab(),
                const DisplayTab(),
                const MemoryTab(),
                const CameraTab(),
                const SensorsTab(),
                const ThermalTab(),
                const AppsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
