import 'package:flutter/material.dart';

/// Global search across CubicDevice Info: keyword → tab index.
///
/// Tab order mirrors DeviceInfoView._tabs (keep in sync):
/// 0 Dashboard · 1 Device · 2 System · 3 CPU · 4 Battery · 5 Network ·
/// 6 Connectivity · 7 Display · 8 Memory · 9 Camera · 10 Sensors ·
/// 11 Thermal · 12 Apps · 13 Category.
class DeviceInfoSearchHit {
  final int tab;
  final String section;
  final List<String> keywords;
  const DeviceInfoSearchHit(this.tab, this.section, this.keywords);
}

const _tabNames = [
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

String deviceInfoTabName(int tab) =>
    (tab >= 0 && tab < _tabNames.length)
        ? _tabNames[tab]
        : 'Device Info';

const deviceInfoSearchIndex = <DeviceInfoSearchHit>[
  // ── 0 Dashboard ──
  DeviceInfoSearchHit(
      0, 'Dashboard · RAM', ['ram', 'free ram', 'memory usage']),
  DeviceInfoSearchHit(
      0, 'Dashboard · CPU status', ['cpu status', 'cpu cores']),
  DeviceInfoSearchHit(0, 'Dashboard · Storage',
      ['storage', 'disk space', 'internal storage']),
  DeviceInfoSearchHit(0, 'Dashboard · Battery',
      ['battery level', 'charging']),
  DeviceInfoSearchHit(0, 'Dashboard · Display & sensors',
      ['display overview', 'sensors overview']),
  // ── 1 Device ──
  DeviceInfoSearchHit(1, 'Device · Identity',
      ['device name', 'model', 'manufacturer', 'board', 'hardware', 'brand', 'fingerprint', 'android id']),
  DeviceInfoSearchHit(1, 'Device · SIM & network',
      ['sim', 'operator', 'carrier', 'network operator', 'device type', 'network type', 'esim', 'phone permission', 'grant permission']),
  // ── 2 System ──
  DeviceInfoSearchHit(2, 'System · Android version',
      ['android version', 'sdk', 'api level', 'code name', 'dessert']),
  DeviceInfoSearchHit(2, 'System · Build & kernel',
      ['security patch', 'bootloader', 'build number', 'kernel', 'baseband', 'java vm', 'language', 'timezone', 'drm', 'widevine']),
  // ── 3 CPU ──
  DeviceInfoSearchHit(3, 'CPU · Processor',
      ['processor', 'chipset', 'soc', 'architecture', 'abis', '64 bit']),
  DeviceInfoSearchHit(3, 'CPU · Frequencies',
      ['frequency', 'ghz', 'governor', 'core speed', 'live bars']),
  // ── 4 Battery ──
  DeviceInfoSearchHit(4, 'Battery · Live',
      ['battery level', 'current', 'charging current', 'temperature', 'battery temp', 'power', 'graph']),
  DeviceInfoSearchHit(4, 'Battery · Health',
      ['health', 'capacity', 'mah', 'design capacity', 'technology', 'time to charge']),
  // ── 5 Network ──
  DeviceInfoSearchHit(5, 'Network · Wi-Fi',
      ['wifi', 'wi-fi', 'ssid', 'ip address', 'link speed', 'signal', 'rssi']),
  DeviceInfoSearchHit(5, 'Network · Traffic',
      ['data usage', 'traffic', 'mobile data', 'public ip', 'isp']),
  // ── 6 Connectivity ──
  DeviceInfoSearchHit(6, 'Connectivity · Bluetooth',
      ['bluetooth', 'ble', 'paired']),
  DeviceInfoSearchHit(
      6, 'Connectivity · NFC / UWB / USB', ['nfc', 'uwb', 'usb', 'otg']),
  // ── 7 Display ──
  DeviceInfoSearchHit(7, 'Display · Specs',
      ['resolution', 'refresh rate', 'hz', 'screen size', 'density', 'dpi', 'hdr', 'brightness']),
  // ── 8 Memory ──
  DeviceInfoSearchHit(8, 'Memory · RAM',
      ['ram', 'total ram', 'available ram']),
  DeviceInfoSearchHit(
      8, 'Memory · Storage & swap', ['storage', 'swap', 'zram']),
  // ── 9 Camera ──
  DeviceInfoSearchHit(9, 'Camera · Specs',
      ['camera', 'megapixel', 'mp', 'front camera', 'rear camera', 'back camera', 'facing', 'focal', 'aperture']),
  // ── 10 Sensors ──
  DeviceInfoSearchHit(10, 'Sensors · List',
      ['sensors', 'accelerometer', 'gyroscope', 'compass', 'magnetometer', 'light sensor', 'proximity', 'barometer', 'step counter']),
  // ── 11 Thermal ──
  DeviceInfoSearchHit(11, 'Thermal · Zones',
      ['thermal', 'temperature', 'heat', 'cpu temp', 'throttling', 'cooling']),
  // ── 12 Apps ──
  DeviceInfoSearchHit(12, 'Apps · Installed',
      ['apps', 'installed apps', 'apk', 'package', 'app size', 'version', 'installer']),
  // ── 13 Category ──
  DeviceInfoSearchHit(13, 'Category · Tier & score',
      ['tier', 'score', 'category', 'flagship', 'budget', 'mid range', 'chart']),
  DeviceInfoSearchHit(13, 'Category · AI & benchmark',
      ['ai sweet spot', 'benchmark', 'model size', 'quantization', 'processors table', 'soc ladder', 'all processors']),
];

/// Case-insensitive keyword search. Empty query → no hits.
List<DeviceInfoSearchHit> searchDeviceInfo(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    for (final h in deviceInfoSearchIndex)
      if (h.section.toLowerCase().contains(q) ||
          h.keywords
              .any((k) => k.contains(q) || q.contains(k)))
        h,
  ];
}

/// Search UI: filters the registry live, tapping a hit closes the
/// search and returns its tab index (the caller jumps there).
class DeviceInfoSearchDelegate extends SearchDelegate<int?> {
  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) =>
      _hitList(context);

  @override
  Widget buildSuggestions(BuildContext context) =>
      _hitList(context);

  Widget _hitList(BuildContext context) {
    final hits = searchDeviceInfo(query);
    if (query.trim().isEmpty) {
      return const Center(
          child: Text('Search RAM, battery, sensors, tiers…'));
    }
    if (hits.isEmpty) {
      return Center(child: Text('No match for "$query".'));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (_, i) {
        final h = hits[i];
        return ListTile(
          title: Text(h.section),
          subtitle: Text('${deviceInfoTabName(h.tab)} tab'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => close(context, h.tab),
        );
      },
    );
  }
}
