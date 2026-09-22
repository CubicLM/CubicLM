import 'dart:async';
import 'dart:io' show File, FileMode, RandomAccessFile;
import 'dart:typed_data';
import 'package:get/get.dart';
import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import 'hive_service.dart';
import 'inference_types.dart';
import 'local_server_service.dart';
import '../core/constants.dart';
import 'device_info_service.dart';
import 'app_log_service.dart';

// Conditionally import llama_flutter_android — only on Android
import 'inference_android.dart' if (dart.library.html) 'inference_stub.dart'
    as platform;

/// Cross-platform inference service.
/// - Android / iOS: uses llama_flutter_android for local GGUF models
/// - Android: uses flutter_litert_lm for LiteRT-LM models
/// - Web: cloud-only mode (local inference coming soon)
part 'inference_loading.dart';
part 'inference_lifecycle.dart';
part 'inference_generation.dart';
part 'inference_server.dart';
part 'inference_engine.dart';

class InferenceService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  // ── Observable State ──
  final isModelLoaded = false.obs;
  final isGenerating = false.obs;
  final isLoadingModel = false.obs;
  final isVisionLoaded = false.obs;
  final loadingModelName = ''.obs;
  final loadedModelName = ''.obs;
  final tokenCount = 0.obs;
  final tokensPerSecond = 0.0.obs;
  final contextTokensUsed = 0.obs;
  final contextTokensTotal = 0.obs;
  final modelLoadProgress = 0.0.obs;
  final generationSource = ''.obs;
  final streamingText = ''.obs;
  final gpuName = ''.obs;
  final gpuLayersUsed = 0.obs;
  final isGpuAccelerated = false.obs;
  final loadedModelRuntime = ''.obs;
  final loadedBackend = ''.obs;

  /// GGUF models currently resident in the native multi-model pool
  /// (file names, not full paths). Used by the in-chat switcher to mark
  /// models that can be activated instantly.
  final residentTextModels = <String>[].obs;

  /// Re-query the native pool for resident model paths.
  Future<void> refreshResidency() async {
    try {
      if (_serverActive) {
        // Sidecar serves exactly one model — report it resident so the
        // switcher marks it (instant-switch path handles the rest).
        // Split on both separators: server paths are Windows-style.
        residentTextModels.value = <String>[
          _server!.loadedModelPath.split(RegExp(r'[/\\]')).last
        ];
        return;
      }
      final paths = await _engine?.residentModels() ?? const <String>[];
      residentTextModels.value = paths
          .map((p) => p.split('/').last)
          .toList(growable: true);
    } catch (_) {
      // Pool info is best-effort; never block loading on it.
    }
  }

  /// True when [filename] can be switched to without any loading.
  bool isResident(String filename) => residentTextModels.contains(filename);

  /// Whether the current platform supports local inference.
  bool get supportsLocalInference => platform.supportsLocalInference;

  // Platform-specific engine
  platform.InferenceEngine? _engine;
  String _sessionNativeRuntime = '';

  // Windows local-server sidecar (llama-server.exe child process).
  // Null/absent everywhere else; engine stays null on Windows.
  LocalServerService? _server;
  int _serverCtx = 0;

  bool get _serverActive =>
      _server != null && _server!.isRunning && isModelLoaded.value;

  bool _serverServes(String modelPath) =>
      _serverActive && _server!.loadedModelPath == modelPath;

  String get sessionNativeRuntime => _sessionNativeRuntime;

  bool requiresAppRestartForRuntime(String runtime) {
    final normalized = runtime.toLowerCase();
    if (normalized != 'llama' && normalized != 'litert') return false;
    return _sessionNativeRuntime.isNotEmpty &&
        _sessionNativeRuntime != normalized;
  }

  /// Validates a GGUF file before it reaches the native loader. Returns a
  /// reason string when the file cannot be a valid model, null when it
  /// looks sane. Native llama.cpp aborts (SIGABRT/SIGBUS, instant app
  /// death) on malformed headers AND on tensor data cut short by a
  /// truncated download — Dart must reject these before the FFI boundary.
  /// A valid 32-byte magic alone proves nothing: truncation usually hits
  /// the tensor payload at the END of the file, so the full tensor table
  /// is parsed and every known tensor must fit inside the file.
  /// Public for unit tests.
  static String? validateGgufHeader(File f) {
    try {
      final len = f.lengthSync();
      if (len < 1024 * 1024) return 'file too small (${len}B)';
      final raf = f.openSync(mode: FileMode.read);
      try {
        final head = raf.readSync(32);
        if (head.length < 32) return 'cannot read header';
        final bd = head.buffer.asByteData(head.offsetInBytes);
        if (bd.getUint8(0) != 0x47 || // G
            bd.getUint8(1) != 0x47 || // G
            bd.getUint8(2) != 0x55 || // U
            bd.getUint8(3) != 0x46) {
          // F
          return 'bad magic';
        }
        final version = bd.getUint32(4, Endian.little);
        if (version != 2 && version != 3) return 'unknown version $version';
        final tensors = bd.getUint64(8, Endian.little);
        if (tensors == 0 || tensors > 100000) {
          return 'implausible tensor count $tensors';
        }
        return _validateGgufTensors(raf, len, tensors);
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      return 'unreadable ($e)';
    }
  }

  /// Block length (elements) and byte size per GGML quant block.
  /// Only long-stable, certain type IDs are listed. Anything else
  /// returns null (skipped, never a false alarm): a wrong size would
  /// either block a valid model or miss a cut, both worse than skipping.
  static int? _ggmlBlockBytes(int type, int nelements) {
    switch (type) {
      case 0:
        return nelements * 4; // F32
      case 1:
        return nelements * 2; // F16
      case 2:
        return (nelements ~/ 32) * 18; // Q4_0
      case 3:
        return (nelements ~/ 32) * 20; // Q4_1
      case 6:
        return (nelements ~/ 32) * 22; // Q5_0
      case 7:
        return (nelements ~/ 32) * 24; // Q5_1
      case 8:
        return (nelements ~/ 32) * 34; // Q8_0
      case 10:
        return (nelements ~/ 256) * 84; // Q2_K
      case 11:
        return (nelements ~/ 256) * 110; // Q3_K
      case 12:
        return (nelements ~/ 256) * 144; // Q4_K
      case 13:
        return (nelements ~/ 256) * 176; // Q5_K
      case 14:
        return (nelements ~/ 256) * 210; // Q6_K
      case 15:
        return (nelements ~/ 256) * 260; // Q8_K
      default:
        return null;
    }
  }

  /// Parses GGUF metadata + tensor infos and requires every known tensor
  /// to end inside the file. Returns null when sane (or unverifiable).
  static String? _validateGgufTensors(
      RandomAccessFile raf, int fileLen, int tensorCount) {
    // Read enough to cover any realistic header (tokenizer arrays can
    // be several MB). Overruns inside a fully-read header are definitive.
    const cap = 32 * 1024 * 1024;
    final want = fileLen < cap ? fileLen : cap;
    raf.setPositionSync(0);
    final bytes = raf.readSync(want);
    if (bytes.length < 32) return 'cannot read header';
    final bd = bytes.buffer.asByteData(bytes.offsetInBytes);
    // Header is exactly 24 bytes: magic(4) + version(4) + tensor
    // count(8) + metadata count(8). Metadata KVs start right after.
    int pos = 24;

    int u32() {
      final v = bd.getUint32(pos, Endian.little);
      pos += 4;
      return v;
    }

    int u64() {
      final v = bd.getUint64(pos, Endian.little);
      pos += 8;
      return v;
    }

    void skipString() {
      final n = u64();
      pos += n;
    }

    void checkBounds(String what) {
      if (pos < 0 || pos > bytes.length) {
        throw StateError('$what overruns file');
      }
    }

    try {
      final metaCount = bd.getUint64(16, Endian.little);
      if (metaCount > 100000) return 'implausible metadata count $metaCount';
      for (var i = 0; i < metaCount; i++) {
        checkBounds('metadata key');
        skipString();
        checkBounds('metadata type');
        final type = u32();
        checkBounds('metadata value');
        switch (type) {
          case 8: // string
            skipString();
            break;
          case 9: // array
            final elemType = u32();
            final arrLen = u64();
            if (arrLen > 1000000) {
              throw StateError('metadata array too long');
            }
            for (var j = 0; j < arrLen; j++) {
              if (elemType == 8) {
                skipString();
              } else {
                pos += _ggufScalarBytes(elemType);
              }
              checkBounds('metadata array element');
            }
            break;
          default:
            pos += _ggufScalarBytes(type);
            break;
        }
        checkBounds('metadata end');
        if (pos > cap) return null; // header bigger than window: unverifiable
      }
      var maxEnd = 0;
      var checked = 0;
      for (var i = 0; i < tensorCount; i++) {
        checkBounds('tensor name');
        skipString();
        checkBounds('tensor dims');
        final nDims = u32();
        if (nDims > 8) throw StateError('implausible dims $nDims');
        var nelements = 1;
        for (var d = 0; d < nDims; d++) {
          checkBounds('tensor dim');
          final dim = u64();
          if (dim > (1 << 40)) throw StateError('implausible dim $dim');
          nelements *= dim;
          if (nelements > (1 << 48)) throw StateError('tensor too big');
        }
        checkBounds('tensor type/offset');
        final ttype = u32();
        final offset = u64();
        final size = _ggmlBlockBytes(ttype, nelements);
        if (size != null) {
          final end = offset + size;
          if (end > maxEnd) maxEnd = end;
          checked++;
        }
      }
      if (checked == 0) return null; // nothing verifiable
      // Tensor data starts after the header, aligned up. We don't know
      // the exact alignment without re-scanning metadata values, so use
      // the table end rounded up to 32 (the default) as the base: any
      // real file's base is >= this only if alignment <= 32... to stay
      // sound for larger alignments, add one alignment span of slack.
      // Tensor data starts after the header, aligned up (default 32).
      // Absolute end = aligned table end + relative tensor end; one
      // alignment span of slack keeps this sound for larger alignments.
      final dataBase = ((pos + 31) ~/ 32) * 32;
      if (dataBase + maxEnd + 32 > fileLen) {
        return 'truncated file: tensor data ends past EOF '
            '(${(dataBase + maxEnd) ~/ (1024 * 1024)}MB > ${fileLen ~/ (1024 * 1024)}MB)';
      }
      return null;
    } catch (e) {
      final msg = '$e';
      final windowed = bytes.length < fileLen;
      if (msg.contains('overruns') ||
          msg.contains('implausible') ||
          msg.contains('too long') ||
          msg.contains('too big')) {
        // Ran past the read window on a bigger file: unverifiable, not
        // proof of corruption. Only a true EOF overrun is a rejection.
        if (windowed && msg.contains('overruns')) return null;
        return 'corrupt header ($msg)';
      }
      return null; // short read inside window: unverifiable, don't block
    }
  }

  static int _ggufScalarBytes(int type) {
    switch (type) {
      case 0:
      case 1:
        return 1;
      case 2:
      case 3:
        return 2;
      case 4:
      case 5:
      case 6:
        return 4;
      case 10:
      case 11:
      case 12:
        return 8;
      default:
        throw StateError('unknown scalar type $type');
    }
  }


  String _getDeviceTier() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.deviceTier.value;
    } catch (_) {
      return 'mid';
    }
  }

  /// Windows generate path: OpenAI-compatible streaming chat against
  /// the sidecar. [onToken] is the shared handler (counters + trip-wire).

  bool _getIsTensorSoC() {
    try {
      final device = Get.find<DeviceInfoService>();
      return device.isTensorSoC.value;
    } catch (_) {
      return false;
    }
  }


}
