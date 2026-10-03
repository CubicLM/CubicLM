import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_camera_detail.dart';
import 'device_info_camera_header.dart';
import 'device_info_camera_list_item.dart';

/// Camera tab: one card per camera id (Back/Front/External) + the full
/// Camera2 characteristics of the selected one. Everything is measured
/// live — no permission needed (characteristics are never opened).
///
/// Thin shell: the outer Obx ONLY gates [DeviceInfoController.loading]
/// and snapshots the static camera list once. It never reads the
/// 2s-ticking Rxs (paintVersion, ramHistory, battLive, extras), so live
/// sampling never rebuilds this tab. Selection lives in [_CameraBody]
/// via plain setState; sorting + pixel-array MP parsing are memoized
/// per source identity, and spec entries are memoized per camera.
class CameraTab extends StatelessWidget {
  const CameraTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();
    return Obx(() {
      if (c.loading.value) {
        return const Center(
            child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ));
      }
      final snapshot = c.cameras.value ?? const [];
      return _CameraBody(cameras: snapshot);
    });
  }
}

class _CameraBody extends StatefulWidget {
  final List<Map<String, dynamic>> cameras;

  const _CameraBody({required this.cameras});

  @override
  State<_CameraBody> createState() => _CameraBodyState();
}

class _CameraBodyState extends State<_CameraBody> {
  var _sel = 0;

  List<Map<String, dynamic>>? _lastSource;
  List<Map<String, dynamic>> _sorted = const [];
  List<CameraCardView> _cards = const [];

  /// Sort + card view-models recomputed ONLY when the source list
  /// identity changes — pixel-array regex parsing happens here once,
  /// not per tick/rebuild.
  void _ensureSorted() {
    if (identical(widget.cameras, _lastSource)) return;
    final cams = widget.cameras
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) => ((a['facing'] as num?)?.toInt() ?? 9)
          .compareTo((b['facing'] as num?)?.toInt() ?? 9));
    _lastSource = widget.cameras;
    _sorted = cams;
    _cards =
        [for (final m in cams) CameraCardView.fromCamera(m)];
  }

  @override
  Widget build(BuildContext context) {
    _ensureSorted();
    final cams = _sorted;
    if (cams.isEmpty) {
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('No cameras reported on this device.',
              style: GoogleFonts.plusJakartaSans(
                  color: Theme.of(context).hintColor)),
        ],
      );
    }
    if (_sel >= cams.length) _sel = 0;
    final sel = cams[_sel];
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        CameraSelectorStrip(
          cards: _cards,
          selected: _sel,
          onSelect: (i) => setState(() => _sel = i),
        ),
        const SizedBox(height: 12),
        const CameraNote(),
        const SizedBox(height: 12),
        CameraSpecSection(camera: sel),
      ],
    );
  }
}
