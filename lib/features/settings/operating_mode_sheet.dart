import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/karen_models.dart';
import '../../core/widgets/karen_widgets.dart';

Future<void> showOperatingModeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _OperatingModeSheet(),
  );
}

class _OperatingModeSheet extends ConsumerStatefulWidget {
  const _OperatingModeSheet();

  @override
  ConsumerState<_OperatingModeSheet> createState() =>
      _OperatingModeSheetState();
}

class _OperatingModeSheetState extends ConsumerState<_OperatingModeSheet> {
  late OperatingMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(karenControllerProvider).activeDevice?.operatingMode ??
        OperatingMode.manual;
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = ref.watch(karenControllerProvider).isBusy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تنظیمات حالت کارکرد',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'نحوه اجرای فرمان‌های دستی و زمان‌بندی روی دستگاه فعال را انتخاب کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 16),
          ...OperatingMode.values.map((mode) {
            final isSelected = _selected == mode;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selected = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isSelected
                        ? KarenColors.brandPurple.withValues(alpha: 0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? KarenColors.brandPurple
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected
                            ? KarenColors.brandPurple
                            : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mode.labelFa,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              switch (mode) {
                                OperatingMode.manual =>
                                  'کنترل فقط از طریق فرمان مستقیم روشن/خاموش',
                                OperatingMode.scheduled =>
                                  'اجرای خودکار بر اساس برنامه روزهای بارگذاری‌شده',
                                OperatingMode.hybrid =>
                                  'اجرای زمان‌بندی با امکان کنترل دستی در هر لحظه',
                              },
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: isBusy
                ? null
                : () async {
                    final res = await ref
                        .read(karenControllerProvider.notifier)
                        .setOperatingMode(_selected);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    showKarenSnackBar(
                      context,
                      message: res.messageFa,
                      isError: !res.dispatched,
                    );
                  },
            icon: const Icon(Icons.send_rounded),
            label: const Text('ارسال حالت کارکرد'),
          ),
        ],
      ),
    );
  }
}
