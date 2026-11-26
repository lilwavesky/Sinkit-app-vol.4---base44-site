import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../core/models/karen_models.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';

Future<void> showDeviceFormSheet(
  BuildContext context, {
  KarenDevice? existingDevice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DeviceFormSheet(existingDevice: existingDevice),
  );
}

class _DeviceFormSheet extends ConsumerStatefulWidget {
  final KarenDevice? existingDevice;

  const _DeviceFormSheet({this.existingDevice});

  @override
  ConsumerState<_DeviceFormSheet> createState() => _DeviceFormSheetState();
}

class _DeviceFormSheetState extends ConsumerState<_DeviceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _phoneController;
  late final TextEditingController _locationController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existingDevice?.title ?? '');
    _phoneController =
        TextEditingController(text: widget.existingDevice?.phoneNumber ?? '');
    _locationController =
        TextEditingController(text: widget.existingDevice?.locationLabel ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final error =
        await ref.read(karenControllerProvider.notifier).addOrUpdateDevice(
              existingId: widget.existingDevice?.id,
              title: _titleController.text,
              phoneNumber: _phoneController.text,
              locationLabel: _locationController.text,
            );
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      showKarenSnackBar(context, message: error, isError: true);
      return;
    }

    Navigator.of(context).pop();
    showKarenSnackBar(
      context,
      message: widget.existingDevice == null
          ? 'دستگاه جدید با موفقیت ثبت شد'
          : 'مشخصات دستگاه بروزرسانی شد',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingDevice != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 16),
            Text(
              isEdit ? 'ویرایش مشخصات دستگاه' : 'ثبت شماره جدید',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'عنوان و شماره سیم‌کارت داخل دستگاه کارن را وارد کنید.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'عنوان',
                hintText: 'مثلاً: پمپ باغچه یا موتورخانه',
                prefixIcon: Icon(Icons.devices_other_rounded),
              ),
              validator: PersianUtils.validateDeviceTitle,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'شماره همراه',
                hintText: '09123456789',
                prefixIcon: Icon(Icons.sim_card_rounded),
              ),
              validator: PersianUtils.validateIranPhone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _locationController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'موقعیت / توضیحات (اختیاری)',
                hintText: 'مثلاً: ورودی شمالی',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('تایید'),
            ),
          ],
        ),
      ),
    );
  }
}
