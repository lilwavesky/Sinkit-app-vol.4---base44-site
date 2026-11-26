import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/karen_models.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';
import '../devices/device_form_sheet.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  CommandCategory? _filter;

  Future<void> _showResultDialog(
    BuildContext context,
    String title,
    String body,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.65)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }

  Future<void> _openClockSyncOptions(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تنظیم ساعت دستگاه',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'now'),
              icon: const Icon(Icons.access_time_filled_rounded),
              label: Text(
                'همگام‌سازی با ساعت فعلی گوشی (${PersianUtils.formatDateTimeShort(DateTime.now())})',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'manual'),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('انتخاب دستی ساعت'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return;
    DateTime targetTime = DateTime.now();
    if (choice == 'manual') {
      final picked = await showTimePicker(
        context: context,
        helpText: 'انتخاب ساعت برای ارسال به دستگاه',
        initialTime: TimeOfDay.now(),
      );
      if (picked == null || !context.mounted) return;
      final now = DateTime.now();
      targetTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
    }

    final res = await ref
        .read(karenControllerProvider.notifier)
        .syncDeviceClock(targetTime);
    if (!context.mounted) return;
    showKarenSnackBar(
      context,
      message: res.simulatedReplyFa ?? res.messageFa,
      isError: !res.dispatched,
    );
  }

  Future<void> _confirmClearLogs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاکسازی تاریخچه فرمان‌ها'),
        content: const Text(
          'آیا از حذف کامل تاریخچه فرمان‌ها و گزارش‌های ثبت‌شده مطمئن هستید؟',
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
            child: const Text('پاکسازی'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(karenControllerProvider.notifier).clearLogs();
    }
  }

  Future<void> _openManualSmsReplySheet(BuildContext context) async {
    final controller = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت پاسخ پیامک دریافتی'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'متن پیامک دریافت‌شده از دستگاه کارن را اینجا جای‌گذاری کنید...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('ثبت در تاریخچه'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null && saved.trim().isNotEmpty) {
      await ref.read(karenControllerProvider.notifier).logManualSmsReply(saved);
      if (context.mounted) {
        showKarenSnackBar(context, message: 'پاسخ پیامک در تاریخچه ذخیره شد');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(karenControllerProvider);
    final device = appState.activeDevice;
    final notifier = ref.read(karenControllerProvider.notifier);

    final deviceLogs = appState.logs.where((log) {
      if (device != null && log.deviceId != device.id) return false;
      if (_filter != null && log.category != _filter) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارشگیری و همگام‌سازی'),
        actions: [
          if (device != null)
            IconButton(
              tooltip: 'ثبت پاسخ پیامک دریافتی',
              icon: const Icon(Icons.mark_chat_read_outlined),
              onPressed: () => _openManualSmsReplySheet(context),
            ),
          if (appState.logs.isNotEmpty)
            IconButton(
              tooltip: 'پاکسازی تاریخچه',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClearLogs(context),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: appState.isDevicesWriteProtected
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StorageRecoveryCard(
                      status: appState.devicesStorageStatus,
                      isBusy: appState.isBusy,
                      onRetry: notifier.retrySecureStorageLoad,
                      onResetCorrupted: notifier.resetAffectedCorruptedStores,
                    ),
                  ],
                )
              : device == null
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        EmptyDeviceStateCard(
                          onAddDevice: () => showDeviceFormSheet(context),
                          onLoadDemoDevice: notifier.seedDemoDevice,
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        KarenCircuitBanner(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'عملیات گزارش‌گیری و ساعت دستگاه',
                                      softWrap: true,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (device.deviceClockSyncedAt != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'ساعت: ${PersianUtils.formatDateTimeShort(device.deviceClockSyncedAt!)}',
                                        textAlign: TextAlign.end,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              _ReportActionButton(
                                key: const Key('btn_general_report'),
                                icon: Icons.assessment_outlined,
                                label: 'گزارشگیری کلی',
                                enabled: !appState.isBusy,
                                onPressed: () async {
                                  final res =
                                      await notifier.requestGeneralReport();
                                  if (!context.mounted) return;
                                  if (res.simulatedReplyFa != null) {
                                    await _showResultDialog(
                                      context,
                                      'گزارش کلی دستگاه (دمو)',
                                      res.simulatedReplyFa!,
                                    );
                                  } else {
                                    showKarenSnackBar(
                                      context,
                                      message: res.messageFa,
                                      isError: !res.dispatched,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              _ReportActionButton(
                                key: const Key('btn_sync_clock'),
                                icon: Icons.schedule_send_outlined,
                                label: 'تنظیم ساعت',
                                enabled: !appState.isBusy,
                                onPressed: () =>
                                    _openClockSyncOptions(context),
                              ),
                              const SizedBox(height: 10),
                              _ReportActionButton(
                                key: const Key('btn_retrieve_days'),
                                icon: Icons.history_rounded,
                                label: 'بازیابی زمان روزها',
                                enabled: !appState.isBusy,
                                onPressed: () async {
                                  final res =
                                      await notifier.retrieveDaysSchedule();
                                  if (!context.mounted) return;
                                  if (res.simulatedReplyFa != null) {
                                    await _showResultDialog(
                                      context,
                                      'زمان‌بندی بازیابی‌شده (دمو)',
                                      res.simulatedReplyFa!,
                                    );
                                  } else {
                                    showKarenSnackBar(
                                      context,
                                      message: res.messageFa,
                                      isError: !res.dispatched,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'تاریخچه فرمان‌ها و گزارش‌ها',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('همه'),
                                selected: _filter == null,
                                onSelected: (_) =>
                                    setState(() => _filter = null),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('روشن/خاموش'),
                                selected: _filter == CommandCategory.power,
                                onSelected: (_) => setState(
                                  () => _filter = CommandCategory.power,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('زمان‌بندی'),
                                selected: _filter == CommandCategory.schedule,
                                onSelected: (_) => setState(
                                  () => _filter = CommandCategory.schedule,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('گزارش‌ها'),
                                selected: _filter == CommandCategory.report,
                                onSelected: (_) => setState(
                                  () => _filter = CommandCategory.report,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('تنظیمات'),
                                selected: _filter == CommandCategory.settings,
                                onSelected: (_) => setState(
                                  () => _filter = CommandCategory.settings,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('کاربران'),
                                selected: _filter == CommandCategory.userAccess,
                                onSelected: (_) => setState(
                                  () => _filter = CommandCategory.userAccess,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (deviceLogs.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Text(
                                'هنوز هیچ فرمانی برای این دستگاه ثبت نشده است.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        else
                          ...deviceLogs.map(
                            (log) => Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            log.actionTitle,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        _LogStatusBadge(status: log.status),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (log.responseSummary != null)
                                      Text(
                                        log.responseSummary!,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.5,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          PersianUtils.formatDateTimeShort(
                                            log.timestamp,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          log.transportMode ==
                                                  TransportMode.demo
                                              ? 'دمو'
                                              : 'پیامک',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: KarenColors.brandPurple,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _ReportActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _ReportActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: KarenColors.brandDeepPurple,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, color: KarenColors.brandBlue),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}

class _LogStatusBadge extends StatelessWidget {
  final CommandLogStatus status;

  const _LogStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CommandLogStatus.simulatedSuccess => KarenColors.brandPurple,
      CommandLogStatus.pendingConfirmation => KarenColors.brandBlue,
      CommandLogStatus.blockedUnverified => KarenColors.warningAmber,
      CommandLogStatus.receivedReply => KarenColors.successGreen,
      CommandLogStatus.failed => KarenColors.dangerRed,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.labelFa,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
