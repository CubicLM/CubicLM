import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/local_server_service.dart';

/// Windows llama-server sidecar: URL/asset naming, CLI args, SSE
/// parsing and health checks. Pure — no process spawned here.
void main() {
  group('serverAssetName / serverDownloadUrl', () {
    test('cpu and vulkan assets are pinned', () {
      expect(serverAssetName(gpu: false),
          'llama-b6403-bin-win-cpu-x64.zip');
      expect(serverAssetName(gpu: true),
          'llama-b6403-bin-win-vulkan-x64.zip');
      expect(serverDownloadUrl(gpu: false), contains('llama-b6403-bin-win-cpu-x64.zip'));
      expect(serverDownloadUrl(gpu: true),
          startsWith('https://github.com/ggerganov/llama.cpp/releases/download/'));
    });
  });

  group('buildServerArgs', () {
    test('maps load params to llama-server flags', () {
      final args = buildServerArgs(
        modelPath: r'C:\m\qwen.gguf',
        port: 17889,
        contextSize: 2048,
        threads: 4,
        gpuLayers: 0,
      );
      expect(
          args,
          [
            '-m', r'C:\m\qwen.gguf',
            '--port', '17889',
            '-c', '2048',
            '-t', '4',
            '--n-gpu-layers', '0',
            '--no-webui',
          ]);
    });
  });

  group('extractServerDelta', () {
    test('parses OpenAI SSE deltas', () {
      expect(
          extractServerDelta(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}'),
          'Hello');
      expect(extractServerDelta('data: [DONE]'), '__DONE__');
      expect(extractServerDelta(': ping'), isNull);
      expect(extractServerDelta(''), isNull);
      expect(
          extractServerDelta(
              'data: {"choices":[{"delta":{}}]}'),
          isNull);
      expect(extractServerDelta('data: garbage'), isNull);
    });
  });

  group('isServerHealthy', () {
    test('accepts only status ok', () {
      expect(isServerHealthy('{"status":"ok"}'), isTrue);
      expect(isServerHealthy('{"status":"loading"}'), isFalse);
      expect(isServerHealthy('not json'), isFalse);
    });
  });
}
