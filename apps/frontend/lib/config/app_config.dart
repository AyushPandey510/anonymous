import 'package:flutter/foundation.dart';

/// Central network and environment configuration.
class AppConfig {
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');
  static const bool usePhysicalDevice = bool.fromEnvironment(
    'USE_PHYSICAL_DEVICE',
  );
  static const bool useProduction = bool.fromEnvironment('USE_PRODUCTION');

  static const String apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String physicalDeviceUrl = String.fromEnvironment(
    'PHYSICAL_DEVICE_API_BASE_URL',
  );
  static const String productionUrl = String.fromEnvironment(
    'PRODUCTION_API_BASE_URL',
  );

  static const String emulatorUrl = 'http://10.0.2.2';

  static String get apiBaseUrl {
    if (apiBaseUrlOverride.isNotEmpty) {
      return apiBaseUrlOverride;
    }

    if (useProduction && productionUrl.isNotEmpty) {
      return productionUrl;
    }

    if (usePhysicalDevice && physicalDeviceUrl.isNotEmpty) {
      return physicalDeviceUrl;
    }

    if (useEmulator ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
      return emulatorUrl;
    }

    return 'http://localhost';
  }
}
