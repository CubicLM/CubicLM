import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/model_controller.dart';
import '../services/download_service.dart';
import '../services/storage_info_service.dart';
import '../theme/design_tokens.dart';

/// Storage details (opens from the StorageStatusBar tap).
/// MIUI-style breakdown, but every number is measured on-device:
/// StatFs free/total, real .gguf footprint, app data + cache from disk.
class StorageDetailsView extends StatefulWidget {
  const StorageDetailsView({super.key});

  @override
  State<StorageDetailsView> createState() => _StorageDetailsViewState();
}

class _StorageDetailsData {
  final int totalBytes;
  final int freeBytes;
  final int modelBytes;
  final int modelCount;
  final int dataBytes;
  final int cacheBytes;
  const _StorageDetailsData({
    required this.totalBytes,
    required this.freeBytes,
    required this.modelBytes,
    required this.modelCount,
    required this.dataBytes,
    required this.cacheBytes,
  });

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
  int get otherBytes =>
      (usedBytes - modelBytes - dataBytes - cacheBytes).clamp(0, usedBytes);
}

class _StorageDetailsViewState extends State<StorageDetailsView> {
  Future<_StorageDetailsData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String _gb(num bytes) =>
      '${(bytes / 1000000000).toStringAsFixed(1)} GB';

  Future<int> _dirBytes(Directory dir) async {
    var sum = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final e
          in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            sum += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return sum;
  }

  Future<_StorageDetailsData> _load() async {
    final stats = await StorageInfoService.getStats(force: true);
    final total = stats?.totalBytes ?? 0;
    final free = stats?.freeBytes ?? 0;

    var models = 0;
    var count = 0;
    var docs = 0;
    var cache = 0;
    try {
      final dl = Get.find<DownloadService>();
      final dir = Directory(await dl.modelsDir);
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File) {
            final p = e.path.toLowerCase();
            if (p.endsWith('.gguf') || p.endsWith('.litertlm')) {
              count++;
              try {
                models += await e.length();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
    try {
      final mc = Get.find<ModelController>();
      if (mc.downloadedFiles.isNotEmpty) {
        count = mc.downloadedFiles.length;
      }
    } catch (_) {}
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      docs = await _dirBytes(docsDir);
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      cache = await _dirBytes(tmp);
    } catch (_) {}
    // App data = everything in documents except the models themselves.
    final data = (docs - models).clamp(0, docs);
    return _StorageDetailsData(
      totalBytes: total,
      freeBytes: free,
      modelBytes: models,
      modelCount: count,
      dataBytes: data,
      cacheBytes: cache,
    );
  }

  Future<void> _clearCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => _future = _load());
        Get.snackbar('Cache cleared', 'Temporary files removed.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('Storage space',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: FutureBuilder<_StorageDetailsData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final segs = [
            _Seg('Free space', d.freeBytes, const Color(0xFFE8E2D5)),
            _Seg('AI Models', d.modelBytes, Dt.accent),
            _Seg('App data', d.dataBytes, const Color(0xFFE8A317)),
            _Seg('Cache', d.cacheBytes, const Color(0xFFFF7A00)),
            _Seg('Other', d.otherBytes, const Color(0xFF9B8E7E)),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                '${_gb(d.usedBytes)}/${_gb(d.totalBytes)} used | ${_gb(d.freeBytes)} available',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StackedBar(
                      segments: segs, total: d.totalBytes),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      children: [
                        _row(context, 'AI Models',
                            '${d.modelCount} file${d.modelCount == 1 ? '' : 's'}',
                            d.modelBytes, Dt.accent, null),
                        _row(
                            context,
                            'App data',
                            'Chats, settings, vault',
                            d.dataBytes,
                            const Color(0xFFE8A317),
                            null),
                        _row(context, 'Cache', 'Temporary files',
                            d.cacheBytes, const Color(0xFFFF7A00),
                            TextButton(
                              onPressed: d.cacheBytes > 0
                                  ? _clearCache
                                  : null,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap,
                              ),
                              child: const Text('Clear'),
                            )),
                        _row(context, 'Other',
                            'System + other apps', d.otherBytes,
                            const Color(0xFF9B8E7E), null),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Measured on this device just now — models are real .gguf/.litertlm bytes on disk.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: Theme.of(context).hintColor),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, String title, String sub, int bytes,
      Color dot, Widget? trailing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 2),
                Text(
                  bytes > 0
                      ? DownloadService.formatBytes(bytes)
                      : '0 B',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19, fontWeight: FontWeight.w700),
                ),
                Text(sub,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Theme.of(context)
                            .hintColor
                            .withValues(alpha: 0.7))),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _Seg {
  final String label;
  final int bytes;
  final Color color;
  const _Seg(this.label, this.bytes, this.color);
}

/// Vertical stadium bar, MIUI-cylinder style but flat (app language).
/// Free on top, then models / data / cache / other.
class _StackedBar extends StatelessWidget {
  final List<_Seg> segments;
  final int total;
  const _StackedBar({required this.segments, required this.total});

  @override
  Widget build(BuildContext context) {
    const height = 300.0;
    const width = 84.0;
    final children = <Widget>[];
    for (final s in segments) {
      final frac =
          total > 0 ? (s.bytes / total).clamp(0.0, 1.0) : 0.0;
      final h = (frac * height).clamp(0.0, height);
      if (h < 0.5) continue;
      children.add(Container(width: width, height: h, color: s.color));
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(42),
        color: Theme.of(context)
            .dividerColor
            .withValues(alpha: 0.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      ),
    );
  }
}
