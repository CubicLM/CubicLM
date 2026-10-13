import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_extra_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_apps.dart';
import 'device_info_camera.dart';
import 'device_info_report.dart';
import 'device_info_search.dart';
import 'device_info_tab_battery.dart';
import 'device_info_tab_category.dart';
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
/// views/device_info_tab_*.dart.
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
    'Apps',
    'Category',
  ];

  static const _tabIcons = [
    LucideIcons.layoutDashboard,
    LucideIcons.smartphone,
    LucideIcons.shieldCheck,
    LucideIcons.cpu,
    LucideIcons.batteryMedium,
    LucideIcons.wifi,
    LucideIcons.radio,
    LucideIcons.monitor,
    LucideIcons.hardDrive,
    LucideIcons.camera,
    LucideIcons.compass,
    LucideIcons.flame,
    LucideIcons.layers,
    LucideIcons.award,
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

  void _showTabGridModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Dt.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.layoutGrid,
                          size: 18, color: Dt.accent),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Hardware Navigation Jump',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tabs.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, i) {
                    final selected = c.tab.value == i;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        Navigator.pop(ctx);
                        _goTab(i);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? Dt.accent.withValues(alpha: 0.15)
                              : Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? Dt.accent
                                : Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _tabIcons[i],
                              size: 18,
                              color: selected
                                  ? Dt.accent
                                  : Theme.of(context).hintColor,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tabs[i],
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: selected
                                    ? Dt.accent
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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
            tooltip: 'Search',
            icon: const Icon(LucideIcons.search, size: 18),
            onPressed: () async {
              final tab = await showSearch<int?>(
                context: context,
                delegate: DeviceInfoSearchDelegate(),
              );
              if (tab != null) _goTab(tab);
            },
          ),
          IconButton(
            tooltip: 'Share report',
            icon: const Icon(LucideIcons.share2, size: 18),
            onPressed: () => shareDeviceReport(),
          ),
          IconButton(
            tooltip: 'Quick Tab Jump',
            icon: const Icon(LucideIcons.layoutGrid, size: 18),
            onPressed: () => _showTabGridModal(context),
          ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < _tabs.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(_tabs[i],
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                  selected: {c.tab.value},
                  onSelectionChanged: (s) => _goTab(s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Expanded(
            // Scroll gate: inner ListView drags AND page swipes bubble
            // their notifications up here. While a gesture is active
            // the controller freezes sampling UI (waves, live maps,
            // repaint clock) so rebuilds never land mid-scroll.
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification ||
                    n is UserScrollNotification) {
                  c.setUserScrolling(true);
                } else if (n is ScrollEndNotification) {
                  c.setUserScrolling(false);
                }
                return false;
              },
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
                  const CategoryTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
