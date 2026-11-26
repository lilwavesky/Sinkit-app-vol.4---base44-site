import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';

import '../test_helpers/in_memory_secure_store.dart';

Future<ProviderContainer> _createDemoContainer() async {
  final storage = LocalStorageService.withStores(
    InMemoryPreferencesStore(),
    InMemorySecureStore(),
  );
  final initial = await storage.loadAll();
  return ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      initialAppDataProvider.overrideWithValue(initial),
      demoTransportProvider.overrideWithValue(
        const DemoCommandTransport(latency: Duration.zero),
      ),
    ],
  );
}

void main() {
  test('edits existing TimeSlot in place, prevents overlaps, and deletes cleanly', () async {
    final container = await _createDemoContainer();
    addTearDown(container.dispose);
    final notifier = container.read(karenControllerProvider.notifier);

    await notifier.addOrUpdateDevice(
      title: 'پمپ باغ',
      phoneNumber: '09123456789',
    );

    // Add two non-overlapping slots
    expect(
      await notifier.addTimeSlotLocal(
        0,
        const TimeSlot(
          id: 's1',
          startHour: 6,
          startMinute: 0,
          endHour: 8,
          endMinute: 0,
        ),
      ),
      isNull,
    );
    expect(
      await notifier.addTimeSlotLocal(
        0,
        const TimeSlot(
          id: 's2',
          startHour: 10,
          startMinute: 0,
          endHour: 12,
          endMinute: 0,
        ),
      ),
      isNull,
    );

    // Edit s1 into an overlapping range with s2 -> rejected
    final overlapErr = await notifier.addTimeSlotLocal(
      0,
      const TimeSlot(
        id: 's1',
        startHour: 7,
        startMinute: 0,
        endHour: 10,
        endMinute: 30,
      ),
    );
    expect(overlapErr, isNotNull);

    // Edit s1 into a valid non-overlapping range -> succeeds without duplicating
    final editErr = await notifier.addTimeSlotLocal(
      0,
      const TimeSlot(
        id: 's1',
        startHour: 6,
        startMinute: 30,
        endHour: 9,
        endMinute: 0,
      ),
    );
    expect(editErr, isNull);

    final day0Slots =
        container.read(karenControllerProvider).activeDevice!.weeklySchedules[0].slots;
    expect(day0Slots.length, 2);
    expect(day0Slots.first.id, 's1');
    expect(day0Slots.first.endHour, 9);

    await notifier.removeTimeSlotLocal(0, 's1');
    expect(
      container
          .read(karenControllerProvider)
          .activeDevice!
          .weeklySchedules[0]
          .slots
          .length,
      1,
    );
  });

  test('applies multi-slot daily routine to working days, edits authorized user, and syncs manual clock', () async {
    final container = await _createDemoContainer();
    addTearDown(container.dispose);
    final notifier = container.read(karenControllerProvider.notifier);

    await notifier.addOrUpdateDevice(
      title: 'موتورخانه مرکزی',
      phoneNumber: '09351112233',
    );

    final routineRes = await notifier.applyAndUploadDailyRoutine(
      routineSlots: const [
        TimeSlot(
          id: 'r1',
          startHour: 6,
          startMinute: 0,
          endHour: 8,
          endMinute: 0,
        ),
        TimeSlot(
          id: 'r2',
          startHour: 18,
          startMinute: 0,
          endHour: 20,
          endMinute: 0,
        ),
      ],
      targetDayIndices: {0, 1, 2, 3, 4},
    );
    expect(routineRes.isSimulatedExecution, isTrue);

    final devAfterRoutine = container.read(karenControllerProvider).activeDevice!;
    expect(devAfterRoutine.activeScheduleDaysCount, 5);
    expect(devAfterRoutine.totalSlotsCount, 10);

    // Add and then edit an authorized user
    await notifier.addOrUpdateAuthorizedUser(
      name: 'رضا',
      phoneNumber: '09120001122',
      role: DeviceUserRole.user,
      avatarIndex: 1,
    );
    final createdUser = container
        .read(karenControllerProvider)
        .activeDevice!
        .authorizedUsers
        .single;

    await notifier.addOrUpdateAuthorizedUser(
      existingUserId: createdUser.id,
      name: 'رضا احمدی',
      phoneNumber: '09120009988',
      role: DeviceUserRole.user,
      avatarIndex: 4,
    );
    final editedUsers = container
        .read(karenControllerProvider)
        .activeDevice!
        .authorizedUsers;
    expect(editedUsers.length, 1);
    expect(editedUsers.single.name, 'رضا احمدی');
    expect(editedUsers.single.phoneNumber, '09120009988');
    expect(editedUsers.single.avatarIndex, 4);

    // Manual clock sync
    final manualClock = DateTime(2026, 11, 20, 15, 45);
    final clockRes = await notifier.syncDeviceClock(manualClock);
    expect(clockRes.isSimulatedExecution, isTrue);
    expect(
      container
          .read(karenControllerProvider)
          .activeDevice!
          .deviceClockSyncedAt,
      manualClock,
    );
  });
}
