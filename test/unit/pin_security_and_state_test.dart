import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/security/pin_hasher.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';
import 'package:karen_next/core/transport/protocol_templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/in_memory_secure_store.dart';

String _bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<(ProviderContainer, InMemorySecureStore, LocalStorageService, SharedPreferences)>
    _createContainer({
  SmsUrlLauncher? smsLauncher,
  InMemorySecureStore? existingSecureStore,
  SharedPreferences? existingPrefs,
  int hashIterations = 1000,
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
      pinHashIterationsProvider.overrideWithValue(hashIterations),
      demoTransportProvider.overrideWithValue(
        const DemoCommandTransport(latency: Duration.zero),
      ),
      smsTransportProvider.overrideWithValue(
        SmsComposerCommandTransport(launcher: smsLauncher ?? (_) async => true),
      ),
    ],
  );
  return (container, secureStore, storage, prefs);
}

void main() {
  group('PBKDF2-HMAC-SHA256 Cryptography, Vectors & Migration', () {
    test('matches official RFC 2898 / OpenSSL PBKDF2-HMAC-SHA256 test vectors', () {
      final v1 = PinHasher.derivePbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLengthBytes: 32,
      );
      expect(
        _bytesToHex(v1),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );

      final v2 = PinHasher.derivePbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 2,
        keyLengthBytes: 32,
      );
      expect(
        _bytesToHex(v2),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );

      final v4096 = PinHasher.derivePbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 4096,
        keyLengthBytes: 32,
      );
      expect(
        _bytesToHex(v4096),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('produces unique random salt per PIN and stores algorithm parameters', () {
      final h1 = PinHasher.createSaltedHash('2580', iterations: 2000);
      final h2 = PinHasher.createSaltedHash('2580', iterations: 2000);

      expect(h1, startsWith('pbkdf2_sha256\$2000\$32\$'));
      expect(h2, startsWith('pbkdf2_sha256\$2000\$32\$'));
      expect(h1, isNot(equals(h2)));
      expect(PinHasher.verifySaltedHash('2580', h1), isTrue);
      expect(PinHasher.verifySaltedHash('0000', h1), isFalse);
    });

    test('migrates legacy V2.0 SHA-256 hash automatically to PBKDF2-HMAC-SHA256 on unlock', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService(prefs, secureStore);

      // Seed legacy V2.0 hash & enable PIN lock
      final legacyHash =
          PinHasher.createLegacyV2HashForTesting('7391', '0123456789abcdef');
      secureStore.data[AppConstants.secureKeyAppPinHash] = legacyHash;
      await storage.saveSettings(const AppSettings(pinLockEnabled: true));

      final (container, _, _, _) = await _createContainer(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
        hashIterations: 5000,
      );
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      final wrong = await notifier.verifyPin('0000');
      expect(wrong.isUnlocked, isFalse);

      final ok = await notifier.verifyPin('7391');
      expect(ok.isUnlocked, isTrue);
      expect(ok.hashMigrated, isTrue);

      // Stored hash is now upgraded to parameterized PBKDF2-HMAC-SHA256
      final upgraded = secureStore.data[AppConstants.secureKeyAppPinHash]!;
      expect(upgraded, startsWith('pbkdf2_sha256\$5000\$32\$'));
      expect(PinHasher.verifySaltedHash('7391', upgraded), isTrue);
    });

    test('PBKDF2 benchmark reports valid latency metrics', () {
      final bench = PinHasher.benchmarkPbkdf2(iterations: 500);
      expect(bench.algorithm, PinHasher.algorithmPbkdf2Sha256);
      expect(bench.iterations, 500);
      expect(bench.keyLengthBytes, 32);
      expect(bench.elapsedMicroseconds, greaterThanOrEqualTo(0));
    });
  });

  group('Persistent Brute-Force Protection Across Full App Restarts', () {
    test('preserves failed attempt count and active lockout timestamp after complete restart', () async {
      final (c1, secureStore, _, prefs) = await _createContainer();
      final notifier1 = c1.read(karenControllerProvider.notifier);
      await notifier1.setPinLock('4321');
      notifier1.lockApp();

      final t0 = DateTime.utc(2026, 11, 19, 12, 0, 0);
      // 3 failed attempts in Session 1
      for (var i = 0; i < 3; i++) {
        final res = await notifier1.verifyPin('9999', nowOverride: t0);
        expect(res.status, PinVerificationStatus.invalidPin);
      }
      expect(c1.read(karenControllerProvider).failedPinAttempts, 3);
      c1.dispose();

      // Simulate complete app close & cold restart (Session 2)
      final (c2, _, _, _) = await _createContainer(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
      );
      expect(c2.read(karenControllerProvider).failedPinAttempts, 3);
      expect(c2.read(karenControllerProvider).isUnlocked, isFalse);

      final notifier2 = c2.read(karenControllerProvider.notifier);
      // 4th attempt -> still invalidPin (1 remaining)
      final fourth = await notifier2.verifyPin('9999', nowOverride: t0);
      expect(fourth.status, PinVerificationStatus.invalidPin);
      expect(fourth.remainingAttempts, 1);

      // 5th attempt -> triggers 30s persistent lockout
      final fifth = await notifier2.verifyPin('9999', nowOverride: t0);
      expect(fifth.status, PinVerificationStatus.lockedOut);
      c2.dispose();

      // Simulate ANOTHER complete restart during active lockout (Session 3)
      final (c3, _, _, _) = await _createContainer(
        existingSecureStore: secureStore,
        existingPrefs: prefs,
      );
      addTearDown(c3.dispose);
      final notifier3 = c3.read(karenControllerProvider.notifier);

      // Even the correct PIN is blocked 10s later after restart!
      final duringLockout = await notifier3.verifyPin(
        '4321',
        nowOverride: t0.add(const Duration(seconds: 10)),
      );
      expect(duringLockout.isUnlocked, isFalse);
      expect(duringLockout.status, PinVerificationStatus.lockedOut);

      // After 31s cooldown expires, correct PIN succeeds and resets counter
      final afterLockout = await notifier3.verifyPin(
        '4321',
        nowOverride: t0.add(const Duration(seconds: 31)),
      );
      expect(afterLockout.isUnlocked, isTrue);
      expect(c3.read(karenControllerProvider).failedPinAttempts, 0);
    });

    test('FAILS CLOSED when secure storage returns null or throws while PIN lock is enabled', () async {
      final (container, secureStore, _, _) = await _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.setPinLock('1234');
      notifier.lockApp();

      // Case 1: Missing hash
      secureStore.data.remove(AppConstants.secureKeyAppPinHash);
      final missingRes = await notifier.verifyPin('1234');
      expect(missingRes.isUnlocked, isFalse);
      expect(missingRes.status, PinVerificationStatus.storageUnavailable);

      // Case 2: Storage throws
      secureStore.failReads = true;
      final errorRes = await notifier.verifyPin('1234');
      expect(errorRes.isUnlocked, isFalse);
      expect(errorRes.status, PinVerificationStatus.storageUnavailable);
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
    });
  });

  group('Honest Device State Management (Demo vs Live SMS)', () {
    test('Demo mode updates simulated power, schedule, and user states', () async {
      final (container, _, _, _) = await _createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'پمپ تست',
        phoneNumber: '09123456789',
      );

      final powerRes = await notifier.setPower(true);
      expect(powerRes.isSimulatedExecution, isTrue);
      expect(
        container.read(karenControllerProvider).activeDevice!.powerState,
        DevicePowerState.on,
      );

      final schedRes = await notifier.uploadDayStatus(0);
      expect(schedRes.isSimulatedExecution, isTrue);
      expect(
        container
            .read(karenControllerProvider)
            .activeDevice!
            .weeklySchedules[0]
            .syncStatus,
        SyncStatus.syncedDemo,
      );
    });

    test('Live SMS mode NEVER mutates powerState or claims synced when opening SMS composer', () async {
      final launchedUris = <Uri>[];
      final (container, _, _, _) = await _createContainer(
        smsLauncher: (uri) async {
          launchedUris.add(uri);
          return true;
        },
      );
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      await notifier.addOrUpdateDevice(
        title: 'پمپ واقعی',
        phoneNumber: '09123456789',
      );

      final currentSettings = container.read(karenControllerProvider).settings;
      await notifier.updateSettings(
        currentSettings.copyWith(transportMode: TransportMode.liveSmsComposer),
      );

      // Unverified template blocked
      final blocked = await notifier.setPower(true);
      expect(blocked.status, CommandLogStatus.blockedUnverified);
      expect(launchedUris, isEmpty);
      expect(
        container.read(karenControllerProvider).activeDevice!.powerState,
        DevicePowerState.unknown,
      );

      // Verified template opens composer -> pendingConfirmation, powerState stays unknown
      await notifier.updateProtocolTemplate(
        ProtocolTemplates.keyPowerOn,
        'VERIFIED_ON',
      );
      final powerSms = await notifier.setPower(true);
      expect(powerSms.isPendingConfirmation, isTrue);
      expect(powerSms.status, CommandLogStatus.pendingConfirmation);
      expect(launchedUris.length, 1);
      expect(
        container.read(karenControllerProvider).activeDevice!.powerState,
        DevicePowerState.unknown,
      );
    });
  });
}
