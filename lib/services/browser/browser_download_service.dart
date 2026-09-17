import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../services/hive_service.dart';
import '../../utils/export_file.dart';

/// UC-Browser-style download states.
enum BrowserDownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

/// One download job. Progress fields are reactive so sheets/badges update
/// live; [toJson] persists only the resumable metadata.
class BrowserDownload {
  final String id;
  final String url;
  final String fileName;
  final String? mimeType;
  final String? tempPath;

  final Rx<BrowserDownloadStatus> status;
  final RxInt received;
  final RxInt total; // -1 = unknown length
  final RxString error;

  BrowserDownload({
    required this.id,
    required this.url,
    required this.fileName,
    this.mimeType,
    this.tempPath,
    BrowserDownloadStatus initialStatus = BrowserDownloadStatus.queued,
    int initialReceived = 0,
    int initialTotal = -1,
    String initialError = '',
  })  : status = initialStatus.obs,
        received = initialReceived.obs,
        total = initialTotal.obs,
        error = initialError.obs;

  double get progress {
    final t = total.value;
    if (t <= 0) return 0;
    return (received.value / t).clamp(0.0, 1.0);
  }

  bool get isActive =>
      status.value == BrowserDownloadStatus.downloading ||
      status.value == BrowserDownloadStatus.queued;

  bool get isResumable =>
      status.value == BrowserDownloadStatus.paused ||
      status.value == BrowserDownloadStatus.failed ||
      status.value == BrowserDownloadStatus.canceled;

  String get progressLabel {
    final got = _fmtBytes(received.value);
    final t = total.value;
    if (t <= 0) return got;
    return '$got / ${_fmtBytes(t)}';
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'mimeType': mimeType,
        'tempPath': tempPath,
        'status': status.value.name,
        'received': received.value,
        'total': total.value,
        'error': error.value,
      };

  factory BrowserDownload.fromJson(Map<String, dynamic> m) {
    BrowserDownloadStatus st;
    try {
      st = BrowserDownloadStatus.values.byName('${m['status']}');
    } catch (_) {
      st = BrowserDownloadStatus.failed;
    }
    // Anything in-flight at shutdown becomes paused (resumable on demand).
    if (st == BrowserDownloadStatus.downloading ||
        st == BrowserDownloadStatus.queued) {
      st = BrowserDownloadStatus.paused;
    }
    return BrowserDownload(
      id: '${m['id'] ?? ''}',
      url: '${m['url'] ?? ''}',
      fileName: '${m['fileName'] ?? 'download'}',
      mimeType: m['mimeType']?.toString(),
      tempPath: m['tempPath']?.toString(),
      initialStatus: st,
      initialReceived: (m['received'] as num?)?.toInt() ?? 0,
      initialTotal: (m['total'] as num?)?.toInt() ?? -1,
      initialError: '${m['error'] ?? ''}',
    );
  }
}

/// Builds a `Range` header for resuming at [offset].
String buildRangeHeader(int offset) => 'bytes=$offset-';

/// Parses `Content-Range: bytes <first>-<last>/<complete>` → total length,
/// or null when the header is absent/malformed.
int? parseContentRangeTotal(String? header) {
  if (header == null || header.isEmpty) return null;
  final m = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(header);
  if (m == null) return null;
  final total = m.group(1);
  if (total == null || total == '*') return null;
  return int.tryParse(total);
}

/// Streaming download manager with pause / resume (HTTP Range) / retry.
/// Partial data lives in a `.part` temp file, so resume survives restarts
/// when the server honours ranges; otherwise the job restarts from zero.
/// Completed files are handed to [ExportFile.quickExport] (save + share).
class BrowserDownloadService extends GetxService {
  static const int maxParallel = 3;
  static const int maxJobs = 50;

  final downloads = <BrowserDownload>[].obs;

  final _clients = <String, http.Client>{};
  final _subs = <String, StreamSubscription<List<int>>>{};

  int get activeCount => downloads.where((d) => d.isActive).length;

  int get runningCount =>
      downloads.where((d) => d.status.value == BrowserDownloadStatus.downloading).length;

  @override
  void onInit() {
    super.onInit();
    _restore();
  }

  @override
  void onClose() {
    for (final c in _clients.values) {
      try {
        c.close();
      } catch (_) {}
    }
    _clients.clear();
    super.onClose();
  }

  HiveService? get _hive =>
      Get.isRegistered<HiveService>() ? Get.find<HiveService>() : null;

  void _restore() {
    try {
      final raw = _hive?.getSetting<String>(AppConstants.keyBrowserDownloads);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => BrowserDownload.fromJson(
              Map<String, dynamic>.from(m)))
          .where((d) => d.id.isNotEmpty && d.url.isNotEmpty)
          .toList();
      // Drop completed jobs from previous sessions (files already saved).
      downloads.assignAll(
          list.where((d) => d.status.value != BrowserDownloadStatus.completed));
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await _hive?.setSetting(AppConstants.keyBrowserDownloads,
          jsonEncode(downloads.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  Future<String> _tempPath(String id) async {
    final dir = await getTemporaryDirectory();
    final dl = Directory('${dir.path}/cubiclm_dl');
    if (!await dl.exists()) await dl.create(recursive: true);
    return '${dl.path}/$id.part';
  }

  /// Enqueue a download and start it when a slot is free. Returns the job.
  Future<BrowserDownload?> enqueue({
    required String url,
    required String fileName,
    String? mimeType,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      Get.snackbar('Download', 'Only http(s) downloads are supported.',
          snackPosition: SnackPosition.BOTTOM);
      return null;
    }
    if (downloads.length >= maxJobs) {
      downloads.removeWhere((d) =>
          d.status.value == BrowserDownloadStatus.completed ||
          d.status.value == BrowserDownloadStatus.canceled);
    }
    final job = BrowserDownload(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url.trim(),
      fileName: fileName,
      mimeType: mimeType,
      tempPath: await _tempPath(
          DateTime.now().millisecondsSinceEpoch.toString()),
    );
    downloads.insert(0, job);
    await _persist();
    _pump();
    return job;
  }

  BrowserDownload? byId(String id) {
    try {
      return downloads.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  void _pump() {
    if (runningCount >= maxParallel) return;
    for (final d in downloads) {
      if (runningCount >= maxParallel) break;
      if (d.status.value == BrowserDownloadStatus.queued) {
        unawaited(_run(d));
      }
    }
  }

  Future<void> _run(BrowserDownload job) async {
    job.status.value = BrowserDownloadStatus.downloading;
    job.error.value = '';
    await _persist();

    final client = http.Client();
    _clients[job.id] = client;
    try {
      final tmp = File(job.tempPath ?? await _tempPath(job.id));
      var offset = 0;
      if (await tmp.exists()) {
        // Resume attempt: keep what we have only if the server honours it.
        offset = (job.received.value > 0) ? job.received.value : await tmp.length();
      }

      final req = http.Request('GET', Uri.parse(job.url));
      if (offset > 0) req.headers['Range'] = buildRangeHeader(offset);
      final res = await client.send(req);

      final partial = res.statusCode == 206;
      if (res.statusCode != 200 && !partial) {
        throw 'HTTP ${res.statusCode}';
      }
      if (partial) {
        final total = parseContentRangeTotal(res.headers['content-range']);
        if (total != null) job.total.value = total;
      } else {
        // Fresh response — previous partial data is invalid.
        offset = 0;
        job.received.value = 0;
        final len = res.contentLength;
        job.total.value = len ?? -1;
      }

      final sink = tmp.openWrite(mode: offset > 0 && partial ? FileMode.append : FileMode.write);
      final sub = res.stream.listen(
        (chunk) {
          try {
            sink.add(chunk);
            job.received.value += chunk.length;
          } catch (_) {}
        },
        onError: (e) async {
          try {
            await sink.close();
          } catch (_) {}
          _onStreamError(job, '$e');
        },
        onDone: () async {
          try {
            await sink.close();
          } catch (_) {}
          await _onStreamDone(job, tmp);
        },
        cancelOnError: true,
      );
      _subs[job.id] = sub;
    } catch (e) {
      _clients.remove(job.id);
      try {
        client.close();
      } catch (_) {}
      // Pause (not fail) on manual abort — resume() continues.
      if (job.status.value == BrowserDownloadStatus.downloading) {
        job.status.value = BrowserDownloadStatus.failed;
        job.error.value = '$e';
        Get.snackbar('Download failed', job.fileName,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 3));
      }
      await _persist();
      _pump();
    }
  }

  Future<void> _onStreamError(BrowserDownload job, String e) async {
    _subs.remove(job.id);
    _clients.remove(job.id);
    if (job.status.value == BrowserDownloadStatus.downloading) {
      job.status.value = BrowserDownloadStatus.failed;
      job.error.value = e;
    }
    await _persist();
    _pump();
  }

  Future<void> _onStreamDone(BrowserDownload job, File tmp) async {
    _subs.remove(job.id);
    final client = _clients.remove(job.id);
    try {
      client?.close();
    } catch (_) {}
    if (job.status.value != BrowserDownloadStatus.downloading) {
      // Paused/cancelled mid-stream — leave partial file for resume.
      await _persist();
      _pump();
      return;
    }
    try {
      final bytes = await tmp.readAsBytes();
      if (bytes.isEmpty) throw 'Empty file';
      await ExportFile.quickExport(
        bytes: bytes,
        fileName: job.fileName,
        mimeType: job.mimeType,
        shareText: job.fileName,
      );
      try {
        await tmp.delete();
      } catch (_) {}
      job.status.value = BrowserDownloadStatus.completed;
      job.received.value = bytes.length;
      if (job.total.value <= 0) job.total.value = bytes.length;
    } catch (e) {
      job.status.value = BrowserDownloadStatus.failed;
      job.error.value = '$e';
      Get.snackbar('Download failed', job.fileName,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3));
    }
    await _persist();
    _pump();
  }

  /// Pause a running/queued job (partial file kept for resume).
  Future<void> pause(String id) async {
    final job = byId(id);
    if (job == null) return;
    try {
      await _subs.remove(id)?.cancel();
    } catch (_) {}
    try {
      _clients.remove(id)?.close();
    } catch (_) {}
    if (job.status.value == BrowserDownloadStatus.downloading ||
        job.status.value == BrowserDownloadStatus.queued) {
      job.status.value = BrowserDownloadStatus.paused;
    }
    await _persist();
    _pump();
  }

  /// Resume a paused/failed/cancelled job.
  Future<void> resume(String id) async {
    final job = byId(id);
    if (job == null || !job.isResumable) return;
    job.error.value = '';
    job.status.value = BrowserDownloadStatus.queued;
    await _persist();
    _pump();
  }

  /// Cancel + delete partial data.
  Future<void> cancel(String id) async {
    final job = byId(id);
    if (job == null) return;
    try {
      await _subs.remove(id)?.cancel();
    } catch (_) {}
    try {
      _clients.remove(id)?.close();
    } catch (_) {}
    try {
      final p = job.tempPath;
      if (p != null) await File(p).delete();
    } catch (_) {}
    job.status.value = BrowserDownloadStatus.canceled;
    job.received.value = 0;
    await _persist();
    _pump();
  }

  /// Retry from scratch (drops partial data).
  Future<void> retry(String id) async {
    final job = byId(id);
    if (job == null) return;
    try {
      await _subs.remove(id)?.cancel();
    } catch (_) {}
    try {
      _clients.remove(id)?.close();
    } catch (_) {}
    try {
      final p = job.tempPath;
      if (p != null && await File(p).exists()) await File(p).delete();
    } catch (_) {}
    job.received.value = 0;
    job.total.value = -1;
    job.error.value = '';
    job.status.value = BrowserDownloadStatus.queued;
    await _persist();
    _pump();
  }

  Future<void> remove(String id) async {
    final job = byId(id);
    if (job == null) return;
    if (job.status.value == BrowserDownloadStatus.downloading) {
      await cancel(id);
    }
    downloads.remove(job);
    await _persist();
  }

  Future<void> clearFinished() async {
    downloads.removeWhere((d) =>
        d.status.value == BrowserDownloadStatus.completed ||
        d.status.value == BrowserDownloadStatus.canceled);
    await _persist();
  }
}
