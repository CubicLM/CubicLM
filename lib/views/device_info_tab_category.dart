import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../controllers/home_controller.dart';
import '../controllers/model_controller.dart';
import '../services/chip_advice.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import '../views/benchmark_view.dart';
import 'device_info_category.dart';
import 'device_info_soc.dart';
import 'device_info_soc_table.dart';
import 'device_info_widgets.dart';

/// Device Category tab: which tier this phone belongs to (scored from
/// measured signals), why (per-signal bars), the full 11-tier chart
/// with the device row highlighted, and the AI-model sweet spot.
class CategoryTab extends StatelessWidget {
  const CategoryTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  SocScoreClass _chipClass() {
    try {
      final dev = Get.find<DeviceInfoService>();
      final cls = classifyChip(
          dev.socFamily.value,
          dev.processorName.value.isEmpty
              ? dev.socHardware.value
              : dev.processorName.value);
      switch (cls) {
        case ChipClass.modernFlagship:
          return SocScoreClass.modernFlagship;
        case ChipClass.oldFlagship:
          return SocScoreClass.oldFlagship;
        case ChipClass.upperMid:
          return SocScoreClass.upperMid;
        case ChipClass.mid:
          return SocScoreClass.mid;
        case ChipClass.entry:
          return SocScoreClass.entry;
        case ChipClass.unknown:
          return SocScoreClass.unknown;
      }
    } catch (_) {}
    return SocScoreClass.unknown;
  }

  /// Rear-camera max megapixels from pixel arrays (true sensor size).
  int _rearMaxMp() {
    var best = 0;
    try {
      for (final e in (c.cameras.value ?? const [])) {
        final facing = (e['facing'] as num?)?.toInt() ?? -1;
        if (facing != 0) continue;
        final pa = '${e['pixelArray'] ?? ''}';
        final m =
            RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(pa);
        if (m != null) {
          final w = int.tryParse(m.group(1)!) ?? 0;
          final h = int.tryParse(m.group(2)!) ?? 0;
          final mp = w * h ~/ 1000000;
          if (mp > best) best = mp;
        }
      }
    } catch (_) {}
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Loading gate: without it the first paint scores empty data
      // as "Ultra Budget" for a flash before native values arrive.
      if (c.loading.value) {
        return const Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ));
      }
      double ram = 0, avail = 0;
      var hw = '';
      try {
        final dev = Get.find<DeviceInfoService>();
        dev.totalRamGB.value;
        dev.availableRamGB.value;
        dev.socHardware.value;
        dev.processorName.value;
        ram = dev.totalRamGB.value;
        avail = dev.availableRamGB.value;
        hw = dev.processorName.value.isEmpty
            ? dev.socHardware.value
            : dev.processorName.value;
      } catch (_) {}
      final st = c.storage.value;
      final dTotal = st?.totalBytes ?? 0;
      final disp = c.display.value;
      final wPx = (disp?['wPx'] as num?)?.toInt() ?? 0;
      final hPx = (disp?['hPx'] as num?)?.toInt() ?? 0;
      var maxHz = 0.0;
      try {
        for (final e in ((disp?['refreshAll'] as List?) ??
            const [])) {
          final v = (e as num).toDouble();
          if (v > maxHz) maxHz = v;
        }
      } catch (_) {}
      final live = c.battLive.value;
      final designMah =
          (live?['designMah'] as num?)?.toInt() ?? -1;

      final chipYear = chipYearFor(hw);
      final equiv = chipEquivFor(hw);
      final score = scoreDevice(
        chip: _chipClass(),
        ramGb: ram,
        storageTotalBytes: dTotal,
        dispMinPx: wPx > 0 && hPx > 0
            ? (wPx < hPx ? wPx : hPx)
            : 0,
        refreshMaxHz: maxHz,
        camMaxMp: _rearMaxMp(),
        battDesignMah: designMah,
        chipYear: chipYear,
      );
      final cat = score.category;

      // AI sweet spot (same engine as the dashboard advice).
      String quant = '—', sizeLine = '—';
      try {
        final dev = Get.find<DeviceInfoService>();
        final adv = adviseChip(
          family: dev.socFamily.value,
          processorName: dev.processorName.value,
          socHardware: dev.socHardware.value,
          totalRamGb: ram,
        );
        quant = adv.quantLine;
        sizeLine = adv.sizeLine;
      } catch (_) {}
      final roomMb = avail > 0
          ? (((avail - 0.25) / 1.25 * 1024).round()
              .clamp(0, 1 << 30))
          : 0;

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Hero: your tier ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _tierBadge(cat, big: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Your device',
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 11.5,
                                        color: Theme.of(
                                                context)
                                            .hintColor)),
                            Text(cat.name,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 19,
                                        fontWeight:
                                            FontWeight
                                                .w800)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${score.total}',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 26,
                                      fontWeight:
                                          FontWeight.w800,
                                      color: cat.color)),
                          _infoBtn(context, 'Your tier & score',
                              'Your tier (${cat.tier} ${cat.name}) comes from your 0–100 score: ${score.total} points.\n\nScore bands: S+ 86+, S 77+, A 68+, A− 59+, B+ 51+, B 43+, B− 35+, C 27+, C− 19+, else D.\n\nThe "performs like" line compares your aged chip against a modern class (e.g. a 2019 flagship behaves like a 2024 upper-mid). Era penalty and equivalent class come from public launch data, everything else is measured on your phone right now.'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      score.next == null
                          ? 'Top of the chart — nothing above.'
                          : '${score.toNext} pts to ${score.next!.name} (${score.next!.tier}).',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color:
                              Theme.of(context).hintColor)),
                  if (equiv != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        'Performs like a $equiv today.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Dt.accent)),
                  ],
                  if (score.socPenalty > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                        'Era-adjusted −${score.socPenalty} SoC pts (${score.chipAge} yrs old — flagships decay as years pass).',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .hintColor)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Why this score',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      _infoBtn(context, 'How scoring works',
                          'Score is 0–100 from measured signals only:\n\n• SoC /42 — chip class from your processor name. Flagships decay 4 pts per year after a 2-year grace period (floor 8), so old flagships settle near their modern equivalent class.\n• RAM /20 — physical total RAM.\n• Storage /10 — internal partition size.\n• Display /13 — resolution class (up to 9) + refresh rate (up to 4).\n• Camera /9 — rear sensor megapixels from the pixel array (true sensor size, not binned JPEG).\n• Battery /6 — design capacity.\n\nUnknown signals score 0, never guessed. Bands: S+ 86+, S 77+, A 68+, A− 59+, B+ 51+, B 43+, B− 35+, C 27+, C− 19+, else D. Foldables are reference-only.'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final k in [
                    'SoC',
                    'RAM',
                    'Storage',
                    'Display',
                    'Camera',
                    'Battery'
                  ])
                    _scoreBar(
                        context,
                        k,
                        score.earned[k] ?? 0,
                        categoryMaxParts()[k] ?? 1),
                ],
              )),
          const SizedBox(height: 12),
          // ── SoC tier ladder (S → D), yours highlighted ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('SoC tier ladder',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      _infoBtn(context, 'SoC tier ladder',
                          'S = current flagship, A+ = high flagship, A = old flagship, B+ = upper mid, B = mid, C = entry, D = basic.\n\nThe check mark is YOUR band from the score above. SoC decides the most — a big RAM number never outranks the chip, which is why SoC alone is worth 42 of 100 points.'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'SoC decides the most — a big RAM number never outranks the chip.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color:
                              Theme.of(context).hintColor)),
                  const SizedBox(height: 8),
                  for (final t in [
                    ['S', 'Flagship', _bandColor('S')],
                    ['A+', 'High flagship', _bandColor('A')],
                    ['A', 'Old flagship', _bandColor('A')],
                    ['A-', 'Premium mid', _bandColor('A-')],
                    ['B+', 'Upper mid', _bandColor('B+')],
                    ['B', 'Mid', _bandColor('B')],
                    ['B-', 'Lower mid', _bandColor('B-')],
                    ['C', 'Entry', _bandColor('C')],
                    ['C-', 'Low budget', _bandColor('C-')],
                    ['D', 'Basic', _bandColor('D')],
                  ])
                    Padding(
                      padding:
                          const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: (t[2] as Color)
                                  .withValues(alpha: 0.14),
                              borderRadius:
                                  BorderRadius.circular(
                                      9),
                            ),
                            child: Center(
                              child: Text(t[0] as String,
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight
                                                  .w800,
                                          color: t[2]
                                              as Color)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(t[1] as String,
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 12,
                                        color: Theme.of(
                                                context)
                                            .hintColor)),
                          ),
                          if (_ladderHit(
                              cat.tier, t[0] as String))
                            const Icon(
                                LucideIcons.checkCircle2,
                                size: 15,
                                color: Dt.accent),
                        ],
                      ),
                    ),
                ],
              )),
          const SizedBox(height: 12),
          // ── AI sweet spot ──
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.sparkles,
                          size: 18, color: Dt.accent),
                      const SizedBox(width: 8),
                      Text('AI sweet spot for this device',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight:
                                      FontWeight.w800)),
                      _infoBtn(context, 'AI sweet spot',
                          '"Best" is the quantization family that balances speed and quality on your chip (e.g. Q4_K_M). "Stick to ≤1B" is the largest model size class that fits your RAM with working headroom. "Room right now" = (free RAM − 0.25 GB reserve) ÷ 1.25 model overhead — the biggest GGUF file you can load at this moment.'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(quant,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(sizeLine,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color:
                              Theme.of(context).hintColor)),
                  if (roomMb > 0)
                    Text(
                        'Room right now ≈ $roomMb MB — download from the Local marketplace.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .hintColor)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        try {
                          Get.find<ModelController>()
                              .modelScope
                              .value = 'local';
                        } catch (_) {}
                        try {
                          Get.find<HomeController>()
                              .changeTab(1);
                          Get.back();
                        } catch (_) {}
                      },
                      icon: const Icon(
                          LucideIcons.download,
                          size: 16),
                      label: const Text(
                          'Open Local marketplace'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Dt.accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    12)),
                      ),
                    ),
                  ),
                ],
              )),
          const SizedBox(height: 12),
          // ── Benchmark this device ──
          devCard(context,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Dt.accent
                          .withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: const Icon(
                        LucideIcons.gauge,
                        size: 20,
                        color: Dt.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('Benchmark this device',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13.5,
                                    fontWeight:
                                        FontWeight.w800)),
                      _infoBtn(context, 'Benchmark this device',
                          'Runs a live benchmark on your loaded local model: 1 discarded warm-up + 3 measured generations on the real inference engine.\n\nMeasured: generation tok/s, time-to-first-token, prompt-processing estimate, RAM before/peak, battery and thermal status, stability. Nothing is simulated — estimates are labeled est, unknowns show —.\n\nResult is a documented CubicLM AI Score (0–100) with history and JSON export.'),
                        Text(
                            'Live tok/s, TTFT, RAM, thermal + AI score.',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12,
                                    color: Theme.of(
                                            context)
                                        .hintColor)),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Get.to(
                        () => const BenchmarkView()),
                    style: FilledButton.styleFrom(
                      backgroundColor: Dt.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize
                              .shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  12)),
                      textStyle: GoogleFonts
                          .plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight:
                                  FontWeight.w700),
                    ),
                    child: const Text('Benchmark'),
                  ),
                ],
              )),
          const SizedBox(height: 12),
          // ── Full chart ──
          Row(
            children: [
              Text('Complete category chart',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              _infoBtn(context, 'Category chart',
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
            _categoryRow(context, dc,
                selected: identical(dc, cat)),
          const SizedBox(height: 12),
          Text(
              'Judged as a whole: SoC first, then display, camera hardware, storage, RAM, battery — never RAM or megapixels alone. RAM numbers vary by brand marketing; physical RAM matters.\nFoldables are listed for reference (form factor, not performance).',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  height: 1.5,
                  color: Theme.of(context).hintColor)),
        ],
      );
    });
  }

  /// Band color for a ladder tier letter (S/A+/A/B+/B/C/D).
  static Color _bandColor(String tier) {
    for (final c in deviceCategories) {
      if (c.tier == tier) return c.color;
    }
    if (tier == 'A+') {
      for (final c in deviceCategories) {
        if (c.tier == 'A') return c.color;
      }
    }
    return const Color(0xFF8D8D8D);
  }

  /// Does band letter [letter] represent the matched [tier]?
  /// S+ lights the S rung (nearest rung above entry ladder top);
  /// S/F never auto-matches by design.
  static bool _ladderHit(String tier, String letter) {
    if (tier == letter) return true;
    if (tier == 'S+' && letter == 'S') return true;
    return false;
  }

  void _info(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(body,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, height: 1.55)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoBtn(
      BuildContext context, String title, String body) {
    return InkWell(
      onTap: () => _info(context, title, body),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(LucideIcons.info,
            size: 14,
            color: Theme.of(context)
                .hintColor
                .withValues(alpha: 0.8)),
      ),
    );
  }

  Widget _tierBadge(DeviceCategory c, {bool big = false}) {
    return Container(
      width: big ? 46 : 34,
      height: big ? 46 : 34,
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.14),
        borderRadius:
            BorderRadius.circular(big ? 14 : 10),
      ),
      child: Center(
        child: Text(c.tier,
            style: GoogleFonts.plusJakartaSans(
                fontSize: big ? 15 : 12,
                fontWeight: FontWeight.w800,
                color: c.color)),
      ),
    );
  }

  Widget _scoreBar(
      BuildContext context, String k, int got, int max) {
    final f = max > 0 ? (got / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(k,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: Theme.of(context).hintColor)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 6,
                backgroundColor: Theme.of(context)
                    .dividerColor
                    .withValues(alpha: 0.35),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(
                        Dt.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('$got/$max',
                textAlign: TextAlign.end,
                style: GoogleFonts.firaCode(
                    fontSize: 10.5,
                    color: Theme.of(context).hintColor)),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(
      BuildContext context, DeviceCategory dc,
      {required bool selected}) {
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
          leading: _tierBadge(dc),
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
            _spec(context, 'SoC / Processor', dc.soc),
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
            _spec(context, 'RAM', dc.ram),
            _spec(context, 'ROM / Storage', dc.rom),
            _spec(context, 'Display', dc.display),
            _spec(context, 'Main Camera', dc.camera),
            _spec(
                context, 'Battery / Charging', dc.battery),
                    _spec(context, '5G', dc.fiveG),
                    _spec(context, 'Typical use', dc.use),
          ],
        ),
      ),
    );
  }

  Widget _spec(
      BuildContext context, String k, String v) {
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
}
