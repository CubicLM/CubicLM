import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sensors tab: count banner. Static — plain params only.
class SensorsBanner extends StatelessWidget {
  final int count;
  const SensorsBanner({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context)
                  .dividerColor
                  .withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
              count == 0
                  ? 'No sensors reported on this device.'
                  : '$count Sensors are available on your device',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
