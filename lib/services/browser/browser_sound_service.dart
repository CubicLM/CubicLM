import 'package:flutter/foundation.dart' show debugPrint;
import 'package:audioplayers/audioplayers.dart';
import 'package:get/get.dart';
import '../../controllers/settings_controller.dart';

class BrowserSoundService extends GetxService {
  final AudioPlayer _ambientPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  
  // Example public Lo-Fi stream or asset path
  static const String lofiUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

  @override
  void onInit() {
    super.onInit();
    _ambientPlayer.setReleaseMode(ReleaseMode.loop);
    
    // Listen to settings changes
    final settings = Get.find<SettingsController>();
    ever(settings.browserAmbientMusicEnabled, (enabled) {
      if (enabled) {
        _startAmbient();
      } else {
        _stopAmbient();
      }
    });
  }

  Future<void> _startAmbient() async {
    try {
      await _ambientPlayer.play(UrlSource(lofiUrl));
      await _ambientPlayer.setVolume(0.1); // Keep it very low
    } catch (e) {
      debugPrint('[BrowserSoundService] Could not play ambient music: $e');
    }
  }

  Future<void> _stopAmbient() async {
    await _ambientPlayer.stop();
  }

  Future<void> playClick() async {
    if (!Get.find<SettingsController>().browserHapticsEnabled.value) return;
    // We would play a short asset here. For now, we'll skip SFX without assets
    // but the structure is ready.
  }

  @override
  void onClose() {
    _ambientPlayer.dispose();
    _sfxPlayer.dispose();
    super.onClose();
  }
}
