import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_apps_detail.dart';
import 'device_info_apps_header.dart';
import 'device_info_apps_list.dart';

/// Apps tab: visible installed packages with icons, versions, APK
/// sizes + a detail sheet (SDK levels, dates, installer, components,
/// Play/Extract/Launch/Data-Usage actions). No QUERY_ALL_PACKAGES —
/// only packages visible to the app are listed (count is honest).
///
/// Thin shell: the outer Obx ONLY gates [DeviceInfoController.loading]
/// and snapshots the static app list once. It never reads the 2s-ticking
/// Rxs (paintVersion, ramHistory, battLive, extras), so live sampling
/// never rebuilds this tab. Filtering state lives in [_AppsBody] via
/// plain setState; the list itself memoizes filtering and renders with
/// [ListView.builder].
class AppsTab extends StatelessWidget {
  const AppsTab({super.key});

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
      final snapshot = c.apps.value ?? const [];
      return _AppsBody(apps: snapshot);
    });
  }
}

class _AppsBody extends StatefulWidget {
  final List<Map<String, dynamic>> apps;

  const _AppsBody({required this.apps});

  @override
  State<_AppsBody> createState() => _AppsBodyState();
}

class _AppsBodyState extends State<_AppsBody> {
  var _filter = 2; // 0 user, 1 system, 2 all

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppsFilterHeader(
          totalCount: widget.apps.length,
          filter: _filter,
          onFilter: (v) => setState(() => _filter = v),
          onAnalyze: () =>
              showAppAnalyzeDialog(context, widget.apps),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: MemoizedAppList(
            apps: widget.apps,
            filter: _filter,
            onTapApp: (a) =>
                showAppDetailSheet(context, a),
          ),
        ),
      ],
    );
  }
}
