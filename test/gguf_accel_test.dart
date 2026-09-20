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
}
