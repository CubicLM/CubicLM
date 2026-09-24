import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/inference_gguf.dart';

/// GGUF acceleration override (Settings › Parameters › Auto/CPU/GPU):
/// pure resolution logic — the native load itself can't be unit-tested.
void main() {
  group('resolveGpuLayers', () {
    test('cpu always disables offload', () {
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'cpu', autoLayers: 99, vulkanSupported: true),
          0);
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'cpu', autoLayers: 0, vulkanSupported: false),
          0);
    });

    test('gpu forces full offload only with Vulkan', () {
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'gpu', autoLayers: 0, vulkanSupported: true),
          99);
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'gpu', autoLayers: 33, vulkanSupported: false),
          0);
    });

    test('auto and unknown modes keep the tier heuristic', () {
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'auto', autoLayers: 33, vulkanSupported: true),
          33);
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'auto', autoLayers: 0, vulkanSupported: false),
          0);
      expect(
          GgufEngine.resolveGpuLayers(
              mode: 'bogus', autoLayers: 12, vulkanSupported: true),
          12);
    });
  });

  group('resolveAutoGpuLayers', () {
    const gb = 1024 * 1024 * 1024;

    test('no Vulkan always means CPU', () {
      expect(
          GgufEngine.resolveAutoGpuLayers(
            vulkanSupported: false,
            gpuNum: 870,
            recommendedLayers: 40,
            fileBytes: 2 * gb,
            kvBytes: 100 * 1024 * 1024,
            availBytes: 6 * gb,
          ),
          0);
    });

    test('roomy phone gets full offload on any Vulkan GPU', () {
      expect(
          GgufEngine.resolveAutoGpuLayers(
            vulkanSupported: true,
            gpuNum: 610, // mid-range tier — fit wins over tier table
            recommendedLayers: 20,
            fileBytes: 2 * gb,
            kvBytes: 100 * 1024 * 1024,
            availBytes: 6 * gb,
          ),
          99);
    });

    test('tight flagship falls back to tier heuristic, not OOM', () {
      expect(
          GgufEngine.resolveAutoGpuLayers(
            vulkanSupported: true,
            gpuNum: 870,
            recommendedLayers: 40,
            fileBytes: 4 * gb,
            kvBytes: 200 * 1024 * 1024,
            availBytes: 1 * gb,
          ),
          40);
    });

    test('tight mid-range GPU stays on CPU', () {
      expect(
          GgufEngine.resolveAutoGpuLayers(
            vulkanSupported: true,
            gpuNum: 610,
            recommendedLayers: 20,
            fileBytes: 4 * gb,
            kvBytes: 200 * 1024 * 1024,
            availBytes: 1 * gb,
          ),
          0);
    });

    test('unknown RAM or size falls back to tier heuristic', () {
      expect(
          GgufEngine.resolveAutoGpuLayers(
            vulkanSupported: true,
            gpuNum: 750,
            recommendedLayers: 30,
            fileBytes: 0,
            kvBytes: 0,
            availBytes: 0,
          ),
          30);
    });
  });

  group('resolveBatchThreads', () {
    test('tiers batch threads to free RAM', () {
      expect(GgufEngine.resolveBatchThreads(1.0), 1);
      expect(GgufEngine.resolveBatchThreads(1.49), 1);
      expect(GgufEngine.resolveBatchThreads(1.5), 2);
      expect(GgufEngine.resolveBatchThreads(2.1), 2);
      expect(GgufEngine.resolveBatchThreads(2.5), -1);
      expect(GgufEngine.resolveBatchThreads(8.0), -1);
      expect(GgufEngine.resolveBatchThreads(0), -1);
    });
  });

  group('resolveBatchSize', () {
    test('scales the prompt-parallel batch to free RAM', () {
      expect(GgufEngine.resolveBatchSize(1.5), 128);
      expect(GgufEngine.resolveBatchSize(1.99), 128);
      expect(GgufEngine.resolveBatchSize(2.0), 128);
      expect(GgufEngine.resolveBatchSize(2.4), 128);
      expect(GgufEngine.resolveBatchSize(2.5), 256);
      expect(GgufEngine.resolveBatchSize(2.9), 256);
      expect(GgufEngine.resolveBatchSize(3.0), 512);
      expect(GgufEngine.resolveBatchSize(8.0), 512);
      // Unknown RAM keeps the historic default.
      expect(GgufEngine.resolveBatchSize(0), 512);
      expect(GgufEngine.resolveBatchSize(-1), 512);
    });
  });
}
