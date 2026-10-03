import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'device_info_widgets.dart';

/// Connectivity tab: Ultra Wide Band section (plain title + card,
/// matching the original layout which has no icon header here).
/// Static snapshot — plain params only, no rebuilds on the timer.
class UwbSection extends StatelessWidget {
  final Map<String, dynamic>? conn;
  const UwbSection({super.key, required this.conn});

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
        Text('Ultra Wide Band',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800)),
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
      ],
    );
  }
}
