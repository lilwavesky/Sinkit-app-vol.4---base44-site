import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/transport/protocol_templates.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';

class ProtocolTemplatesScreen extends ConsumerWidget {
  const ProtocolTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(karenControllerProvider).templates;
    final entries = ProtocolTemplates.labelsFa.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('قالب فرمان‌های پیامکی (پروتکل)'),
        actions: [
          IconButton(
            tooltip: 'بازنشانی به پیش‌فرض',
            onPressed: () async {
              final err = await ref
                  .read(karenControllerProvider.notifier)
                  .resetProtocolTemplates();
              if (context.mounted) {
                showKarenSnackBar(
                  context,
                  message: err ?? 'قالب‌ها به حالت اولیه [UNVERIFIED] بازنشانی شد',
                  isError: err != null,
                );
              }
            },
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: templates.hasAnyUnverified
                  ? KarenColors.warningAmber.withValues(alpha: 0.12)
                  : KarenColors.successGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (templates.hasAnyUnverified
                        ? KarenColors.warningAmber
                        : KarenColors.successGreen)
                    .withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  templates.hasAnyUnverified
                      ? Icons.gpp_maybe_rounded
                      : Icons.verified_user_rounded,
                  color: templates.hasAnyUnverified
                      ? KarenColors.warningAmber
                      : KarenColors.successGreen,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'وضعیت تایید: ${PersianUtils.toPersianDigits(templates.verifiedCount.toString())} از ${PersianUtils.toPersianDigits(templates.totalCount.toString())} فرمان تایید شده',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'کدهای پیامکی سخت‌افزار کارن در نسخه استاتیک APK قابل استخراج قطعی نبودند. هر فرمان با برچسب [UNVERIFIED] یا متن خالی در حالت پیامک واقعی به‌طور کامل مسدود می‌شود تا پیامک اشتباه ارسال نشود.',
                        style: TextStyle(fontSize: 12.2, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...entries.map((entry) {
            final currentValue = templates.rawTemplate(entry.key);
            final isVerified = templates.isVerified(entry.key);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isVerified
                                ? KarenColors.successGreen
                                : KarenColors.dangerRed)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isVerified ? 'تایید شده' : 'مسدود در پیامک',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isVerified
                              ? KarenColors.successGreen
                              : KarenColors.dangerRed,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    currentValue.isEmpty ? '(خالی)' : currentValue,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: isVerified
                          ? KarenColors.successGreen
                          : KarenColors.warningAmber,
                    ),
                  ),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editTemplate(
                  context,
                  ref,
                  keyName: entry.key,
                  labelFa: entry.value,
                  initialValue: currentValue,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _editTemplate(
    BuildContext context,
    WidgetRef ref, {
    required String keyName,
    required String labelFa,
    required String initialValue,
  }) async {
    final controller = TextEditingController(
      text: ProtocolTemplates.containsUnverifiedMarker(initialValue)
          ? ''
          : initialValue,
    );
    String? errorText;

    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(labelFa),
          content: TextField(
            controller: controller,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'کد رسمی پیامک سخت‌افزار کارن',
              hintText: 'کد تایید شده از دفترچه دستگاه',
              helperText:
                  'متغیرهای مجاز: {mode}, {phone}, {day}, {state}, {slots}, {time}',
              helperMaxLines: 2,
              errorText: errorText,
              errorMaxLines: 3,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final err =
                    ProtocolTemplates.validateUserTemplateInput(controller.text);
                if (err != null) {
                  setDialogState(() => errorText = err);
                  return;
                }
                Navigator.pop(ctx, controller.text.trim());
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (saved != null) {
      final err = await ref
          .read(karenControllerProvider.notifier)
          .updateProtocolTemplate(keyName, saved);
      if (context.mounted) {
        showKarenSnackBar(
          context,
          message: err ?? 'قالب فرمان با موفقیت ذخیره شد',
          isError: err != null,
        );
      }
    }
  }
}
