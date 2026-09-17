import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:get/get.dart';

class QrScannerView extends StatelessWidget {
  const QrScannerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: MobileScanner(
        controller: MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        ),
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final code = barcode.rawValue ?? '';
            if (code.isNotEmpty) {
              Get.back(result: code);
              break;
            }
          }
        },
      ),
    );
  }
}
