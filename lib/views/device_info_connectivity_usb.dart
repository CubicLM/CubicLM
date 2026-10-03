import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'device_info_widgets.dart';

/// Connectivity tab: USB section (header + card).
/// Static snapshot — plain params only, no rebuilds on the timer.
class UsbSection extends StatelessWidget {
  final Map<String, dynamic>? conn;
  const UsbSection({super.key, required this.conn});

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
              Icon(LucideIcons.usb,
                  size: 22,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface),
              const SizedBox(width: 10),
              Text('USB',
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
  }
}
