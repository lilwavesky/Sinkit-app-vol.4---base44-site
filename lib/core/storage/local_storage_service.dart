import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../models/karen_models.dart';
import '../security/pin_hasher.dart';
import '../transport/protocol_templates.dart';

class SecureStorageFailure implements Exception {
  final String message;
  final Object? cause;

  const SecureStorageFailure(this.message, [this.cause]);

  @override
  String toString() => 'SecureStorageFailure: $message';
}

class PreferencesStorageFailure implements Exception {
  final String message;
  final Object? cause;

  const PreferencesStorageFailure(this.message, [this.cause]);

  @override
  String toString() => 'PreferencesStorageFailure: $message';
}

enum StorageLoadStatus {
  /// Key either absent (genuinely empty store) or successfully decrypted & parsed.
  loaded,

  /// Encrypted keystore / secure storage threw an error when reading.
  readError,

  /// Stored payload was readable but corrupted / failed JSON schema validation.
  corruptedData,
}

class EmergencyWipeResult {
  final bool success;
  final List<String> failedKeys;
  final String messageFa;

  const EmergencyWipeResult({
    required this.success,
    this.failedKeys = const [],
    required this.messageFa,
  });
}

/// Abstract key-value secure store so production uses Android Keystore-backed
/// [FlutterSecureStorage] while tests can inject deterministic in-memory or
/// failing/no-op stores.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureKeyValueStore(this._storage);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Abstract preferences store so production uses [SharedPreferences] while
/// tests can inject failing or silent no-op preference writes.
abstract class PreferencesKeyValueStore {
  String? getString(String key);
  bool containsKey(String key);
  Future<bool> setString(String key, String value);
  Future<bool> remove(String key);
}

class FlutterSharedPreferencesStore implements PreferencesKeyValueStore {
  final SharedPreferences _prefs;

  const FlutterSharedPreferencesStore(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}

class LoadedAppData {
  final List<KarenDevice> devices;
  final String? activeDeviceId;
  final List<CommandLogEntry> logs;
  final AppSettings settings;
  final ProtocolTemplates templates;
  final PinSecurityState pinSecurityState;
  final bool pinSettingsCorrupted;
  final bool pinHashPresent;
  final bool pinJournalRecoveryFailed;
  final bool interruptedTransactionRecovered;

  final StorageLoadStatus devicesStatus;
  final StorageLoadStatus logsStatus;
  final StorageLoadStatus templatesStatus;
  final StorageLoadStatus pinSecurityStatus;
  final StorageLoadStatus pinJournalStatus;

  const LoadedAppData({
    required this.devices,
    required this.activeDeviceId,
    required this.logs,
    required this.settings,
    required this.templates,
    this.pinSecurityState = const PinSecurityState(),
    this.pinSettingsCorrupted = false,
    this.pinHashPresent = false,
    this.pinJournalRecoveryFailed = false,
    this.interruptedTransactionRecovered = false,
    this.devicesStatus = StorageLoadStatus.loaded,
    this.logsStatus = StorageLoadStatus.loaded,
    this.templatesStatus = StorageLoadStatus.loaded,
    this.pinSecurityStatus = StorageLoadStatus.loaded,
    this.pinJournalStatus = StorageLoadStatus.loaded,
  });

  bool get hasDevicesError => devicesStatus != StorageLoadStatus.loaded;
  bool get hasLogsError => logsStatus != StorageLoadStatus.loaded;
  bool get hasTemplatesError => templatesStatus != StorageLoadStatus.loaded;
  bool get hasPinSecurityError =>
      pinSecurityStatus != StorageLoadStatus.loaded ||
      pinJournalStatus != StorageLoadStatus.loaded ||
      pinJournalRecoveryFailed;

  bool get hasAnyStorageError =>
      hasDevicesError ||
      hasLogsError ||
      hasTemplatesError ||
      hasPinSecurityError ||
      pinSettingsCorrupted;

  bool get hasAnyReadError =>
      devicesStatus == StorageLoadStatus.readError ||
      logsStatus == StorageLoadStatus.readError ||
      templatesStatus == StorageLoadStatus.readError ||
      pinSecurityStatus == StorageLoadStatus.readError ||
      pinJournalStatus == StorageLoadStatus.readError;

  bool get hasAnyCorruption =>
      devicesStatus == StorageLoadStatus.corruptedData ||
      logsStatus == StorageLoadStatus.corruptedData ||
      templatesStatus == StorageLoadStatus.corruptedData ||
      pinSecurityStatus == StorageLoadStatus.corruptedData ||
      pinJournalStatus == StorageLoadStatus.corruptedData ||
      pinSettingsCorrupted;

  List<String> get affectedStoreKeys => [
        if (hasDevicesError) AppConstants.secureKeyDevices,
        if (hasLogsError) AppConstants.secureKeyLogs,
        if (hasTemplatesError) AppConstants.secureKeyTemplates,
        if (pinSecurityStatus != StorageLoadStatus.loaded)
          AppConstants.secureKeyPinSecurityState,
        if (pinJournalStatus != StorageLoadStatus.loaded)
          AppConstants.secureKeyPinJournal,
      ];
}

/// Splits storage strictly by sensitivity:
/// - Non-sensitive UI prefs (`themeMode`, `transportMode`, `confirmPowerActions`,
///   `pinLockEnabled`, `activeDeviceId`) -> [PreferencesKeyValueStore]
/// - Sensitive data (device SIM numbers, locations, authorized user phone numbers,
///   SMS command logs/replies, protocol templates, PBKDF2 PIN hash, brute-force
///   lockout state, and persistent PIN recovery journal) -> [SecureKeyValueStore]
class LocalStorageService {
  final PreferencesKeyValueStore _prefsStore;
  final SecureKeyValueStore _secureStore;

  LocalStorageService(
    SharedPreferences prefs,
    SecureKeyValueStore secureStore,
  )   : _prefsStore = FlutterSharedPreferencesStore(prefs),
        _secureStore = secureStore;

  LocalStorageService.withStores(
    PreferencesKeyValueStore prefsStore,
    SecureKeyValueStore secureStore,
  )   : _prefsStore = prefsStore,
        _secureStore = secureStore;

  factory LocalStorageService.withFlutterSecureStorage(
    SharedPreferences prefs,
    FlutterSecureStorage secureStorage,
  ) {
    return LocalStorageService(
      prefs,
      FlutterSecureKeyValueStore(secureStorage),
    );
  }

  /// Loads all persisted state, runs automatic Fail-Closed startup recovery for
  /// any interrupted PIN transaction journal, and cleanly separates empty DBs
  /// from keystore read errors and corrupted payloads.
  Future<LoadedAppData> loadAll() async {
    await _migrateLegacyPlaintextIfPresent();

    // 0. Check & reconcile any persisted PIN recovery journal BEFORE reading
    //    final PIN settings / hash / security state.
    var pinJournalStatus = StorageLoadStatus.loaded;
    var pinJournalRecoveryFailed = false;
    var interruptedTransactionRecovered = false;

    PinTransactionJournal? pendingJournal;
    try {
      final rawJournal =
          await _secureStore.read(AppConstants.secureKeyPinJournal);
      if (rawJournal != null && rawJournal.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJournal);
          if (decoded is! Map<String, dynamic>) {
            pinJournalStatus = StorageLoadStatus.corruptedData;
          } else {
            pendingJournal = PinTransactionJournal.fromJson(decoded);
          }
        } catch (_) {
          pinJournalStatus = StorageLoadStatus.corruptedData;
        }
      }
    } catch (_) {
      pinJournalStatus = StorageLoadStatus.readError;
    }

    if (pendingJournal != null) {
      final recovered = await _recoverFromPersistedJournal(pendingJournal);
      if (recovered) {
        interruptedTransactionRecovered = true;
      } else {
        pinJournalRecoveryFailed = true;
      }
    }

    final settings = loadSettings();
    var pinSettingsCorrupted = _hasCorruptedStoredSettings();
    final activeDeviceId = loadActiveDeviceId();

    // 1. Devices
    List<KarenDevice> devices = [];
    var devicesStatus = StorageLoadStatus.loaded;
    try {
      final raw = await _secureStore.read(AppConstants.secureKeyDevices);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List<dynamic>) {
            devicesStatus = StorageLoadStatus.corruptedData;
          } else {
            devices = decoded
                .map((e) => KarenDevice.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } catch (_) {
          devicesStatus = StorageLoadStatus.corruptedData;
        }
      }
    } catch (_) {
      devicesStatus = StorageLoadStatus.readError;
    }

    // 2. Command Logs
    List<CommandLogEntry> logs = [];
    var logsStatus = StorageLoadStatus.loaded;
    try {
      final raw = await _secureStore.read(AppConstants.secureKeyLogs);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List<dynamic>) {
            logsStatus = StorageLoadStatus.corruptedData;
          } else {
            logs = decoded
                .map((e) => CommandLogEntry.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } catch (_) {
          logsStatus = StorageLoadStatus.corruptedData;
        }
      }
    } catch (_) {
      logsStatus = StorageLoadStatus.readError;
    }

    // 3. Protocol Templates
    ProtocolTemplates templates = ProtocolTemplates.unverifiedDefaults();
    var templatesStatus = StorageLoadStatus.loaded;
    try {
      final raw = await _secureStore.read(AppConstants.secureKeyTemplates);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            templatesStatus = StorageLoadStatus.corruptedData;
          } else {
            templates = ProtocolTemplates.fromJson(decoded);
          }
        } catch (_) {
          templatesStatus = StorageLoadStatus.corruptedData;
        }
      }
    } catch (_) {
      templatesStatus = StorageLoadStatus.readError;
    }

    // 4. Persisted PIN Brute-Force Security State
    var pinSecurityState = const PinSecurityState();
    var pinSecurityStatus = StorageLoadStatus.loaded;
    try {
      final raw =
          await _secureStore.read(AppConstants.secureKeyPinSecurityState);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            pinSecurityStatus = StorageLoadStatus.corruptedData;
          } else {
            pinSecurityState = PinSecurityState.fromJson(decoded);
          }
        } catch (_) {
          pinSecurityStatus = StorageLoadStatus.corruptedData;
        }
      }
    } catch (_) {
      pinSecurityStatus = StorageLoadStatus.readError;
    }

    // 5. Read PIN hash during bootstrap to detect missing-hash or
    //    deleted-settings bypass attempts on upgraded V2.1.1/V2.1.2 installs.
    var pinHashPresent = false;
    try {
      final hash = await _secureStore.read(AppConstants.secureKeyAppPinHash);
      pinHashPresent = hash != null && hash.isNotEmpty;
    } catch (_) {
      if (pinSecurityStatus == StorageLoadStatus.loaded) {
        pinSecurityStatus = StorageLoadStatus.readError;
      }
    }
    if (pinHashPresent &&
        !_prefsStore.containsKey(AppConstants.prefsKeySettings)) {
      pinSettingsCorrupted = true;
    }

    return LoadedAppData(
      devices: devices,
      activeDeviceId: activeDeviceId,
      logs: logs,
      settings: settings,
      templates: templates,
      pinSecurityState: pinSecurityState,
      pinSettingsCorrupted: pinSettingsCorrupted,
      pinHashPresent: pinHashPresent,
      pinJournalRecoveryFailed: pinJournalRecoveryFailed,
      interruptedTransactionRecovered: interruptedTransactionRecovered,
      devicesStatus: devicesStatus,
      logsStatus: logsStatus,
      templatesStatus: templatesStatus,
      pinSecurityStatus: pinSecurityStatus,
      pinJournalStatus: pinJournalStatus,
    );
  }

  /// Reconciles a persisted [PinTransactionJournal] found during startup:
  /// - If `committed == true`, verifies the committed target state is intact
  ///   on disk and deletes the journal (Fail-Closed if inconsistent).
  /// - If `committed == false`, deterministically restores the complete prior
  ///   valid security snapshot (`previousHash`, `previousPinLockEnabled`,
  ///   `previousFailedAttempts`, `previousLockoutUntilUtc`), verifies read-back
  ///   of every component, and deletes the journal ONLY after full verification.
  Future<bool> _recoverFromPersistedJournal(
    PinTransactionJournal journal,
  ) async {
    // If a prior runtime rollback already failed, NEVER auto-clear recovery;
    // keep the application strictly locked until explicit emergency wipe.
    if (journal.rollbackFailed) {
      return false;
    }

    final baseSettings = loadSettings();

    if (journal.committed) {
      final targetSettings = baseSettings.copyWith(
        pinLockEnabled: journal.targetPinLockEnabled,
      );
      if (!await storedPinHashEquals(journal.targetHash)) return false;

      if (!settingsMatch(targetSettings)) {
        try {
          await saveSettings(targetSettings);
        } on PreferencesStorageFailure {
          // Verify below in case write succeeded before reporting failure.
        }
        if (!settingsMatch(targetSettings)) return false;
      }

      try {
        final actualSec = await loadPinSecurityState();
        if (actualSec != journal.targetSecurityState) {
          await savePinSecurityState(journal.targetSecurityState);
        }
      } on SecureStorageFailure {
        try {
          if (await loadPinSecurityState() != journal.targetSecurityState) {
            return false;
          }
        } on SecureStorageFailure {
          return false;
        }
      }

      try {
        await deletePinTransactionJournal();
        return true;
      } on SecureStorageFailure {
        return false;
      }
    }

    // Uncommitted journal -> restore complete previous valid state.
    final priorSettings = baseSettings.copyWith(
      pinLockEnabled: journal.previousPinLockEnabled,
    );
    final priorSecurity = journal.previousSecurityState;

    // 1. Restore previous PIN hash and verify read-back.
    try {
      await writeAppPinHash(journal.previousHash);
    } on SecureStorageFailure {
      // Never assume write didn't happen; verify actual stored hash below.
    }
    if (!await storedPinHashEquals(journal.previousHash)) {
      return false;
    }

    // 2. Restore previous settings and verify exact match.
    try {
      await saveSettings(priorSettings);
    } on PreferencesStorageFailure {
      // Verify actual stored settings below.
    }
    if (!settingsMatch(priorSettings)) {
      return false;
    }

    // 3. Restore previous failed-attempt & lockout security state and verify read-back.
    try {
      await savePinSecurityState(priorSecurity);
    } on SecureStorageFailure {
      // Verify actual stored security state below.
    }
    try {
      if (await loadPinSecurityState() != priorSecurity) {
        return false;
      }
    } on SecureStorageFailure {
      return false;
    }

    // 4. Remove journal ONLY after every restored field is verified.
    try {
      await deletePinTransactionJournal();
      return true;
    } on SecureStorageFailure {
      return false;
    }
  }

  Future<bool> storedPinHashEquals(String? expectedHash) async {
    try {
      final actual = await readAppPinHash();
      if (expectedHash == null || expectedHash.isEmpty) {
        return actual == null || actual.isEmpty;
      }
      return actual == expectedHash;
    } on SecureStorageFailure {
      return false;
    }
  }

  Future<PinTransactionJournal?> loadPinTransactionJournal() async {
    try {
      final raw = await _secureStore.read(AppConstants.secureKeyPinJournal);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const SecureStorageFailure(
          'ساختار ژورنال بازیابی امنیتی نامعتبر است.',
        );
      }
      return PinTransactionJournal.fromJson(decoded);
    } on SecureStorageFailure {
      rethrow;
    } catch (e) {
      throw SecureStorageFailure(
        'خواندن ژورنال بازیابی تراکنش امنیتی ناموفق بود.',
        e,
      );
    }
  }

  Future<void> savePinTransactionJournal(PinTransactionJournal journal) async {
    final encoded = jsonEncode(journal.toJson());
    try {
      await _secureStore.write(AppConstants.secureKeyPinJournal, encoded);
      final readBack = await loadPinTransactionJournal();
      if (readBack == null || readBack != journal) {
        throw const SecureStorageFailure(
          'بازخوانی تاییدی ژورنال بازیابی با داده ذخیره‌شده مطابقت ندارد.',
        );
      }
    } on SecureStorageFailure {
      rethrow;
    } catch (e) {
      throw SecureStorageFailure(
        'ذخیره و تایید ژورنال بازیابی تراکنش امنیتی ناموفق بود.',
        e,
      );
    }
  }

  Future<void> deletePinTransactionJournal() async {
    try {
      await _secureStore.delete(AppConstants.secureKeyPinJournal);
      final residual =
          await _secureStore.read(AppConstants.secureKeyPinJournal);
      if (residual != null && residual.isNotEmpty) {
        throw const SecureStorageFailure(
          'حذف ژورنال بازیابی تراکنش امنیتی تایید نشد.',
        );
      }
    } on SecureStorageFailure {
      rethrow;
    } catch (e) {
      throw SecureStorageFailure(
        'پاکسازی ژورنال بازیابی تراکنش امنیتی ناموفق بود.',
        e,
      );
    }
  }

  Future<void> _migrateLegacyPlaintextIfPresent() async {
    final migrations = <(String legacyKey, String secureKey)>[
      (AppConstants.legacyPrefsKeyDevices, AppConstants.secureKeyDevices),
      (AppConstants.legacyPrefsKeyLogs, AppConstants.secureKeyLogs),
      (AppConstants.legacyPrefsKeyTemplates, AppConstants.secureKeyTemplates),
    ];

    for (final (legacyKey, secureKey) in migrations) {
      final legacyRaw = _prefsStore.getString(legacyKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        try {
          final existingSecure = await _secureStore.read(secureKey);
          if (existingSecure == null || existingSecure.isEmpty) {
            await _secureStore.write(secureKey, legacyRaw);
            final verified = await _secureStore.read(secureKey);
            if (verified != legacyRaw) {
              continue;
            }
          }
          await _prefsStore.remove(legacyKey);
        } catch (_) {
          // Preserve legacy key until encrypted migration succeeds.
        }
      }
    }
  }

  Future<void> saveDevices(List<KarenDevice> devices) async {
    final encoded = jsonEncode(devices.map((e) => e.toJson()).toList());
    try {
      await _secureStore.write(AppConstants.secureKeyDevices, encoded);
    } catch (e) {
      throw SecureStorageFailure(
        'ذخیره امن اطلاعات دستگاه‌ها با خطا مواجه شد.',
        e,
      );
    }
  }

  String? loadActiveDeviceId() {
    return _prefsStore.getString(AppConstants.prefsKeyActiveDeviceId);
  }

  Future<void> saveActiveDeviceId(String? id) async {
    if (id == null) {
      final ok = await _prefsStore.remove(AppConstants.prefsKeyActiveDeviceId);
      if (!ok && _prefsStore.containsKey(AppConstants.prefsKeyActiveDeviceId)) {
        throw const PreferencesStorageFailure(
          'حذف شناسه دستگاه فعال تایید نشد.',
        );
      }
    } else {
      final ok = await _prefsStore.setString(
        AppConstants.prefsKeyActiveDeviceId,
        id,
      );
      if (!ok ||
          _prefsStore.getString(AppConstants.prefsKeyActiveDeviceId) != id) {
        throw const PreferencesStorageFailure(
          'ذخیره شناسه دستگاه فعال تایید نشد.',
        );
      }
    }
  }

  Future<void> saveLogs(List<CommandLogEntry> logs) async {
    final trimmed = logs.take(150).toList();
    final encoded = jsonEncode(trimmed.map((e) => e.toJson()).toList());
    try {
      await _secureStore.write(AppConstants.secureKeyLogs, encoded);
    } catch (e) {
      throw SecureStorageFailure(
        'ذخیره امن تاریخچه فرمان‌ها با خطا مواجه شد.',
        e,
      );
    }
  }

  AppSettings loadSettings() {
    final raw = _prefsStore.getString(AppConstants.prefsKeySettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  bool _hasCorruptedStoredSettings() {
    final key = AppConstants.prefsKeySettings;
    if (!_prefsStore.containsKey(key)) return false;
    final raw = _prefsStore.getString(key);
    if (raw == null || raw.isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['pinLockEnabled'] is! bool) {
        return true;
      }
      AppSettings.fromJson(decoded);
      return false;
    } catch (_) {
      return true;
    }
  }

  bool settingsMatch(AppSettings expected) {
    final raw = _prefsStore.getString(AppConstants.prefsKeySettings);
    if (raw == null || raw.isEmpty) {
      return expected.pinLockEnabled == const AppSettings().pinLockEnabled &&
          expected.themeMode == const AppSettings().themeMode &&
          expected.transportMode == const AppSettings().transportMode &&
          expected.confirmPowerActions ==
              const AppSettings().confirmPowerActions;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final actual = AppSettings.fromJson(decoded);
      return actual.pinLockEnabled == expected.pinLockEnabled &&
          actual.themeMode == expected.themeMode &&
          actual.transportMode == expected.transportMode &&
          actual.confirmPowerActions == expected.confirmPowerActions;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final encoded = jsonEncode(settings.toJson());
    bool writeSucceeded;
    try {
      writeSucceeded = await _prefsStore.setString(
        AppConstants.prefsKeySettings,
        encoded,
      );
    } catch (e) {
      throw PreferencesStorageFailure(
        'ذخیره تنظیمات برنامه با خطا مواجه شد.',
        e,
      );
    }

    if (!writeSucceeded) {
      throw const PreferencesStorageFailure(
        'ذخیره تنظیمات در حافظه تنظیمات برنامه تایید نشد.',
      );
    }

    final readRaw = _prefsStore.getString(AppConstants.prefsKeySettings);
    if (readRaw == null || readRaw.isEmpty) {
      throw const PreferencesStorageFailure(
        'بازخوانی تاییدی تنظیمات پس از ذخیره ناموفق بود.',
      );
    }

    try {
      final verified = AppSettings.fromJson(
        jsonDecode(readRaw) as Map<String, dynamic>,
      );
      if (verified.pinLockEnabled != settings.pinLockEnabled ||
          verified.transportMode != settings.transportMode ||
          verified.themeMode != settings.themeMode ||
          verified.confirmPowerActions != settings.confirmPowerActions) {
        throw const PreferencesStorageFailure(
          'تنظیمات ذخیره‌شده با مقدار درخواستی مطابقت ندارد.',
        );
      }
    } catch (e) {
      if (e is PreferencesStorageFailure) rethrow;
      throw PreferencesStorageFailure(
        'تایید ساختار تنظیمات ذخیره‌شده ناموفق بود.',
        e,
      );
    }
  }

  Future<void> saveTemplates(ProtocolTemplates templates) async {
    try {
      await _secureStore.write(
        AppConstants.secureKeyTemplates,
        jsonEncode(templates.toJson()),
      );
    } catch (e) {
      throw SecureStorageFailure(
        'ذخیره امن قالب فرمان‌ها با خطا مواجه شد.',
        e,
      );
    }
  }

  Future<PinSecurityState> loadPinSecurityState() async {
    try {
      final raw =
          await _secureStore.read(AppConstants.secureKeyPinSecurityState);
      if (raw == null || raw.isEmpty) return const PinSecurityState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const SecureStorageFailure('ساختار وضعیت قفل امنیتی نامعتبر است.');
      }
      return PinSecurityState.fromJson(decoded);
    } on SecureStorageFailure {
      rethrow;
    } catch (e) {
      throw SecureStorageFailure(
        'خواندن وضعیت تلاش‌های ناموفق رمز عبور از حافظه امن ناموفق بود.',
        e,
      );
    }
  }

  Future<void> savePinSecurityState(PinSecurityState securityState) async {
    final encoded = jsonEncode(securityState.toJson());
    try {
      await _secureStore.write(
        AppConstants.secureKeyPinSecurityState,
        encoded,
      );
      final readBackRaw =
          await _secureStore.read(AppConstants.secureKeyPinSecurityState);
      if (readBackRaw == null || readBackRaw.isEmpty) {
        throw const SecureStorageFailure(
          'تایید ذخیره وضعیت قفل امنیتی ناموفق بود (مقدار بازخوانی خالی است).',
        );
      }
      final decoded = jsonDecode(readBackRaw);
      if (decoded is! Map<String, dynamic>) {
        throw const SecureStorageFailure(
          'ساختار بازخوانی وضعیت قفل امنیتی نامعتبر است.',
        );
      }
      final verified = PinSecurityState.fromJson(decoded);
      if (verified != securityState) {
        throw const SecureStorageFailure(
          'مقدار بازخوانی وضعیت قفل امنیتی با مقدار ذخیره‌شده مطابقت ندارد.',
        );
      }
    } on SecureStorageFailure {
      rethrow;
    } catch (e) {
      throw SecureStorageFailure(
        'ذخیره و تایید وضعیت قفل امنیتی در حافظه امن ناموفق بود.',
        e,
      );
    }
  }

  Future<String?> readAppPinHash() async {
    try {
      return await _secureStore.read(AppConstants.secureKeyAppPinHash);
    } catch (e) {
      throw SecureStorageFailure(
        'خواندن رمز امنیتی از حافظه امن ناموفق بود.',
        e,
      );
    }
  }

  Future<void> writeAppPinHash(String? hash) async {
    try {
      if (hash == null || hash.isEmpty) {
        await _secureStore.delete(AppConstants.secureKeyAppPinHash);
        final residual =
            await _secureStore.read(AppConstants.secureKeyAppPinHash);
        if (residual != null && residual.isNotEmpty) {
          throw const SecureStorageFailure(
            'حذف رمز قبلی از حافظه امن تایید نشد.',
          );
        }
      } else {
        await _secureStore.write(AppConstants.secureKeyAppPinHash, hash);
        final verified =
            await _secureStore.read(AppConstants.secureKeyAppPinHash);
        if (verified != hash) {
          throw const SecureStorageFailure(
            'تایید نوشتن رمز در حافظه امن ناموفق بود.',
          );
        }
      }
    } catch (e) {
      if (e is SecureStorageFailure) rethrow;
      throw SecureStorageFailure(
        'ذخیره رمز امنیتی در حافظه امن ناموفق بود.',
        e,
      );
    }
  }

  Future<List<String>> deleteAndVerifySecureKeys(List<String> keys) async {
    final failedKeys = <String>[];
    for (final key in keys) {
      var threwOnDelete = false;
      try {
        await _secureStore.delete(key);
      } catch (_) {
        threwOnDelete = true;
      }
      try {
        final remaining = await _secureStore.read(key);
        if (remaining != null && remaining.isNotEmpty) {
          failedKeys.add(key);
        } else if (threwOnDelete) {
          failedKeys.add(key);
        }
      } catch (_) {
        failedKeys.add(key);
      }
    }
    return failedKeys;
  }

  Future<EmergencyWipeResult> wipeAllSensitiveDataAndResetSecurity() async {
    final dataKeys = AppConstants.allSensitiveSecureKeys
        .where((k) => k != AppConstants.secureKeyAppPinHash)
        .toList();

    final failedDataKeys = await deleteAndVerifySecureKeys(dataKeys);
    if (failedDataKeys.isNotEmpty) {
      return EmergencyWipeResult(
        success: false,
        failedKeys: failedDataKeys,
        messageFa:
            'بازنشانی امنیتی متوقف شد: حذف تاییدشده داده‌های حساس در حافظه امن (Android Keystore) ناموفق بود. برای حفظ امنیت، قفل برنامه غیرفعال نمی‌شود.',
      );
    }

    for (final legacyKey in AppConstants.allLegacyPlaintextKeys) {
      try {
        final removed = await _prefsStore.remove(legacyKey);
        if ((!removed && _prefsStore.containsKey(legacyKey)) ||
            _prefsStore.containsKey(legacyKey)) {
          return EmergencyWipeResult(
            success: false,
            failedKeys: [legacyKey],
            messageFa:
                'بازنشانی امنیتی متوقف شد: پاکسازی کامل داده‌های قدیمی تایید نشد و قفل برنامه بسته می‌ماند.',
          );
        }
      } catch (_) {
        return EmergencyWipeResult(
          success: false,
          failedKeys: [legacyKey],
          messageFa:
              'بازنشانی امنیتی متوقف شد: خطا در حذف داده‌های قدیمی رخ داد و قفل برنامه بسته می‌ماند.',
        );
      }
    }

    final failedPinKeys =
        await deleteAndVerifySecureKeys([AppConstants.secureKeyAppPinHash]);
    if (failedPinKeys.isNotEmpty) {
      return EmergencyWipeResult(
        success: false,
        failedKeys: failedPinKeys,
        messageFa:
            'بازنشانی امنیتی متوقف شد: حذف کلید رمز عبور از حافظه امن تایید نشد. قفل برنامه همچنان فعال می‌ماند.',
      );
    }

    try {
      await saveActiveDeviceId(null);
      final current = loadSettings();
      await saveSettings(current.copyWith(pinLockEnabled: false));
    } catch (_) {
      return const EmergencyWipeResult(
        success: false,
        failedKeys: [AppConstants.prefsKeySettings],
        messageFa:
            'بازنشانی امنیتی کامل نشد: ثبت و تایید غیرفعال‌سازی قفل برنامه در تنظیمات ناموفق بود. برنامه همچنان قفل می‌ماند.',
      );
    }

    final persistedSettings = loadSettings();
    if (persistedSettings.pinLockEnabled) {
      return const EmergencyWipeResult(
        success: false,
        failedKeys: [AppConstants.prefsKeySettings],
        messageFa:
            'تایید نهایی غیرفعال‌سازی قفل برنامه در تنظیمات ناموفق بود. قفل امنیتی همچنان فعال می‌ماند.',
      );
    }

    return const EmergencyWipeResult(
      success: true,
      messageFa:
          'تمامی داده‌های حساس به‌صورت تاییدشده حذف شدند و غیرفعال‌سازی قفل برنامه تایید شد.',
    );
  }
}
