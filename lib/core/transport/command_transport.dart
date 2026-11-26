import 'package:url_launcher/url_launcher.dart';

import '../models/karen_models.dart';
import '../utils/persian_utils.dart';
import 'protocol_templates.dart';

typedef SmsUrlLauncher = Future<bool> Function(Uri uri);

class CommandDispatchRequest {
  final KarenDevice device;
  final String actionKey;
  final String actionTitle;
  final CommandCategory category;
  final String rawTemplate;
  final String payload;
  final bool isPlaceholderTemplate;

  const CommandDispatchRequest({
    required this.device,
    required this.actionKey,
    required this.actionTitle,
    required this.category,
    required this.rawTemplate,
    required this.payload,
    required this.isPlaceholderTemplate,
  });
}

class CommandDispatchResult {
  /// Whether the transport action itself completed (simulator ran OR SMS app opened).
  final bool dispatched;

  /// True ONLY when executed inside DemoCommandTransport (local simulator).
  /// Device state should ONLY be optimistically updated when this is true.
  final bool isSimulatedExecution;

  /// True when Android's SMS composer was opened and hardware confirmation is still pending.
  final bool isPendingConfirmation;

  final CommandLogStatus status;
  final String messageFa;
  final String? simulatedReplyFa;

  const CommandDispatchResult({
    required this.dispatched,
    required this.isSimulatedExecution,
    required this.isPendingConfirmation,
    required this.status,
    required this.messageFa,
    this.simulatedReplyFa,
  });

  bool get isBlocked => status == CommandLogStatus.blockedUnverified;
}

abstract class CommandTransport {
  TransportMode get mode;
  Future<CommandDispatchResult> dispatch(CommandDispatchRequest request);
}

/// Clearly separated local simulator for full feature evaluation without real
/// hardware or SMS costs. Never misrepresents simulated operations as real SMS.
class DemoCommandTransport implements CommandTransport {
  final Duration latency;

  const DemoCommandTransport({
    this.latency = const Duration(milliseconds: 350),
  });

  @override
  TransportMode get mode => TransportMode.demo;

  @override
  Future<CommandDispatchResult> dispatch(CommandDispatchRequest request) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }

    final timeStr = PersianUtils.formatDateTimeShort(DateTime.now());
    final reply = switch (request.actionKey) {
      ProtocolTemplates.keyPowerOn =>
        '[پاسخ شبیه‌سازی دمو] دستگاه «${request.device.title}» با موفقیت روشن شد ($timeStr).',
      ProtocolTemplates.keyPowerOff =>
        '[پاسخ شبیه‌سازی دمو] دستگاه «${request.device.title}» با موفقیت خاموش شد ($timeStr).',
      ProtocolTemplates.keyGeneralReport =>
        '[گزارش شبیه‌سازی دمو]\n'
            'وضعیت برق خروجی: ${request.device.powerState.labelFa}\n'
            'حالت کارکرد: ${request.device.operatingMode.labelFa}\n'
            'اخطار قطع برق: ${request.device.powerOutageAlertEnabled ? "فعال" : "غیرفعال"}\n'
            'روزهای دارای زمان‌بندی: ${PersianUtils.toPersianDigits(request.device.activeScheduleDaysCount.toString())} روز\n'
            'کاربران مجاز: ${PersianUtils.toPersianDigits(request.device.authorizedUsers.length.toString())} نفر\n'
            'زمان ثبت: $timeStr',
      ProtocolTemplates.keySyncClock =>
        '[پاسخ شبیه‌سازی دمو] ساعت دستگاه با زمان $timeStr همگام‌سازی شد.',
      ProtocolTemplates.keyRetrieveDays =>
        '[پاسخ شبیه‌سازی دمو] ${PersianUtils.toPersianDigits(request.device.totalSlotsCount.toString())} بازه زمانی در ${PersianUtils.toPersianDigits(request.device.activeScheduleDaysCount.toString())} روز بازیابی شد.',
      _ =>
        '[پاسخ شبیه‌سازی دمو] فرمان «${request.actionTitle}» با موفقیت در شبیه‌ساز اجرا شد.',
    };

    return CommandDispatchResult(
      dispatched: true,
      isSimulatedExecution: true,
      isPendingConfirmation: false,
      status: CommandLogStatus.simulatedSuccess,
      messageFa: 'عملیات در حالت دمو (شبیه‌ساز) با موفقیت انجام شد.',
      simulatedReplyFa: reply,
    );
  }
}

/// Real Android SMS composer handoff (`sms:` URI).
/// - Completely blocks empty templates, `[UNVERIFIED:...]` placeholders, and unresolved variables.
/// - Never reports opening the SMS composer as confirmed hardware execution.
class SmsComposerCommandTransport implements CommandTransport {
  final SmsUrlLauncher? _launcher;

  const SmsComposerCommandTransport({SmsUrlLauncher? launcher})
      : _launcher = launcher;

  @override
  TransportMode get mode => TransportMode.liveSmsComposer;

  Future<bool> _launch(Uri uri) {
    final customLauncher = _launcher;
    if (customLauncher != null) {
      return customLauncher(uri);
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<CommandDispatchResult> dispatch(CommandDispatchRequest request) async {
    final phone = PersianUtils.normalizeIranPhone(request.device.phoneNumber);
    if (PersianUtils.validateIranPhone(phone) != null) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.failed,
        messageFa: 'شماره همراه دستگاه معتبر نیست.',
      );
    }

    // Security Gate 1: Reject empty/whitespace template or payload.
    final raw = request.rawTemplate.trim();
    final payload = request.payload.trim();
    if (raw.isEmpty || payload.isEmpty) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.blockedUnverified,
        messageFa:
            'ارسال مسدود شد: قالب فرمان خالی است. ارسال پیامک خالی مجاز نیست.',
      );
    }

    // Security Gate 2: Strictly block any [UNVERIFIED:...] placeholder template.
    if (request.isPlaceholderTemplate ||
        ProtocolTemplates.containsUnverifiedMarker(raw) ||
        ProtocolTemplates.containsUnverifiedMarker(payload)) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.blockedUnverified,
        messageFa:
            'ارسال مسدود شد: قالب این فرمان هنوز تاییدنشده ([UNVERIFIED]) است. ابتدا کد رسمی سخت‌افزار کارن را در تنظیمات قالب‌ها وارد کنید.',
      );
    }

    // Security Gate 3: Block unresolved parameter tokens like {phone} or {slots}.
    if (ProtocolTemplates.containsUnresolvedParams(payload)) {
      return const CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.blockedUnverified,
        messageFa:
            'ارسال مسدود شد: بخشی از متغیرهای قالب فرمان مقداردهی نشده‌اند.',
      );
    }

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': payload},
    );

    try {
      final launched = await _launch(uri);
      if (!launched) {
        return const CommandDispatchResult(
          dispatched: false,
          isSimulatedExecution: false,
          isPendingConfirmation: false,
          status: CommandLogStatus.failed,
          messageFa: 'امکان باز کردن برنامه پیامک روی این دستگاه وجود ندارد.',
        );
      }

      // Honest pending state: opening the SMS composer does NOT mean hardware executed anything.
      return const CommandDispatchResult(
        dispatched: true,
        isSimulatedExecution: false,
        isPendingConfirmation: true,
        status: CommandLogStatus.pendingConfirmation,
        messageFa:
            'برنامه پیامک باز شد (در انتظار ارسال و تایید دستگاه). وضعیت دستگاه تا دریافت پاسخ سخت‌افزار تغییر نمی‌کند.',
      );
    } catch (e) {
      return CommandDispatchResult(
        dispatched: false,
        isSimulatedExecution: false,
        isPendingConfirmation: false,
        status: CommandLogStatus.failed,
        messageFa: 'خطا در فراخوانی برنامه پیامک: $e',
      );
    }
  }
}
