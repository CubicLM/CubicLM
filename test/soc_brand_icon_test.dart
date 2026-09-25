import 'package:cubiclm/services/soc_family.dart';
import 'package:cubiclm/widgets/soc_brand_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocBrandIcon.assetFor', () {
    test('known families map to bundled vendor logos', () {
      expect(SocBrandIcon.assetFor(SocFamily.snapdragon),
          'assets/device_soc/snapdragon.png');
      expect(SocBrandIcon.assetFor(SocFamily.googleTensor),
          'assets/device_soc/tensor.png');
      expect(SocBrandIcon.assetFor(SocFamily.mediatek),
          'assets/device_soc/mediatek.png');
      expect(SocBrandIcon.assetFor(SocFamily.hisilicon),
          'assets/device_soc/Kirin.png');
      expect(SocBrandIcon.assetFor(SocFamily.exynos),
          'assets/device_soc/Exynos.png');
    });

    test('desktop vendors map to their logos', () {
      expect(SocBrandIcon.assetFor(SocFamily.amd),
          'assets/device_soc/amd-color.png');
      expect(SocBrandIcon.assetFor(SocFamily.intel),
          'assets/device_soc/intel.png');
    });

    test('families without a logo fall back to the CPU icon', () {
      expect(SocBrandIcon.assetFor(SocFamily.apple), isNull);
      expect(SocBrandIcon.assetFor(SocFamily.unisoc), isNull);
      expect(SocBrandIcon.assetFor(SocFamily.rockchip), isNull);
      expect(SocBrandIcon.assetFor(SocFamily.unknown), isNull);
    });
  });
}
