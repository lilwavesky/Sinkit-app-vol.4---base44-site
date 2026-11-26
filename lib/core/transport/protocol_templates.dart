/// IMPORTANT TRANSPARENCY & SAFETY NOTICE:
/// Because the original KAREN 1.0.0 APK did not expose plaintext hardware SMS
/// command protocols during static analysis, every default template below is
/// explicitly marked as an UNVERIFIED PLACEHOLDER (`[UNVERIFIED:...]`).
///
/// Live SMS dispatch strictly blocks any empty template, any `[UNVERIFIED:...]`
/// marker, or any unresolved `{placeholder}` variable until the user enters
/// verified Karen Electronic hardware commands.
class ProtocolTemplates {
  final Map<String, String> templates;

  const ProtocolTemplates(this.templates);

  static const String keyPowerOn = 'power_on';
  static const String keyPowerOff = 'power_off';
  static const String keySilenceOutageAlert = 'silence_outage_alert';
  static const String keyDisableOutageAlert = 'disable_outage_alert';
  static const String keyEnableOutageAlert = 'enable_outage_alert';
  static const String keyOperatingMode = 'operating_mode';
  static const String keyDefineAdmin = 'define_admin';
  static const String keyDefineUser = 'define_user';
  static const String keySetDay = 'set_day';
  static const String keySetDayHours = 'set_day_hours';
  static const String keySetDailyRoutine = 'set_daily_routine';
  static const String keyGeneralReport = 'general_report';
  static const String keySyncClock = 'sync_clock';
  static const String keyRetrieveDays = 'retrieve_days';

  static const Map<String, String> labelsFa = {
    keyPowerOn: 'روشن کردن دستگاه',
    keyPowerOff: 'خاموش کردن دستگاه',
    keySilenceOutageAlert: 'قطع کردن اخطار قطع برق',
    keyDisableOutageAlert: 'غیرفعال کردن اخطار قطع برق',
    keyEnableOutageAlert: 'فعال کردن اخطار قطع برق',
    keyOperatingMode: 'تنظیم حالت کارکرد',
    keyDefineAdmin: 'تعریف مدیر',
    keyDefineUser: 'تعریف کاربر',
    keySetDay: 'تنظیم روز',
    keySetDayHours: 'تنظیم ساعات روز',
    keySetDailyRoutine: 'تنظیم روزانه',
    keyGeneralReport: 'گزارشگیری کلی',
    keySyncClock: 'تنظیم ساعت دستگاه',
    keyRetrieveDays: 'بازیابی زمان روزها',
  };

  static final RegExp _unverifiedPattern = RegExp(
    r'\[?\s*UNVERIFIED\s*:',
    caseSensitive: false,
  );

  static final RegExp _unresolvedParamPattern = RegExp(r'\{[a-zA-Z0-9_]+\}');

  factory ProtocolTemplates.unverifiedDefaults() {
    return const ProtocolTemplates({
      keyPowerOn: '[UNVERIFIED:POWER_ON]',
      keyPowerOff: '[UNVERIFIED:POWER_OFF]',
      keySilenceOutageAlert: '[UNVERIFIED:MUTE_OUTAGE_ALERT]',
      keyDisableOutageAlert: '[UNVERIFIED:DISABLE_OUTAGE_ALERT]',
      keyEnableOutageAlert: '[UNVERIFIED:ENABLE_OUTAGE_ALERT]',
      keyOperatingMode: '[UNVERIFIED:SET_MODE:{mode}]',
      keyDefineAdmin: '[UNVERIFIED:ADD_ADMIN:{phone}]',
      keyDefineUser: '[UNVERIFIED:ADD_USER:{phone}]',
      keySetDay: '[UNVERIFIED:SET_DAY:{day}:{state}]',
      keySetDayHours: '[UNVERIFIED:SET_HOURS:{day}:{slots}]',
      keySetDailyRoutine: '[UNVERIFIED:SET_DAILY:{slots}]',
      keyGeneralReport: '[UNVERIFIED:GENERAL_REPORT]',
      keySyncClock: '[UNVERIFIED:SET_CLOCK:{time}]',
      keyRetrieveDays: '[UNVERIFIED:GET_DAYS_SCHEDULE]',
    });
  }

  static bool containsUnverifiedMarker(String text) {
    return _unverifiedPattern.hasMatch(text);
  }

  static bool containsUnresolvedParams(String text) {
    return _unresolvedParamPattern.hasMatch(text);
  }

  String rawTemplate(String key) => templates[key] ?? '';

  bool isEmptyOrBlank(String key) => rawTemplate(key).trim().isEmpty;

  bool isPlaceholder(String key) {
    final value = rawTemplate(key);
    return value.trim().isEmpty || containsUnverifiedMarker(value);
  }

  bool isVerified(String key) => !isEmptyOrBlank(key) && !isPlaceholder(key);

  int get totalCount => labelsFa.length;

  int get verifiedCount =>
      labelsFa.keys.where((key) => isVerified(key)).length;

  int get unverifiedCount => totalCount - verifiedCount;

  bool get hasAnyUnverified => unverifiedCount > 0;

  bool get isAllVerified => unverifiedCount == 0;

  String render(String key, [Map<String, String> params = const {}]) {
    final raw = rawTemplate(key);
    if (raw.trim().isEmpty) return '';
    var result = raw;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result.trim();
  }

  /// Validates a template & rendered payload for Live SMS mode.
  /// Returns a Persian error message if blocked, or null if safe to open SMS composer.
  String? validateForLiveSms(String key, String renderedPayload) {
    final raw = rawTemplate(key).trim();
    if (raw.isEmpty || renderedPayload.trim().isEmpty) {
      return 'قالب فرمان خالی است. ارسال پیامک خالی در حالت واقعی مسدود شده است.';
    }
    if (containsUnverifiedMarker(raw) ||
        containsUnverifiedMarker(renderedPayload)) {
      return 'ارسال مسدود شد: قالب این فرمان هنوز تاییدنشده ([UNVERIFIED]) است. ابتدا کد رسمی سخت‌افزار کارن را در «تنظیم قالب فرمان‌های پیامکی» وارد کنید.';
    }
    if (containsUnresolvedParams(renderedPayload)) {
      return 'ارسال مسدود شد: برخی متغیرهای قالب فرمان مقداردهی نشده‌اند.';
    }
    return null;
  }

  /// Validates a user-entered template before saving in the editor.
  static String? validateUserTemplateInput(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'متن قالب فرمان نمی‌تواند خالی باشد';
    }
    if (containsUnverifiedMarker(input)) {
      return 'برای تایید قالب، عبارت [UNVERIFIED:...] را با کد واقعی سخت‌افزار جایگزین کنید';
    }
    return null;
  }

  ProtocolTemplates copyWithEntry(String key, String value) {
    return ProtocolTemplates({...templates, key: value.trim()});
  }

  Map<String, dynamic> toJson() => templates;

  factory ProtocolTemplates.fromJson(Map<String, dynamic> json) {
    final defaults = ProtocolTemplates.unverifiedDefaults().templates;
    final merged = <String, String>{...defaults};
    for (final entry in json.entries) {
      if (entry.value is String) {
        merged[entry.key] = entry.value as String;
      }
    }
    return ProtocolTemplates(merged);
  }
}
