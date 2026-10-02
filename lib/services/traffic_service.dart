import 'package:flutter/services.dart';

/// Device + per-app network traffic via NetworkStatsManager
/// (native `com.cubiclm.app/device` channel). Exact per-period bytes —
/// no sampling daemon needed. Needs Usage Access; without it only
/// since-boot totals (TrafficStats) are available.
class TrafficSummary {
  final int rx;
  final int tx;
  final int wifiRx;
  final int wifiTx;
  final int mobileRx;
  final int mobileTx;
  const TrafficSummary({
    required this.rx,
    required this.tx,
    required this.wifiRx,
    required this.wifiTx,
    required this.mobileRx,
    required this.mobileTx,
  });

  int get total => rx + tx;
}

class TrafficApp {
  final String package;
  final String label;
  final Uint8List? icon;
  final int rx;
  final int tx;
  final int wifiRx;
  final int wifiTx;
  final int mobileRx;
  final int mobileTx;
  const TrafficApp({
    required this.package,
    required this.label,
    required this.icon,
    required this.rx,
    required this.tx,
    required this.wifiRx,
    required this.wifiTx,
    required this.mobileRx,
    required this.mobileTx,
  });

  int get total => rx + tx;
}

class TrafficService {
  static const _ch = MethodChannel('com.cubiclm.app/device');

  static Future<bool> hasPermission() async {
    try {
      return await _ch.invokeMethod<bool>('trafficPerm') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod<bool>('openUsageAccess');
    } catch (_) {}
  }

  static int _i(Map m, String k) =>
      (m[k] as num?)?.toInt() ?? 0;

  static Future<TrafficSummary?> summary(
      int startMs, int endMs) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
          'trafficSummary', {'startMs': startMs, 'endMs': endMs});
      if (m == null) return null;
      return TrafficSummary(
        rx: _i(m, 'rx'),
        tx: _i(m, 'tx'),
        wifiRx: _i(m, 'wifiRx'),
        wifiTx: _i(m, 'wifiTx'),
        mobileRx: _i(m, 'mobileRx'),
        mobileTx: _i(m, 'mobileTx'),
      );
    } on PlatformException catch (e) {
      if (e.code == 'NEEDS_PERMISSION') return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  static Future<List<TrafficApp>> apps(
      int startMs, int endMs) async {
    try {
      final list = await _ch.invokeListMethod<dynamic>(
          'trafficApps', {'startMs': startMs, 'endMs': endMs});
      if (list == null) return const [];
      final out = <TrafficApp>[];
      for (final e in list) {
        if (e is! Map) continue;
        Uint8List? icon;
        try {
          final b = e['icon'];
          if (b is Uint8List) {
            icon = b;
          } else if (b is List) {
            icon = Uint8List.fromList(b.cast<int>());
          }
        } catch (_) {}
        out.add(TrafficApp(
          package: '${e['package'] ?? ''}',
          label: '${e['label'] ?? e['package'] ?? ''}',
          icon: icon,
          rx: _i(e, 'rx'),
          tx: _i(e, 'tx'),
          wifiRx: _i(e, 'wifiRx'),
          wifiTx: _i(e, 'wifiTx'),
          mobileRx: _i(e, 'mobileRx'),
          mobileTx: _i(e, 'mobileTx'),
        ));
      }
      out.sort((a, b) => b.total.compareTo(a.total));
      return out;
    } on PlatformException catch (e) {
      if (e.code == 'NEEDS_PERMISSION') return const [];
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Since-boot totals, permission-free fallback.
  static Future<TrafficSummary?> boot() async {
    try {
      final m = await _ch
          .invokeMapMethod<String, dynamic>('trafficBoot');
      if (m == null) return null;
      return TrafficSummary(
        rx: _i(m, 'rx'),
        tx: _i(m, 'tx'),
        wifiRx: _i(m, 'wifiRx'),
        wifiTx: _i(m, 'wifiTx'),
        mobileRx: _i(m, 'mobileRx'),
        mobileTx: _i(m, 'mobileTx'),
      );
    } catch (_) {
      return null;
    }
  }
}
