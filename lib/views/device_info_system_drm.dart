import 'package:flutter/material.dart';

import 'device_info_widgets.dart';

/// System tab: DRM card.
/// Static snapshot passed in as a plain param — no rebuilds on the
/// sampling timer.
class DrmCard extends StatelessWidget {
  final Map<String, dynamic> sys;
  const DrmCard({super.key, required this.sys});

  String _safe(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            devRow(
                context, 'Vendor', _safe(sys['drmVendor'])),
            devRow(context, 'Description',
                _safe(sys['drmDesc'])),
            devRow(context, 'Version',
                _safe(sys['drmVersion'])),
            devRow(context, 'Algorithms',
                _safe(sys['drmAlgos'])),
            devRow(context, 'Security Level',
                _safe(sys['drmSec'])),
            devRow(context, 'Max HDCP level',
                _safe(sys['drmHdcp']),
                last: true),
          ],
        ));
  }
}
