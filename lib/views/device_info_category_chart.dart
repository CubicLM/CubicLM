import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/design_tokens.dart';
import 'device_info_category.dart';
import 'device_info_category_widgets.dart';
import 'device_info_soc_table.dart';

/// Full 11-tier chart with the device row highlighted. Fully static —
/// [cat] is a plain value.
class CategoryChart extends StatelessWidget {
  final DeviceCategory cat;
  const CategoryChart({super.key, required this.cat});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Complete category chart',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const CatInfoBtn('Category chart',
                'All 11 market tiers with typical SoC, RAM, storage, display, camera, battery and 5G for each. Your tier row is accent-bordered with a YOUR DEVICE chip - tap any row for its full specs.\n\nFoldable Flagship is reference-only (form factor, not performance) and is never auto-matched.'),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () =>
                  Get.to(() => const SocAllTableView()),
              icon: const Icon(LucideIcons.layoutGrid,
                  size: 14),
              label: Text('All processors',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Dt.accent,
                side: BorderSide(
                    color: Dt.accent
                        .withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
            'Tap a row for full specs. Your tier is highlighted.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        for (final dc in deviceCategories)
          CategoryRow(dc: dc, selected: identical(dc, cat)),
        const SizedBox(height: 12),
        Text(
            'Judged as a whole: SoC sets the speed class, then display, camera hardware, storage, RAM, battery — never RAM or megapixels alone. Physical RAM is what counts (brand-marketed "extended RAM" is storage, not memory).\nFor running AI models on-device, RAM is the gatekeeper: the AI sweet spot card above sizes models to your measured free RAM.\nFoldables are listed for reference (form factor, not performance).',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                height: 1.5,
                color: Theme.of(context).hintColor)),
      ],
    );
  }
}

/// One expandable chart row (moved verbatim; [selected] highlights
/// the device tier).
class CategoryRow extends StatelessWidget {
  final DeviceCategory dc;
  final bool selected;
  const CategoryRow(
      {super.key, required this.dc, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: selected
                ? Dt.accent
                : Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.6),
            width: selected ? 1.5 : 1),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: CatTierBadge(dc),
          title: Row(
            children: [
              Expanded(
                child: Text(dc.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ),
              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        Dt.accent.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(6),
                  ),
                  child: Text('YOUR DEVICE',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Dt.accent)),
                ),
            ],
          ),
          subtitle: Text(
              '${dc.soc} · ${dc.ram} · ${dc.rom}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(context).hintColor)),
          children: [
            catSpec(context, 'SoC / Processor', dc.soc),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => Get.to(() => SocTableView(
                    tier: dc.tier, tierName: dc.name)),
                icon: const Icon(LucideIcons.listOrdered,
                    size: 14),
                label: Text('More ${dc.tier} processors',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Dt.accent,
                  side: BorderSide(
                      color: Dt.accent
                          .withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10)),
                ),
              ),
            ),
            catSpec(context, 'RAM', dc.ram),
            catSpec(context, 'ROM / Storage', dc.rom),
            catSpec(context, 'Display', dc.display),
            catSpec(context, 'Main Camera', dc.camera),
            catSpec(
                context, 'Battery / Charging', dc.battery),
            catSpec(context, '5G', dc.fiveG),
            catSpec(context, 'Typical use', dc.use),
          ],
        ),
      ),
    );
  }
}

/// One spec line inside an expanded chart row.
Widget catSpec(BuildContext context, String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(k,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: Theme.of(context).hintColor)),
        ),
        Expanded(
          child: Text(v,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
