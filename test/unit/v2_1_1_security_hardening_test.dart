import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/security/pin_hasher.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';

import '../test_helpers/in_memory_secure_store.dart';

Future<(ProviderContainer, InMemoryPreferencesStore, InMemorySecureStore, LocalStorageService)>
    _bootWithStores({
  InMemoryPreferencesStore? prefsStore,
  InMemorySecureStore? secureStore,
  int hashIterations = 1000,
}) async {
  final effectivePrefs = prefsStore ?? InMemoryPreferencesStore();
  final effectiveSecure = secureStore ?? InMemorySecureStore();
  final storage = LocalStorageService.withStores(
    effectivePrefs,
    effectiveSecure,
  );
  final initial = await storage.loadAll();

  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      initialAppDataProvider.overrideWithValue(initial),
      pinHashIterationsProvider.overrideWithValue(hashIterations),
      demoTransportProvider.overrideWithValue(
        const DemoCommandTransport(latency: Duration.zero),
      ),
    ],
  );
  return (container, effectivePrefs, effectiveSecure, storage);
}

void main() {
  group('1. PIN Lockout Persistence — Fail-Closed on Write & Silent No-Op Failures', () {
    test('fails closed with storageUnavailable when persisting failed PIN attempt throws', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('2468')).succeeded, isTrue);
      notifier.lockApp();

      // Inject write failure on PIN security state key
      secureStore.failingWriteKeys.add(AppConstants.secureKeyPinSecurityState);

      final res = await notifier.verifyPin('9999');
      expect(res.isUnlocked, isFalse);
      expect(res.status, PinVerificationStatus.storageUnavailable);
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
    });

    test('fails closed with storageUnavailable on silent no-op security-state write', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('2468')).succeeded, isTrue);
      notifier.lockApp();

      // Keystore silently ignores write without throwing!
      secureStore.silentNoOpWriteKeys.add(AppConstants.secureKeyPinSecurityState);

      final res = await notifier.verifyPin('9999');
      expect(res.isUnlocked, isFalse);
      expect(res.status, PinVerificationStatus.storageUnavailable);
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
    });

    test('fails closed on 5th failed attempt if persisting lockout timestamp fails or no-ops', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('2468')).succeeded, isTrue);
      notifier.lockApp();

      final t0 = DateTime.utc(2026, 11, 19, 12, 0, 0);
      for (var i = 0; i < 4; i++) {
        final r = await notifier.verifyPin('0000', nowOverride: t0);
        expect(r.status, PinVerificationStatus.invalidPin);
      }

      // Silent no-op on the 5th attempt that would write lockoutUntilUtc
      secureStore.silentNoOpWriteKeys.add(AppConstants.secureKeyPinSecurityState);
      final fifth = await notifier.verifyPin('0000', nowOverride: t0);
      expect(fifth.isUnlocked, isFalse);
      expect(fifth.status, PinVerificationStatus.storageUnavailable);
    });

    test('fails closed on unlock if clearing lockout state fails silently', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('2468')).succeeded, isTrue);
      notifier.lockApp();

      // Record 1 failure first so persisted security state is non-zero
      final bad = await notifier.verifyPin('0000');
      expect(bad.status, PinVerificationStatus.invalidPin);

      // Now simulate silent no-op write when clearing failures on correct PIN
      secureStore.silentNoOpWriteKeys.add(AppConstants.secureKeyPinSecurityState);
      final unlockAttempt = await notifier.verifyPin('2468');
      expect(unlockAttempt.isUnlocked, isFalse);
      expect(unlockAttempt.status, PinVerificationStatus.storageUnavailable);
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
    });
  });

  group('2. PBKDF2 Parameter Validation & Malformed/DoS Rejection', () {
    const validSalt32Hex = '0123456789abcdef0123456789abcdef';
    const validKey64Hex =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('rejects excessively expensive iteration count safely without CPU DoS', () {
      const dosRecord =
          'pbkdf2_sha256\$999999999\$32\$$validSalt32Hex\$$validKey64Hex';
      final sw = Stopwatch()..start();
      final res = PinHasher.verifyRecord('1234', dosRecord);
      sw.stop();

      expect(res.matched, isFalse);
      expect(res.isMalformed, isTrue);
      expect(res.rejectionReason, 'iterations_out_of_bounds');
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('rejects iterations below minimum threshold and negative/signed values', () {
      for (final badIter in ['0', '1', '500', '-1000', '+100000', 'abc']) {
        final rec =
            'pbkdf2_sha256\$$badIter\$32\$$validSalt32Hex\$$validKey64Hex';
        final res = PinHasher.verifyRecord('1234', rec);
        expect(res.matched, isFalse);
        expect(res.isMalformed, isTrue);
      }
    });

    test('validates exact 16-byte salt length and strict hex encoding', () {
      // Too short (15 bytes = 30 hex), too long (17 bytes = 34 hex), non-hex
      final badSalts = [
        '0123456789abcdef0123456789abcd',
        '0123456789abcdef0123456789abcdef00',
        'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
      ];
      for (final salt in badSalts) {
        final rec = 'pbkdf2_sha256\$100000\$32\$$salt\$$validKey64Hex';
        final res = PinHasher.verifyRecord('1234', rec);
        expect(res.matched, isFalse);
        expect(res.isMalformed, isTrue);
        expect(res.rejectionReason, 'invalid_salt_format_or_length');
      }
    });

    test('validates exact 32-byte derived key length and strict hex encoding', () {
      // Wrong declared key length
      const badLenRec =
          'pbkdf2_sha256\$100000\$64\$$validSalt32Hex\$$validKey64Hex$validKey64Hex';
      expect(PinHasher.verifyRecord('1234', badLenRec).isMalformed, isTrue);

      // Truncated key hex
      const shortKeyRec =
          'pbkdf2_sha256\$100000\$32\$$validSalt32Hex\$0123456789abcdef';
      expect(PinHasher.verifyRecord('1234', shortKeyRec).isMalformed, isTrue);

      // Non-hex chars in derived key
      const nonHexKey =
          'gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg';
      const badHexRec =
          'pbkdf2_sha256\$100000\$32\$$validSalt32Hex\$$nonHexKey';
      expect(PinHasher.verifyRecord('1234', badHexRec).isMalformed, isTrue);
    });

    test('verifyPin fails closed with storageUnavailable when stored hash is malformed', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      notifier.lockApp();

      // Tamper hash with DoS iteration count
      secureStore.data[AppConstants.secureKeyAppPinHash] =
          'pbkdf2_sha256\$99999999\$32\$$validSalt32Hex\$$validKey64Hex';

      final res = await notifier.verifyPin('1234');
      expect(res.isUnlocked, isFalse);
      expect(res.status, PinVerificationStatus.storageUnavailable);
    });

    test('preserves migration for both legacy V2.0 and lower-iteration PBKDF2 records', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final lowIterHash = PinHasher.createSaltedHash('8842', iterations: 2000);
      secureStore.data[AppConstants.secureKeyAppPinHash] = lowIterHash;

      final storage = LocalStorageService.withStores(prefsStore, secureStore);
      await storage.saveSettings(const AppSettings(pinLockEnabled: true));

      final (container, _, _, _) = await _bootWithStores(
        prefsStore: prefsStore,
        secureStore: secureStore,
        hashIterations: 5000,
      );
      addTearDown(container.dispose);

      final res = await container
          .read(karenControllerProvider.notifier)
          .verifyPin('8842');
      expect(res.isUnlocked, isTrue);
      expect(res.hashMigrated, isTrue);
      expect(
        secureStore.data[AppConstants.secureKeyAppPinHash],
        startsWith('pbkdf2_sha256\$5000\$32\$'),
      );
    });
  });

  group('3. Settings Persistence Integrity', () {
    test('setPinLock activation fails and rolls back hash when SharedPreferences returns false', () async {
      final (container, prefsStore, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      prefsStore.returnFalseOnSet = true;
      final res = await container
          .read(karenControllerProvider.notifier)
          .setPinLock('1234');

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isFalse,
      );
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNull);
    });

    test('setPinLock activation fails on silent no-op SharedPreferences write', () async {
      final (container, prefsStore, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      prefsStore.silentNoOpSet = true;
      final res = await container
          .read(karenControllerProvider.notifier)
          .setPinLock('1234');

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isFalse,
      );
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNull);
    });

    test('setPinLock deactivation fails before commit and preserves PIN hash if SharedPreferences write fails', () async {
      final (container, prefsStore, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      final originalHash = secureStore.data[AppConstants.secureKeyAppPinHash];
      expect(originalHash, isNotNull);

      prefsStore.returnFalseOnSet = true;
      final res = await notifier.setPinLock(null);

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isTrue,
      );
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], originalHash);
    });

    test('setPinLock deactivation rolls back completely if deleting the old hash fails', () async {
      final (container, _, secureStore, storage) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      secureStore.failingDeleteKeys.add(AppConstants.secureKeyAppPinHash);
      final res = await notifier.setPinLock(null);

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(res.pinLockEnabledAfter, isTrue);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isTrue,
      );
      expect(storage.loadSettings().pinLockEnabled, isTrue);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(
        await storage.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
    });

    test('emergency reset fails and keeps app locked if pinLockEnabled == false cannot be persisted', () async {
      final (container, prefsStore, _, storage) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      notifier.lockApp();

      // Settings persistence silently fails to save pinLockEnabled == false
      prefsStore.silentNoOpSetKeys.add(AppConstants.prefsKeySettings);

      final wipeRes = await notifier.emergencyWipeAndUnlock();
      expect(wipeRes.success, isFalse);
      expect(wipeRes.failedKeys, contains(AppConstants.prefsKeySettings));
      expect(container.read(karenControllerProvider).isUnlocked, isFalse);
      expect(
        container.read(karenControllerProvider).settings.pinLockEnabled,
        isTrue,
      );
      expect(storage.loadSettings().pinLockEnabled, isTrue);
    });
  });

  group('4. PIN Verification Reliability: Concurrency & Expired Lockout Recovery', () {
    test('serializes 5 concurrent verifyPin calls cleanly without lost attempt increments', () async {
      final (container, _, secureStore, _) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('7777')).succeeded, isTrue);
      notifier.lockApp();

      // Add small async write delay to maximize race pressure
      secureStore.artificialWriteDelay = const Duration(milliseconds: 5);
      final t0 = DateTime.utc(2026, 11, 19, 14, 0, 0);

      final results = await Future.wait([
        notifier.verifyPin('0001', nowOverride: t0),
        notifier.verifyPin('0002', nowOverride: t0),
        notifier.verifyPin('0003', nowOverride: t0),
        notifier.verifyPin('0004', nowOverride: t0),
        notifier.verifyPin('0005', nowOverride: t0),
      ]);

      expect(results[0].status, PinVerificationStatus.invalidPin);
      expect(results[0].remainingAttempts, 4);
      expect(results[1].remainingAttempts, 3);
      expect(results[2].remainingAttempts, 2);
      expect(results[3].remainingAttempts, 1);
      expect(results[4].status, PinVerificationStatus.lockedOut);
      expect(results[4].remainingAttempts, 0);
    });

    test('expired lockout cleanly resets attempt counter on next wrong PIN and unlocks on right PIN', () async {
      final (container, _, _, storage) = await _bootWithStores();
      addTearDown(container.dispose);

      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('5151')).succeeded, isTrue);
      notifier.lockApp();

      final t0 = DateTime.utc(2026, 11, 19, 15, 0, 0);
      for (var i = 0; i < 5; i++) {
        await notifier.verifyPin('0000', nowOverride: t0);
      }

      // After 31s lockout expires, a wrong PIN starts a fresh attempt window (1 of 5 -> 4 remaining)
      final tAfter = t0.add(const Duration(seconds: 31));
      final wrongAfterExpiry = await notifier.verifyPin('9999', nowOverride: tAfter);
      expect(wrongAfterExpiry.status, PinVerificationStatus.invalidPin);
      expect(wrongAfterExpiry.remainingAttempts, 4);

      final persisted = await storage.loadPinSecurityState();
      expect(persisted.failedAttempts, 1);
      expect(persisted.lockoutUntilUtc, isNull);

      // Correct PIN now unlocks and clears persisted failure count to 0
      final ok = await notifier.verifyPin('5151', nowOverride: tAfter);
      expect(ok.isUnlocked, isTrue);
      final cleared = await storage.loadPinSecurityState();
      expect(cleared.failedAttempts, 0);
      expect(cleared.lockoutUntilUtc, isNull);
    });
  });
}
