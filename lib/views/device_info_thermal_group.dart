import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import 'device_info_thermal_utils.dart';

/// One thermal group card with show more/less (first 5 + "Show all").
/// Keyed by group title by the caller so the expanded state follows
/// the group (not the list position) when re-sorting by temperature.
class ThermalGroupCard extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> sensors;
  const ThermalGroupCard(
      {super.key, required this.title, required this.sensors});

  @override
  State<ThermalGroupCard> createState() =>
      _ThermalGroupCardState();
}

class _ThermalGroupCardState extends State<ThermalGroupCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.sensors;
    final shown =
        _expanded ? list : list.take(5).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context)
                .dividerColor
                .withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              Text('${list.length} Sensors',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Theme.of(context).hintColor)),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in shown)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${s['name'] ?? '—'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .hintColor)),
                  ),
                  Text(
                      thermalTemp(s['tempC']),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          if (list.length > 5)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _expanded = !_expanded),
                child: Text(
                    _expanded
                        ? 'Show less'
                        : 'Show all · ${list.length - 5} more',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Dt.accent)),
              ),
            ),
        ],
      ),
    );
  }
}
