import 'package:flutter/foundation.dart';

/// Central Network & Environment Configuration
///
/// Simply set ONE of the three variables below to `true` and the others to `false`.
class AppConfig {
  // ===========================================================================
  // 🔘 TOGGLE ENVIRONMENT HERE (Set ONE to true, others to false)
  // ===========================================================================

  /// 🟢 Set to `true` when running on Android EMULATOR
  static const bool useEmulator = true;

  /// 🟢 Set to `true` when running on PHYSICAL PHONE
  static const bool usePhysicalDevice = false;

  /// 🟢 Set to `true` when building PRODUCTION RELEASE APK
  static const bool useProduction = false;

  // ===========================================================================
  // 🌐 SERVER ADDRESSES
  // ===========================================================================

  /// 1. Android Emulator address (10.0.2.2 connects from Android emulator to PC host nginx)
  static const String emulatorUrl = 'http://10.0.2.2';

  /// 2. Physical Device address (Your PC's Wi-Fi IP from ipconfig, served by nginx)
  static const String physicalDeviceUrl = 'http://192.168.1.7';

  /// 3. Production Live Backend address (HTTPS domain)
  static const String productionUrl = 'https://api.yourdomain.com';

  // ===========================================================================
  // 🚀 ACTIVE URL RESOLVER (Automatically uses the active variable above)
  // ===========================================================================

  static String get apiBaseUrl {
    // 1. Allows CLI override if passed via --dart-define=API_BASE_URL=...
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // 2. Production mode
    if (useProduction) {
      return productionUrl;
    }

    // 3. Physical phone mode
    if (usePhysicalDevice) {
      return physicalDeviceUrl;
    }

    // 4. Emulator / Localhost mode (nginx in front of backend)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return emulatorUrl;
    }
    return 'http://localhost';
  }
}
