import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/karen_providers.dart';
import '../../app/theme/app_theme.dart';
import '../../core/security/pin_hasher.dart';
import '../../core/utils/persian_utils.dart';
import '../../core/widgets/karen_widgets.dart';

class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _storageUnavailable = false;
  bool _verifying = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    final result = await ref
        .read(karenControllerProvider.notifier)
        .verifyPin(_pinController.text);

    if (!mounted) return;
    setState(() => _verifying = false);

    if (result.isUnlocked) {
      context.go('/home');
      return;
    }

    setState(() {
      _error = result.messageFa;
      _storageUnavailable =
          result.status == PinVerificationStatus.storageUnavailable;
    });
    _pinController.clear();
  }

  Future<void> _confirmEmergencyReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازنشانی امنیتی و حذف داده‌های محلی'),
        content: const Text(
          'برای جلوگیری از دور زدن قفل امنیتی، بازنشانی قفل تنها زمانی انجام می‌شود که حذف کامل لیست دستگاه‌ها، کاربران مجاز، قالب فرمان‌ها و تاریخچه محلی در Android Keystore تایید شود. در صورت خطای حذف، قفل برنامه بسته می‌ماند. آیا ادامه می‌دهید؟',
          style: TextStyle(height: 1.6),
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
            child: const Text('حذف تاییدشده و بازنشانی'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    final wipeResult =
        await ref.read(karenControllerProvider.notifier).emergencyWipeAndUnlock();

    if (!mounted) return;
    setState(() => _verifying = false);

    if (wipeResult.success) {
      context.go('/home');
    } else {
      // Remain strictly locked and show clear recovery error!
      setState(() {
        _error = wipeResult.messageFa;
        _storageUnavailable = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(karenControllerProvider);
    final nowUtc = DateTime.now().toUtc();
    final lockoutUntil = appState.pinLockoutUntil;
    final hasActiveLockout =
        lockoutUntil != null && nowUtc.isBefore(lockoutUntil);
    final showRecoveryOption =
        _storageUnavailable || appState.pinRecoveryRequired;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const KarenLogoMark(size: 72),
                        const SizedBox(height: 16),
                        const Text(
                          'ورود امن به Sinkit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'برای دسترسی به کنترل دستگاه‌ها رمز ۴ رقمی خود را وارد کنید.',
                          textAlign: TextAlign.center,
                        ),
                        if (appState.pinRecoveryRequired) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const Key('pin_recovery_required_banner'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: KarenColors.dangerRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: KarenColors.dangerRed.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              appState.lastError ??
                                  'وضعیت بازیابی امنیتی فعال است: بازگردانی رمز عبور تایید نشد و برنامه برای حفظ امنیت قفل شده است.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: KarenColors.dangerRed,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ] else if (hasActiveLockout) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: KarenColors.dangerRed.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'قفل موقت فعال است (${PersianUtils.toPersianDigits((lockoutUntil.difference(nowUtc).inSeconds + 1).toString())} ثانیه باقی‌مانده).',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: KarenColors.dangerRed,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('pin_input_field'),
                          controller: _pinController,
                          obscureText: true,
                          maxLength: 4,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            labelText: 'رمز ۴ رقمی',
                            errorText: _error,
                            errorMaxLines: 5,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('btn_verify_pin'),
                            onPressed: _verifying ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: KarenColors.brandPurple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: _verifying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded),
                            label: const Text('ورود'),
                          ),
                        ),
                        if (showRecoveryOption) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('btn_retry_pin_storage'),
                            onPressed: _verifying
                                ? null
                                : () async {
                                    setState(() {
                                      _verifying = true;
                                      _error = null;
                                    });
                                    final ok = await ref
                                        .read(karenControllerProvider.notifier)
                                        .retrySecureStorageLoad();
                                    if (!mounted) return;
                                    setState(() {
                                      _verifying = false;
                                      _error = ok
                                          ? 'حافظه امن بازخوانی شد؛ لطفاً رمز ۴ رقمی را وارد کنید.'
                                          : 'حافظه امن همچنان در دسترس نیست یا نیازمند بازیابی است.';
                                    });
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('تلاش مجدد خواندن حافظه امن'),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            key: const Key('btn_emergency_wipe'),
                            onPressed: _verifying ? null : _confirmEmergencyReset,
                            style: TextButton.styleFrom(
                              foregroundColor: KarenColors.dangerRed,
                            ),
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text(
                              'حذف تاییدشده داده‌های محلی و بازنشانی قفل',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
