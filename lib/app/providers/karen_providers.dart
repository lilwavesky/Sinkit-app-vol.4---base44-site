import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/karen_models.dart';
import '../../core/security/pin_hasher.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/transport/command_transport.dart';
import '../../core/transport/protocol_templates.dart';
import '../../core/utils/persian_utils.dart';

final localStorageProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('localStorageProvider must be overridden in main()');
});

final initialAppDataProvider = Provider<LoadedAppData>((ref) {
  throw UnimplementedError(
    'initialAppDataProvider must be overridden in main()',
  );
});

final demoTransportProvider = Provider<CommandTransport>((ref) {
  return const DemoCommandTransport();
});

final smsTransportProvider = Provider<CommandTransport>((ref) {
  return const SmsComposerCommandTransport();
});

/// Configurable PBKDF2 iteration count so production uses 100,000 iterations
/// while unit tests can override for speed or explicitly test migration/defaults.
final pinHashIterationsProvider = Provider<int>((ref) {
  return PinHasher.defaultIterations;
});

class KarenAppState {
  final List<KarenDevice> devices;
  final String? activeDeviceId;
  final List<CommandLogEntry> logs;
  final AppSettings settings;
  final ProtocolTemplates templates;
  final bool isBusy;
  final bool isUnlocked;
  final bool pinRecoveryRequired;
  final String? pinCleanupWarning;
  final int failedPinAttempts;
  final DateTime? pinLockoutUntil;
  final StorageLoadStatus devicesStorageStatus;
  final StorageLoadStatus logsStorageStatus;
  final StorageLoadStatus templatesStorageStatus;
  final StorageLoadStatus pinSecurityStorageStatus;
  final String? lastError;

  const KarenAppState({
    this.devices = const [],
    this.activeDeviceId,
    this.logs = const [],
    this.settings = const AppSettings(),
    required this.templates,
    this.isBusy = false,
    this.isUnlocked = true,
    this.pinRecoveryRequired = false,
    this.pinCleanupWarning,
    this.failedPinAttempts = 0,
    this.pinLockoutUntil,
    this.devicesStorageStatus = StorageLoadStatus.loaded,
    this.logsStorageStatus = StorageLoadStatus.loaded,
    this.templatesStorageStatus = StorageLoadStatus.loaded,
    this.pinSecurityStorageStatus = StorageLoadStatus.loaded,
    this.lastError,
  });

  KarenDevice? get activeDevice {
    if (devices.isEmpty) return null;
    if (activeDeviceId == null) return devices.first;
    for (final device in devices) {
      if (device.id == activeDeviceId) return device;
    }
    return devices.first;
  }

  bool get requiresUnlock =>
      (settings.pinLockEnabled && !isUnlocked) || pinRecoveryRequired;

  bool get isDevicesWriteProtected =>
      devicesStorageStatus != StorageLoadStatus.loaded;

  bool get isLogsWriteProtected =>
      logsStorageStatus != StorageLoadStatus.loaded;

  bool get isTemplatesWriteProtected =>
      templatesStorageStatus != StorageLoadStatus.loaded;

  bool get hasStorageRecoveryIssue =>
      isDevicesWriteProtected ||
      isLogsWriteProtected ||
      isTemplatesWriteProtected ||
      pinSecurityStorageStatus != StorageLoadStatus.loaded;

  KarenAppState copyWith({
    List<KarenDevice>? devices,
    String? activeDeviceId,
    bool clearActiveDeviceId = false,
    List<CommandLogEntry>? logs,
    AppSettings? settings,
    ProtocolTemplates? templates,
    bool? isBusy,
    bool? isUnlocked,
    bool? pinRecoveryRequired,
    String? pinCleanupWarning,
    bool clearPinCleanupWarning = false,
    int? failedPinAttempts,
    DateTime? pinLockoutUntil,
    bool clearLockout = false,
    StorageLoadStatus? devicesStorageStatus,
    StorageLoadStatus? logsStorageStatus,
    StorageLoadStatus? templatesStorageStatus,
    StorageLoadStatus? pinSecurityStorageStatus,
    String? lastError,
    bool clearError = false,
  }) {
    return KarenAppState(
      devices: devices ?? this.devices,
      activeDeviceId:
          clearActiveDeviceId ? null : (activeDeviceId ?? this.activeDeviceId),
      logs: logs ?? this.logs,
      settings: settings ?? this.settings,
      templates: templates ?? this.templates,
      isBusy: isBusy ?? this.isBusy,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      pinRecoveryRequired: pinRecoveryRequired ?? this.pinRecoveryRequired,
      pinCleanupWarning: clearPinCleanupWarning
          ? null
          : (pinCleanupWarning ?? this.pinCleanupWarning),
      failedPinAttempts: failedPinAttempts ?? this.failedPinAttempts,
      pinLockoutUntil:
          clearLockout ? null : (pinLockoutUntil ?? this.pinLockoutUntil),
      devicesStorageStatus: devicesStorageStatus ?? this.devicesStorageStatus,
      logsStorageStatus: logsStorageStatus ?? this.logsStorageStatus,
      templatesStorageStatus:
          templatesStorageStatus ?? this.templatesStorageStatus,
      pinSecurityStorageStatus:
          pinSecurityStorageStatus ?? this.pinSecurityStorageStatus,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class KarenController extends Notifier<KarenAppState> {
  Future<void> _pinOperationChain = Future<void>.value();

  @override
  KarenAppState build() {
    final initial = ref.read(initialAppDataProvider);
    final activeId = initial.activeDeviceId ??
        (initial.devices.isNotEmpty ? initial.devices.first.id : null);
    final effectivePinLockEnabled = initial.settings.pinLockEnabled ||
        initial.pinSecurityState.pinLockEnabled ||
        (initial.pinSettingsCorrupted && initial.pinHashPresent);
    final pinRecoveryRequired = initial.pinSecurityState.recoveryRequired ||
        initial.pinSecurityStatus != StorageLoadStatus.loaded ||
        initial.pinJournalStatus != StorageLoadStatus.loaded ||
        initial.pinJournalRecoveryFailed ||
        (effectivePinLockEnabled && !initial.pinHashPresent) ||
        (initial.pinSettingsCorrupted && !initial.pinHashPresent);

    return KarenAppState(
      devices: initial.devices,
      activeDeviceId: activeId,
      logs: initial.logs,
      settings: initial.settings.copyWith(
        pinLockEnabled: effectivePinLockEnabled,
      ),
      templates: initial.templates,
      isUnlocked: !effectivePinLockEnabled && !pinRecoveryRequired,
      pinRecoveryRequired: pinRecoveryRequired,
      failedPinAttempts: initial.pinSecurityState.failedAttempts,
      pinLockoutUntil: initial.pinSecurityState.lockoutUntilUtc,
      devicesStorageStatus: initial.devicesStatus,
      logsStorageStatus: initial.logsStatus,
      templatesStorageStatus: initial.templatesStatus,
      pinSecurityStorageStatus: initial.pinSecurityStatus,
      lastError: initial.hasAnyStorageError
          ? 'حافظه تنظیمات یا اطلاعات امن PIN در دسترس نیست یا آسیب دیده است. برای جلوگیری از دور زدن قفل یا بازنویسی داده‌های قبلی، حالت محافظت فعال شد.'
          : null,
    );
  }

  /// Strictly serializes all PIN security operations (verify, set/disable,
  /// emergency wipe) so concurrent requests cannot race on attempt counters,
  /// lockout timestamps, or PIN hash migration.
  Future<T> _runPinOperationSerialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pinOperationChain = _pinOperationChain.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  LocalStorageService get _storage => ref.read(localStorageProvider);

  CommandTransport get _activeTransport =>
      state.settings.transportMode == TransportMode.demo
          ? ref.read(demoTransportProvider)
          : ref.read(smsTransportProvider);

  int get _hashIterations => ref.read(pinHashIterationsProvider);

  String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  /// Re-reads encrypted storage without mutating or overwriting anything.
  /// Preserves all existing data whenever Android Keystore recovers.
  Future<bool> retrySecureStorageLoad() async {
    state = state.copyWith(isBusy: true, clearError: true);
    final reloaded = await _storage.loadAll();
    final activeId = reloaded.activeDeviceId ??
        (reloaded.devices.isNotEmpty ? reloaded.devices.first.id : null);
    final effectivePinLockEnabled = reloaded.settings.pinLockEnabled ||
        reloaded.pinSecurityState.pinLockEnabled ||
        (reloaded.pinSettingsCorrupted && reloaded.pinHashPresent);
    final recoveryRequired = reloaded.pinSecurityState.recoveryRequired ||
        reloaded.pinSecurityStatus != StorageLoadStatus.loaded ||
        reloaded.pinJournalStatus != StorageLoadStatus.loaded ||
        reloaded.pinJournalRecoveryFailed ||
        (effectivePinLockEnabled && !reloaded.pinHashPresent) ||
        (reloaded.pinSettingsCorrupted && !reloaded.pinHashPresent);

    state = state.copyWith(
      devices: reloaded.devices,
      activeDeviceId: activeId,
      clearActiveDeviceId: activeId == null,
      logs: reloaded.logs,
      settings: reloaded.settings.copyWith(
        pinLockEnabled: effectivePinLockEnabled,
      ),
      templates: reloaded.templates,
      failedPinAttempts: reloaded.pinSecurityState.failedAttempts,
      pinLockoutUntil: reloaded.pinSecurityState.lockoutUntilUtc,
      clearLockout: reloaded.pinSecurityState.lockoutUntilUtc == null,
      devicesStorageStatus: reloaded.devicesStatus,
      logsStorageStatus: reloaded.logsStatus,
      templatesStorageStatus: reloaded.templatesStatus,
      pinSecurityStorageStatus: reloaded.pinSecurityStatus,
      pinRecoveryRequired: recoveryRequired,
      isUnlocked: effectivePinLockEnabled
          ? state.isUnlocked && !recoveryRequired
          : !recoveryRequired,
      isBusy: false,
      lastError: reloaded.hasAnyStorageError
          ? 'بازیابی حافظه تنظیمات یا اطلاعات امن همچنان ناموفق است. داده‌های موجود برای جلوگیری از حذف تصادفی محافظت می‌شوند.'
          : null,
      clearError: !reloaded.hasAnyStorageError,
    );
    return !reloaded.hasAnyStorageError;
  }

  /// Explicit user-confirmed recovery ONLY for affected/corrupted non-PIN stores
  /// after retry has failed. Verifies deletion before lifting write protection.
  Future<EmergencyWipeResult> resetAffectedCorruptedStores() async {
    final keysToReset = <String>[
      if (state.isDevicesWriteProtected) AppConstants.secureKeyDevices,
      if (state.isLogsWriteProtected) AppConstants.secureKeyLogs,
      if (state.isTemplatesWriteProtected) AppConstants.secureKeyTemplates,
    ];
    if (keysToReset.isEmpty) {
      return const EmergencyWipeResult(
        success: true,
        messageFa: 'هیچ بخش آسیب‌دیده‌ای برای بازنشانی وجود ندارد.',
      );
    }

    final failed = await _storage.deleteAndVerifySecureKeys(keysToReset);
    if (failed.isNotEmpty) {
      const msg =
          'پاکسازی بخش آسیب‌دیده در حافظه امن تایید نشد. حالت محافظت برای جلوگیری از خطا فعال می‌ماند.';
      state = state.copyWith(lastError: msg);
      return EmergencyWipeResult(
        success: false,
        failedKeys: failed,
        messageFa: msg,
      );
    }

    await retrySecureStorageLoad();
    return const EmergencyWipeResult(
      success: true,
      messageFa: 'بخش‌های آسیب‌دیده با موفقیت پاکسازی و بازیابی شدند.',
    );
  }

  Future<String?> _persistDevicesSafe(List<KarenDevice> devices) async {
    if (state.isDevicesWriteProtected) {
      const msg =
          'نوشتن اطلاعات مسدود است: حافظه امن دستگاه‌ها قابل خواندن نیست. ابتدا از بخش بازیابی تلاش مجدد کنید تا داده‌های قبلی از بین نروند.';
      state = state.copyWith(lastError: msg);
      return msg;
    }
    try {
      await _storage.saveDevices(devices);
      return null;
    } on SecureStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
      return e.message;
    }
  }

  Future<void> _persistLogsSafe(List<CommandLogEntry> logs) async {
    if (state.isLogsWriteProtected) {
      return;
    }
    try {
      await _storage.saveLogs(logs);
    } on SecureStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
    }
  }

  Future<void> _persistActiveDeviceIdSafe(String? id) async {
    try {
      await _storage.saveActiveDeviceId(id);
    } on PreferencesStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
    }
  }

  /// Seeds a clean Demo device only when explicitly requested by the user.
  /// Refuses to overwrite encrypted storage if devices store is write-protected.
  Future<String?> seedDemoDevice() async {
    if (state.isDevicesWriteProtected) {
      const msg =
          'امکان افزودن دستگاه نمونه در زمان خطای حافظه امن وجود ندارد. ابتدا داده‌های قبلی را بازیابی کنید.';
      state = state.copyWith(lastError: msg);
      return msg;
    }

    final demoSchedules = List.generate(7, (index) {
      if (index < 5) {
        return DaySchedule(
          dayIndex: index,
          enabled: true,
          syncStatus: SyncStatus.syncedDemo,
          slots: [
            TimeSlot(
              id: 'slot_${index}_1',
              startHour: 6,
              startMinute: 30,
              endHour: 8,
              endMinute: 30,
            ),
            TimeSlot(
              id: 'slot_${index}_2',
              startHour: 17,
              startMinute: 0,
              endHour: 19,
              endMinute: 0,
            ),
          ],
        );
      }
      return DaySchedule(
        dayIndex: index,
        enabled: false,
        syncStatus: SyncStatus.syncedDemo,
      );
    });

    final demoDevice = KarenDevice(
      id: _nextId('dev'),
      title: 'پمپ آب باغچه (نمونه دمو)',
      phoneNumber: '09120000001',
      locationLabel: 'باغ شمال - تابلو اصلی',
      powerState: DevicePowerState.off,
      operatingMode: OperatingMode.hybrid,
      powerOutageAlertEnabled: true,
      lastSyncedAt: DateTime.now(),
      deviceClockSyncedAt: DateTime.now(),
      weeklySchedules: demoSchedules,
      authorizedUsers: const [
        AuthorizedUser(
          id: 'usr_admin_demo',
          name: 'مدیر اصلی (دمو)',
          phoneNumber: '09121112233',
          role: DeviceUserRole.admin,
          avatarIndex: 0,
          syncStatus: SyncStatus.syncedDemo,
        ),
        AuthorizedUser(
          id: 'usr_member_demo',
          name: 'نگهبان مجموعه',
          phoneNumber: '09354445566',
          role: DeviceUserRole.user,
          avatarIndex: 2,
          syncStatus: SyncStatus.syncedDemo,
        ),
      ],
    );

    final updated = [demoDevice, ...state.devices];
    final err = await _persistDevicesSafe(updated);
    if (err != null) return err;

    state = state.copyWith(
      devices: updated,
      activeDeviceId: demoDevice.id,
      clearError: true,
    );
    await _persistActiveDeviceIdSafe(demoDevice.id);
    return null;
  }

  Future<String?> addOrUpdateDevice({
    String? existingId,
    required String title,
    required String phoneNumber,
    String locationLabel = '',
  }) async {
    if (state.isDevicesWriteProtected) {
      const msg =
          'امکان ثبت دستگاه جدید در حالت خطای حافظه امن وجود ندارد تا داده‌های قبلی بازنویسی نشوند.';
      state = state.copyWith(lastError: msg);
      return msg;
    }

    final titleError = PersianUtils.validateDeviceTitle(title);
    if (titleError != null) return titleError;

    final phoneError = PersianUtils.validateIranPhone(phoneNumber);
    if (phoneError != null) return phoneError;

    final normalizedPhone = PersianUtils.normalizeIranPhone(phoneNumber);
    List<KarenDevice> updated;
    String activeId;

    if (existingId != null) {
      updated = state.devices.map((d) {
        if (d.id == existingId) {
          return d.copyWith(
            title: title.trim(),
            phoneNumber: normalizedPhone,
            locationLabel: locationLabel.trim(),
          );
        }
        return d;
      }).toList();
      activeId = existingId;
    } else {
      final created = KarenDevice(
        id: _nextId('dev'),
        title: title.trim(),
        phoneNumber: normalizedPhone,
        locationLabel: locationLabel.trim(),
        weeklySchedules: KarenDevice.defaultWeeklySchedules(),
      );
      updated = [...state.devices, created];
      activeId = created.id;
    }

    final err = await _persistDevicesSafe(updated);
    if (err != null) return err;

    state = state.copyWith(
      devices: updated,
      activeDeviceId: activeId,
      clearError: true,
    );
    await _persistActiveDeviceIdSafe(activeId);
    return null;
  }

  Future<void> selectDevice(String deviceId) async {
    state = state.copyWith(activeDeviceId: deviceId);
    await _persistActiveDeviceIdSafe(deviceId);
  }

  Future<String?> deleteDevice(String deviceId) async {
    if (state.isDevicesWriteProtected) {
      return 'حذف دستگاه در زمان خطای حافظه امن غیرفعال است.';
    }
    final updated = state.devices.where((d) => d.id != deviceId).toList();
    final nextActive = updated.isEmpty
        ? null
        : (state.activeDeviceId == deviceId
            ? updated.first.id
            : state.activeDeviceId);
    final err = await _persistDevicesSafe(updated);
    if (err != null) return err;

    state = state.copyWith(
      devices: updated,
      activeDeviceId: nextActive,
      clearActiveDeviceId: nextActive == null,
    );
    await _persistActiveDeviceIdSafe(nextActive);
    return null;
  }

  /// Dispatches a command through the active transport with strict state rules:
  /// - [onDemoSuccessTransform]: applied ONLY when DemoCommandTransport succeeds.
  /// - [onSmsPendingTransform]: applied ONLY when SmsComposerCommandTransport opens
  ///   the SMS composer (used strictly to record pending confirmation metadata, NEVER
  ///   to claim hardware executed the command).
  Future<CommandDispatchResult> _executeCommand({
    required String actionKey,
    required String actionTitle,
    required CommandCategory category,
    Map<String, String> params = const {},
    KarenDevice Function(KarenDevice device)? onDemoSuccessTransform,
    KarenDevice Function(KarenDevice device)? onSmsPendingTransform,
  }) async {
    final device = state.activeDevice;
    if (device == null) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.failed,
        messageFa: 'ابتدا یک دستگاه ثبت یا انتخاب کنید.',
      );
    }

    state = state.copyWith(isBusy: true, clearError: true);

    final rawTemplate = state.templates.rawTemplate(actionKey);
    final payload = state.templates.render(actionKey, params);
    final isPlaceholder = state.templates.isPlaceholder(actionKey);

    final result = await _activeTransport.dispatch(
      CommandDispatchRequest(
        device: device,
        actionKey: actionKey,
        actionTitle: actionTitle,
        category: category,
        rawTemplate: rawTemplate,
        payload: payload,
        isPlaceholderTemplate: isPlaceholder,
      ),
    );

    var updatedDevices = state.devices;
    var devicesChanged = false;

    if (result.isSimulatedExecution && onDemoSuccessTransform != null) {
      updatedDevices = state.devices.map((d) {
        if (d.id == device.id) {
          return onDemoSuccessTransform(d).copyWith(
            lastSyncedAt: DateTime.now(),
            clearPendingAction: true,
          );
        }
        return d;
      }).toList();
      devicesChanged = true;
    } else if (result.isPendingConfirmation) {
      updatedDevices = state.devices.map((d) {
        if (d.id == device.id) {
          final next = onSmsPendingTransform != null
              ? onSmsPendingTransform(d)
              : d;
          return next.copyWith(
            pendingActionSummary: '$actionTitle (در انتظار ارسال و تایید دستگاه)',
          );
        }
        return d;
      }).toList();
      devicesChanged = true;
    }

    if (devicesChanged && !state.isDevicesWriteProtected) {
      await _persistDevicesSafe(updatedDevices);
    }

    final logEntry = CommandLogEntry(
      id: _nextId('log'),
      deviceId: device.id,
      deviceTitle: device.title,
      actionTitle: actionTitle,
      category: category,
      transportMode: _activeTransport.mode,
      status: result.status,
      payloadPreview: payload.isEmpty ? '(خالی)' : payload,
      responseSummary: result.simulatedReplyFa ?? result.messageFa,
      timestamp: DateTime.now(),
    );

    final updatedLogs = [logEntry, ...state.logs];
    state = state.copyWith(
      devices: updatedDevices,
      logs: updatedLogs,
      isBusy: false,
      lastError: result.dispatched ? null : result.messageFa,
    );
    await _persistLogsSafe(updatedLogs);
    return result;
  }

  Future<CommandDispatchResult> setPower(bool turnOn) {
    return _executeCommand(
      actionKey: turnOn
          ? ProtocolTemplates.keyPowerOn
          : ProtocolTemplates.keyPowerOff,
      actionTitle: turnOn ? 'روشن کردن دستگاه' : 'خاموش کردن دستگاه',
      category: CommandCategory.power,
      onDemoSuccessTransform: (d) => d.copyWith(
        powerState: turnOn ? DevicePowerState.on : DevicePowerState.off,
      ),
    );
  }

  Future<CommandDispatchResult> silencePowerOutageAlert() {
    return _executeCommand(
      actionKey: ProtocolTemplates.keySilenceOutageAlert,
      actionTitle: 'قطع کردن اخطار قطع برق',
      category: CommandCategory.settings,
      onDemoSuccessTransform: (d) => d.copyWith(powerOutageAlertSilenced: true),
    );
  }

  Future<CommandDispatchResult> setPowerOutageAlertEnabled(bool enabled) {
    return _executeCommand(
      actionKey: enabled
          ? ProtocolTemplates.keyEnableOutageAlert
          : ProtocolTemplates.keyDisableOutageAlert,
      actionTitle:
          enabled ? 'فعال کردن اخطار قطع برق' : 'غیرفعال کردن اخطار قطع برق',
      category: CommandCategory.settings,
      onDemoSuccessTransform: (d) => d.copyWith(
        powerOutageAlertEnabled: enabled,
        powerOutageAlertSilenced: !enabled,
      ),
    );
  }

  Future<CommandDispatchResult> setOperatingMode(OperatingMode mode) {
    return _executeCommand(
      actionKey: ProtocolTemplates.keyOperatingMode,
      actionTitle: 'تنظیم حالت کارکرد (${mode.labelFa})',
      category: CommandCategory.settings,
      params: {'mode': mode.name.toUpperCase()},
      onDemoSuccessTransform: (d) => d.copyWith(operatingMode: mode),
    );
  }

  Future<CommandDispatchResult> addOrUpdateAuthorizedUser({
    String? existingUserId,
    required String name,
    required String phoneNumber,
    required DeviceUserRole role,
    required int avatarIndex,
  }) async {
    if (name.trim().length < 2) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.failed,
        messageFa: 'نام کاربر باید حداقل ۲ کاراکتر باشد.',
      );
    }
    final phoneErr = PersianUtils.validateIranPhone(phoneNumber);
    if (phoneErr != null) {
      return CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.failed,
        messageFa: phoneErr,
      );
    }

    final normalized = PersianUtils.normalizeIranPhone(phoneNumber);
    final isAdmin = role == DeviceUserRole.admin;
    final userId = existingUserId ?? _nextId('usr');

    KarenDevice upsertUser(KarenDevice d, SyncStatus syncStatus) {
      final userObj = AuthorizedUser(
        id: userId,
        name: name.trim(),
        phoneNumber: normalized,
        role: role,
        avatarIndex: avatarIndex,
        syncStatus: syncStatus,
      );
      final list = [...d.authorizedUsers];
      final idx = list.indexWhere((u) => u.id == userObj.id);
      if (idx >= 0) {
        list[idx] = userObj;
      } else {
        list.add(userObj);
      }
      return d.copyWith(authorizedUsers: list);
    }

    return _executeCommand(
      actionKey: isAdmin
          ? ProtocolTemplates.keyDefineAdmin
          : ProtocolTemplates.keyDefineUser,
      actionTitle: isAdmin
          ? 'تعریف مدیر (${name.trim()})'
          : 'تعریف کاربر (${name.trim()})',
      category: CommandCategory.userAccess,
      params: {'phone': normalized},
      onDemoSuccessTransform: (d) => upsertUser(d, SyncStatus.syncedDemo),
      onSmsPendingTransform: (d) =>
          upsertUser(d, SyncStatus.pendingConfirmation),
    );
  }

  Future<void> markAuthorizedUserConfirmed(String userId) async {
    final device = state.activeDevice;
    if (device == null || state.isDevicesWriteProtected) return;
    final updated = state.devices.map((d) {
      if (d.id != device.id) return d;
      return d.copyWith(
        authorizedUsers: d.authorizedUsers
            .map((u) =>
                u.id == userId ? u.copyWith(syncStatus: SyncStatus.confirmed) : u)
            .toList(),
      );
    }).toList();
    if (await _persistDevicesSafe(updated) == null) {
      state = state.copyWith(devices: updated);
    }
  }

  Future<void> removeAuthorizedUser(String userId) async {
    final device = state.activeDevice;
    if (device == null || state.isDevicesWriteProtected) return;
    final updated = state.devices.map((d) {
      if (d.id == device.id) {
        return d.copyWith(
          authorizedUsers:
              d.authorizedUsers.where((u) => u.id != userId).toList(),
        );
      }
      return d;
    }).toList();
    if (await _persistDevicesSafe(updated) == null) {
      state = state.copyWith(devices: updated);
    }
  }

  Future<void> updateDayEnabledLocal(int dayIndex, bool enabled) async {
    final device = state.activeDevice;
    if (device == null || state.isDevicesWriteProtected) return;
    final updated = state.devices.map((d) {
      if (d.id != device.id) return d;
      final schedules = d.weeklySchedules.map((s) {
        if (s.dayIndex == dayIndex) {
          return s.copyWith(
            enabled: enabled,
            syncStatus: SyncStatus.localDraft,
          );
        }
        return s;
      }).toList();
      return d.copyWith(weeklySchedules: schedules);
    }).toList();
    if (await _persistDevicesSafe(updated) == null) {
      state = state.copyWith(devices: updated);
    }
  }

  Future<String?> addTimeSlotLocal(int dayIndex, TimeSlot slot) async {
    if (state.isDevicesWriteProtected) {
      return 'حافظه امن دستگاه‌ها قابل نوشتن نیست. ابتدا بازیابی انجام دهید.';
    }
    if (!slot.isValid) {
      return 'ساعت پایان باید بعد از ساعت شروع باشد';
    }
    final device = state.activeDevice;
    if (device == null) return 'دستگاهی انتخاب نشده است';

    final day = device.weeklySchedules[dayIndex];
    for (final existing in day.slots) {
      if (existing.id != slot.id && existing.overlapsWith(slot)) {
        return 'بازه زمانی انتخابی با یکی از بازه‌های فعلی تداخل دارد';
      }
    }

    final updated = state.devices.map((d) {
      if (d.id != device.id) return d;
      final schedules = d.weeklySchedules.map((s) {
        if (s.dayIndex != dayIndex) return s;
        final nextSlots = [...s.slots.where((e) => e.id != slot.id), slot]
          ..sort((a, b) => a.startTotalMinutes.compareTo(b.startTotalMinutes));
        return s.copyWith(
          enabled: true,
          slots: nextSlots,
          syncStatus: SyncStatus.localDraft,
        );
      }).toList();
      return d.copyWith(weeklySchedules: schedules);
    }).toList();

    final err = await _persistDevicesSafe(updated);
    if (err != null) return err;

    state = state.copyWith(devices: updated);
    return null;
  }

  Future<void> removeTimeSlotLocal(int dayIndex, String slotId) async {
    final device = state.activeDevice;
    if (device == null || state.isDevicesWriteProtected) return;
    final updated = state.devices.map((d) {
      if (d.id != device.id) return d;
      final schedules = d.weeklySchedules.map((s) {
        if (s.dayIndex != dayIndex) return s;
        return s.copyWith(
          slots: s.slots.where((e) => e.id != slotId).toList(),
          syncStatus: SyncStatus.localDraft,
        );
      }).toList();
      return d.copyWith(weeklySchedules: schedules);
    }).toList();
    if (await _persistDevicesSafe(updated) == null) {
      state = state.copyWith(devices: updated);
    }
  }

  Future<CommandDispatchResult> uploadDayStatus(int dayIndex) {
    final device = state.activeDevice;
    final enabled = device?.weeklySchedules[dayIndex].enabled ?? false;
    return _executeCommand(
      actionKey: ProtocolTemplates.keySetDay,
      actionTitle: 'تنظیم روز (${AppConstants.persianWeekDays[dayIndex]})',
      category: CommandCategory.schedule,
      params: {
        'day': '${dayIndex + 1}',
        'state': enabled ? 'ON' : 'OFF',
      },
      onDemoSuccessTransform: (d) => d.copyWith(
        weeklySchedules: d.weeklySchedules
            .map((s) => s.dayIndex == dayIndex
                ? s.copyWith(syncStatus: SyncStatus.syncedDemo)
                : s)
            .toList(),
      ),
      onSmsPendingTransform: (d) => d.copyWith(
        weeklySchedules: d.weeklySchedules
            .map((s) => s.dayIndex == dayIndex
                ? s.copyWith(syncStatus: SyncStatus.pendingConfirmation)
                : s)
            .toList(),
      ),
    );
  }

  Future<CommandDispatchResult> uploadDayHours(int dayIndex) {
    final device = state.activeDevice;
    final slots = device?.weeklySchedules[dayIndex].slots ?? [];
    final summary = slots
        .map((s) =>
            '${s.startHour.toString().padLeft(2, '0')}:${s.startMinute.toString().padLeft(2, '0')}-'
            '${s.endHour.toString().padLeft(2, '0')}:${s.endMinute.toString().padLeft(2, '0')}')
        .join(',');
    return _executeCommand(
      actionKey: ProtocolTemplates.keySetDayHours,
      actionTitle:
          'بارگذاری ساعات روز (${AppConstants.persianWeekDays[dayIndex]})',
      category: CommandCategory.schedule,
      params: {
        'day': '${dayIndex + 1}',
        'slots': summary.isEmpty ? 'CLEAR' : summary,
      },
      onDemoSuccessTransform: (d) => d.copyWith(
        weeklySchedules: d.weeklySchedules
            .map((s) => s.dayIndex == dayIndex
                ? s.copyWith(syncStatus: SyncStatus.syncedDemo)
                : s)
            .toList(),
      ),
      onSmsPendingTransform: (d) => d.copyWith(
        weeklySchedules: d.weeklySchedules
            .map((s) => s.dayIndex == dayIndex
                ? s.copyWith(syncStatus: SyncStatus.pendingConfirmation)
                : s)
            .toList(),
      ),
    );
  }

  Future<CommandDispatchResult> applyAndUploadDailyRoutine({
    required List<TimeSlot> routineSlots,
    required Set<int> targetDayIndices,
  }) async {
    final summary = routineSlots
        .map((s) =>
            '${s.startHour.toString().padLeft(2, '0')}:${s.startMinute.toString().padLeft(2, '0')}-'
            '${s.endHour.toString().padLeft(2, '0')}:${s.endMinute.toString().padLeft(2, '0')}')
        .join(',');

    KarenDevice applyRoutine(KarenDevice d, SyncStatus status) {
      return d.copyWith(
        weeklySchedules: d.weeklySchedules.map((s) {
          if (targetDayIndices.contains(s.dayIndex)) {
            return s.copyWith(
              enabled: routineSlots.isNotEmpty,
              slots: routineSlots
                  .map((slot) => slot.copyWith(id: '${slot.id}_d${s.dayIndex}'))
                  .toList(),
              syncStatus: status,
            );
          }
          return s;
        }).toList(),
      );
    }

    return _executeCommand(
      actionKey: ProtocolTemplates.keySetDailyRoutine,
      actionTitle: 'تنظیم روزانه (${targetDayIndices.length} روز)',
      category: CommandCategory.schedule,
      params: {'slots': summary.isEmpty ? 'CLEAR' : summary},
      onDemoSuccessTransform: (d) => applyRoutine(d, SyncStatus.syncedDemo),
      onSmsPendingTransform: (d) =>
          applyRoutine(d, SyncStatus.pendingConfirmation),
    );
  }

  Future<CommandDispatchResult> requestGeneralReport() {
    return _executeCommand(
      actionKey: ProtocolTemplates.keyGeneralReport,
      actionTitle: 'گزارشگیری کلی',
      category: CommandCategory.report,
    );
  }

  Future<CommandDispatchResult> syncDeviceClock(DateTime targetTime) {
    final formatted =
        '${targetTime.year}-${targetTime.month.toString().padLeft(2, '0')}-${targetTime.day.toString().padLeft(2, '0')} '
        '${targetTime.hour.toString().padLeft(2, '0')}:${targetTime.minute.toString().padLeft(2, '0')}';
    return _executeCommand(
      actionKey: ProtocolTemplates.keySyncClock,
      actionTitle: 'تنظیم ساعت دستگاه',
      category: CommandCategory.report,
      params: {'time': formatted},
      onDemoSuccessTransform: (d) => d.copyWith(deviceClockSyncedAt: targetTime),
    );
  }

  Future<CommandDispatchResult> retrieveDaysSchedule() {
    return _executeCommand(
      actionKey: ProtocolTemplates.keyRetrieveDays,
      actionTitle: 'بازیابی زمان روزها',
      category: CommandCategory.report,
    );
  }

  Future<void> logManualSmsReply(String replyText) async {
    final device = state.activeDevice;
    if (device == null || replyText.trim().isEmpty) return;

    final entry = CommandLogEntry(
      id: _nextId('log'),
      deviceId: device.id,
      deviceTitle: device.title,
      actionTitle: 'ثبت پاسخ پیامک دریافتی',
      category: CommandCategory.report,
      transportMode: TransportMode.liveSmsComposer,
      status: CommandLogStatus.receivedReply,
      payloadPreview: 'SMS INBOX',
      responseSummary: replyText.trim(),
      timestamp: DateTime.now(),
    );
    final updatedLogs = [entry, ...state.logs];
    final updatedDevices = state.devices.map((d) {
      if (d.id != device.id) return d;
      return d.copyWith(clearPendingAction: true, lastSyncedAt: DateTime.now());
    }).toList();

    state = state.copyWith(logs: updatedLogs, devices: updatedDevices);
    if (!state.isDevicesWriteProtected) {
      await _persistDevicesSafe(updatedDevices);
    }
    await _persistLogsSafe(updatedLogs);
  }

  Future<void> clearLogs() async {
    if (state.isLogsWriteProtected) return;
    state = state.copyWith(logs: []);
    await _persistLogsSafe([]);
  }

  /// Persists and verifies settings BEFORE updating in-memory state.
  /// Never allows changing `pinLockEnabled` directly (must go through `setPinLock`).
  Future<String?> updateSettings(AppSettings next) async {
    final safeNext = next.copyWith(pinLockEnabled: state.settings.pinLockEnabled);
    try {
      await _storage.saveSettings(safeNext);
      state = state.copyWith(settings: safeNext, clearError: true);
      return null;
    } on PreferencesStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
      return e.message;
    }
  }

  Future<String?> updateProtocolTemplate(String key, String value) async {
    if (state.isTemplatesWriteProtected) {
      return 'قالب‌های ذخیره‌شده در حالت محافظت خطا هستند. ابتدا بازیابی حافظه امن را انجام دهید.';
    }
    final validationError = ProtocolTemplates.validateUserTemplateInput(value);
    if (validationError != null) return validationError;

    final next = state.templates.copyWithEntry(key, value.trim());
    try {
      await _storage.saveTemplates(next);
      state = state.copyWith(templates: next, clearError: true);
      return null;
    } on SecureStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
      return e.message;
    }
  }

  Future<String?> resetProtocolTemplates() async {
    if (state.isTemplatesWriteProtected) {
      return 'برای جلوگیری از بازنویسی، ابتدا از صفحه اصلی حافظه امن را بازیابی کنید.';
    }
    final defaults = ProtocolTemplates.unverifiedDefaults();
    try {
      await _storage.saveTemplates(defaults);
      state = state.copyWith(templates: defaults, clearError: true);
      return null;
    } on SecureStorageFailure catch (e) {
      state = state.copyWith(lastError: e.message);
      return e.message;
    }
  }

  /// Locks the app immediately if PIN lock is enabled (used on backgrounding).
  void lockApp() {
    if (state.settings.pinLockEnabled && state.isUnlocked) {
      state = state.copyWith(isUnlocked: false);
    }
  }

  /// Verifies that `secureKeyAppPinHash` holds the exact expected value
  /// (`expectedHash == null` means deleted/absent).
  Future<bool> _verifyStoredPinHashEquals(String? expectedHash) async {
    try {
      final actual = await _storage.readAppPinHash();
      if (expectedHash == null || expectedHash.isEmpty) {
        return actual == null || actual.isEmpty;
      }
      return actual == expectedHash;
    } on SecureStorageFailure {
      return false;
    }
  }

  /// Restores the complete pre-transaction snapshot (hash, settings, failed
  /// attempts, and lockout state), reads back & verifies every component, and
  /// removes the recovery journal ONLY after complete restoration is verified.
  Future<bool> _restoreAndVerifyPinTransaction({
    required String? previousHash,
    required PinSecurityState previousSecurityState,
    required AppSettings previousSettings,
    required bool removeJournalOnSuccess,
  }) async {
    try {
      await _storage.writeAppPinHash(previousHash);
    } on SecureStorageFailure {
      // Verified via explicit read-back below.
    }
    if (!await _verifyStoredPinHashEquals(previousHash)) return false;

    try {
      await _storage.saveSettings(previousSettings);
    } on PreferencesStorageFailure {
      // Verified via settingsMatch below.
    }
    if (!_storage.settingsMatch(previousSettings)) return false;

    try {
      await _storage.savePinSecurityState(previousSecurityState);
    } on SecureStorageFailure {
      // Verified via explicit loadPinSecurityState below.
    }
    try {
      if (await _storage.loadPinSecurityState() != previousSecurityState) {
        return false;
      }
    } on SecureStorageFailure {
      return false;
    }

    if (removeJournalOnSuccess) {
      try {
        await _storage.deletePinTransactionJournal();
      } on SecureStorageFailure {
        return false;
      }
    }
    return true;
  }

  /// Fail-Closed recovery-required transition. Keeps the persistent journal and
  /// durable `recoveryRequired` marker set so restarts cannot bypass the lock.
  Future<PinTransactionResult> _enterPinRecoveryRequired(
    String reasonFa,
  ) async {
    state = state.copyWith(
      isUnlocked: false,
      pinRecoveryRequired: true,
      lastError: reasonFa,
    );
    try {
      final persisted = await _storage.loadPinSecurityState();
      if (!persisted.recoveryRequired) {
        await _storage.savePinSecurityState(
          persisted.copyWith(
            recoveryRequired: true,
            pinLockEnabled: persisted.pinLockEnabled ||
                state.settings.pinLockEnabled,
          ),
        );
      }
    } on SecureStorageFailure {
      // In-memory lock and any persisted recovery journal remain strictly active.
    }
    return PinTransactionResult(
      status: PinTransactionStatus.recoveryRequired,
      pinLockEnabledAfter: state.settings.pinLockEnabled,
      cleanupSucceeded: false,
      recoveryRequired: true,
      messageFa: reasonFa,
    );
  }

  /// 8-step transactional PIN activation, rotation, and deactivation backed by
  /// a persistent [PinTransactionJournal] in encrypted secure storage:
  /// 1. Read & validate current security state (hash, securityState, settings, journal).
  /// 2. Save the complete previous valid state into [PinTransactionJournal].
  /// 3. Persist the recovery journal in secure storage.
  /// 4. Read back and verify the journal matches byte-for-byte.
  /// 5. Perform the intended security-state changes (hash, securityState, settings).
  /// 6. Read back and validate the complete new state.
  /// 7. Mark the transaction committed in BOTH security state & journal, verifying read-back.
  /// 8. Remove the journal and verify deletion ONLY after step 7 succeeds.
  Future<PinTransactionResult> setPinLock(String? pin) {
    return _runPinOperationSerialized(() async {
      if (state.requiresUnlock) {
        return PinTransactionResult(
          status: PinTransactionStatus.rejected,
          pinLockEnabledAfter: state.settings.pinLockEnabled,
          recoveryRequired: state.pinRecoveryRequired,
          messageFa:
              'تغییر یا غیرفعال‌سازی رمز عبور در حالت قفل یا نیازمند بازیابی مجاز نیست.',
        );
      }

      final previousSettings = state.settings;
      final isDeactivation = pin == null || pin.isEmpty;
      if (!isDeactivation && !PinHasher.isValidPinFormat(pin)) {
        return PinTransactionResult(
          status: PinTransactionStatus.rejected,
          pinLockEnabledAfter: previousSettings.pinLockEnabled,
          messageFa: 'رمز عبور باید دقیقاً ۴ رقم عددی باشد.',
        );
      }

      final operation = isDeactivation
          ? PinTransactionOperation.deactivate
          : (previousSettings.pinLockEnabled
              ? PinTransactionOperation.rotate
              : PinTransactionOperation.activate);

      String? newHash;
      if (!isDeactivation) {
        try {
          newHash = PinHasher.createSaltedHash(
            pin,
            iterations: _hashIterations,
          );
        } on RangeError catch (e) {
          return PinTransactionResult(
            status: PinTransactionStatus.rejected,
            pinLockEnabledAfter: previousSettings.pinLockEnabled,
            messageFa: 'تعداد تکرارهای PBKDF2 خارج از محدوده مجاز است: $e',
          );
        } on ArgumentError catch (e) {
          return PinTransactionResult(
            status: PinTransactionStatus.rejected,
            pinLockEnabledAfter: previousSettings.pinLockEnabled,
            messageFa: 'پارامترهای رمزنگاری معتبر نیستند: $e',
          );
        }
      }

      // STEP 1: Read & validate current security state and check existing journal.
      String? previousHash;
      PinSecurityState previousSecurityState;
      PinTransactionJournal? existingJournal;
      try {
        existingJournal = await _storage.loadPinTransactionJournal();
        previousHash = await _storage.readAppPinHash();
        final storedSecurityState = await _storage.loadPinSecurityState();
        previousSecurityState = storedSecurityState.copyWith(
          pinLockEnabled: previousSettings.pinLockEnabled ||
              storedSecurityState.pinLockEnabled,
        );
      } on SecureStorageFailure catch (e) {
        return await _enterPinRecoveryRequired(
          'تغییر وضعیت PIN متوقف شد؛ خواندن وضعیت فعلی حافظه امن ناموفق بود. برنامه برای حفظ امنیت قفل شد: ${e.message}',
        );
      }

      if (existingJournal != null || previousSecurityState.recoveryRequired) {
        return await _enterPinRecoveryRequired(
          'یک ژورنال تراکنش امنیتی ناتمام از قبل وجود دارد. ابتدا بازیابی امنیتی تاییدشده را انجام دهید.',
        );
      }

      if (previousSettings.pinLockEnabled &&
          (previousHash == null || previousHash.isEmpty)) {
        return await _enterPinRecoveryRequired(
          'خطای امنیتی: قفل PIN فعال است اما کلید رمز فعلی در حافظه امن یافت نشد. برنامه برای حفظ امنیت قفل شد و نیازمند بازیابی است.',
        );
      }

      // STEP 2: Save the complete previous valid state into the recovery journal.
      final targetPinLockEnabled = !isDeactivation;
      final targetHash = isDeactivation ? null : newHash;
      final journal = PinTransactionJournal(
        transactionId: _nextId('pintx'),
        operation: operation,
        startedAtUtc: DateTime.now().toUtc(),
        committed: false,
        previousHash: previousHash,
        previousPinLockEnabled: previousSettings.pinLockEnabled,
        previousFailedAttempts: previousSecurityState.failedAttempts,
        previousLockoutUntilUtc: previousSecurityState.lockoutUntilUtc,
        targetHash: targetHash,
        targetPinLockEnabled: targetPinLockEnabled,
      );

      // STEP 3 & 4: Persist the recovery journal AND read back to verify it.
      try {
        await _storage.savePinTransactionJournal(journal);
      } on SecureStorageFailure catch (e) {
        try {
          final residualJournal = await _storage.loadPinTransactionJournal();
          if (residualJournal == null) {
            return PinTransactionResult(
              status: PinTransactionStatus.rolledBack,
              pinLockEnabledAfter: previousSettings.pinLockEnabled,
              messageFa:
                  'تراکنش PIN پیش از هر تغییری متوقف شد؛ ثبت ژورنال بازیابی ناموفق بود: ${e.message}',
            );
          }
          await _storage.deletePinTransactionJournal();
          return PinTransactionResult(
            status: PinTransactionStatus.rolledBack,
            pinLockEnabledAfter: previousSettings.pinLockEnabled,
            messageFa:
                'ژورنال ناقص پیش از اعمال هر تغییری با موفقیت پاکسازی شد: ${e.message}',
          );
        } on SecureStorageFailure {
          return await _enterPinRecoveryRequired(
            'ثبت و تایید ژورنال تراکنش PIN ناموفق بود و پاکسازی آن نیز تایید نشد. برنامه تا بازیابی امنیتی قفل می‌ماند.',
          );
        }
      }

      Future<PinTransactionResult> rollback(String failureMessage) async {
        final restored = await _restoreAndVerifyPinTransaction(
          previousHash: previousHash,
          previousSecurityState: previousSecurityState,
          previousSettings: previousSettings,
          removeJournalOnSuccess: true,
        );
        if (!restored) {
          try {
            await _storage.savePinTransactionJournal(
              journal.markRollbackFailed(),
            );
          } on SecureStorageFailure {
            // Uncommitted journal + durable recoveryRequired marker remain active.
          }
          return await _enterPinRecoveryRequired(
            'خطای بحرانی در تراکنش PIN: $failureMessage بازگردانی کامل رمز، تنظیمات و وضعیت امنیتی تایید نشد. ژورنال بازیابی حفظ شد و برنامه قفل می‌ماند.',
          );
        }
        state = state.copyWith(
          settings: previousSettings,
          isUnlocked: previousSettings.pinLockEnabled ? state.isUnlocked : true,
          pinRecoveryRequired: false,
          failedPinAttempts: previousSecurityState.failedAttempts,
          pinLockoutUntil: previousSecurityState.lockoutUntilUtc,
          clearLockout: previousSecurityState.lockoutUntilUtc == null,
          pinSecurityStorageStatus: StorageLoadStatus.loaded,
          lastError: failureMessage,
        );
        return PinTransactionResult(
          status: PinTransactionStatus.rolledBack,
          pinLockEnabledAfter: previousSettings.pinLockEnabled,
          messageFa:
              'تراکنش PIN انجام نشد و تمام وضعیت قبلی با بازخوانی تاییدشده بازگردانی شد: $failureMessage',
        );
      }

      try {
        final targetSettings = previousSettings.copyWith(
          pinLockEnabled: targetPinLockEnabled,
        );
        final inFlightSecurityState = PinSecurityState(
          failedAttempts: 0,
          lockoutUntilUtc: null,
          recoveryRequired: true,
          pinLockEnabled: previousSettings.pinLockEnabled,
        );
        final finalSecurityState = PinSecurityState(
          failedAttempts: 0,
          lockoutUntilUtc: null,
          recoveryRequired: false,
          pinLockEnabled: targetPinLockEnabled,
        );

        // STEP 5: Perform intended security-state changes while uncommitted
        //         journal and `recoveryRequired: true` guard against restarts.
        await _storage.savePinSecurityState(inFlightSecurityState);
        await _storage.writeAppPinHash(targetHash);
        await _storage.saveSettings(targetSettings);

        // STEP 6: Read back and validate the complete new state BEFORE commit.
        if (!await _verifyStoredPinHashEquals(targetHash)) {
          throw const SecureStorageFailure(
            'بازخوانی تاییدی کلید رمز جدید با مقدار مورد انتظار مطابقت ندارد.',
          );
        }
        if (!_storage.settingsMatch(targetSettings)) {
          throw const PreferencesStorageFailure(
            'بازخوانی تاییدی تنظیمات جدید PIN با مقدار مورد انتظار مطابقت ندارد.',
          );
        }

        // STEP 7: Mark transaction committed & verify read-back.
        await _storage.savePinSecurityState(finalSecurityState);
        if (await _storage.loadPinSecurityState() != finalSecurityState) {
          throw const SecureStorageFailure(
            'بازخوانی تاییدی وضعیت نهایی امنیتی PIN ناموفق بود.',
          );
        }
        await _storage.savePinTransactionJournal(journal.markCommitted());

        // STEP 8: Remove recovery journal ONLY after verified commit!
        try {
          await _storage.deletePinTransactionJournal();
        } on SecureStorageFailure {
          return await _enterPinRecoveryRequired(
            'تغییر رمز ثبت شد اما پاکسازی نهایی ژورنال بازیابی در حافظه امن تایید نشد. برنامه برای اطمینان از یکپارچگی قفل شد.',
          );
        }

        state = state.copyWith(
          settings: targetSettings,
          isUnlocked: true,
          pinRecoveryRequired: false,
          clearPinCleanupWarning: true,
          failedPinAttempts: 0,
          clearLockout: true,
          pinSecurityStorageStatus: StorageLoadStatus.loaded,
          clearError: true,
        );

        return PinTransactionResult(
          status: PinTransactionStatus.committed,
          pinLockEnabledAfter: targetPinLockEnabled,
          cleanupSucceeded: true,
          messageFa: switch (operation) {
            PinTransactionOperation.deactivate =>
              'قفل امنیتی با موفقیت غیرفعال و کلید رمز به‌صورت تاییدشده پاکسازی شد.',
            PinTransactionOperation.rotate =>
              'رمز ۴ رقمی با موفقیت تغییر و در حافظه امن تایید شد.',
            PinTransactionOperation.activate =>
              'قفل امنیتی ۴ رقمی با موفقیت فعال شد.',
          },
        );
      } on SecureStorageFailure catch (e) {
        return await rollback(e.message);
      } on PreferencesStorageFailure catch (e) {
        return await rollback(e.message);
      } catch (e) {
        return await rollback('خطای پیش‌بینی‌نشده در تراکنش امنیتی: $e');
      }
    });
  }

  /// Verifies candidate PIN with:
  /// - Strict FIFO serialization against concurrent calls
  /// - FAIL-CLOSED behavior on recovery-required state, read/write/no-op failures, or malformed hashes
  /// - Verified persistent brute-force attempt counter and lockout across restarts
  /// - Clean expired-lockout recovery
  /// - Automatic legacy V2.0 -> PBKDF2-HMAC-SHA256 migration
  Future<PinVerificationResult> verifyPin(
    String candidate, {
    DateTime? nowOverride,
  }) {
    return _runPinOperationSerialized(
      () => _verifyPinInternal(candidate, nowOverride: nowOverride),
    );
  }

  Future<PinVerificationResult> _verifyPinInternal(
    String candidate, {
    DateTime? nowOverride,
  }) async {
    final nowUtc = (nowOverride ?? DateTime.now()).toUtc();

    if (state.pinRecoveryRequired) {
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای بحرانی امنیتی: به دلیل شکست در تایید بازگردانی رمز عبور، برنامه در وضعیت قفل نیازمند بازیابی قرار دارد. لطفاً بازنشانی امنیتی را انجام دهید.',
      );
    }

    if (!state.settings.pinLockEnabled) {
      state = state.copyWith(isUnlocked: true);
      return const PinVerificationResult(
        status: PinVerificationStatus.unlocked,
        remainingAttempts: AppConstants.maxPinFailedAttempts,
        messageFa: 'ورود موفق',
      );
    }

    if (state.isUnlocked) {
      return const PinVerificationResult(
        status: PinVerificationStatus.unlocked,
        remainingAttempts: AppConstants.maxPinFailedAttempts,
        messageFa: 'برنامه در حال حاضر باز است.',
      );
    }

    // 1. Refresh persisted brute-force security state from encrypted storage.
    PinSecurityState persistedSecurity;
    try {
      persistedSecurity = await _storage.loadPinSecurityState();
    } on SecureStorageFailure {
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای امنیتی: وضعیت قفل امنیتی از حافظه امن قابل خواندن نیست. برنامه برای حفظ امنیت بسته می‌ماند.',
      );
    }

    final effectiveLockout =
        persistedSecurity.lockoutUntilUtc ?? state.pinLockoutUntil;
    final isLockoutActive =
        effectiveLockout != null && nowUtc.isBefore(effectiveLockout);
    final isLockoutExpired =
        effectiveLockout != null && !nowUtc.isBefore(effectiveLockout);

    // 2. Enforce active persistent lockout.
    if (isLockoutActive) {
      final remaining = effectiveLockout.difference(nowUtc);
      state = state.copyWith(
        isUnlocked: false,
        failedPinAttempts: persistedSecurity.failedAttempts,
        pinLockoutUntil: effectiveLockout,
      );
      return PinVerificationResult(
        status: PinVerificationStatus.lockedOut,
        remainingAttempts: 0,
        lockoutRemaining: remaining,
        messageFa:
            'تلاش‌های ناموفق بیش از حد مجاز بوده است. لطفاً ${PersianUtils.toPersianDigits((remaining.inSeconds + 1).toString())} ثانیه صبر کنید.',
      );
    }

    // Expired lockout cleanly resets the attempt window to 0.
    final baseFailures = isLockoutExpired
        ? 0
        : (persistedSecurity.failedAttempts > state.failedPinAttempts
            ? persistedSecurity.failedAttempts
            : state.failedPinAttempts);

    if (!PinHasher.isValidPinFormat(candidate)) {
      return PinVerificationResult(
        status: PinVerificationStatus.invalidPin,
        remainingAttempts: (AppConstants.maxPinFailedAttempts - baseFailures)
            .clamp(0, AppConstants.maxPinFailedAttempts),
        messageFa: 'لطفاً رمز ۴ رقمی معتبر وارد کنید.',
      );
    }

    // 3. Read PIN hash from encrypted storage (fail closed on missing or error).
    String? storedHash;
    try {
      storedHash = await _storage.readAppPinHash();
    } on SecureStorageFailure {
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای امنیتی: دسترسی به حافظه امن رمز عبور امکان‌پذیر نیست. قفل برنامه برای حفظ امنیت بسته می‌ماند.',
      );
    }

    if (storedHash == null || storedHash.isEmpty) {
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای امنیتی: کلید رمز در حافظه امن یافت نشد. قفل برنامه باز نمی‌شود.',
      );
    }

    // 4. Validate PBKDF2/legacy record parameters and verify PIN.
    final check = PinHasher.verifyRecord(candidate, storedHash);
    if (check.isMalformed) {
      state = state.copyWith(
        isUnlocked: false,
        lastError: 'ساختار کلید رمز ذخیره‌شده نامعتبر یا آسیب‌دیده است.',
      );
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای امنیتی: ساختار رمز ذخیره‌شده در حافظه امن نامعتبر است. قفل برنامه برای حفظ امنیت بسته می‌ماند.',
      );
    }

    if (check.matched) {
      var migrated = false;
      if (check.needsMigration) {
        try {
          final upgradedHash = PinHasher.createSaltedHash(
            candidate,
            iterations: _hashIterations,
          );
          await _storage.writeAppPinHash(upgradedHash);
          migrated = true;
        } on SecureStorageFailure {
          // Non-fatal if only hash upgrade write failed; lockout reset below
          // will still verify secure-storage writability before unlocking.
        }
      }

      // Persist & verify cleared security state BEFORE unlocking.
      // Fail closed if security-state persistence fails or silently no-ops.
      try {
        await _storage.savePinSecurityState(
          const PinSecurityState(pinLockEnabled: true),
        );
      } on SecureStorageFailure {
        state = state.copyWith(
          isUnlocked: false,
          lastError: 'تایید بروزرسانی وضعیت قفل امنیتی ناموفق بود.',
        );
        return const PinVerificationResult(
          status: PinVerificationStatus.storageUnavailable,
          remainingAttempts: 0,
          messageFa:
              'خطای امنیتی: ثبت و تایید وضعیت قفل امنیتی در حافظه امن ناموفق بود. برنامه برای حفظ امنیت بسته می‌ماند.',
        );
      }

      state = state.copyWith(
        isUnlocked: true,
        pinRecoveryRequired: false,
        failedPinAttempts: 0,
        clearLockout: true,
        pinSecurityStorageStatus: StorageLoadStatus.loaded,
        clearError: true,
      );
      return PinVerificationResult(
        status: PinVerificationStatus.unlocked,
        remainingAttempts: AppConstants.maxPinFailedAttempts,
        hashMigrated: migrated,
        messageFa: migrated
            ? 'ورود موفق (الگوریتم رمز به PBKDF2-SHA256 ارتقا یافت).'
            : 'ورود با موفقیت انجام شد.',
      );
    }

    // 5. Incorrect PIN -> compute next brute-force state and PERSIST + VERIFY it.
    final nextFailures = baseFailures + 1;
    final remainingAttempts =
        (AppConstants.maxPinFailedAttempts - nextFailures)
            .clamp(0, AppConstants.maxPinFailedAttempts);

    if (nextFailures >= AppConstants.maxPinFailedAttempts) {
      final untilUtc = nowUtc.add(AppConstants.pinLockoutDuration);
      final lockedState = PinSecurityState(
        failedAttempts: 0,
        lockoutUntilUtc: untilUtc,
        pinLockEnabled: true,
      );
      try {
        await _storage.savePinSecurityState(lockedState);
      } on SecureStorageFailure {
        state = state.copyWith(
          isUnlocked: false,
          lastError: 'ثبت وضعیت قفل موقت در حافظه امن تایید نشد.',
        );
        return const PinVerificationResult(
          status: PinVerificationStatus.storageUnavailable,
          remainingAttempts: 0,
          messageFa:
              'خطای امنیتی: ذخیره و تایید وضعیت قفل امنیتی در حافظه امن ناموفق بود. برنامه در حالت قفل بسته می‌ماند.',
        );
      }

      state = state.copyWith(
        isUnlocked: false,
        failedPinAttempts: 0,
        pinLockoutUntil: untilUtc,
      );
      return const PinVerificationResult(
        status: PinVerificationStatus.lockedOut,
        remainingAttempts: 0,
        lockoutRemaining: AppConstants.pinLockoutDuration,
        messageFa:
            'رمز عبور ۵ بار نادرست وارد شد. ورودی به مدت ۳۰ ثانیه قفل شد.',
      );
    }

    final failedState = PinSecurityState(
      failedAttempts: nextFailures,
      lockoutUntilUtc: null,
      pinLockEnabled: true,
    );
    try {
      await _storage.savePinSecurityState(failedState);
    } on SecureStorageFailure {
      state = state.copyWith(
        isUnlocked: false,
        lastError: 'ثبت شمارنده تلاش ناموفق در حافظه امن تایید نشد.',
      );
      return const PinVerificationResult(
        status: PinVerificationStatus.storageUnavailable,
        remainingAttempts: 0,
        messageFa:
            'خطای امنیتی: ذخیره و تایید شمارنده تلاش‌های ناموفق در حافظه امن ناموفق بود. برنامه برای حفظ امنیت بسته می‌ماند.',
      );
    }

    state = state.copyWith(
      isUnlocked: false,
      failedPinAttempts: nextFailures,
      clearLockout: true,
    );
    return PinVerificationResult(
      status: PinVerificationStatus.invalidPin,
      remainingAttempts: remainingAttempts,
      messageFa:
          'رمز عبور نادرست است (${PersianUtils.toPersianDigits(remainingAttempts.toString())} تلاش باقی‌مانده).',
    );
  }

  /// Destructive recovery when Android Keystore is corrupted, rollback failed,
  /// or PIN is lost.
  /// CRITICAL: Never unlocks or disables PIN lock if deletion OR `pinLockEnabled == false`
  /// persistence verification fails!
  Future<EmergencyWipeResult> emergencyWipeAndUnlock() {
    return _runPinOperationSerialized(() async {
      final result = await _storage.wipeAllSensitiveDataAndResetSecurity();
      if (!result.success) {
        state = state.copyWith(
          isUnlocked: false,
          lastError: result.messageFa,
        );
        return result;
      }

      final persisted = _storage.loadSettings();
      if (persisted.pinLockEnabled) {
        const msg =
            'تایید نهایی غیرفعال‌سازی قفل برنامه در تنظیمات ناموفق بود. برنامه قفل می‌ماند.';
        state = state.copyWith(isUnlocked: false, lastError: msg);
        return const EmergencyWipeResult(
          success: false,
          failedKeys: [AppConstants.prefsKeySettings],
          messageFa: msg,
        );
      }

      state = KarenAppState(
        devices: const [],
        activeDeviceId: null,
        logs: const [],
        settings: persisted,
        templates: ProtocolTemplates.unverifiedDefaults(),
        isUnlocked: true,
        pinRecoveryRequired: false,
        pinCleanupWarning: null,
        failedPinAttempts: 0,
        pinLockoutUntil: null,
        devicesStorageStatus: StorageLoadStatus.loaded,
        logsStorageStatus: StorageLoadStatus.loaded,
        templatesStorageStatus: StorageLoadStatus.loaded,
        pinSecurityStorageStatus: StorageLoadStatus.loaded,
      );
      return result;
    });
  }
}

final karenControllerProvider =
    NotifierProvider<KarenController, KarenAppState>(KarenController.new);
