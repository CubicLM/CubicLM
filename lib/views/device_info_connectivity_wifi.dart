import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'device_info_widgets.dart';

/// Connectivity tab: Wi-Fi section (header + card).
/// Null from native = "could not determine" (never faked).
/// Static snapshot — plain params only, no rebuilds on the timer.
class WifiSection extends StatelessWidget {
  final Map<String, dynamic>? conn;
  const WifiSection({super.key, required this.conn});

  String _tri(dynamic v) {
    if (v == null) return 'Unknown';
    return (v == true) ? 'Supported' : 'Not Supported';
  }

  @override
  Widget build(BuildContext context) {
    final m = conn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(LucideIcons.wifi,
                  size: 22,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface),
              const SizedBox(width: 10),
              Text('Wi-Fi',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
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
                devRow(context, '6GHz', _tri(m?['band6']),
                    last: true),
              ],
            )),
      ],
    );
  }
}
