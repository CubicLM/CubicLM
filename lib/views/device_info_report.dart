import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';

/// Plain-text device report for Share. Pure function of plain values
/// (testable); [shareDeviceReport] gathers them from the live
/// controllers. Unknowns render as —, never guessed.
String buildDeviceReport({
  required String deviceLabel,
  required String processor,
  required String androidRelease,
  required double ramTotalGb,
  required double ramAvailGb,
  required int storageTotalGb,
  required int storageFreeGb,
  required int batteryLevel,
  required int appCount,
  required int sensorCount,
  required int cameraCount,
}) {
  final b = StringBuffer()
    ..writeln('CubicDevice Info report')
    ..writeln('Device: $deviceLabel')
    ..writeln('Processor: $processor')
    ..writeln('Android: $androidRelease')
    ..writeln(
        'RAM: ${ramTotalGb.toStringAsFixed(1)} GB total, ${ramAvailGb.toStringAsFixed(1)} GB free')
    ..writeln('Storage: $storageFreeGb GB free of $storageTotalGb GB')
    ..writeln('Battery: $batteryLevel%')
    ..writeln(
        'Apps: $appCount · Sensors: $sensorCount · Cameras: $cameraCount');
  return b.toString();
}

/// Gathers the report inputs (all best-effort) and opens the share
/// sheet. Never throws — share is a convenience, not load-bearing.
Future<void> shareDeviceReport() async {
  try {
    var deviceLabel = '—';
    var processor = '—';
    var release = '—';
    var ramTotal = 0.0, ramAvail = 0.0;
    try {
      final dev = Get.find<DeviceInfoService>();
      if (dev.deviceLabel.value.isNotEmpty) {
        deviceLabel = dev.deviceLabel.value;
      }
      processor = dev.processorName.value.isEmpty
          ? dev.socHardware.value
          : dev.processorName.value;
      if (processor.isEmpty) processor = '—';
      if (dev.osVersion.value.isNotEmpty) {
        release = dev.osVersion.value;
      }
      ramTotal = dev.totalRamGB.value;
      ramAvail = dev.availableRamGB.value;
    } catch (_) {}
    var batt = 0, stTotal = 0, stFree = 0;
    var apps = 0, sensors = 0, cams = 0;
    try {
      final c = Get.find<DeviceInfoController>();
      batt = c.batteryLevel.value;
      final st = c.storage.value;
      stTotal = ((st?.totalBytes ?? 0) / 1e9).round();
      stFree = ((st?.freeBytes ?? 0) / 1e9).round();
      apps = c.apps.value?.length ?? 0;
      sensors = c.extras.value?.sensorCount ?? 0;
      if (sensors < 0) sensors = 0;
      cams = c.cameras.value?.length ?? 0;
    } catch (_) {}
    await Share.share(
      buildDeviceReport(
        deviceLabel: deviceLabel,
        processor: processor,
        androidRelease: release,
        ramTotalGb: ramTotal,
        ramAvailGb: ramAvail,
        storageTotalGb: stTotal,
        storageFreeGb: stFree,
        batteryLevel: batt,
        appCount: apps,
        sensorCount: sensors,
        cameraCount: cams,
      ),
      subject: 'CubicDevice Info report',
    );
  } catch (_) {}
}
