import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/sandbox/apk_installer_service.dart';

void main() {
  group('ApkInstallerService (hermetic)', () {
    test('missing file errors without a channel call', () async {
      final svc = ApkInstallerService();
      final err = await svc.installApkFile('/no/such/app.apk');
      expect(err, contains('not found'));
    });

    test('non-apk files are rejected', () async {
      final tmp = await Directory.systemTemp.createTemp('clm_apk_');
      try {
        final zip = File('${tmp.path}/app.zip');
        await zip.writeAsString('not an apk');
        final err =
            await ApkInstallerService().installApkFile(zip.path);
        expect(err, contains('Not an APK'));
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('no picked path reports cancellation', () async {
      expect(
          await ApkInstallerService().installPickedPath(null),
          'No file picked.');
      expect(await ApkInstallerService().installPickedPath(''), 'No file picked.');
    });

    test('desktop hosts explain Android-only install', () async {
      if (Platform.isAndroid) return; // real path needs a device
      final tmp = await Directory.systemTemp.createTemp('clm_apk_');
      try {
        final apk = File('${tmp.path}/app.apk');
        await apk.writeAsBytes([0, 1, 2, 3]);
        final err = await ApkInstallerService().installApkFile(apk.path);
        expect(err, contains('Android'));
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
