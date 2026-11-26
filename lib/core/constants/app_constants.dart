class AppConstants {
  static const String appNameFa = 'Sinkit';
  static const String appNameEn = 'Sinkit';
  static const String appPackageId = 'ir.bestdroid.karen';
  static const String appVersion = '2.2.0';

  // Non-sensitive UI preferences (SharedPreferences)
  static const String prefsKeySettings = 'karen_app_settings_v2';
  static const String prefsKeyActiveDeviceId = 'karen_active_device_id_v2';

  // Legacy plaintext keys (migrated into encrypted storage and deleted)
  static const String legacyPrefsKeyDevices = 'karen_devices_v2';
  static const String legacyPrefsKeyLogs = 'karen_command_logs_v2';
  static const String legacyPrefsKeyTemplates = 'karen_protocol_templates_v2';

  // Sensitive data keys (FlutterSecureStorage / Android Keystore)
  static const String secureKeyDevices = 'karen_sec_devices_v2';
  static const String secureKeyLogs = 'karen_sec_command_logs_v2';
  static const String secureKeyTemplates = 'karen_sec_protocol_templates_v2';
  static const String secureKeyAppPinHash = 'karen_sec_pin_hash_v2';
  static const String secureKeyPinSecurityState = 'karen_sec_pin_lockout_v2_1';
  static const String secureKeyPinJournal = 'karen_sec_pin_journal_v2_2';

  static const List<String> allSensitiveSecureKeys = [
    secureKeyDevices,
    secureKeyLogs,
    secureKeyTemplates,
    secureKeyPinJournal,
    secureKeyAppPinHash,
    secureKeyPinSecurityState,
  ];

  static const List<String> allLegacyPlaintextKeys = [
    legacyPrefsKeyDevices,
    legacyPrefsKeyLogs,
    legacyPrefsKeyTemplates,
  ];

  static const int maxPinFailedAttempts = 5;
  static const Duration pinLockoutDuration = Duration(seconds: 30);

  static const List<String> persianWeekDays = [
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنج‌شنبه',
    'جمعه',
  ];
}
