import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../core/colors.dart';
import '../theme/design_tokens.dart';
import 'data_usage_view.dart';
import 'device_info_widgets.dart';

/// Network tab: Wi-Fi header (IP + generation + Usage/Public IP
/// buttons) then link rows. SSID is never read (needs location).
class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  String _wifiStd(int s) {
    switch (s) {
      case 4:
        return 'Wi-Fi 802.11n (Wi-Fi 4)';
      case 5:
        return 'Wi-Fi 802.11ac (Wi-Fi 5)';
      case 6:
        return 'Wi-Fi 802.11ad (WiGig)';
      case 7:
        return 'Wi-Fi 802.11ax (Wi-Fi 6)';
      case 8:
        return 'Wi-Fi 802.11be (Wi-Fi 7)';
      case 1:
        return 'Wi-Fi 802.11a';
      case 2:
        return 'Wi-Fi 802.11b';
      case 3:
        return 'Wi-Fi 802.11g';
      default:
        return '—';
    }
  }

  String _wifiGen(int s, int freq) {
    String gen;
    switch (s) {
      case 4:
        gen = 'Wi-Fi 4';
        break;
      case 5:
        gen = 'Wi-Fi 5';
      case 7:
        gen = 'Wi-Fi 6';
        break;
      case 8:
        gen = 'Wi-Fi 7';
        break;
      default:
        gen = 'Wi-Fi';
    }
    if (freq <= 0) return gen;
    final band = freq < 3000
        ? '2.4 GHz'
        : freq < 6000
            ? '5 GHz'
            : '6 GHz';
    return '$gen ($band)';
  }

  String _wifiChannel(int freq) {
    if (freq <= 0) return '—';
    if (freq == 2484) return 'CH 14';
    if (freq >= 2412 && freq <= 2472) {
      return 'CH ${(freq - 2407) ~/ 5}';
    }
    if (freq >= 5035 && freq <= 5865) {
      return 'CH ${(freq - 5000) ~/ 5}';
    }
    if (freq >= 5955 && freq <= 7115) {
      return 'CH ${(freq - 5950) ~/ 5}';
    }
    return '—';
  }

  String _lease(String raw) {
    final sec = int.tryParse(raw) ?? -1;
    if (sec < 0) return raw.isEmpty ? '—' : raw;
    if (sec >= 3600) return '${sec ~/ 3600}H';
    if (sec >= 60) return '${sec ~/ 60}M';
    return '${sec}S';
  }

  Future<Map<String, String>> _fetchPublicIp() async {
    // ipapi.co (HTTPS, keyless): ip + isp/org + country + timezone.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .getUrl(Uri.parse('https://ipapi.co/json/'));
      final resp =
          await req.close().timeout(const Duration(seconds: 8));
      final body =
          (await resp.transform(utf8.decoder).join()).trim();
      final m = json.decode(body);
      if (m is! Map) throw 'bad response';
      String str(String k) =>
          (m[k]?.toString() ?? '').trim();
      final ip = str('ip');
      if (ip.isEmpty) throw 'bad response';
      return {
        'ip': ip,
        'isp': str('org').isEmpty ? '—' : str('org'),
        'country': str('country_name').isEmpty
            ? '—'
            : str('country_name'),
        'timezone': str('timezone').isEmpty
            ? '—'
            : str('timezone'),
      };
    } finally {
      client.close(force: true);
    }
  }

  /// Bottom sheet like the reference: IP + ISP + Country + Timezone,
  /// spinner while fetching, refresh + tap-to-copy.
  Future<void> _showPublicIp(BuildContext context) async {
    var nonce = 0;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.globe, size: 18),
                  const SizedBox(width: 8),
                  Text('Public IP',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 16),
                    onPressed: () =>
                        setSheet(() => nonce++),
                  ),
                ],
              ),
              const Divider(height: 20),
              // Inline future: refetches on every sheet rebuild
              // (initial open + refresh button tap).
              FutureBuilder<Map<String, String>>(
                future: _fetchPublicIp(),
                builder: (context, snap) {
                  if (snap.connectionState !=
                      ConnectionState.done) {
                    return const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child:
                              CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError ||
                      (snap.data ?? const {}).isEmpty) {
                    return Text(
                        'Unavailable — check internet.',
                        style: GoogleFonts
                            .plusJakartaSans(
                                color:
                                    AppColors.error));
                  }
                  final d = snap.data!;
                  return Column(
                    children: [
                      _ipRow(
                          ctx,
                          LucideIcons.smartphone,
                          'IP Address',
                          d['ip'] ?? '—'),
                      _ipRow(ctx, LucideIcons.building2,
                          'ISP', d['isp'] ?? '—'),
                      _ipRow(ctx, LucideIcons.mapPin,
                          'Country', d['country'] ?? '—'),
                      _ipRow(ctx, LucideIcons.clock,
                          'Timezone', d['timezone'] ?? '—',
                          last: true),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ipRow(BuildContext context, IconData icon, String label,
      String value,
      {bool last = false}) {
    return InkWell(
      onTap: () {
        if (value.isNotEmpty && value != '—') {
          try {
            Clipboard.setData(ClipboardData(text: value));
            Get.snackbar('Copied', '$label copied.',
                snackPosition: SnackPosition.BOTTOM,
                duration: const Duration(seconds: 1));
          } catch (_) {}
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon,
                size: 17,
                color: Theme.of(context).hintColor),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final w = c.wifi.value;
      final connected = w?['connected'] == true;
      final ip = w?['ip']?.toString() ?? '—';
      final freq = (w?['freqMhz'] as num?)?.toInt() ?? -1;
      final std = (w?['standard'] as num?)?.toInt() ?? -1;
      final gen = connected ? _wifiGen(std, freq) : '—';
      String safe(dynamic v) {
        final s = v?.toString().trim() ?? '';
        return s.isEmpty || s == '-1' ? '—' : s;
      }

      return ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          devCard(context,
              child: Row(
                children: [
                  Icon(
                      connected
                          ? LucideIcons.wifi
                          : LucideIcons.wifiOff,
                      size: 34,
                      color: Dt.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                            connected
                                ? 'Wi-Fi'
                                : 'Not connected',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w800)),
                        if (connected) ...[
                          Text(ip,
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight:
                                          FontWeight.w600,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                          Text(gen,
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12.5,
                                      fontWeight:
                                          FontWeight.w600,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            Get.to(() => const DataUsageView()),
                        icon: const Icon(
                            LucideIcons.refreshCw,
                            size: 13),
                        label: const Text('Usage'),
                        style:
                            OutlinedButton.styleFrom(
                          padding: const EdgeInsets
                              .symmetric(
                              horizontal: 12,
                              vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize
                                  .shrinkWrap,
                          textStyle: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showPublicIp(context),
                        icon: const Icon(
                            LucideIcons.globe,
                            size: 13),
                        label: const Text('Public IP'),
                        style:
                            OutlinedButton.styleFrom(
                          padding: const EdgeInsets
                              .symmetric(
                              horizontal: 12,
                              vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize
                                  .shrinkWrap,
                          textStyle: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              )),
          const SizedBox(height: 14),
          devCard(context,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  devRow(context, 'IP Address',
                      connected ? ip : '—'),
                  devRow(context, 'IPv6 Address',
                      safe(w?['ipv6'])),
                  devRow(context, 'Gateway',
                      safe(w?['gateway'])),
                  devRow(context, 'Subnet Mask',
                      safe(w?['mask'])),
                  devRow(context, 'DNS 1',
                      safe(w?['dns'])),
                  devRow(context, 'Lease Duration',
                      _lease(w?['leaseSec']?.toString() ?? '')),
                  devRow(context, 'Interface',
                      safe(w?['iface'])),
                  devRow(
                      context,
                      'Link Speed',
                      (w?['linkMbps'] as num?) != null &&
                              (w?['linkMbps'] as num) >=
                                  0
                          ? '${w?['linkMbps']} Mbps'
                          : '—'),
                  devRow(context, 'Channel',
                      _wifiChannel(freq)),
                  devRow(context, 'Frequency',
                      freq > 0 ? '$freq MHz' : '—'),
                  devRow(context, 'WiFi Standard',
                      _wifiStd(std),
                      last: true),
                ],
              )),
        ],
      );
    });
  }
}
