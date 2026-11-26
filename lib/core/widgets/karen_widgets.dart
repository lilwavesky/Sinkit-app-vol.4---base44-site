import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';
import '../models/karen_models.dart';
import '../storage/local_storage_service.dart';
import '../utils/persian_utils.dart';

class KarenLogoMark extends StatelessWidget {
  final double size;

  const KarenLogoMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KarenLogoPainter()),
    );
  }
}

class _KarenLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.22),
    );
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A124C), Color(0xFF150929)],
      ).createShader(Rect.fromLTWH(0, 0, s, s));
    canvas.drawRRect(bgRect, bgPaint);

    final kPaint = Paint()..color = const Color(0xFF8B5CF6);
    final kPath = Path()
      ..moveTo(s * 0.22, s * 0.20)
      ..lineTo(s * 0.36, s * 0.20)
      ..lineTo(s * 0.36, s * 0.42)
      ..lineTo(s * 0.58, s * 0.20)
      ..lineTo(s * 0.77, s * 0.20)
      ..lineTo(s * 0.50, s * 0.46)
      ..lineTo(s * 0.78, s * 0.80)
      ..lineTo(s * 0.58, s * 0.80)
      ..lineTo(s * 0.40, s * 0.56)
      ..lineTo(s * 0.36, s * 0.60)
      ..lineTo(s * 0.36, s * 0.80)
      ..lineTo(s * 0.22, s * 0.80)
      ..close();
    canvas.drawPath(kPath, kPaint);

    final plugPaint = Paint()..color = KarenColors.brandOrange;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.28, s * 0.54, s * 0.18, s * 0.14),
        Radius.circular(s * 0.04),
      ),
      plugPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.32, s * 0.47, s * 0.032, s * 0.08),
        Radius.circular(s * 0.015),
      ),
      plugPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.39, s * 0.47, s * 0.032, s * 0.08),
        Radius.circular(s * 0.015),
      ),
      plugPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.355, s * 0.68, s * 0.036, s * 0.12),
        Radius.circular(s * 0.018),
      ),
      plugPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class KarenCircuitBanner extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const KarenCircuitBanner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFFEA580C),
            Color(0xFF7C3AED),
            Color(0xFF1E1038),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: KarenColors.brandPurple.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CustomPaint(
          painter: _CircuitOverlayPainter(),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _CircuitOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.11)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    for (var i = 1; i <= 5; i++) {
      final x = size.width * (i / 6);
      final h = size.height * (i.isEven ? 0.42 : 0.28);
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, h * 0.65)
        ..lineTo(x + (i.isEven ? 12 : -12), h);
      canvas.drawPath(path, linePaint);
      canvas.drawCircle(Offset(x + (i.isEven ? 12 : -12), h), 3, nodePaint);
    }

    for (var i = 1; i <= 4; i++) {
      final x = size.width * (i / 5);
      final startY = size.height;
      final endY = size.height - (size.height * (i.isOdd ? 0.34 : 0.22));
      final path = Path()
        ..moveTo(x, startY)
        ..lineTo(x, endY + 12)
        ..lineTo(x + 10, endY);
      canvas.drawPath(path, linePaint);
      canvas.drawCircle(Offset(x + 10, endY), 3, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ModeStatusPill extends StatelessWidget {
  final TransportMode mode;
  final VoidCallback? onTap;

  const ModeStatusPill({super.key, required this.mode, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDemo = mode == TransportMode.demo;
    final bg = isDemo
        ? KarenColors.warningAmber.withValues(alpha: 0.16)
        : KarenColors.successGreen.withValues(alpha: 0.16);
    final fg = isDemo ? KarenColors.warningAmber : KarenColors.successGreen;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDemo ? Icons.science_rounded : Icons.sms_rounded,
              size: 15,
              color: fg,
            ),
            const SizedBox(width: 5),
            Text(
              isDemo ? 'حالت دمو' : 'حالت پیامک',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnverifiedProtocolWarningBanner extends StatelessWidget {
  final int unverifiedCount;
  final int totalCount;
  final VoidCallback onOpenTemplates;

  const UnverifiedProtocolWarningBanner({
    super.key,
    required this.unverifiedCount,
    required this.totalCount,
    required this.onOpenTemplates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('unverified_protocol_banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KarenColors.dangerRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: KarenColors.dangerRed.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.gpp_maybe_rounded,
                color: KarenColors.dangerRed,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'هشدار امنیتی: قالب فرمان‌های پیامکی تایید نشده است',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: KarenColors.dangerRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${PersianUtils.toPersianDigits(unverifiedCount.toString())} مورد از ${PersianUtils.toPersianDigits(totalCount.toString())} فرمان هنوز دارای برچسب [UNVERIFIED] هستند و ارسال آن‌ها در حالت پیامک واقعی به‌طور خودکار مسدود می‌شود.',
                      style: const TextStyle(fontSize: 12, height: 1.55),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: onOpenTemplates,
              icon: const Icon(Icons.code_rounded, size: 17),
              label: const Text('تنظیم قالب فرمان‌ها'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displayed instead of [EmptyDeviceStateCard] whenever encrypted storage fails
/// to read or contains corrupted data. Prevents users from misinterpreting an
/// unreadable keystore as an empty database or overwriting existing records.
class StorageRecoveryCard extends StatelessWidget {
  final StorageLoadStatus status;
  final bool isBusy;
  final VoidCallback onRetry;
  final VoidCallback onResetCorrupted;

  const StorageRecoveryCard({
    super.key,
    required this.status,
    required this.isBusy,
    required this.onRetry,
    required this.onResetCorrupted,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrupted = status == StorageLoadStatus.corruptedData;

    return Card(
      key: const Key('storage_recovery_card'),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KarenColors.dangerRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrupted
                      ? Icons.broken_image_outlined
                      : Icons.lock_clock_outlined,
                  size: 38,
                  color: KarenColors.dangerRed,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isCorrupted
                  ? 'خرابی در داده‌های رمزنگاری‌شده محلی'
                  : 'حافظه امن رمزنگاری‌شده در دسترس نیست',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: KarenColors.dangerRed,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isCorrupted
                  ? 'داده‌های ذخیره‌شده دستگاه‌ها ساختار معتبری ندارند. برای جلوگیری از بازنویسی ناخواسته، ثبت اطلاعات جدید مسدود شده است. ابتدا تلاش مجدد را بزنید و تنها در صورت تداوم خطا، بخش آسیب‌دیده را بازنشانی کنید.'
                  : 'برنامه نتوانست داده‌های دستگاه‌ها را از Android Keystore بخواند. پایگاه‌داده شما خالی نیست — برای حفظ اطلاعات قبلی، نوشتن داده جدید تا زمان بازیابی مسدود شده است.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.65),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('btn_retry_storage'),
              onPressed: isBusy ? null : onRetry,
              icon: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('تلاش مجدد برای بازیابی داده‌ها'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('btn_reset_corrupted_storage'),
              onPressed: isBusy ? null : onResetCorrupted,
              style: OutlinedButton.styleFrom(
                foregroundColor: KarenColors.dangerRed,
                side: BorderSide(
                  color: KarenColors.dangerRed.withValues(alpha: 0.5),
                ),
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('پاکسازی بخش آسیب‌دیده (حذف داده‌های غیرقابل‌خواندن)'),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncStatusChip extends StatelessWidget {
  final SyncStatus status;

  const SyncStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.localDraft => KarenColors.warningAmber,
      SyncStatus.pendingConfirmation => KarenColors.brandBlue,
      SyncStatus.syncedDemo => KarenColors.brandPurple,
      SyncStatus.confirmed => KarenColors.successGreen,
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
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class KarenAvatarBadge extends StatelessWidget {
  final int index;
  final double radius;

  const KarenAvatarBadge({super.key, required this.index, this.radius = 22});

  static const List<Color> _palette = [
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
    Color(0xFF9333EA),
    Color(0xFFD97706),
  ];

  static const List<IconData> _icons = [
    Icons.person_rounded,
    Icons.engineering_rounded,
    Icons.support_agent_rounded,
    Icons.manage_accounts_rounded,
    Icons.face_3_rounded,
    Icons.face_4_rounded,
    Icons.face_6_rounded,
    Icons.shield_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final safeIdx = index.abs() % _palette.length;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _palette[safeIdx].withValues(alpha: 0.16),
      child: Icon(
        _icons[safeIdx],
        color: _palette[safeIdx],
        size: radius * 1.05,
      ),
    );
  }
}

class EmptyDeviceStateCard extends StatelessWidget {
  final VoidCallback onAddDevice;
  final VoidCallback onLoadDemoDevice;

  const EmptyDeviceStateCard({
    super.key,
    required this.onAddDevice,
    required this.onLoadDemoDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KarenColors.brandPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.router_rounded,
                size: 40,
                color: KarenColors.brandPurple,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'هنوز دستگاهی ثبت نشده است',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'برای کنترل برق، تنظیم زمان‌بندی روزانه و دریافت گزارش، ابتدا شماره سیم‌کارت دستگاه کارن خود را ثبت کنید یا یک دستگاه نمونه دمو بارگذاری نمایید.',
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAddDevice,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('ثبت شماره جدید'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLoadDemoDevice,
                icon: const Icon(Icons.science_outlined),
                label: const Text('بارگذاری دستگاه نمونه (حالت دمو)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showKarenSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? KarenColors.dangerRed : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}
