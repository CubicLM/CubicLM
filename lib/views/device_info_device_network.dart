import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/device_info_controller.dart';
import 'device_info_widgets.dart';

/// ISO country code ("bd") → flag emoji ("🇧🇩"). Empty/unknown → ''.
String flagForIso(String? iso) {
  if (iso == null || iso.length != 2) return '';
  final s = iso.toUpperCase();
  final a = s.codeUnitAt(0) - 65, b = s.codeUnitAt(1) - 65;
  if (a < 0 || a > 25 || b < 0 || b > 25) return '';
  return ' ${String.fromCharCode(0x1F1E6 + a)}'
      '${String.fromCharCode(0x1F1E6 + b)}';
}

/// Device tab: type/eSIM/network card + SIM operator rows.
/// All rows come from [DeviceInfoController.extras], so the whole
/// (small) card sits in one tiny Obx — the ListView itself never
/// subscribes to the sampling timer. Operator rows appear only after
/// the phone permission is granted (same gate as the Grant button).
class DeviceNetworkCard extends StatelessWidget {
  const DeviceNetworkCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ex =
          Get.find<DeviceInfoController>().extras.value;
      String perm(String? v) => v == 'PERMISSION'
          ? 'Permission needed'
          : (v ?? '—');
      final gated = ex?.phoneType == 'PERMISSION' ||
          ex?.mobileNet == 'PERMISSION';
      final sims = ex?.sims ?? const <Map<String, String>>[];
      final items = <List<String>>[
        ['Device Type', perm(ex?.phoneType)],
        ['eSIM', ex?.esim ?? '—'],
        ['Network Type', perm(ex?.mobileNet)],
      ];
      if (!gated) {
        if (sims.isEmpty) {
          items.add(['Network Operator', 'No SIM']);
        } else {
          for (var i = 0; i < sims.length; i++) {
            items.add([
              'Network Operator ${i + 1}',
              '${sims[i]['name']}${flagForIso(sims[i]['iso'])}'
            ]);
          }
        }
      }
      return devCard(context,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                devRow(context, items[i][0], items[i][1],
                    last: i == items.length - 1),
            ],
          ));
    });
  }
}
