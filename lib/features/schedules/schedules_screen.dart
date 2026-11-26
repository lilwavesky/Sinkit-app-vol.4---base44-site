import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/karen_models.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';
import '../devices/device_form_sheet.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  int _selectedDayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(karenControllerProvider);
    final device = appState.activeDevice;
    final notifier = ref.read(karenControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('بارگذاری روزها و زمان‌بندی'),
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
                  : DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const TabBar(
                                indicatorSize: TabBarIndicatorSize.tab,
                                tabs: [
                                  Tab(text: 'تنظیم روز'),
                                  Tab(text: 'تنظیم ساعات روز'),
                                  Tab(text: 'تنظیم روزانه'),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _SetDayTab(
                                  device: device,
                                  isBusy: appState.isBusy,
                                ),
                                _SetDayHoursTab(
                                  device: device,
                                  isBusy: appState.isBusy,
                                  selectedDayIndex: _selectedDayIndex,
                                  onSelectDay: (i) =>
                                      setState(() => _selectedDayIndex = i),
                                ),
                                _DailyRoutineTab(
                                  device: device,
                                  isBusy: appState.isBusy,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _SetDayTab extends ConsumerWidget {
  final KarenDevice device;
  final bool isBusy;

  const _SetDayTab({required this.device, required this.isBusy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(karenControllerProvider.notifier);
    final enabledDays =
        device.weeklySchedules.where((d) => d.enabled).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x1F5B21B6),
                  child: Icon(
                    Icons.calendar_view_week_rounded,
                    color: KarenColors.brandPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'برنامه هفتگی «${device.title}»',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${PersianUtils.toPersianDigits(enabledDays.toString())} روز فعال • ${PersianUtils.toPersianDigits(device.totalSlotsCount.toString())} بازه زمانی ثبت‌شده',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(7, (index) {
          final schedule = device.weeklySchedules[index];
          final dayName = AppConstants.persianWeekDays[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                dayName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SyncStatusChip(status: schedule.syncStatus),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${PersianUtils.toPersianDigits(schedule.slots.length.toString())} بازه زمانی ثبت شده',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: schedule.enabled,
                      onChanged: (v) =>
                          notifier.updateDayEnabledLocal(index, v),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonal(
                      onPressed: isBusy
                          ? null
                          : () async {
                              final res = await notifier.uploadDayStatus(index);
                              if (!context.mounted) return;
                              showKarenSnackBar(
                                context,
                                message: res.messageFa,
                                isError: !res.dispatched,
                              );
                            },
                      child: const Text('ارسال'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SetDayHoursTab extends ConsumerWidget {
  final KarenDevice device;
  final bool isBusy;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;

  const _SetDayHoursTab({
    required this.device,
    required this.isBusy,
    required this.selectedDayIndex,
    required this.onSelectDay,
  });

  Future<void> _addOrEditSlot(
    BuildContext context,
    WidgetRef ref, {
    TimeSlot? existingSlot,
  }) async {
    final start = await showTimePicker(
      context: context,
      helpText: existingSlot == null
          ? 'انتخاب ساعت شروع'
          : 'ویرایش ساعت شروع',
      initialTime: existingSlot != null
          ? TimeOfDay(
              hour: existingSlot.startHour,
              minute: existingSlot.startMinute,
            )
          : const TimeOfDay(hour: 8, minute: 0),
    );
    if (start == null || !context.mounted) return;

    final end = await showTimePicker(
      context: context,
      helpText: existingSlot == null
          ? 'انتخاب ساعت پایان'
          : 'ویرایش ساعت پایان',
      initialTime: existingSlot != null
          ? TimeOfDay(
              hour: existingSlot.endHour,
              minute: existingSlot.endMinute,
            )
          : TimeOfDay(
              hour: (start.hour + 1) % 24,
              minute: start.minute,
            ),
    );
    if (end == null || !context.mounted) return;

    final slot = TimeSlot(
      id: existingSlot?.id ?? 'slot_${DateTime.now().microsecondsSinceEpoch}',
      startHour: start.hour,
      startMinute: start.minute,
      endHour: end.hour,
      endMinute: end.minute,
      enabled: existingSlot?.enabled ?? true,
    );
    final error = await ref
        .read(karenControllerProvider.notifier)
        .addTimeSlotLocal(selectedDayIndex, slot);
    if (!context.mounted) return;
    if (error != null) {
      showKarenSnackBar(context, message: error, isError: true);
    } else {
      showKarenSnackBar(
        context,
        message: existingSlot == null
            ? 'بازه زمانی اضافه شد (آماده بارگذاری)'
            : 'بازه زمانی با موفقیت ویرایش شد (آماده بارگذاری)',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = device.weeklySchedules[selectedDayIndex];
    final notifier = ref.read(karenControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final selected = idx == selectedDayIndex;
              return ChoiceChip(
                label: Text(AppConstants.persianWeekDays[idx]),
                selected: selected,
                onSelected: (_) => onSelectDay(idx),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ساعات ${AppConstants.persianWeekDays[selectedDayIndex]}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SyncStatusChip(status: schedule.syncStatus),
          ],
        ),
        const SizedBox(height: 12),
        if (schedule.slots.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  const Text('هیچ بازه زمانی برای این روز ثبت نشده است.'),
                ],
              ),
            ),
          )
        else
          ...schedule.slots.map(
            (slot) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1F5B21B6),
                  child: Icon(
                    Icons.schedule_rounded,
                    color: KarenColors.brandPurple,
                  ),
                ),
                title: Text(
                  'از ${PersianUtils.formatTime24(slot.startHour, slot.startMinute)} تا ${PersianUtils.formatTime24(slot.endHour, slot.endMinute)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'ویرایش بازه',
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: KarenColors.brandBlue,
                      ),
                      onPressed: () =>
                          _addOrEditSlot(context, ref, existingSlot: slot),
                    ),
                    IconButton(
                      tooltip: 'حذف بازه',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: KarenColors.dangerRed,
                      ),
                      onPressed: () => notifier.removeTimeSlotLocal(
                        selectedDayIndex,
                        slot.id,
                      ),
                    ),
                  ],
                ),
                onTap: () => _addOrEditSlot(context, ref, existingSlot: slot),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('btn_add_time_slot'),
                onPressed: () => _addOrEditSlot(context, ref),
                icon: const Icon(Icons.add_alarm_rounded),
                label: const Text('افزودن بازه ساعت'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('btn_upload_day_hours'),
                onPressed: isBusy
                    ? null
                    : () async {
                        final res =
                            await notifier.uploadDayHours(selectedDayIndex);
                        if (!context.mounted) return;
                        showKarenSnackBar(
                          context,
                          message: res.messageFa,
                          isError: !res.dispatched,
                        );
                      },
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('بارگذاری ساعات'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyRoutineTab extends ConsumerStatefulWidget {
  final KarenDevice device;
  final bool isBusy;

  const _DailyRoutineTab({required this.device, required this.isBusy});

  @override
  ConsumerState<_DailyRoutineTab> createState() => _DailyRoutineTabState();
}

class _DailyRoutineTabState extends ConsumerState<_DailyRoutineTab> {
  final Set<int> _targetDays = {0, 1, 2, 3, 4};
  final List<TimeSlot> _routineSlots = [
    const TimeSlot(
      id: 'routine_init_1',
      startHour: 7,
      startMinute: 0,
      endHour: 9,
      endMinute: 0,
    ),
  ];

  Future<void> _addOrEditRoutineSlot({TimeSlot? existing}) async {
    final start = await showTimePicker(
      context: context,
      helpText: 'ساعت شروع بازه روزانه',
      initialTime: existing != null
          ? TimeOfDay(hour: existing.startHour, minute: existing.startMinute)
          : const TimeOfDay(hour: 17, minute: 0),
    );
    if (start == null || !mounted) return;

    final end = await showTimePicker(
      context: context,
      helpText: 'ساعت پایان بازه روزانه',
      initialTime: existing != null
          ? TimeOfDay(hour: existing.endHour, minute: existing.endMinute)
          : TimeOfDay(hour: (start.hour + 2) % 24, minute: start.minute),
    );
    if (end == null || !mounted) return;

    final candidate = TimeSlot(
      id: existing?.id ?? 'routine_${DateTime.now().microsecondsSinceEpoch}',
      startHour: start.hour,
      startMinute: start.minute,
      endHour: end.hour,
      endMinute: end.minute,
    );
    if (!candidate.isValid) {
      showKarenSnackBar(
        context,
        message: 'ساعت پایان باید بعد از ساعت شروع باشد',
        isError: true,
      );
      return;
    }
    for (final s in _routineSlots) {
      if (s.id != candidate.id && s.overlapsWith(candidate)) {
        showKarenSnackBar(
          context,
          message: 'بازه انتخابی با یکی از بازه‌های الگوی روزانه تداخل دارد',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      _routineSlots.removeWhere((s) => s.id == candidate.id);
      _routineSlots.add(candidate);
      _routineSlots
          .sort((a, b) => a.startTotalMinutes.compareTo(b.startTotalMinutes));
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(karenControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الگوی تکرار روزانه و روزهای کاری',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'یک یا چند بازه زمانی ثابت تعریف کنید و هم‌زمان برای روزهای کاری یا منتخب هفته بارگذاری نمایید.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('روزهای کاری (شنبه تا چهارشنبه)'),
                      onPressed: () => setState(() {
                        _targetDays
                          ..clear()
                          ..addAll([0, 1, 2, 3, 4]);
                      }),
                    ),
                    ActionChip(
                      label: const Text('همه روزهای هفته'),
                      onPressed: () => setState(() {
                        _targetDays
                          ..clear()
                          ..addAll([0, 1, 2, 3, 4, 5, 6]);
                      }),
                    ),
                    ActionChip(
                      label: const Text('آخر هفته'),
                      onPressed: () => setState(() {
                        _targetDays
                          ..clear()
                          ..addAll([5, 6]);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (idx) {
                    final selected = _targetDays.contains(idx);
                    return FilterChip(
                      label: Text(AppConstants.persianWeekDays[idx]),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _targetDays.add(idx);
                          } else {
                            _targetDays.remove(idx);
                          }
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'بازه‌های روزانه (${PersianUtils.toPersianDigits(_routineSlots.length.toString())})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addOrEditRoutineSlot,
                      icon: const Icon(Icons.add_alarm_rounded, size: 18),
                      label: const Text('افزودن بازه'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_routineSlots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'حداقل یک بازه زمانی برای اعمال الگوی روزانه اضافه کنید.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  ..._routineSlots.map(
                    (slot) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.25),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.schedule_rounded,
                          color: KarenColors.brandPurple,
                        ),
                        title: Text(
                          'از ${PersianUtils.formatTime24(slot.startHour, slot.startMinute)} تا ${PersianUtils.formatTime24(slot.endHour, slot.endMinute)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'ویرایش',
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: KarenColors.brandBlue,
                              ),
                              onPressed: () =>
                                  _addOrEditRoutineSlot(existing: slot),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: KarenColors.dangerRed,
                              ),
                              onPressed: () => setState(() {
                                _routineSlots
                                    .removeWhere((s) => s.id == slot.id);
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: widget.isBusy
                      ? null
                      : () async {
                          if (_targetDays.isEmpty) {
                            showKarenSnackBar(
                              context,
                              message: 'حداقل یک روز را انتخاب کنید',
                              isError: true,
                            );
                            return;
                          }
                          if (_routineSlots.isEmpty) {
                            showKarenSnackBar(
                              context,
                              message: 'حداقل یک بازه زمانی تعریف کنید',
                              isError: true,
                            );
                            return;
                          }
                          final res = await notifier.applyAndUploadDailyRoutine(
                            routineSlots: List<TimeSlot>.from(_routineSlots),
                            targetDayIndices: Set<int>.from(_targetDays),
                          );
                          if (!context.mounted) return;
                          showKarenSnackBar(
                            context,
                            message: res.messageFa,
                            isError: !res.dispatched,
                          );
                        },
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('اعمال و بارگذاری برنامه روزانه'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
