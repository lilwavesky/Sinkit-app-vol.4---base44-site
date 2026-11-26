import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/karen_models.dart';
import '../../core/security/pin_hasher.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';
import 'operating_mode_sheet.dart';

Future<void> showDeviceSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _DeviceSettingsSheet(),
  );
}

class _DeviceSettingsSheet extends ConsumerWidget {
  const _DeviceSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(karenControllerProvider);
    final device = appState.activeDevice;
    final settings = appState.settings;
    final templates = appState.templates;
    final notifier = ref.read(karenControllerProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (_, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'تنظیمات دستگاه و برنامه',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Section 1: Confirmed KAREN 1.0.0 Device Settings Actions
            Text(
              device == null
                  ? 'تنظیمات دستگاه (ابتدا دستگاهی انتخاب کنید)'
                  : 'فرمان‌های تنظیمات «${device.title}»',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            _SettingActionCard(
              icon: Icons.notifications_off_outlined,
              iconColor: KarenColors.warningAmber,
              title: 'قطع کردن اخطار قطع برق',
              subtitle: 'توقف موقت یا بی‌صدا کردن هشدار فعلی قطع برق دستگاه',
              enabled: device != null && !appState.isBusy,
              onTap: () async {
                final res = await notifier.silencePowerOutageAlert();
                if (!context.mounted) return;
                showKarenSnackBar(
                  context,
                  message: res.messageFa,
                  isError: !res.dispatched,
                );
              },
            ),
            const SizedBox(height: 8),
            _SettingActionCard(
              icon: device?.powerOutageAlertEnabled == false
                  ? Icons.notifications_active_outlined
                  : Icons.do_not_disturb_on_outlined,
              iconColor: KarenColors.dangerRed,
              title: device?.powerOutageAlertEnabled == false
                  ? 'فعال کردن اخطار قطع برق'
                  : 'غیرفعال کردن اخطار قطع برق',
              subtitle: device?.powerOutageAlertEnabled == false
                  ? 'وضعیت فعلی: غیرفعال — برای فعال‌سازی مجدد لمس کنید'
                  : 'غیرفعال‌سازی دائمی ارسال پیامک هشدار هنگام قطع برق',
              enabled: device != null && !appState.isBusy,
              onTap: () async {
                final nextEnable = !(device?.powerOutageAlertEnabled ?? true);
                final res = await notifier.setPowerOutageAlertEnabled(nextEnable);
                if (!context.mounted) return;
                showKarenSnackBar(
                  context,
                  message: res.messageFa,
                  isError: !res.dispatched,
                );
              },
            ),
            const SizedBox(height: 8),
            _SettingActionCard(
              icon: Icons.tune_rounded,
              iconColor: KarenColors.brandPurple,
              title: 'تنظیمات حالت کارکرد',
              subtitle: device == null
                  ? 'انتخاب حالت دستی، خودکار یا ترکیبی'
                  : 'حالت فعلی: ${device.operatingMode.labelFa}',
              enabled: device != null,
              onTap: () {
                Navigator.of(context).pop();
                showOperatingModeSheet(context);
              },
            ),
            const SizedBox(height: 8),
            _SettingActionCard(
              icon: Icons.admin_panel_settings_outlined,
              iconColor: KarenColors.brandBlue,
              title: 'تعریف مدیر',
              subtitle: 'ثبت یا مشاهده شماره‌های مدیر دستگاه',
              enabled: device != null,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/users/admin');
              },
            ),
            const SizedBox(height: 8),
            _SettingActionCard(
              icon: Icons.person_add_outlined,
              iconColor: KarenColors.successGreen,
              title: 'تعریف کاربر',
              subtitle: 'مدیریت کاربران مجاز با آواتار اختصاصی',
              enabled: device != null,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/users/member');
              },
            ),

            const Divider(height: 32),

            // Section 2: Transport, Security & Theme
            const Text(
              'حالت ارتباط، امنیت و ظاهر برنامه',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حالت ارسال فرمان‌ها',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<TransportMode>(
                      segments: const [
                        ButtonSegment(
                          value: TransportMode.demo,
                          icon: Icon(Icons.science_outlined),
                          label: Text('حالت دمو'),
                        ),
                        ButtonSegment(
                          value: TransportMode.liveSmsComposer,
                          icon: Icon(Icons.sms_outlined),
                          label: Text('پیامک واقعی'),
                        ),
                      ],
                      selected: {settings.transportMode},
                      onSelectionChanged: (selection) async {
                        final err = await notifier.updateSettings(
                          settings.copyWith(transportMode: selection.first),
                        );
                        if (context.mounted && err != null) {
                          showKarenSnackBar(context, message: err, isError: true);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.transportMode == TransportMode.demo
                          ? 'در حالت دمو تمام عملیات به‌صورت محلی شبیه‌سازی می‌شوند و هیچ پیامکی ارسال نمی‌شود.'
                          : 'در حالت پیامک واقعی، فقط فرمان‌های دارای قالب تاییدشده به برنامه پیامک گوشی منتقل می‌شوند و وضعیت دستگاه تا زمان دریافت تاییدیه واقعی تغییر نمی‌کند.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    if (settings.transportMode == TransportMode.liveSmsComposer &&
                        templates.hasAnyUnverified) ...[
                      const SizedBox(height: 12),
                      UnverifiedProtocolWarningBanner(
                        unverifiedCount: templates.unverifiedCount,
                        totalCount: templates.totalCount,
                        onOpenTemplates: () {
                          Navigator.of(context).pop();
                          context.push('/protocol-templates');
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('تایید قبل از روشن/خاموش کردن'),
                    subtitle: const Text('جلوگیری از لمس اشتباهی فرمان‌های برق'),
                    value: settings.confirmPowerActions,
                    onChanged: (v) async {
                      final err = await notifier.updateSettings(
                        settings.copyWith(confirmPowerActions: v),
                      );
                      if (context.mounted && err != null) {
                        showKarenSnackBar(context, message: err, isError: true);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('قفل امنیتی برنامه (رمز ۴ رقمی)'),
                    subtitle: Text(
                      settings.pinLockEnabled
                          ? 'فعال (PBKDF2-HMAC-SHA256 + قفل خودکار پس‌زمینه)'
                          : (appState.pinCleanupWarning ?? 'غیرفعال'),
                    ),
                    value: settings.pinLockEnabled,
                    onChanged: (enable) async {
                      if (!enable) {
                        final res = await notifier.setPinLock(null);
                        if (!context.mounted) return;
                        showKarenSnackBar(
                          context,
                          message: res.messageFa,
                          isError: !res.succeeded || res.hasCleanupWarning,
                        );
                        return;
                      }
                      final pin = await _promptPinDialog(
                        context,
                        title: 'تعیین رمز ۴ رقمی',
                      );
                      if (pin != null) {
                        final res = await notifier.setPinLock(pin);
                        if (!context.mounted) return;
                        showKarenSnackBar(
                          context,
                          message: res.messageFa,
                          isError: !res.succeeded,
                        );
                      }
                    },
                  ),
                  if (settings.pinLockEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.password_rounded),
                      title: const Text('تغییر رمز ۴ رقمی (چرخش امن رمز)'),
                      subtitle: const Text(
                        'تراکنش امن با بازگردانی تاییدشده در صورت بروز خطا',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final newPin = await _promptPinDialog(
                          context,
                          title: 'تغییر رمز ۴ رقمی',
                        );
                        if (newPin == null) return;
                        final res = await notifier.setPinLock(newPin);
                        if (!context.mounted) return;
                        showKarenSnackBar(
                          context,
                          message: res.messageFa,
                          isError: !res.succeeded,
                        );
                      },
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dark_mode_outlined),
                    title: const Text('پوسته برنامه'),
                    trailing: DropdownButton<ThemeMode>(
                      value: settings.themeMode,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('خودکار'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('روشن'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('تاریک'),
                        ),
                      ],
                      onChanged: (mode) async {
                        if (mode != null) {
                          final err = await notifier.updateSettings(
                            settings.copyWith(themeMode: mode),
                          );
                          if (context.mounted && err != null) {
                            showKarenSnackBar(context, message: err, isError: true);
                          }
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.code_rounded),
                    title: const Text('تنظیم قالب فرمان‌های پیامکی'),
                    subtitle: const Text('سفارشی‌سازی کدهای پروتکل سخت‌افزار کارن'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/protocol-templates');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.speed_rounded),
                    title: const Text('آزمون سرعت رمزنگاری (PBKDF2)'),
                    subtitle: const Text(
                      'مقایسه زمان ۱۰۰٬۰۰۰ دور (پیش‌فرض موبایل) و ۶۰۰٬۰۰۰ دور (مرجع OWASP) روی این گوشی',
                    ),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: () {
                      final bench100k = PinHasher.benchmarkPbkdf2(
                        iterations: PinHasher.defaultIterations,
                      );
                      final bench600k = PinHasher.benchmarkPbkdf2(
                        iterations:
                            PinHasher.owaspRecommendedPbkdf2Sha256Iterations,
                      );
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('نتیجه بنچمارک امنیتی دستگاه'),
                          content: Text(
                            'الگوریتم: ${bench100k.algorithm} (طول کلید: ${PersianUtils.toPersianDigits(bench100k.keyLengthBytes.toString())} بایت)\n\n'
                            '• ۱۰۰٬۰۰۰ دور (پیش‌فرض): ${PersianUtils.toPersianDigits(bench100k.elapsedMilliseconds.toStringAsFixed(1))} میلی‌ثانیه (${bench100k.isResponsiveForMobileUi ? "روان برای موبایل" : "سنگین روی این گوشی"})\n'
                            '• ۶۰۰٬۰۰۰ دور (مرجع OWASP): ${PersianUtils.toPersianDigits(bench600k.elapsedMilliseconds.toStringAsFixed(1))} میلی‌ثانیه (${bench600k.isResponsiveForMobileUi ? "قابل استفاده روی این گوشی" : "کند در Dart خالص — نیازمند Argon2id بومی"})\n\n'
                            'توصیه OWASP: برای سیستم‌های جدید، Argon2id بومی (FFI) بهترین مقاومت در برابر GPU با زمان پاسخ کوتاه‌تر است.',
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('بستن'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptPinDialog(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'مثلاً 1234',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = PinHasher.normalizePin(controller.text);
                if (!PinHasher.isValidPinFormat(normalized)) {
                  setDialogState(
                    () => errorText = 'رمز عبور باید دقیقاً ۴ رقم عددی باشد',
                  );
                  return;
                }
                Navigator.pop(ctx, normalized);
              },
              child: const Text('ثبت رمز'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }
}

class _SettingActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _SettingActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.14),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
