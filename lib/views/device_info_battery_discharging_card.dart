import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Real-time Battery Discharge Rate & Charging Wattage analysis card.
class BatteryDischargingCard extends StatelessWidget {
  const BatteryDischargingCard({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  num? _numOf(Map<String, dynamic>? live, String k) {
    final v = live?[k];
    if (v is num) return v;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return devCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.zap, size: 16, color: Dt.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'Live Power Flow & Wattage',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(() {
            final live = c.battLive.value;
            final ex = c.extras.value;
            final chg = c.batteryCharging.value;
            final ua = _numOf(live, 'currentUa');
            final voltMv = _numOf(live, 'voltageMv')?.toInt() ??
                (ex != null && ex.battVoltageMv > 0 ? ex.battVoltageMv : 3850);
            
            final ma = (ua != null && ua != -1) ? (ua / 1000.0).abs() : 0.0;
            final watts = (voltMv > 0 && ma > 0) ? (voltMv / 1000.0) * (ma / 1000.0) : 0.0;

            String speedTier;
            Color speedColor;
            if (chg) {
              if (watts >= 45) {
                speedTier = 'Super Fast Charging (45W+) ⚡⚡';
                speedColor = const Color(0xFF10B981);
              } else if (watts >= 25) {
                speedTier = 'Fast Charging (25W - 45W) ⚡';
                speedColor = Dt.accent;
              } else if (watts >= 15) {
                speedTier = 'Quick Charge (15W - 25W)';
                speedColor = const Color(0xFFE8A317);
              } else {
                speedTier = 'Standard / Trickle Charge (<15W)';
                speedColor = Theme.of(context).hintColor;
              }
            } else {
              if (ma > 800) {
                speedTier = 'High Discharge (Heavy Load / Gaming) ⚠️';
                speedColor = const Color(0xFFEF4444);
              } else if (ma > 400) {
                speedTier = 'Moderate Discharge (Active Use)';
                speedColor = const Color(0xFFE8A317);
              } else {
                speedTier = 'Normal / Low Idle Discharge 🔋';
                speedColor = const Color(0xFF10B981);
              }
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chg ? 'Charge Current' : 'Discharge Rate',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ma > 0 ? '${ma.round()} mA' : '—',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: chg ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Instant Power',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              watts > 0 ? '${watts.toStringAsFixed(2)} W' : '—',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Dt.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: speedColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: speedColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        chg ? LucideIcons.batteryCharging : LucideIcons.activity,
                        size: 14,
                        color: speedColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          speedTier,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: speedColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

