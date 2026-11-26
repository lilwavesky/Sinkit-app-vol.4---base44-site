import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/karen_models.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';
import '../devices/device_drawer.dart';
import '../devices/device_form_sheet.dart';
import '../settings/device_settings_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _handlePowerCommand(
    BuildContext context,
    WidgetRef ref,
    bool turnOn,
  ) async {
    final appState = ref.read(karenControllerProvider);
    final device = appState.activeDevice;
    if (device == null) return;

    if (appState.settings.confirmPowerActions) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            turnOn ? 'تایید روشن کردن دستگاه' : 'تایید خاموش کردن دستگاه',
          ),
          content: Text(
            'آیا مطمئن هستید که فرمان «${turnOn ? "روشن" : "خاموش"}» برای دستگاه «${device.title}» اجرا شود؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    turnOn ? KarenColors.successGreen : KarenColors.dangerRed,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(turnOn ? 'بله، روشن شود' : 'بله، خاموش شود'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await HapticFeedback.mediumImpact();
    final res =
        await ref.read(karenControllerProvider.notifier).setPower(turnOn);
    if (!context.mounted) return;
    showKarenSnackBar(
      context,
      message: res.messageFa,
      isError: !res.dispatched,
    );
  }

  Future<void> _confirmResetCorrupted(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تایید پاکسازی بخش آسیب‌دیده'),
        content: const Text(
          'اگر تلاش مجدد موفق نبود، این گزینه فقط کلیدهای آسیب‌دیده در حافظه امن را پاک می‌کند تا برنامه دوباره قابل استفاده شود. آیا مطمئن هستید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KarenColors.dangerRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاکسازی و بازنشانی'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final res = await ref
        .read(karenControllerProvider.notifier)
        .resetAffectedCorruptedStores();
    if (!context.mounted) return;
    showKarenSnackBar(context, message: res.messageFa, isError: !res.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(karenControllerProvider);
    final device = appState.activeDevice;
    final notifier = ref.read(karenControllerProvider.notifier);
    final showUnverifiedWarning =
        appState.settings.transportMode == TransportMode.liveSmsComposer &&
            appState.templates.hasAnyUnverified;

    return Scaffold(
      drawer: const DeviceListDrawer(),
      appBar: AppBar(
        title: const Text('کارن الکترونیک'),
        leading: Builder(
          builder: (ctx) => IconButton(
            key: const Key('btn_open_drawer'),
            tooltip: 'لیست دستگاه‌ها',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            key: const Key('btn_add_device'),
            tooltip: 'ثبت شماره جدید',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: appState.isDevicesWriteProtected
                ? () => showKarenSnackBar(
                      context,
                      message:
                          'تا زمان بازیابی حافظه امن، ثبت دستگاه جدید برای حفظ داده‌های قبلی مسدود است.',
                      isError: true,
                    )
                : () => showDeviceFormSheet(context),
          ),
          IconButton(
            key: const Key('btn_open_settings'),
            tooltip: 'تنظیمات دستگاه',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showDeviceSettingsSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ModeStatusPill(
                mode: appState.settings.transportMode,
                onTap: () => showDeviceSettingsSheet(context),
              ),
              if (device != null && device.lastSyncedAt != null)
                Text(
                  'آخرین بروزرسانی: ${PersianUtils.formatDateTimeShort(device.lastSyncedAt!)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
            ],
          ),
          if (showUnverifiedWarning) ...[
            const SizedBox(height: 12),
            UnverifiedProtocolWarningBanner(
              unverifiedCount: appState.templates.unverifiedCount,
              totalCount: appState.templates.totalCount,
              onOpenTemplates: () => context.push('/protocol-templates'),
            ),
          ],
          const SizedBox(height: 14),
          if (appState.isDevicesWriteProtected)
            StorageRecoveryCard(
              status: appState.devicesStorageStatus,
              isBusy: appState.isBusy,
              onRetry: () async {
                final ok = await notifier.retrySecureStorageLoad();
                if (!context.mounted) return;
                showKarenSnackBar(
                  context,
                  message: ok
                      ? 'داده‌های حافظه امن با موفقیت بازیابی شدند'
                      : 'بازیابی حافظه امن همچنان ناموفق است',
                  isError: !ok,
                );
              },
              onResetCorrupted: () => _confirmResetCorrupted(context, ref),
            )
          else if (device == null)
            EmptyDeviceStateCard(
              onAddDevice: () => showDeviceFormSheet(context),
              onLoadDemoDevice: () async {
                final err = await notifier.seedDemoDevice();
                if (context.mounted && err != null) {
                  showKarenSnackBar(context, message: err, isError: true);
                }
              },
            )
          else ...[
            if (device.pendingActionSummary != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KarenColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: KarenColors.brandBlue.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      size: 18,
                      color: KarenColors.brandBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        device.pendingActionSummary!,
                        style: const TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Active Device Hero Card + Power Controls
            KarenCircuitBanner(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const KarenLogoMark(size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              PersianUtils.formatPhoneForDisplay(
                                device.phoneNumber,
                              ),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PowerBadge(state: device.powerState),
                    ],
                  ),
                  if (device.locationLabel.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          device.locationLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text(
                    'روشن و خاموش کردن دستگاه',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('btn_power_on'),
                          onPressed: appState.isBusy
                              ? null
                              : () => _handlePowerCommand(context, ref, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: KarenColors.successGreen,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: appState.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.power_settings_new_rounded),
                          label: const Text(
                            'روشن',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('btn_power_off'),
                          onPressed: appState.isBusy
                              ? null
                              : () => _handlePowerCommand(context, ref, false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: KarenColors.dangerRed,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.power_off_rounded),
                          label: const Text(
                            'خاموش',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quick Telemetry Summary Grid
            Row(
              children: [
                Expanded(
                  child: _MiniMetricCard(
                    icon: Icons.tune_rounded,
                    color: KarenColors.brandPurple,
                    label: 'حالت کارکرد',
                    value: device.operatingMode.labelFa,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniMetricCard(
                    icon: Icons.bolt_rounded,
                    color: device.powerOutageAlertEnabled
                        ? KarenColors.warningAmber
                        : Colors.grey,
                    label: 'اخطار قطع برق',
                    value: !device.powerOutageAlertEnabled
                        ? 'غیرفعال'
                        : (device.powerOutageAlertSilenced
                            ? 'بی‌صدا شده'
                            : 'فعال'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniMetricCard(
                    icon: Icons.calendar_month_rounded,
                    color: KarenColors.brandBlue,
                    label: 'روزهای زمان‌بندی',
                    value:
                        '${PersianUtils.toPersianDigits(device.activeScheduleDaysCount.toString())} روز (${PersianUtils.toPersianDigits(device.totalSlotsCount.toString())} بازه)',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniMetricCard(
                    icon: Icons.groups_rounded,
                    color: KarenColors.successGreen,
                    label: 'کاربران و مدیران',
                    value:
                        '${PersianUtils.toPersianDigits(device.authorizedUsers.length.toString())} نفر',
                  ),
                ),
              ],
            ),
            if (appState.devices.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: appState.devices.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) {
                    final d = appState.devices[idx];
                    return ChoiceChip(
                      label: Text(d.title),
                      selected: d.id == device.id,
                      onSelected: (_) => notifier.selectDevice(d.id),
                    );
                  },
                ),
              ),
            ],
            if (appState.logs.any((l) => l.deviceId == device.id)) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'آخرین فعالیت‌های دستگاه',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                  TextButton(
                    onPressed: () => context.go('/reports'),
                    child: const Text('مشاهده همه'),
                  ),
                ],
              ),
              ...appState.logs
                  .where((l) => l.deviceId == device.id)
                  .take(3)
                  .map(
                    (log) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          log.transportMode == TransportMode.demo
                              ? Icons.science_outlined
                              : Icons.sms_outlined,
                          color: KarenColors.brandPurple,
                        ),
                        title: Text(
                          log.actionTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          PersianUtils.formatDateTimeShort(log.timestamp),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Text(
                          log.status.labelFa,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: KarenColors.brandBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      ),
        ),
      ),
    );
  }
}

class _PowerBadge extends StatelessWidget {
  final DevicePowerState state;

  const _PowerBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final bg = switch (state) {
      DevicePowerState.on => KarenColors.successGreen,
      DevicePowerState.off => KarenColors.dangerRed,
      DevicePowerState.unknown => Colors.white.withValues(alpha: 0.2),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        state.labelFa,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _MiniMetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
