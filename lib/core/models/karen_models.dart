enum DevicePowerState {
  unknown('نامشخص'),
  on('روشن'),
  off('خاموش');

  final String labelFa;
  const DevicePowerState(this.labelFa);
}

enum OperatingMode {
  manual('دستی'),
  scheduled('خودکار (زمان‌بندی)'),
  hybrid('ترکیبی (دستی + زمان‌بندی)');

  final String labelFa;
  const OperatingMode(this.labelFa);
}

enum DeviceUserRole {
  admin('مدیر'),
  user('کاربر مجاز');

  final String labelFa;
  const DeviceUserRole(this.labelFa);
}

enum TransportMode {
  demo('حالت دمو (شبیه‌ساز)'),
  liveSmsComposer('ارسال پیامک (SMS)');

  final String labelFa;
  const TransportMode(this.labelFa);
}

enum CommandCategory {
  power,
  schedule,
  report,
  settings,
  userAccess,
}

enum CommandLogStatus {
  simulatedSuccess('شبیه‌سازی موفق (دمو)'),
  pendingConfirmation('در انتظار ارسال و تایید دستگاه'),
  blockedUnverified('مسدود (قالب تاییدنشده)'),
  receivedReply('پاسخ دریافتی'),
  failed('خطا');

  final String labelFa;
  const CommandLogStatus(this.labelFa);
}

enum SyncStatus {
  localDraft('نیاز به ارسال'),
  pendingConfirmation('در انتظار تایید دستگاه'),
  syncedDemo('همگام‌شده (دمو)'),
  confirmed('تایید شده');

  final String labelFa;
  const SyncStatus(this.labelFa);
}

class TimeSlot {
  final String id;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final bool enabled;

  const TimeSlot({
    required this.id,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.enabled = true,
  });

  int get startTotalMinutes => startHour * 60 + startMinute;
  int get endTotalMinutes => endHour * 60 + endMinute;

  bool get isValid =>
      startHour >= 0 &&
      startHour <= 23 &&
      endHour >= 0 &&
      endHour <= 23 &&
      startMinute >= 0 &&
      startMinute <= 59 &&
      endMinute >= 0 &&
      endMinute <= 59 &&
      endTotalMinutes > startTotalMinutes;

  bool overlapsWith(TimeSlot other) {
    if (!enabled || !other.enabled) return false;
    return startTotalMinutes < other.endTotalMinutes &&
        other.startTotalMinutes < endTotalMinutes;
  }

  TimeSlot copyWith({
    String? id,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    bool? enabled,
  }) {
    return TimeSlot(
      id: id ?? this.id,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'enabled': enabled,
      };

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
        id: json['id'] as String,
        startHour: json['startHour'] as int,
        startMinute: json['startMinute'] as int,
        endHour: json['endHour'] as int,
        endMinute: json['endMinute'] as int,
        enabled: (json['enabled'] as bool?) ?? true,
      );
}

class DaySchedule {
  /// 0 = Saturday (شنبه) ... 6 = Friday (جمعه)
  final int dayIndex;
  final bool enabled;
  final List<TimeSlot> slots;
  final SyncStatus syncStatus;

  const DaySchedule({
    required this.dayIndex,
    this.enabled = true,
    this.slots = const [],
    this.syncStatus = SyncStatus.localDraft,
  });

  bool get syncedWithDevice =>
      syncStatus == SyncStatus.syncedDemo || syncStatus == SyncStatus.confirmed;

  DaySchedule copyWith({
    int? dayIndex,
    bool? enabled,
    List<TimeSlot>? slots,
    SyncStatus? syncStatus,
  }) {
    return DaySchedule(
      dayIndex: dayIndex ?? this.dayIndex,
      enabled: enabled ?? this.enabled,
      slots: slots ?? this.slots,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'dayIndex': dayIndex,
        'enabled': enabled,
        'slots': slots.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.name,
      };

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['syncStatus'] as String?;
    SyncStatus resolvedStatus;
    if (rawStatus != null) {
      resolvedStatus = SyncStatus.values.firstWhere(
        (e) => e.name == rawStatus,
        orElse: () => SyncStatus.localDraft,
      );
    } else {
      final legacySynced = (json['syncedWithDevice'] as bool?) ?? false;
      resolvedStatus =
          legacySynced ? SyncStatus.syncedDemo : SyncStatus.localDraft;
    }

    return DaySchedule(
      dayIndex: json['dayIndex'] as int,
      enabled: (json['enabled'] as bool?) ?? true,
      slots: (json['slots'] as List<dynamic>? ?? [])
          .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
      syncStatus: resolvedStatus,
    );
  }
}

class AuthorizedUser {
  final String id;
  final String name;
  final String phoneNumber;
  final DeviceUserRole role;
  final int avatarIndex;
  final SyncStatus syncStatus;

  const AuthorizedUser({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.role,
    this.avatarIndex = 0,
    this.syncStatus = SyncStatus.localDraft,
  });

  AuthorizedUser copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    DeviceUserRole? role,
    int? avatarIndex,
    SyncStatus? syncStatus,
  }) {
    return AuthorizedUser(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'role': role.name,
        'avatarIndex': avatarIndex,
        'syncStatus': syncStatus.name,
      };

  factory AuthorizedUser.fromJson(Map<String, dynamic> json) => AuthorizedUser(
        id: json['id'] as String,
        name: json['name'] as String,
        phoneNumber: json['phoneNumber'] as String,
        role: DeviceUserRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => DeviceUserRole.user,
        ),
        avatarIndex: (json['avatarIndex'] as int?) ?? 0,
        syncStatus: SyncStatus.values.firstWhere(
          (e) => e.name == json['syncStatus'],
          orElse: () => SyncStatus.localDraft,
        ),
      );
}

class KarenDevice {
  final String id;
  final String title;
  final String phoneNumber;
  final String locationLabel;
  final DevicePowerState powerState;
  final OperatingMode operatingMode;
  final bool powerOutageAlertEnabled;
  final bool powerOutageAlertSilenced;
  final DateTime? lastSyncedAt;
  final DateTime? deviceClockSyncedAt;
  final String? pendingActionSummary;
  final List<DaySchedule> weeklySchedules;
  final List<AuthorizedUser> authorizedUsers;

  const KarenDevice({
    required this.id,
    required this.title,
    required this.phoneNumber,
    this.locationLabel = '',
    this.powerState = DevicePowerState.unknown,
    this.operatingMode = OperatingMode.manual,
    this.powerOutageAlertEnabled = true,
    this.powerOutageAlertSilenced = false,
    this.lastSyncedAt,
    this.deviceClockSyncedAt,
    this.pendingActionSummary,
    required this.weeklySchedules,
    this.authorizedUsers = const [],
  });

  static List<DaySchedule> defaultWeeklySchedules() {
    return List.generate(7, (index) => DaySchedule(dayIndex: index));
  }

  int get activeScheduleDaysCount =>
      weeklySchedules.where((d) => d.enabled && d.slots.isNotEmpty).length;

  int get totalSlotsCount =>
      weeklySchedules.fold(0, (sum, d) => sum + d.slots.length);

  KarenDevice copyWith({
    String? id,
    String? title,
    String? phoneNumber,
    String? locationLabel,
    DevicePowerState? powerState,
    OperatingMode? operatingMode,
    bool? powerOutageAlertEnabled,
    bool? powerOutageAlertSilenced,
    DateTime? lastSyncedAt,
    DateTime? deviceClockSyncedAt,
    String? pendingActionSummary,
    bool clearPendingAction = false,
    List<DaySchedule>? weeklySchedules,
    List<AuthorizedUser>? authorizedUsers,
  }) {
    return KarenDevice(
      id: id ?? this.id,
      title: title ?? this.title,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      locationLabel: locationLabel ?? this.locationLabel,
      powerState: powerState ?? this.powerState,
      operatingMode: operatingMode ?? this.operatingMode,
      powerOutageAlertEnabled:
          powerOutageAlertEnabled ?? this.powerOutageAlertEnabled,
      powerOutageAlertSilenced:
          powerOutageAlertSilenced ?? this.powerOutageAlertSilenced,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      deviceClockSyncedAt: deviceClockSyncedAt ?? this.deviceClockSyncedAt,
      pendingActionSummary: clearPendingAction
          ? null
          : (pendingActionSummary ?? this.pendingActionSummary),
      weeklySchedules: weeklySchedules ?? this.weeklySchedules,
      authorizedUsers: authorizedUsers ?? this.authorizedUsers,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'phoneNumber': phoneNumber,
        'locationLabel': locationLabel,
        'powerState': powerState.name,
        'operatingMode': operatingMode.name,
        'powerOutageAlertEnabled': powerOutageAlertEnabled,
        'powerOutageAlertSilenced': powerOutageAlertSilenced,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'deviceClockSyncedAt': deviceClockSyncedAt?.toIso8601String(),
        'pendingActionSummary': pendingActionSummary,
        'weeklySchedules': weeklySchedules.map((e) => e.toJson()).toList(),
        'authorizedUsers': authorizedUsers.map((e) => e.toJson()).toList(),
      };

  factory KarenDevice.fromJson(Map<String, dynamic> json) => KarenDevice(
        id: json['id'] as String,
        title: json['title'] as String,
        phoneNumber: json['phoneNumber'] as String,
        locationLabel: (json['locationLabel'] as String?) ?? '',
        powerState: DevicePowerState.values.firstWhere(
          (e) => e.name == json['powerState'],
          orElse: () => DevicePowerState.unknown,
        ),
        operatingMode: OperatingMode.values.firstWhere(
          (e) => e.name == json['operatingMode'],
          orElse: () => OperatingMode.manual,
        ),
        powerOutageAlertEnabled:
            (json['powerOutageAlertEnabled'] as bool?) ?? true,
        powerOutageAlertSilenced:
            (json['powerOutageAlertSilenced'] as bool?) ?? false,
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
        deviceClockSyncedAt: json['deviceClockSyncedAt'] != null
            ? DateTime.tryParse(json['deviceClockSyncedAt'] as String)
            : null,
        pendingActionSummary: json['pendingActionSummary'] as String?,
        weeklySchedules: (json['weeklySchedules'] as List<dynamic>?)
                ?.map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
                .toList() ??
            defaultWeeklySchedules(),
        authorizedUsers: (json['authorizedUsers'] as List<dynamic>? ?? [])
            .map((e) => AuthorizedUser.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CommandLogEntry {
  final String id;
  final String deviceId;
  final String deviceTitle;
  final String actionTitle;
  final CommandCategory category;
  final TransportMode transportMode;
  final CommandLogStatus status;
  final String payloadPreview;
  final String? responseSummary;
  final DateTime timestamp;

  const CommandLogEntry({
    required this.id,
    required this.deviceId,
    required this.deviceTitle,
    required this.actionTitle,
    required this.category,
    required this.transportMode,
    required this.status,
    required this.payloadPreview,
    this.responseSummary,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'deviceTitle': deviceTitle,
        'actionTitle': actionTitle,
        'category': category.name,
        'transportMode': transportMode.name,
        'status': status.name,
        'payloadPreview': payloadPreview,
        'responseSummary': responseSummary,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CommandLogEntry.fromJson(Map<String, dynamic> json) => CommandLogEntry(
        id: json['id'] as String,
        deviceId: json['deviceId'] as String,
        deviceTitle: json['deviceTitle'] as String,
        actionTitle: json['actionTitle'] as String,
        category: CommandCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => CommandCategory.power,
        ),
        transportMode: TransportMode.values.firstWhere(
          (e) => e.name == json['transportMode'],
          orElse: () => TransportMode.demo,
        ),
        status: CommandLogStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => CommandLogStatus.pendingConfirmation,
        ),
        payloadPreview: json['payloadPreview'] as String,
        responseSummary: json['responseSummary'] as String?,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class AppSettings {
  final ThemeMode themeMode;
  final TransportMode transportMode;
  final bool confirmPowerActions;
  final bool pinLockEnabled;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.transportMode = TransportMode.demo,
    this.confirmPowerActions = true,
    this.pinLockEnabled = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    TransportMode? transportMode,
    bool? confirmPowerActions,
    bool? pinLockEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      transportMode: transportMode ?? this.transportMode,
      confirmPowerActions: confirmPowerActions ?? this.confirmPowerActions,
      pinLockEnabled: pinLockEnabled ?? this.pinLockEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'transportMode': transportMode.name,
        'confirmPowerActions': confirmPowerActions,
        'pinLockEnabled': pinLockEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (e) => e.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        transportMode: TransportMode.values.firstWhere(
          (e) => e.name == json['transportMode'],
          orElse: () => TransportMode.demo,
        ),
        confirmPowerActions: (json['confirmPowerActions'] as bool?) ?? true,
        pinLockEnabled: (json['pinLockEnabled'] as bool?) ?? false,
      );
}
