import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/karen_models.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';

class AuthorizedUsersScreen extends ConsumerWidget {
  final DeviceUserRole initialRole;

  const AuthorizedUsersScreen({
    super.key,
    required this.initialRole,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(karenControllerProvider);
    final device = appState.activeDevice;
    final isAdminMode = initialRole == DeviceUserRole.admin;

    final filteredUsers = (device?.authorizedUsers ?? [])
        .where((u) => u.role == initialRole)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdminMode ? 'تعریف و مدیریت مدیران' : 'تعریف و مدیریت کاربران',
        ),
      ),
      floatingActionButton: device == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openUserSheet(context, initialRole),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(isAdminMode ? 'افزودن مدیر' : 'افزودن کاربر'),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: device == null
              ? const Center(child: Text('ابتدا یک دستگاه فعال انتخاب کنید.'))
              : filteredUsers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAdminMode
                                  ? Icons.admin_panel_settings_outlined
                                  : Icons.group_outlined,
                              size: 52,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isAdminMode
                                  ? 'هنوز مدیری برای «${device.title}» ثبت نشده است'
                                  : 'هنوز کاربری برای «${device.title}» ثبت نشده است',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'شماره‌های مجاز می‌توانند فرمان‌ها را برای دستگاه ارسال کرده یا هشدارها را دریافت کنند.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        return Card(
                          child: ListTile(
                            leading: KarenAvatarBadge(index: user.avatarIndex),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SyncStatusChip(status: user.syncStatus),
                              ],
                            ),
                            subtitle: Text(
                              PersianUtils.formatPhoneForDisplay(
                                user.phoneNumber,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (user.syncStatus ==
                                    SyncStatus.pendingConfirmation)
                                  IconButton(
                                    tooltip: 'ثبت تاییدیه دریافتی از دستگاه',
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      color: KarenColors.successGreen,
                                    ),
                                    onPressed: () => ref
                                        .read(karenControllerProvider.notifier)
                                        .markAuthorizedUserConfirmed(user.id),
                                  ),
                                IconButton(
                                  tooltip: 'ویرایش',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: KarenColors.brandBlue,
                                  ),
                                  onPressed: () => _openUserSheet(
                                    context,
                                    initialRole,
                                    existingUser: user,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: KarenColors.dangerRed,
                                  ),
                                  onPressed: () => ref
                                      .read(karenControllerProvider.notifier)
                                      .removeAuthorizedUser(user.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Future<void> _openUserSheet(
    BuildContext context,
    DeviceUserRole role, {
    AuthorizedUser? existingUser,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddUserFormSheet(
        role: role,
        existingUser: existingUser,
      ),
    );
  }
}

class _AddUserFormSheet extends ConsumerStatefulWidget {
  final DeviceUserRole role;
  final AuthorizedUser? existingUser;

  const _AddUserFormSheet({required this.role, this.existingUser});

  @override
  ConsumerState<_AddUserFormSheet> createState() => _AddUserFormSheetState();
}

class _AddUserFormSheetState extends ConsumerState<_AddUserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late int _selectedAvatar;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingUser?.name ?? '');
    _phoneController =
        TextEditingController(text: widget.existingUser?.phoneNumber ?? '');
    _selectedAvatar = widget.existingUser?.avatarIndex ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final res = await ref
        .read(karenControllerProvider.notifier)
        .addOrUpdateAuthorizedUser(
          existingUserId: widget.existingUser?.id,
          name: _nameController.text,
          phoneNumber: _phoneController.text,
          role: widget.role,
          avatarIndex: _selectedAvatar,
        );
    if (!mounted) return;
    if (res.dispatched) {
      Navigator.of(context).pop();
    }
    showKarenSnackBar(
      context,
      message: res.messageFa,
      isError: !res.dispatched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final isAdmin = widget.role == DeviceUserRole.admin;
    final isEdit = widget.existingUser != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + inset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit
                  ? (isAdmin ? 'ویرایش مشخصات مدیر' : 'ویرایش مشخصات کاربر')
                  : (isAdmin ? 'تعریف مدیر جدید' : 'تعریف کاربر جدید'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'انتخاب آواتار',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, idx) {
                  final active = idx == _selectedAvatar;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAvatar = idx),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active
                              ? KarenColors.brandPurple
                              : Colors.transparent,
                          width: 2.4,
                        ),
                      ),
                      child: KarenAvatarBadge(index: idx, radius: 22),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'نام و نام خانوادگی',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'لطفاً نام معتبر وارد کنید'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'شماره همراه',
                hintText: '09123456789',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              validator: PersianUtils.validateIranPhone,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(
                isEdit ? 'ذخیره و ارسال به دستگاه' : 'ثبت و ارسال به دستگاه',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
