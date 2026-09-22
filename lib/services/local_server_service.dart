/// On-device inference for Windows via a prebuilt `llama-server.exe`
/// sidecar (no NDK/MSVC build needed on the farm).
///
/// Android/iOS keep the native plugin path; Windows spawns the pinned
/// llama.cpp server release, serves the downloaded GGUF over
/// 127.0.0.1, and talks OpenAI-compatible `/v1/chat/completions`
/// (streaming SSE). Pure helpers at the bottom are unit-tested.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pinned llama.cpp release with `bin-win-{cpu,vulkan}-x64` assets.
const localServerRelease = 'b6403';

/// `true` on Windows desktop only (web + mobile use other engines).
bool get supportsLocalServer => !GetPlatform.isWeb && GetPlatform.isWindows;

/// Best-effort Vulkan driver presence check (vulkan-1.dll ships with
/// the driver). Presence ≠ working GPU, but absence means the Vulkan
/// build can never init — so auto mode picks the CPU asset then.
bool vulkanPresent() {
  try {
    final sys32 = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return File('$sys32/System32/vulkan-1.dll').existsSync();
  } catch (_) {
    return false;
  }
}

/// Server zip asset for the [gpu] variant (Vulkan / CPU-only).
String serverAssetName({required bool gpu}) =>
    gpu ? 'llama-b6403-bin-win-vulkan-x64.zip' : 'llama-b6403-bin-win-cpu-x64.zip';

/// Download URL for the pinned server asset.
String serverDownloadUrl({required bool gpu}) =>
    'https://github.com/ggerganov/llama.cpp/releases/download/$localServerRelease/${serverAssetName(gpu: gpu)}';

/// CLI args for `llama-server.exe`. Pure — unit tested.
List<String> buildServerArgs({
  required String modelPath,
  required int port,
  required int contextSize,
  required int threads,
  required int gpuLayers,
}) {
  return [
    '-m', modelPath,
    '--port', '$port',
    '-c', '$contextSize',
    '-t', '$threads',
    '--n-gpu-layers', '$gpuLayers',
    '--no-webui',
  ];
}

/// Parses one SSE `data:` line from `/v1/chat/completions` (stream).
/// Returns the text delta, `'__DONE__'` on `[DONE]`, null otherwise.
/// Pure — unit tested.
String? extractServerDelta(String line) {
  final t = line.trim();
  if (!t.startsWith('data:')) return null;
  final payload = t.substring(5).trim();
  if (payload == '[DONE]') return '__DONE__';
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final delta = (choices[0] as Map)['delta'];
    if (delta is! Map) return null;
    final content = delta['content'];
    return content is String ? content : null;
  } catch (_) {
    return null;
  }
}

/// `true` when a `/health` body reports ready. Pure — unit tested.
bool isServerHealthy(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['status'] == 'ok';
  } catch (_) {
    return false;
  }
}

/// Owns the `llama-server.exe` child process + its HTTP client.
/// Registered lazily by [InferenceService] on Windows only.
class LocalServerService extends GetxService {
  Process? _proc;
  http.Client? _chatClient;
  int port = 0;
  String loadedModelPath = '';
  int contextSize = 0;
  int gpuLayers = 0;
  bool starting = false;

  bool get isRunning => _proc != null && port > 0;

  /// Versioned variant dir: `<support>/llama_server/<release>-<cpu|vulkan>/`.
  Future<Directory> serverDir({required bool gpu}) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
        '${support.path}/llama_server/$localServerRelease-${gpu ? 'vulkan' : 'cpu'}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _exeFile({required bool gpu}) async =>
      File('${(await serverDir(gpu: gpu)).path}/llama-server.exe');

  /// Deletes server dirs from older pins (each pin is versioned, so a
  /// release bump orphans the previous download). Best-effort only.
  Future<void> _pruneStaleVersions() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/llama_server');
      if (!await root.exists()) return;
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        final name = e.path.split(RegExp(r'[/\\]')).last;
        if (!name.startsWith(localServerRelease)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
  /// Downloads + extracts the pinned server the first time it is
  /// needed (14MB CPU / 26MB Vulkan). Returns the exe file.
  Future<File> ensureServer({
    required bool wantGpu,
    void Function(double)? onProgress,
  }) async {
    final exe = await _exeFile(gpu: wantGpu);
    if (await exe.exists()) return exe;
    unawaited(_pruneStaleVersions());
    final dir = await serverDir(gpu: wantGpu);
    final zipPath = '${dir.path}/${serverAssetName(gpu: wantGpu)}';
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse(serverDownloadUrl(gpu: wantGpu)));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw 'Server download HTTP ${res.statusCode}';
      }
      final total = res.contentLength;
      final sink = File(zipPath).openWrite();
      var received = 0;
      await for (final chunk in res) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final out = File('${dir.path}/${f.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
      }
      await File(zipPath).delete();
    } finally {
      client.close(force: true);
    }
    if (!await exe.exists()) throw 'Server extract failed (no exe)';
    return exe;
  }

  /// Starts the server for [modelPath] (stops any previous one) and
  /// waits for `/health`. Returns the port. Throws on timeout.
  Future<int> start({
    required String modelPath,
    required int contextSize,
    required int threads,
    required int gpuLayers,
    required bool wantGpu,
    void Function(double)? onBinaryProgress,
  }) async {
    await stop();
    starting = true;
    try {
      final exe = await ensureServer(
          wantGpu: wantGpu, onProgress: onBinaryProgress);
      port = await _freePort();
      final args = buildServerArgs(
        modelPath: modelPath,
        port: port,
        contextSize: contextSize,
        threads: threads,
        gpuLayers: gpuLayers,
      );
      _proc = await Process.start(exe.path, args,
          workingDirectory: exe.parent.path,
          mode: ProcessStartMode.detachedWithStdio);
      final ok = await _waitHealthy(
          Duration(seconds: wantGpu ? 120 : 150));
      if (!ok) {
        await stop();
        throw 'llama-server did not become ready in time';
      }
      loadedModelPath = modelPath;
      this.contextSize = contextSize;
      this.gpuLayers = gpuLayers;
      return port;
    } finally {
      starting = false;
    }
  }

  Future<void> stop() async {
    _chatClient?.close();
    _chatClient = null;
    final p = _proc;
    _proc = null;
    port = 0;
    loadedModelPath = '';
    contextSize = 0;
    gpuLayers = 0;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigkill);
        await p.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          p.kill();
        } catch (_) {}
      }
    }
  }

  /// Streaming chat against the running server. Mirrors
  /// `POST /v1/chat/completions` (OpenAI SSE). Throws on HTTP errors;
  /// returns the full assembled text.
  Future<String> chat({
    required List<Map<String, String>> messages,
    required double temperature,
    required double topP,
    required int maxTokens,
    required void Function(String token) onToken,
  }) async {
    if (!isRunning) throw 'Local server is not running';
    final client = http.Client();
    _chatClient = client;
    final out = StringBuffer();
    try {
      final req = http.Request(
          'POST', Uri.parse('http://127.0.0.1:$port/v1/chat/completions'));
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode({
        'model': 'local',
        'messages': messages,
        'temperature': temperature,
        'top_p': topP,
        'max_tokens': maxTokens,
        'stream': true,
      });
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw 'Local server HTTP ${res.statusCode}';
      }
      await for (final line
          in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        final delta = extractServerDelta(line);
        if (delta == null) continue;
        if (delta == '__DONE__') break;
        if (delta.isEmpty) continue;
        out.write(delta);
        onToken(delta);
      }
      return out.toString();
    } finally {
      if (identical(_chatClient, client)) _chatClient = null;
      client.close();
    }
  }

  /// Aborts an in-flight [chat] call (stop button).
  void abortChat() {
    try {
      _chatClient?.close();
    } catch (_) {}
    _chatClient = null;
  }

  Future<bool> _waitHealthy(Duration timeout) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        try {
          final req = await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/health'));
          final res =
              await req.close().timeout(const Duration(seconds: 5));
          final body = await res.transform(utf8.decoder).join();
          if (res.statusCode == 200 && isServerHealthy(body)) return true;
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _freePort() async {
    for (var p = 17889; p < 17909; p++) {
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
        await s.close();
        return p;
      } catch (_) {}
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }
}
