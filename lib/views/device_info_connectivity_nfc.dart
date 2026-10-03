import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'device_info_widgets.dart';

/// Connectivity tab: NFC section (header + card).
/// Static snapshot — plain params only, no rebuilds on the timer.
class NfcSection extends StatelessWidget {
  final Map<String, dynamic>? conn;
  const NfcSection({super.key, required this.conn});

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
              Icon(LucideIcons.nfc,
                  size: 22,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface),
              const SizedBox(width: 10),
              Text('NFC',
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
      ],
    );
  }
}
