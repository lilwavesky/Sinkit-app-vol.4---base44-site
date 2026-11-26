import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/in_memory_secure_store.dart';

Future<(ProviderContainer, InMemorySecureStore, LocalStorageService)>
    _bootApp({
  InMemorySecureStore? existingSecureStore,
  SharedPreferences? existingPrefs,
}) async {
  SharedPreferences prefs;
  if (existingPrefs != null) {
    prefs = existingPrefs;
  } else {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }
  final secureStore = existingSecureStore ?? InMemorySecureStore();
  final storage = LocalStorageService(prefs, secureStore);
  final initial = await storage.loadAll();

  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      initialAppDataProvider.overrideWithValue(initial),
      pinHashIterationsProvider.overrideWithValue(1000),
      demoTransportProvider.overrideWithValue(
        const DemoCommandTransport(latency: Duration.zero),
      ),
    ],
  );
  return (container, secureStore, storage);
}

void main() {
  group('Emergency PIN Wipe Security Invariants', () {
    test('NEVER disables PIN or unlocks on complete deletion failure', () async {
      final (container, secureStore, storage) = await _bootApp();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'تابلو اصلی',
        phoneNumber: '09123456789',
      );
      await notifier.setPinLock('2468');
      notifier.lockApp();

      // Keystore unavailable for all deletes
      secureStore.failDeletes = true;

      final result = await notifier.emergencyWipeAndUnlock();
      expect(result.success, isFalse);
      expect(result.failedKeys, isNotEmpty);

      final state = container.read(karenControllerProvider);
      expect(state.isUnlocked, isFalse);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(storage.loadSettings().pinLockEnabled, isTrue);
    });

    test('NEVER disables PIN or unlocks on partial deletion failure', () async {
      final (container, secureStore, storage) = await _bootApp();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'پمپ چاه',
        phoneNumber: '09121112233',
      );
      await notifier.setPower(true);
      await notifier.setPinLock('1357');
      notifier.lockApp();

      // Devices deletes cleanly, but logs fail to delete!
      secureStore.failingDeleteKeys.add(AppConstants.secureKeyLogs);

      final result = await notifier.emergencyWipeAndUnlock();
      expect(result.success, isFalse);
      expect(result.failedKeys, contains(AppConstants.secureKeyLogs));

      // PIN hash MUST still be intact and lock MUST stay enabled!
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNotNull);
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isTrue,
      );
      expect(storage.loadSettings().pinLockEnabled, isTrue);
    });

    test('NEVER disables PIN when delete() silently leaves residual data behind', () async {
      final (container, secureStore, _) = await _bootApp();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'موتورخانه',
        phoneNumber: '09351112233',
      );
      await notifier.setPinLock('9876');
      notifier.lockApp();

      // Simulate silent no-op delete on devices key
      secureStore.stickyKeys.add(AppConstants.secureKeyDevices);

      final result = await notifier.emergencyWipeAndUnlock();
      expect(result.success, isFalse);
      expect(result.failedKeys, contains(AppConstants.secureKeyDevices));
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isTrue,
      );
    });

    test('succeeds and unlocks ONLY when every sensitive key is verified deleted', () async {
      final (container, secureStore, storage) = await _bootApp();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'پمپ شمال',
        phoneNumber: '09127778899',
      );
      await notifier.setPower(true);
      await notifier.setPinLock('5555');
      notifier.lockApp();

      final result = await notifier.emergencyWipeAndUnlock();
      expect(result.success, isTrue);
      expect(result.failedKeys, isEmpty);

      for (final key in AppConstants.allSensitiveSecureKeys) {
        expect(secureStore.data.containsKey(key), isFalse);
      }
      final state = container.read(karenControllerProvider);
      expect(state.isUnlocked, isTrue);
      expect(state.settings.pinLockEnabled, isFalse);
      expect(state.devices, isEmpty);
      expect(storage.loadSettings().pinLockEnabled, isFalse);
    });
  });

  group('Secure Storage Read Failures, Corruption & Write Protection', () {
    test('distinguishes unavailable encrypted storage from an empty DB, blocks overwrites, and recovers on retry', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = InMemorySecureStore();

      // Session 1: Save a real device
      final (c1, _, _) = await _bootApp(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
      );
      await c1.read(karenControllerProvider.notifier).addOrUpdateDevice(
            title: 'دستگاه مهم قبلی',
            phoneNumber: '09129998877',
          );
      c1.dispose();

      // Session 2: Android Keystore temporarily fails reads
      secureStore.failReads = true;
      final (c2, _, _) = await _bootApp(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
      );
      addTearDown(c2.dispose);

      final degradedState = c2.read(karenControllerProvider);
      expect(degradedState.devicesStorageStatus, StorageLoadStatus.readError);
      expect(degradedState.isDevicesWriteProtected, isTrue);

      // Attempt to add or seed a device MUST be blocked so real data is NOT overwritten
      final addErr =
          await c2.read(karenControllerProvider.notifier).addOrUpdateDevice(
                title: 'دستگاه جدید',
                phoneNumber: '09120001122',
              );
      expect(addErr, isNotNull);

      final seedErr =
          await c2.read(karenControllerProvider.notifier).seedDemoDevice();
      expect(seedErr, isNotNull);

      // Session 2 Recovery: Keystore recovers -> retry restores original device intact!
      secureStore.failReads = false;
      final recovered = await c2
          .read(karenControllerProvider.notifier)
          .retrySecureStorageLoad();
      expect(recovered, isTrue);

      final restoredState = c2.read(karenControllerProvider);
      expect(restoredState.devicesStorageStatus, StorageLoadStatus.loaded);
      expect(restoredState.isDevicesWriteProtected, isFalse);
      expect(restoredState.devices.length, 1);
      expect(restoredState.devices.first.title, 'دستگاه مهم قبلی');
      expect(restoredState.devices.first.phoneNumber, '09129998877');
    });

    test('detects corrupted encrypted JSON payload and recovers only after explicit confirmed reset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = InMemorySecureStore();
      secureStore.data[AppConstants.secureKeyDevices] = '{corrupted_json!!!';

      final (container, _, _) = await _bootApp(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
      );
      addTearDown(container.dispose);

      final state = container.read(karenControllerProvider);
      expect(state.devicesStorageStatus, StorageLoadStatus.corruptedData);
      expect(state.isDevicesWriteProtected, isTrue);

      // Write protection active before explicit reset
      final blockedErr = await container
          .read(karenControllerProvider.notifier)
          .addOrUpdateDevice(title: 'تست', phoneNumber: '09121234567');
      expect(blockedErr, isNotNull);

      // Explicit user-confirmed reset of corrupted store
      final wipeRes = await container
          .read(karenControllerProvider.notifier)
          .resetAffectedCorruptedStores();
      expect(wipeRes.success, isTrue);
      expect(
        container.read(karenControllerProvider).devicesStorageStatus,
        StorageLoadStatus.loaded,
      );
      expect(
        container.read(karenControllerProvider).isDevicesWriteProtected,
        isFalse,
      );
    });

    test('handles secure storage write failures gracefully without corrupting in-memory state', () async {
      final (container, secureStore, _) = await _bootApp();
      addTearDown(container.dispose);

      secureStore.failWrites = true;
      final err = await container
          .read(karenControllerProvider.notifier)
          .addOrUpdateDevice(title: 'پمپ ۱', phoneNumber: '09123456789');
      expect(err, isNotNull);
      expect(container.read(karenControllerProvider).devices, isEmpty);
    });
  });
}
