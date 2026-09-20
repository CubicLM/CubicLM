/// Fonts, themes, lock/PIN, cache, export, reset, dev tools, info.
///
/// Split from `settings_controller.dart` - behavior is unchanged.
/// Contains: setFontScale(), setLocale(), setTheme(), setDynamicColorEnabled(), setGlassIntensity()
///   setFontFamily(), setOrbAnim(), setAutoLoadLastModel(), resetOnboarding(), setReadAloudEnabled()
///   setCodeEditorType(), _detectBiometrics(), setAppLockEnabled(), _setSecureFlag(), authenticate()
///   setLockTimeoutMinutes(), setLockBiometricOnly(), setThemeMode(), _updateSystemUI()
part of 'settings_controller.dart';

extension SettingsControllerAppearance on SettingsController {
  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.8, 1.4);
    fontScale.value = clamped;
    await _hive.setSetting(AppConstants.keyFontScale, clamped);
  }

  Future<void> setLocale(AppLanguage lang) async {
    locale.value = lang;
    await _hive.setSetting(AppConstants.keyLanguage, lang.code);
    Get.updateLocale(lang.locale);
  }

  // ── Personalization ──

  Future<void> setTheme(String name, Color? color) async {
    selectedThemeName.value = name;
    customAccentColor.value = color;
    await _hive.setSetting(AppConstants.keySelectedTheme, name);
    if (color != null) {
      await _hive.setSetting(AppConstants.keyCustomAccentColor, color.toARGB32());
    } else {
      await _hive.deleteSetting(AppConstants.keyCustomAccentColor);
    }
    // Automatically turn off Dynamic Color if a manual theme is picked
    if (name != 'Material You') {
      await setDynamicColorEnabled(false);
    }
    _updateSystemUI();
  }

  Future<void> setDynamicColorEnabled(bool enabled) async {
    dynamicColorEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyDynamicColorEnabled, enabled);
    if (enabled) {
      selectedThemeName.value = 'Material You';
      await _hive.setSetting(AppConstants.keySelectedTheme, 'Material You');
    }
  }

  Future<void> setGlassIntensity(double value) async {
    glassIntensity.value = value;
    await _hive.setSetting(AppConstants.keyGlassIntensity, value);
  }

  Future<void> setFontFamily(String family) async {
    selectedFontFamily.value = family;
    await _hive.setSetting(AppConstants.keySelectedFont, family);
  }

  /// Persist a thinking-orb animation choice ('random' | OrbState name).
  Future<void> setOrbAnim(String slot, String value) async {
    switch (slot) {
      case 'chat':
        orbChatAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbChat, value);
        break;
      case 'image':
        orbImageAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbImage, value);
        break;
      case 'analysis':
        orbAnalysisAnim.value = value;
        await _hive.setSetting(AppConstants.keyOrbAnalysis, value);
        break;
    }
  }

  Future<void> setAutoLoadLastModel(bool enabled) async {
    autoLoadLastModel.value = enabled;
    await _hive.setSetting(AppConstants.keyAutoLoadLastModel, enabled);
  }

  /// Clears the onboarding-done flag so the setup flow can be replayed
  /// from App Settings (navigated by the caller).
  Future<void> resetOnboarding() async {
    await _hive.setSetting(AppConstants.keyOnboardingDone, false);
  }

  Future<void> setReadAloudEnabled(bool enabled) async {
    readAloudEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyReadAloud, enabled);
  }

  Future<void> setCodeEditorType(String type) async {
    codeEditorType.value = type;
    await _hive.setSetting('code_editor_type', type);
  }

  // ─── App Lock (biometric gate) ──────────────────


  Future<void> _detectBiometrics() async {
    if (kIsWeb) {
      biometricsAvailable.value = false;
      hasEnrolledBiometrics.value = false;
      if (!_biometricsDetected.isCompleted) _biometricsDetected.complete();
      return;
    }
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      biometricsAvailable.value = canCheck || supported;
      // Enrollment matters: isDeviceSupported() is true on Windows as soon
      // as the OS supports Hello — even with zero methods enrolled.
      try {
        hasEnrolledBiometrics.value =
            (await _localAuth.getAvailableBiometrics()).isNotEmpty;
      } catch (_) {
        hasEnrolledBiometrics.value = false;
      }
    } catch (_) {
      biometricsAvailable.value = false;
      hasEnrolledBiometrics.value = false;
    } finally {
      if (!_biometricsDetected.isCompleted) _biometricsDetected.complete();
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    if (enabled) {
      // Require a successful authentication before arming the lock so the
      // user can't lock themselves out on a device without enrolled biometrics.
      final ok = await authenticate(
          reason: 'Confirm your identity to enable App Lock');
      if (!ok) {
        appLockEnabled.value = false;
        await _hive.setSetting(AppConstants.keyAppLockEnabled, false);
        return;
      }
    }
    appLockEnabled.value = enabled;
    await _hive.setSetting(AppConstants.keyAppLockEnabled, enabled);
    if (!enabled) isLocked.value = false;
    // Recents/screenshot blackout follows the lock (Android only).
    await _setSecureFlag(enabled);
  }

  /// Toggles FLAG_SECURE so locked content never appears in the task
  /// switcher or screenshots. No-op off Android; never throws.
  Future<void> _setSecureFlag(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await const MethodChannel('com.cubiclm.app/model_import')
          .invokeMethod('setSecureFlag', {'enabled': enabled});
    } catch (_) {}
  }

  /// Runs the platform biometric/PIN prompt. Fails open (returns true) when
  /// no biometric hardware is available so the app never becomes unusable.
  Future<bool> authenticate({String reason = 'Unlock CubicLM'}) async {
    if (kIsWeb || !biometricsAvailable.value) return true;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: la.AuthenticationOptions(
          biometricOnly: lockBiometricOnly.value,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }


  Future<void> setLockTimeoutMinutes(int minutes) async {
    lockTimeoutMinutes.value = minutes;
    await _hive.setSetting(AppConstants.keyLockTimeoutMinutes, minutes);
  }

  Future<void> setLockBiometricOnly(bool value) async {
    lockBiometricOnly.value = value;
    await _hive.setSetting(AppConstants.keyLockBiometricOnly, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _hive.setSetting('theme_mode', mode.name);
    Get.changeThemeMode(mode);
    _updateSystemUI();
  }

  void _updateSystemUI() {
    final isDark = themeMode.value == ThemeMode.dark ||
        (themeMode.value == ThemeMode.system &&
            Get.mediaQuery.platformBrightness == Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? Colors.black : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

}
