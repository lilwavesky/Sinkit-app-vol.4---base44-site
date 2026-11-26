import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/utils/persian_utils.dart';

void main() {
  group('PersianUtils validation & normalization', () {
    test('normalizes Persian digits and +98 prefix to 09xxxxxxxxx', () {
      expect(
        PersianUtils.normalizeIranPhone('+۹۸ ۹۱۲ ۳۴۵ ۶۷۸۹'),
        '09123456789',
      );
      expect(
        PersianUtils.normalizeIranPhone('00989351112233'),
        '09351112233',
      );
      expect(PersianUtils.validateIranPhone('۰۹۱۲۳۴۵۶۷۸۹'), isNull);
      expect(PersianUtils.validateIranPhone('09123'), isNotNull);
      expect(PersianUtils.validateIranPhone('08123456789'), isNotNull);
    });

    test('converts Gregorian date to Jalali accurately', () {
      final (jy, jm, jd) = PersianUtils.gregorianToJalali(2026, 3, 21);
      expect(jy, 1405);
      expect(jm, 1);
      expect(jd, 1);
    });
  });

  group('TimeSlot & DaySchedule models', () {
    test('detects overlapping slots and rejects inverted intervals', () {
      const slotA = TimeSlot(
        id: '1',
        startHour: 8,
        startMinute: 0,
        endHour: 10,
        endMinute: 0,
      );
      const slotB = TimeSlot(
        id: '2',
        startHour: 9,
        startMinute: 30,
        endHour: 11,
        endMinute: 0,
      );
      const invalidSlot = TimeSlot(
        id: '3',
        startHour: 12,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
      );

      expect(slotA.isValid, isTrue);
      expect(invalidSlot.isValid, isFalse);
      expect(slotA.overlapsWith(slotB), isTrue);
    });

    test('KarenDevice serializes and deserializes with SyncStatus intact', () {
      const device = KarenDevice(
        id: 'd1',
        title: 'پمپ اصلی',
        phoneNumber: '09123456789',
        powerState: DevicePowerState.on,
        operatingMode: OperatingMode.hybrid,
        pendingActionSummary: 'تنظیم ساعت (در انتظار تایید)',
        weeklySchedules: [
          const DaySchedule(
            dayIndex: 0,
            enabled: true,
            syncStatus: SyncStatus.pendingConfirmation,
            slots: [
              TimeSlot(
                id: 's1',
                startHour: 7,
                startMinute: 0,
                endHour: 9,
                endMinute: 30,
              ),
            ],
          ),
        ],
        authorizedUsers: const [
          AuthorizedUser(
            id: 'u1',
            name: 'مدیر',
            phoneNumber: '09121112233',
            role: DeviceUserRole.admin,
            syncStatus: SyncStatus.pendingConfirmation,
          ),
        ],
      );

      final roundTrip = KarenDevice.fromJson(device.toJson());
      expect(roundTrip.id, 'd1');
      expect(roundTrip.title, 'پمپ اصلی');
      expect(roundTrip.pendingActionSummary, 'تنظیم ساعت (در انتظار تایید)');
      expect(
        roundTrip.weeklySchedules.first.syncStatus,
        SyncStatus.pendingConfirmation,
      );
      expect(
        roundTrip.authorizedUsers.first.syncStatus,
        SyncStatus.pendingConfirmation,
      );
    });
  });
}
