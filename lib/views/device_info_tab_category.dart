import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import '../services/chip_advice.dart';
import '../services/device_info_service.dart';
import 'device_info_category.dart';
import 'device_info_category_advice.dart';
import 'device_info_category_bench.dart';
import 'device_info_category_chart.dart';
import 'device_info_category_hero.dart';
import 'device_info_category_ladder.dart';
import 'device_info_soc.dart';
import 'device_info_soc_table.dart';

/// Device Category tab: thin shell + data plumbing.
///
/// The outer Obx gates loading and reads slow-moving snapshots only
/// (free RAM is deliberately NOT read here — it ticks every 2s and
/// lives in the advice card's tiny Obx). The score is memoized by
/// value in [_CategoryContent], so sampling ticks rebuild at most the
/// shell while the chart tree diffs to identical widgets.
/// Sections live in device_info_category_*.dart.
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
      double ram = 0;
      var hw = '';
      try {
        final dev = Get.find<DeviceInfoService>();
        ram = dev.totalRamGB.value;
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
      String? detectedChip;
      try {
        detectedChip = deviceChipTierLabel(hw);
      } catch (_) {}

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

      return _CategoryContent(
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
        quant: quant,
        sizeLine: sizeLine,
        equiv: equiv,
        detectedChip: detectedChip,
      );
    });
  }
}

/// Score + section composition. The score recomputes only when an
/// input VALUE changes (keyed memo), so the 5s battery tick and other
/// sampling noise never rebuild the chart.
class _CategoryContent extends StatefulWidget {
  final SocScoreClass chip;
  final double ramGb;
  final int storageTotalBytes;
  final int dispMinPx;
  final double refreshMaxHz;
  final int camMaxMp;
  final int battDesignMah;
  final int chipYear;
  final String quant;
  final String sizeLine;
  final String? equiv;
  final String? detectedChip;
  const _CategoryContent({
    required this.chip,
    required this.ramGb,
    required this.storageTotalBytes,
    required this.dispMinPx,
    required this.refreshMaxHz,
    required this.camMaxMp,
    required this.battDesignMah,
    required this.chipYear,
    required this.quant,
    required this.sizeLine,
    required this.equiv,
    required this.detectedChip,
  });

  @override
  State<_CategoryContent> createState() =>
      _CategoryContentState();
}

class _CategoryContentState extends State<_CategoryContent> {
  var _lastKey = '';
  late CategoryScore _score;

  String _key() =>
      '${widget.chip}|${widget.ramGb}|${widget.storageTotalBytes}|'
      '${widget.dispMinPx}|${widget.refreshMaxHz}|${widget.camMaxMp}|'
      '${widget.battDesignMah}|${widget.chipYear}';

  CategoryScore _current() {
    final k = _key();
    if (k != _lastKey) {
      _lastKey = k;
      _score = scoreDevice(
        chip: widget.chip,
        ramGb: widget.ramGb,
        storageTotalBytes: widget.storageTotalBytes,
        dispMinPx: widget.dispMinPx,
        refreshMaxHz: widget.refreshMaxHz,
        camMaxMp: widget.camMaxMp,
        battDesignMah: widget.battDesignMah,
        chipYear: widget.chipYear,
      );
    }
    return _score;
  }

  @override
  Widget build(BuildContext context) {
    final score = _current();
    final cat = score.category;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // ── Hero: your tier ──
        CategoryHeroCard(
            cat: cat, score: score, equiv: widget.equiv),
        const SizedBox(height: 12),
        // ── SoC tier ladder (S → D), yours highlighted ──
        CategoryLadderCard(
            tier: cat.tier, detected: widget.detectedChip),
        const SizedBox(height: 12),
        // ── AI sweet spot ──
        CategoryAdviceCard(
            quant: widget.quant, sizeLine: widget.sizeLine),
        const SizedBox(height: 12),
        // ── Benchmark this device ──
        const CategoryBenchCard(),
        const SizedBox(height: 12),
        // ── Full chart ──
        CategoryChart(cat: cat),
      ],
    );
  }
}
