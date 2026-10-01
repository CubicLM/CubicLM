import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../services/device_extra_service.dart';
import '../services/device_info_service.dart';
import '../widgets/soc_brand_icon.dart';
import 'device_info_android.dart';
import 'device_info_soc.dart';
import '../theme/design_tokens.dart';
import '../views/hub/hub_widgets.dart';
import 'storage_details_view.dart';

/// CubicDevice Info — on-device hardware dashboard (Toolkit feature).
/// Tabs: Dashboard, Device, System, CPU, Battery, Network. Every number
/// is measured live; unknowns render as '—', never as fake zeros.
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
    'Network'
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
                  return _deviceTab(context);
                case 2:
                  return _systemTab(context);
                case 3:
                  return _cpuTab(context);
                case 4:
                  return _batteryTab(context);
                case 5:
                  return _networkTab(context);
                case 0:
                default:
                  return _dashboardTab(context);
              }
            }),
          ),
        ],
      ),
    );
  }

  // ── shared bits ──────────────────────────────────────────────

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  String _freq(int mhz) {
    if (mhz < 0) return '—';
    if (mhz >= 1000) {
      return '${(mhz / 1000).toStringAsFixed(1)} GHz';
    }
    return '$mhz MHz';
  }

  // ── Dashboard ────────────────────────────────────────────────

  Widget _dashboardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _ramCard(context),
        const SizedBox(height: 12),
        _cpuGridCard(context),
        const SizedBox(height: 12),
        _storageCard(context),
        const SizedBox(height: 12),
        _batteryCard(context),
        const SizedBox(height: 12),
        _displaySensorsRow(context),
      ],
    );
  }

  Widget _ramCard(BuildContext context) {
    final dev = Get.find<DeviceInfoService>();
    return Obx(() {
      final total = dev.totalRamGB.value;
      final avail = dev.availableRamGB.value;
      final used = (total - avail).clamp(0.0, total);
      final frac = total > 0 ? used / total : 0.0;
      final hist = c.ramHistory.toList();
      return _card(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      total > 0
                          ? 'RAM · ${total.toStringAsFixed(1)} GB Total'
                          : 'RAM',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    total > 0
                        ? '${used.toStringAsFixed(1)} GB Used'
                        : '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Dt.accent),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  HubRing(
                    fraction: frac,
                    center: total > 0
                        ? '${(frac * 100).round()}%'
                        : '—',
                    label: '',
                    color: frac > 0.85
                        ? AppColors.warning
                        : Dt.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 88,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          values: hist,
                          line: Dt.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  total > 0
                      ? '${avail.toStringAsFixed(1)} GB Free'
                      : '—',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor),
                ),
              ),
            ],
          ));
    });
  }

  Widget _cpuGridCard(BuildContext context) {
    return Obx(() {
      final freqs = c.extras.value?.cpuFreqsMHz ?? const [];
      final cores = freqs.isEmpty
          ? Get.find<DeviceInfoService>().cpuCores.value
          : freqs.length;
      return _card(context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CPU Status',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (cores <= 0)
                Text('—',
                    style: GoogleFonts.plusJakartaSans(
                        color: Theme.of(context).hintColor))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics:
                      const NeverScrollableScrollPhysics(),
                  itemCount: cores,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.5,
                  ),
                  itemBuilder: (_, i) {
                    final mhz =
                        i < freqs.length ? freqs[i] : -1;
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.25),
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Text('Core $i',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .hintColor)),
                          const SizedBox(height: 2),
                          Text(_freq(mhz),
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w700)),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ));
    });
  }

  Widget _storageCard(BuildContext context) {
    return Obx(() {
      final s = c.storage.value;
      final total = s?.totalBytes ?? 0;
      final free = s?.freeBytes ?? 0;
      final used = (total - free).clamp(0, total);
      final frac = total > 0 ? used / total : 0.0;
      return InkWell(
        onTap: () =>
            Get.to(() => const StorageDetailsView()),
        borderRadius: BorderRadius.circular(16),
        child: _card(context,
            child: Row(
              children: [
                const Icon(LucideIcons.hardDrive,
                    size: 26, color: Dt.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Internal Storage',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight:
                                            FontWeight.w700)),
                          ),
                          Text(
                            total > 0
                                ? '${(frac * 100).round()}%'
                                : '—',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? frac : null,
                          minHeight: 6,
                          backgroundColor:
                              Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.4),
                          valueColor:
                              const AlwaysStoppedAnimation<
                                  Color>(Dt.accent),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        total > 0
                            ? 'Free: ${(free / 1e9).toStringAsFixed(1)} GB, Total: ${(total / 1e9).toStringAsFixed(1)} GB'
                            : 'Tap for details',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color:
                                Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight,
                    size: 18,
                    color: Theme.of(context).hintColor),
              ],
            )),
      );
    });
  }

  Widget _batteryCard(BuildContext context) {
    return Obx(() {
      final lvl = c.batteryLevel.value;
      final chg = c.batteryCharging.value;
      final ex = c.extras.value;
      final sub = StringBuffer();
      if (ex != null && ex.battVoltageMv > 0) {
        sub.write('Voltage: ${ex.battVoltageMv}mV');
      }
      if (ex != null && ex.battTempC >= 0) {
        if (sub.isNotEmpty) sub.write(', ');
        sub.write(
            'Temperature: ${ex.battTempC.toStringAsFixed(1)}°C');
      }
      return _card(context,
          child: Row(
            children: [
              Icon(
                  chg
                      ? LucideIcons.batteryCharging
                      : LucideIcons.batteryMedium,
                  size: 26,
                  color: Dt.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              chg
                                  ? 'Battery · charging'
                                  : 'Battery',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 13.5,
                                      fontWeight:
                                          FontWeight.w700)),
                        ),
                        Text(lvl >= 0 ? '$lvl%' : '—',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: lvl >= 0
                            ? lvl / 100
                            : null,
                        minHeight: 6,
                        backgroundColor:
                            Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.4),
                        valueColor:
                            const AlwaysStoppedAnimation<
                                Color>(Dt.accent),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(sub.toString(),
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 11.5,
                                  color: Theme.of(context)
                                      .hintColor)),
                    ],
                  ],
                ),
              ),
            ],
          ));
    });
  }

  Widget _displaySensorsRow(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Obx(() {
      final sensors = c.extras.value?.sensorCount ?? -1;
      return Row(
        children: [
          Expanded(
            child: _card(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.monitor,
                        size: 24, color: Dt.accent),
                    const SizedBox(height: 8),
                    Text('Display',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(
                      '${size.width.toStringAsFixed(0)} x ${size.height.toStringAsFixed(0)} · ${dpr.toStringAsFixed(2)}x',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color:
                              Theme.of(context).hintColor),
                    ),
                  ],
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _card(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.radio,
                        size: 24, color: Dt.accent),
                    const SizedBox(height: 8),
                    Text(
                        sensors >= 0 ? '$sensors' : '—',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text('Sensors',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color:
                                Theme.of(context).hintColor)),
                  ],
                )),
          ),
        ],
      );
    });
  }

  Future<void> _grantPhonePermission() async {
    try {
      final st = await Permission.phone.request();
      if (st.isGranted) {
        await c.refreshExtras(force: true);
      }
    } catch (_) {}
  }

  // ── Device tab ───────────────────────────────────────────────
  // Screenshot layout: bold label + accent value below + dividers.

  Widget _deviceTab(BuildContext context) {
    return FutureBuilder<AndroidDeviceInfo>(
      future: _androidInfo,
      builder: (context, snap) {
        final a = snap.data;
        return Obx(() {
          final ex = c.extras.value;
          final needPerm = ex?.phoneType == 'PERMISSION' ||
              ex?.mobileNet == 'PERMISSION';
          String perm(String? v) =>
              v == 'PERMISSION' ? 'Permission needed' : (v ?? '—');
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _card(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _devRow(context, 'Device Name',
                          ex?.deviceName ?? '—'),
                      _devRow(context, 'Model',
                          a?.model ?? '—'),
                      _devRow(context, 'Manufacturer',
                          a?.manufacturer ?? '—'),
                      _devRow(context, 'Device',
                          a?.device ?? '—'),
                      _devRow(
                          context, 'Board', a?.board ?? '—'),
                      _devRow(context, 'Hardware',
                          a?.hardware ?? '—'),
                      _devRow(
                          context, 'Brand', a?.brand ?? '—'),
                      _devRow(context, 'Android Device ID',
                          ex?.androidId ?? '—'),
                      _devRow(context, 'Build Fingerprint',
                          a?.fingerprint ?? '—',
                          last: true),
                    ],
                  )),
              if (needPerm) ...[
                const SizedBox(height: 14),
                Center(
                  child: FilledButton(
                    onPressed: _grantPhonePermission,
                    style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(24)),
                      textStyle: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w700),
                    ),
                    child:
                        const Text('Grant Permission'),
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 14),
              _card(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _devRow(context, 'Device Type',
                          perm(ex?.phoneType)),
                      _devRow(context, 'eSIM',
                          ex?.esim ?? '—'),
                      _devRow(context, 'Network Type',
                          perm(ex?.mobileNet),
                          last: true),
                    ],
                  )),
            ],
          );
        });
      },
    );
  }

  Widget _devRow(BuildContext context, String label, String value,
      {bool last = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        SelectableText(value,
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

  String _clock(int ms) {
    if (ms <= 0) return '—';
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  String _langLabel(String tag) {
    const names = {
      'en': 'English', 'bn': 'Bengali', 'hi': 'Hindi', 'ur': 'Urdu',
      'ar': 'Arabic', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'pt': 'Portuguese', 'ru': 'Russian', 'zh': 'Chinese',
      'ja': 'Japanese', 'ko': 'Korean', 'tr': 'Turkish',
      'id': 'Indonesian', 'vi': 'Vietnamese', 'it': 'Italian',
      'nl': 'Dutch', 'th': 'Thai', 'ms': 'Malay',
    };
    final code = tag.split(RegExp(r'[_-]')).first.toLowerCase();
    final name = names[code] ?? code;
    final flat = tag.replaceAll('-', '_');
    return '$name ($flat)';
  }

  // ── System tab ───────────────────────────────────────────────
  // Reference layout: version header card + rows + DRM card.
  // "Released With" is skipped — the factory-shipped OS is not
  // measurable on-device; everything else is live data.

  Widget _systemTab(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_androidInfo!, _sysInfo!]),
      builder: (context, snap) {
        final a = snap.data?[0] as AndroidDeviceInfo?;
        final sys =
            (snap.data?.length ?? 0) > 1 && snap.data?[1] is Map
                ? Map<String, dynamic>.from(snap.data?[1] as Map)
                : <String, dynamic>{};
        final sdk = a?.version.sdkInt ?? 0;
        final release = a?.version.release ?? '—';
        final meta = androidMetaFor(sdk);
        final miui = (sys['miui']?.toString() ?? '').trim();
        String safe(dynamic v) {
          final s = v?.toString().trim() ?? '';
          return s.isEmpty ? '—' : s;
        }

        final off = DateTime.now().timeZoneOffset;
        final sign = off.isNegative ? '-' : '+';
        final oh = off.inHours.abs().toString().padLeft(2, '0');
        final om =
            (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final tz =
            '${sys['tzId'] ?? '—'} (GMT$sign$oh:$om/ ${sys['tzName'] ?? '—'})';

        return Obx(() {
          final ex = c.extras.value;
          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              AndroidVersionHeader(
                meta: meta,
                sdk: sdk,
                release: release,
              ),
              const SizedBox(height: 14),
              _card(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _devRow(context, 'Code Name',
                          '${meta.label} - ${meta.codename}'),
                      _devRow(context, 'API Level', '$sdk'),
                      _devRow(context, 'SDK Extensions',
                          '${sys['sdkExt'] ?? '—'}'),
                      _devRow(context, 'MIUI',
                          miui.isEmpty
                              ? '—'
                              : '$release - $miui'),
                      _devRow(context, 'Security Patch Level',
                          a?.version.securityPatch ?? '—'),
                      _devRow(context, 'Bootloader',
                          safe(sys['bootloader'])),
                      _devRow(context, 'Build Number',
                          a?.display ?? '—'),
                      _devRow(context, 'Baseband',
                          safe(sys['baseband'])),
                      _devRow(context, 'Java VM',
                          safe(sys['javaVm'])),
                      _devRow(context, 'Kernel',
                          ex?.kernelVersion ?? '—'),
                      _devRow(context, 'Language',
                          _langLabel(Platform.localeName)),
                      _devRow(context, 'Timezone', tz),
                      _devRow(context, 'OpenGL ES',
                          safe(sys['gles'])),
                      _devRow(context, 'Root Management Apps',
                          safe(sys['rootApps'])),
                      _devRow(context, 'SELinux',
                          safe(sys['selinux'])),
                      _devRow(context, 'Google Play Services',
                          safe(sys['gms'])),
                      _devRow(context, 'System Uptime',
                          _clock(ex?.uptimeMs ?? 0)),
                      _devRow(context, 'Vulkan',
                          safe(sys['vulkan'])),
                      _devRow(context, 'Treble',
                          safe(sys['treble'])),
                      _devRow(context, 'Seamless Updates',
                          safe(sys['seamless'])),
                      _devRow(context, 'Dynamic Partitions',
                          safe(sys['dynamic']),
                          last: true),
                    ],
                  )),
              const SizedBox(height: 18),
              Text('DRM',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _card(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _devRow(context, 'Vendor',
                          safe(sys['drmVendor'])),
                      _devRow(context, 'Description',
                          safe(sys['drmDesc'])),
                      _devRow(context, 'Version',
                          safe(sys['drmVersion'])),
                      _devRow(context, 'Algorithms',
                          safe(sys['drmAlgos'])),
                      _devRow(context, 'Security Level',
                          safe(sys['drmSec'])),
                      _devRow(context, 'Max HDCP level',
                          safe(sys['drmHdcp']),
                          last: true),
                    ],
                  )),
            ],
          );
        });
      },
    );
  }

  /// Group core indices by max freq → "N x min – max MHz" (desc).
  List<String> _clusterMinMax(List<int> maxF, List<int> minF) {
    final groups = <int, List<int>>{};
    for (var i = 0; i < maxF.length; i++) {
      if (maxF[i] <= 0) continue;
      groups.putIfAbsent(maxF[i], () => []).add(i);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        (() {
          var lo = 1 << 30;
          for (final i in groups[k]!) {
            final m = i < minF.length ? minF[i] : -1;
            if (m > 0 && m < lo) lo = m;
          }
          final n = groups[k]!.length;
          final hi = k >= 1000
              ? '${(k / 1000).toStringAsFixed(2)} GHz'
              : '$k MHz';
          final loS = lo == 1 << 30
              ? '?'
              : lo >= 1000
                  ? '${(lo / 1000).toStringAsFixed(2)} GHz'
                  : '$lo MHz';
          return '$n x $loS - $hi';
        })()
    ];
  }

  /// Group by max freq → "N x X.XX GHz" (desc).
  List<String> _clusterMax(List<int> maxF) {
    final groups = <int, int>{};
    for (final f in maxF) {
      if (f <= 0) continue;
      groups[f] = (groups[f] ?? 0) + 1;
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        '${groups[k]} x ${(k / 1000).toStringAsFixed(2)} GHz'
    ];
  }

  // ── CPU tab ──────────────────────────────────────────────────
  // Reference layout: SoC header card + spec rows + live bars.
  // Marketing lines (name/clusters/process) come from the static
  // SoC table when hardware matches; otherwise measured data only.

  Widget _cpuTab(BuildContext context) {
    return FutureBuilder<AndroidDeviceInfo>(
      future: _androidInfo,
      builder: (context, snap) {
        final a = snap.data;
        return Obx(() {
          final dev = Get.find<DeviceInfoService>();
          final cpu = c.cpu.value;
          var maxF = const <int>[];
          var minF = const <int>[];
          try {
            maxF = (cpu?['maxFreqs'] as List?)
                    ?.map((e) => (e as num).toInt())
                    .toList() ??
                const [];
            minF = (cpu?['minFreqs'] as List?)
                    ?.map((e) => (e as num).toInt())
                    .toList() ??
                const [];
          } catch (_) {}
          final cores = maxF.isNotEmpty
              ? maxF.length
              : dev.cpuCores.value;
          final hw =
              '${dev.socHardware.value} ${a?.model ?? ''} ${a?.hardware ?? ''}';
          final spec = socSpecFor(hw);
          final img =
              SocBrandIcon.assetFor(dev.socFamily.value);
          final abis = a?.supportedAbis ?? const [];
          final is64 = (a?.supported64BitAbis ?? const [])
              .isNotEmpty;
          final freqs = c.extras.value?.cpuFreqsMHz ?? const [];
          var liveMax = 1;
          for (final f in freqs) {
            if (f > liveMax) liveMax = f;
          }
          final archLines = spec != null
              ? spec.clusters.map((e) => e.line).toList()
              : _clusterMax(maxF);
          final freqLines = _clusterMinMax(maxF, minF);
          String safe(dynamic v) {
            final s = v?.toString().trim() ?? '';
            return s.isEmpty ? '—' : s;
          }

          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // SoC header (app card language, not the brown slab).
              _card(context,
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(14),
                          color: Dt.accent
                              .withValues(alpha: 0.10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: img == null
                            ? const Icon(LucideIcons.cpu,
                                size: 30, color: Dt.accent)
                            : Image.asset(img,
                                fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                spec?.name ??
                                    (dev.socHardware.value
                                            .isEmpty
                                        ? 'Processor'
                                        : dev.socHardware.value),
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight.w800)),
                            if (spec != null) ...[
                              const SizedBox(height: 4),
                              for (final cl
                                  in spec.clusters)
                                Text(cl.line,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                            fontSize: 12,
                                            color: Theme.of(
                                                    context)
                                                .hintColor)),
                              const SizedBox(height: 2),
                              Text(spec.process,
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600,
                                          color: Theme.of(
                                                  context)
                                              .hintColor)),
                            ],
                          ],
                        ),
                      ),
                      if (spec != null)
                        const Icon(
                            LucideIcons.badgeCheck,
                            size: 20,
                            color: Dt.accent),
                    ],
                  )),
              const SizedBox(height: 14),
              _card(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _devRow(context, 'Processor',
                          safe(dev.socHardware.value)),
                      _devRow(context, 'CPU Architecture',
                          archLines.isEmpty
                              ? '—'
                              : archLines.join('\n')),
                      _devRow(context, 'Supported ABIs',
                          abis.isEmpty
                              ? '—'
                              : abis.join(', ')),
                      _devRow(context, 'CPU Hardware',
                          a?.hardware ?? '—'),
                      _devRow(context, 'CPU Type',
                          abis.isEmpty
                              ? '—'
                              : (is64
                                  ? '64 Bit'
                                  : '32 Bit')),
                      _devRow(context, 'CPU Governor',
                          safe(cpu?['governor'])),
                      _devRow(context, 'Cores',
                          cores > 0 ? '$cores' : '—'),
                      _devRow(context, 'CPU Frequency',
                          freqLines.isEmpty
                              ? '—'
                              : freqLines.join('\n')),
                      _devRow(context, 'GPU Renderer',
                          safe(cpu?['eglRenderer'])),
                      _devRow(context, 'GPU Vendor',
                          safe(cpu?['eglVendor'])),
                      _devRow(
                          context,
                          'GPU Version',
                          safe(cpu?['eglVersion']),
                          last: true),
                    ],
                  )),
              // Live per-core bars (Dashboard grid shows the same).
              if (cores > 0) ...[
                const SizedBox(height: 14),
                _card(context,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('Live frequency',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800)),
                        const SizedBox(height: 8),
                        for (var i = 0; i < cores; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text('Core $i',
                                      style: GoogleFonts
                                          .plusJakartaSans(
                                              fontSize:
                                                  12.5)),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(
                                            3),
                                    child:
                                        LinearProgressIndicator(
                                      value: i <
                                              freqs.length
                                          ? (freqs[i] /
                                                  liveMax)
                                              .clamp(
                                                  0.0, 1.0)
                                          : 0,
                                      minHeight: 6,
                                      backgroundColor:
                                          Theme.of(context)
                                              .dividerColor
                                              .withValues(
                                                  alpha:
                                                      0.4),
                                      valueColor:
                                          const AlwaysStoppedAnimation<
                                                  Color>(
                                              Dt.accent),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    i < freqs.length
                                        ? _freq(freqs[i])
                                        : '—',
                                    textAlign:
                                        TextAlign.end,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight
                                                    .w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )),
              ],
            ],
          );
        });
      },
    );
  }

  // ── Battery tab ──────────────────────────────────────────────
  // Reference layout: live header (current + graph + power + status)
  // then Health … Capacity rows. No ads card.

  List<double> _normBatt(List<double> hist) {
    if (hist.length < 2) return const [];
    var lo = hist.first;
    var hi = hist.first;
    for (final v in hist) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if ((hi - lo).abs() < 1) {
      return List.filled(hist.length, 0.5);
    }
    return [for (final v in hist) (v - lo) / (hi - lo)];
  }

  Widget _batteryTab(BuildContext context) {
    return Obx(() {
      final live = c.battLive.value;
      final ex = c.extras.value;
      num? numOf(String k) {
        final v = live?[k];
        if (v is num) return v;
        return null;
      }

      final lvl = c.batteryLevel.value;
      final chg = c.batteryCharging.value;
      final ua = numOf('currentUa');
      final hasCurrent = ua != null && ua != -1;
      final ma =
          (ua != null && ua != -1) ? ua / 1000.0 : 0.0;
      final voltMv = numOf('voltageMv')?.toInt() ??
          (ex != null && ex.battVoltageMv > 0
              ? ex.battVoltageMv
              : -1);
      final watts = (voltMv > 0 && hasCurrent)
          ? (voltMv / 1000.0) * ma
          : null;
      final status = live?['status']?.toString() ??
          (lvl < 0
              ? '—'
              : (chg ? 'Charging' : 'Discharging'));
      final plugged =
          live?['plugged']?.toString() ?? 'Battery';
      final tempC = numOf('tempC')?.toDouble() ??
          (ex?.battTempC ?? -1);
      final counterMah = numOf('counterMah')?.toInt() ?? -1;
      final designMah = numOf('designMah')?.toInt() ?? -1;
      final fullMah = numOf('fullMah')?.toInt() ?? -1;
      final estimatedMah = (counterMah > 0 && lvl > 0)
          ? (counterMah / lvl * 100).round()
          : -1;
      String eta() {
        if (status == 'Charging' &&
            ma > 0 &&
            fullMah > 0 &&
            counterMah >= 0 &&
            fullMah > counterMah) {
          final mins =
              ((fullMah - counterMah) / ma * 60).round();
          if (mins < 60) return '$mins min';
          return '${mins ~/ 60}h ${mins % 60}m';
        }
        if (status == 'Charged') return 'Charged';
        if (status == 'Discharging') return 'Discharging';
        return status;
      }

      final curTxt =
          hasCurrent ? '${ma.round()} mA' : '—';
      final powTxt = watts == null
          ? '—'
          : '${watts.toStringAsFixed(2)} W';
      final tempTxt = tempC >= 0
          ? '${tempC.toStringAsFixed(0)} °C'
          : '—';
      final hist = c.battHistory.toList();

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _card(context,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Current : $curTxt',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight:
                                        FontWeight.w800)),
                      ),
                      Text(tempTxt,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                          chg
                              ? LucideIcons
                                  .batteryCharging
                              : LucideIcons
                                  .batteryMedium,
                          size: 40,
                          color: Dt.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 72,
                          child: CustomPaint(
                            painter: _SparklinePainter(
                              values: _normBatt(hist),
                              line: Dt.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Power : $powTxt',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight:
                                        FontWeight.w800)),
                      ),
                      Text(
                          status == 'Charging'
                              ? 'Battery Charging'
                              : status == 'Discharging'
                                  ? 'Battery Discharging'
                                  : status,
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800)),
                    ],
                  ),
                ],
              )),
          const SizedBox(height: 14),
          _card(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _devRow(context, 'Health',
                      ex?.battHealth ?? '—'),
                  _devRow(context, 'Level',
                      lvl >= 0 ? '$lvl%' : '—'),
                  _devRow(
                      context, 'Status', status),
                  _devRow(context, 'Power Source',
                      plugged),
                  _devRow(context, 'Technology',
                      ex?.battTech ?? '—'),
                  _devRow(context, 'Temperature',
                      tempTxt),
                  _devRow(
                      context, 'Current', curTxt),
                  _devRow(context, 'Power', powTxt),
                  _devRow(context, 'Voltage',
                      voltMv > 0 ? '$voltMv mV' : '—'),
                  _devRow(context, 'Time to charge',
                      eta()),
                  _devRow(
                      context,
                      'Capacity (Charged)',
                      counterMah > 0
                          ? '$counterMah mAh'
                          : '—'),
                  _devRow(
                      context,
                      'Capacity (Estimated)',
                      estimatedMah > 0
                          ? '$estimatedMah mAh'
                          : '—'),
                  _devRow(
                      context,
                      'Capacity (System)',
                      designMah > 0
                          ? '$designMah mAh'
                          : '—',
                      last: true),
                ],
              )),
        ],
      );
    });
  }

  // ── Network tab ──────────────────────────────────────────────

  Widget _networkTab(BuildContext context) {
    return Obx(() {
      final net = c.extras.value?.networkType ?? '—';
      IconData icon;
      switch (net) {
        case 'WIFI':
          icon = LucideIcons.wifi;
          break;
        case 'CELLULAR':
          icon = LucideIcons.signal;
          break;
        case 'ETHERNET':
          icon = LucideIcons.network;
          break;
        default:
          icon = LucideIcons.wifiOff;
      }
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _card(context,
              child: Row(
                children: [
                  Icon(icon, size: 26, color: Dt.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(net,
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight:
                                        FontWeight.w800)),
                        Text('Active transport',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .hintColor)),
                      ],
                    ),
                  ),
                ],
              )),
        ],
      );
    });
  }
}

/// RAM history sparkline with soft fill.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color line;
  const _SparklinePainter({required this.values, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final path = Path();
    final stepX = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y = size.height - (values[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.35), line.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.line != line;
}
