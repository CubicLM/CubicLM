import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_extra_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Connectivity tab: Wi-Fi / Bluetooth / NFC / UWB / USB sections.
/// Null from native = "could not determine" (never faked).
class ConnectivityTab extends StatelessWidget {
  const ConnectivityTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  String _tri(dynamic v) {
    if (v == null) return 'Unknown';
    return (v == true) ? 'Supported' : 'Not Supported';
  }

  Widget _connSection(
      BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon,
              size: 22,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface),
          const SizedBox(width: 10),
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final m = c.conn.value;
      final btPresent = m?['btPresent'] == true;
      final btOn = m?['btOn'];
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _connSection(context, LucideIcons.wifi, 'Wi-Fi'),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'WiFi Standard',
                      (m?['wifiGen']?.toString().isNotEmpty ??
                              false)
                          ? m!['wifiGen'].toString()
                          : '—'),
                  devRow(context, 'WiFi Direct',
                      _tri(m?['wifiDirect'])),
                  devRow(context, '5GHz',
                      _tri(m?['band5'])),
                  devRow(context, '6GHz',
                      _tri(m?['band6']),
                      last: true),
                ],
              )),
          const SizedBox(height: 18),
          _connSection(
              context, LucideIcons.bluetooth, 'Bluetooth'),
          if (!btPresent)
            devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    devRow(context, 'Bluetooth',
                        'Not Supported',
                        last: true),
                  ],
                ))
          else if (btOn == false)
            devCard(context,
                child: Center(
                  child: FilledButton(
                    onPressed: () =>
                        DeviceExtraService
                            .openBtSettings(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  24)),
                      textStyle: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight:
                                  FontWeight.w700),
                    ),
                    child:
                        const Text('Turn on Bluetooth'),
                  ),
                ))
          else
            devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    devRow(context, 'Bluetooth',
                        btOn == true
                            ? 'Supported (On)'
                            : 'Supported'),
                    devRow(context,
                        'Multiple Advertisements',
                        _tri(m?['multiAdv'])),
                    devRow(context,
                        'Offloaded Filtering',
                        _tri(m?['offFilt'])),
                    devRow(context,
                        'Offloaded Scan Batching',
                        _tri(m?['offBatch'])),
                    devRow(context,
                        'Bluetooth LE (Low Energy)',
                        _tri(m?['btLe'])),
                    devRow(context,
                        'LE 2M PHY (High Speed)',
                        _tri(m?['le2m'])),
                    devRow(context,
                        'LE Coded PHY (Long Range)',
                        _tri(m?['leCoded'])),
                    devRow(context,
                        'LE Extended Advertising',
                        _tri(m?['leExtAdv'])),
                    devRow(context,
                        'LE Periodic Advertising',
                        _tri(m?['lePeriodAdv']),
                        last: true),
                  ],
                )),
          const SizedBox(height: 18),
          _connSection(context, LucideIcons.nfc, 'NFC'),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(
                      context,
                      'NFC',
                      (m?['nfcPresent'] == true)
                          ? (m?['nfcOn'] == true
                              ? 'On'
                              : m?['nfcOn'] == false
                                  ? 'Off'
                                  : 'Supported')
                          : 'Not Supported',
                      last: true),
                ],
              )),
          const SizedBox(height: 18),
          Text('Ultra Wide Band',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'Ultra Wide Band',
                      _tri(m?['uwb']),
                      last: true),
                ],
              )),
          const SizedBox(height: 18),
          _connSection(context, LucideIcons.usb, 'USB'),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'USB Host',
                      _tri(m?['usbHost'])),
                  devRow(context, 'USB Accessory',
                      _tri(m?['usbAcc'])),
                  devRow(
                      context,
                      'USB Debugging',
                      m?['adbOn'] == null
                          ? '—'
                          : (m?['adbOn'] == true
                              ? 'On'
                              : 'Off'),
                      last: true),
                ],
              )),
        ],
      );
    });
  }
}
