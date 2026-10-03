import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/device_extra_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Connectivity tab: Bluetooth section (header + card).
/// Three states: not present / off (settings button) / on (details).
/// Static snapshot — plain params only, no rebuilds on the timer.
class BluetoothSection extends StatelessWidget {
  final Map<String, dynamic>? conn;
  const BluetoothSection(
      {super.key, required this.conn});

  String _tri(dynamic v) {
    if (v == null) return 'Unknown';
    return (v == true) ? 'Supported' : 'Not Supported';
  }

  @override
  Widget build(BuildContext context) {
    final m = conn;
    final btPresent = m?['btPresent'] == true;
    final btOn = m?['btOn'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(LucideIcons.bluetooth,
                  size: 22,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface),
              const SizedBox(width: 10),
              Text('Bluetooth',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
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
      ],
    );
  }
}
