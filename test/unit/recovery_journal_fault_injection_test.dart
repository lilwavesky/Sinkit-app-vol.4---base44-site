import 'dart:convert';

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
    _boot({
  InMemoryPreferencesStore? prefsStore,
  InMemorySecureStore? secureStore,
  int hashIterations = 1000,
}) async {
  final p = prefsStore ?? InMemoryPreferencesStore();
  final s = secureStore ?? InMemorySecureStore();
  final storage = LocalStorageService.withStores(p, s);
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
  return (container, p, s, storage);
}

void main() {
  group('Persistent Recovery Journal — Lifecycle & Restart Recovery', () {
    test('journal is cleaned up and never contains plaintext PIN after committed activation, rotation, and deactivation', () async {
      final (container, _, secureStore, storage) = await _boot();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);

      expect((await notifier.setPinLock('2468')).status, PinTransactionStatus.committed);
      expect(await storage.loadPinTransactionJournal(), isNull);
      for (final val in secureStore.data.values) {
        expect(val, isNot(contains('2468')));
      }

      expect((await notifier.setPinLock('9753')).status, PinTransactionStatus.committed);
      expect(await storage.loadPinTransactionJournal(), isNull);
      for (final val in secureStore.data.values) {
        expect(val, isNot(contains('9753')));
      }

      expect((await notifier.setPinLock(null)).status, PinTransactionStatus.committed);
      expect(await storage.loadPinTransactionJournal(), isNull);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNull);
    });

    test('application restart during unfinished PIN rotation restores previous hash, failed attempts, and lockout state', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);

      final oldHash = PinHasher.createSaltedHash('1234', iterations: 1000);
      final partialNewHash = PinHasher.createSaltedHash('9999', iterations: 1000);
      final priorLockout = DateTime.utc(2026, 11, 20, 14, 0, 0);

      // Simulate crash mid-rotation: uncommitted journal exists, new hash was partially written,
      // and in-flight security state overwrote failedAttempts.
      final uncommittedJournal = PinTransactionJournal(
        transactionId: 'pintx_crash_rot_1',
        operation: PinTransactionOperation.rotate,
        startedAtUtc: DateTime.utc(2026, 11, 20, 13, 59, 0),
        committed: false,
        previousHash: oldHash,
        previousPinLockEnabled: true,
        previousFailedAttempts: 3,
        previousLockoutUntilUtc: priorLockout,
        targetHash: partialNewHash,
        targetPinLockEnabled: true,
      );
      await storage.savePinTransactionJournal(uncommittedJournal);
      secureStore.data[AppConstants.secureKeyAppPinHash] = partialNewHash;
      await storage.savePinSecurityState(
        const PinSecurityState(recoveryRequired: true, pinLockEnabled: true),
      );
      await storage.saveSettings(const AppSettings(pinLockEnabled: true));

      // Cold restart: loadAll() MUST recover the complete prior snapshot and delete journal
      final (c2, _, _, storage2) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);

      expect(await storage2.loadPinTransactionJournal(), isNull);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);

      final state = c2.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(state.requiresUnlock, isTrue);
      expect(state.pinRecoveryRequired, isFalse);
      expect(state.failedPinAttempts, 3);
      expect(state.pinLockoutUntil, priorLockout);

      // Verify after lockout expires: OLD PIN '1234' works and interrupted '9999' does NOT
      final afterLockout = priorLockout.add(const Duration(seconds: 1));
      final notifier2 = c2.read(karenControllerProvider.notifier);
      expect(
        (await notifier2.verifyPin('9999', nowOverride: afterLockout)).isUnlocked,
        isFalse,
      );
      expect(
        (await notifier2.verifyPin('1234', nowOverride: afterLockout)).isUnlocked,
        isTrue,
      );
    });

    test('application restart during unfinished PIN deactivation restores enabled PIN and stays strictly locked', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);

      final oldHash = PinHasher.createSaltedHash('5544', iterations: 1000);
      final uncommittedDisable = PinTransactionJournal(
        transactionId: 'pintx_crash_deact_1',
        operation: PinTransactionOperation.deactivate,
        startedAtUtc: DateTime.utc(2026, 11, 20, 12, 0, 0),
        committed: false,
        previousHash: oldHash,
        previousPinLockEnabled: true,
        previousFailedAttempts: 2,
        previousLockoutUntilUtc: null,
        targetHash: null,
        targetPinLockEnabled: false,
      );
      // Crash occurred after hash deleted and settings flipped false, BEFORE commit!
      await storage.savePinTransactionJournal(uncommittedDisable);
      secureStore.data.remove(AppConstants.secureKeyAppPinHash);
      await storage.saveSettings(const AppSettings(pinLockEnabled: false));
      await storage.savePinSecurityState(
        const PinSecurityState(recoveryRequired: true, pinLockEnabled: true),
      );

      final (c2, _, _, storage2) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);

      expect(await storage2.loadPinTransactionJournal(), isNull);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(storage2.loadSettings().pinLockEnabled, isTrue);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(c2.read(karenControllerProvider).failedPinAttempts, 2);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('5544'))
            .isUnlocked,
        isTrue,
      );
    });

    test('application restart with committed journal reconciles cleanly and deletes stale journal', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);

      final oldHash = PinHasher.createSaltedHash('1111', iterations: 1000);
      final newHash = PinHasher.createSaltedHash('2222', iterations: 1000);
      final committedJournal = PinTransactionJournal(
        transactionId: 'pintx_committed_crash_1',
        operation: PinTransactionOperation.rotate,
        startedAtUtc: DateTime.utc(2026, 11, 20, 12, 0, 0),
        committed: true,
        previousHash: oldHash,
        previousPinLockEnabled: true,
        previousFailedAttempts: 0,
        previousLockoutUntilUtc: null,
        targetHash: newHash,
        targetPinLockEnabled: true,
      );

      // Simulate crash right after Step 7 (committed) and before Step 8 (journal delete)
      await storage.savePinTransactionJournal(committedJournal);
      secureStore.data[AppConstants.secureKeyAppPinHash] = newHash;
      await storage.savePinSecurityState(
        const PinSecurityState(pinLockEnabled: true),
      );
      await storage.saveSettings(const AppSettings(pinLockEnabled: true));

      final (c2, _, _, storage2) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);

      expect(await storage2.loadPinTransactionJournal(), isNull);
      expect(c2.read(karenControllerProvider).pinRecoveryRequired, isFalse);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('2222'))
            .isUnlocked,
        isTrue,
      );
    });

    test('corrupted recovery journal JSON fails closed and forces pinRecoveryRequired on restart', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      secureStore.data[AppConstants.secureKeyPinJournal] = '{corrupted_journal';

      final (c2, _, _, _) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);

      final state = c2.read(karenControllerProvider);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.requiresUnlock, isTrue);
      expect(state.isUnlocked, isFalse);
    });

    test('unreadable recovery journal fails closed on restart and stays locked', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      secureStore.failingReadKeys.add(AppConstants.secureKeyPinJournal);

      final (c2, _, _, _) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);

      final state = c2.read(karenControllerProvider);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.requiresUnlock, isTrue);
    });
  });

  group('Fault Injection — Journal Write, Post-Write Exception, Post-Delete Exception & Repeated Attempts', () {
    test('journal write failure before writing aborts cleanly without touching prior state', () async {
      final (container, _, secureStore, storage) = await _boot();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);

      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      secureStore.failingWriteKeys.add(AppConstants.secureKeyPinJournal);
      final res = await notifier.setPinLock('5678');

      expect(res.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(await storage.loadPinTransactionJournal(), isNull);
    });

    test('journal write succeeds then throws -> detects residual journal, cleans it up, and aborts cleanly', () async {
      final (container, _, secureStore, storage) = await _boot();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);

      expect((await notifier.setPinLock('1234')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      secureStore.writeThenThrowAfterCount[AppConstants.secureKeyPinJournal] =
          secureStore.writeCounts[AppConstants.secureKeyPinJournal] ?? 0;

      final res = await notifier.setPinLock('5678');
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(await storage.loadPinTransactionJournal(), isNull);
    });

    test('journal deletion fails at Step 8 after commit -> enters Fail-Closed recoveryRequired state', () async {
      final (container, _, secureStore, _) = await _boot();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);

      secureStore.failingDeleteKeys.add(AppConstants.secureKeyPinJournal);
      final res = await notifier.setPinLock('4455');

      expect(res.status, PinTransactionStatus.recoveryRequired);
      expect(container.read(karenControllerProvider).pinRecoveryRequired, isTrue);
      expect(container.read(karenControllerProvider).requiresUnlock, isTrue);
    });

    test('delete-then-throw on PIN hash during deactivation rolls back cleanly and preserves old PIN', () async {
      final (container, prefsStore, secureStore, _) = await _boot();
      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('6161')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      secureStore.deleteThenThrowKeys.add(AppConstants.secureKeyAppPinHash);
      final res = await notifier.setPinLock(null);

      expect(res.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      container.dispose();

      // Restart verifies old PIN still required and works
      final (c2, _, _, _) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('6161'))
            .isUnlocked,
        isTrue,
      );
    });

    test('multiple consecutive failures followed by repeated valid transaction succeeds cleanly', () async {
      final (container, prefsStore, secureStore, _) = await _boot();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);

      expect((await notifier.setPinLock('1111')).succeeded, isTrue);

      // Consecutive failure #1: settings return false
      prefsStore.returnFalseOnSet = true;
      expect((await notifier.setPinLock('2222')).status, PinTransactionStatus.rolledBack);

      // Consecutive failure #2: security state write fails
      prefsStore.returnFalseOnSet = false;
      secureStore.failingWriteKeys.add(AppConstants.secureKeyPinSecurityState);
      expect((await notifier.setPinLock('3333')).status, PinTransactionStatus.rolledBack);

      // Consecutive failure #3: silent no-op on hash write
      secureStore.failingWriteKeys.clear();
      secureStore.silentNoOpWriteKeys.add(AppConstants.secureKeyAppPinHash);
      expect((await notifier.setPinLock('4444')).status, PinTransactionStatus.rolledBack);

      // Recovery: storage healthy -> repeated attempt succeeds cleanly!
      secureStore.silentNoOpWriteKeys.clear();
      expect((await notifier.setPinLock('5555')).status, PinTransactionStatus.committed);

      notifier.lockApp();
      expect((await notifier.verifyPin('1111')).isUnlocked, isFalse);
      expect((await notifier.verifyPin('5555')).isUnlocked, isTrue);
    });

    test('previous-version compatibility: legacy V2.1.1 records without journal or pinLockEnabled mirror boot and migrate cleanly', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();

      // Simulate a V2.1.1 install: old PinSecurityState JSON without `recoveryRequired`/`pinLockEnabled`
      final legacyV2Hash = PinHasher.createLegacyV2HashForTesting(
        '4826',
        '0123456789abcdef0123456789abcdef',
      );
      secureStore.data[AppConstants.secureKeyAppPinHash] = legacyV2Hash;
      secureStore.data[AppConstants.secureKeyPinSecurityState] = jsonEncode({
        'failedAttempts': 2,
        'lockoutUntilUtc': null,
      });
      prefsStore.data[AppConstants.prefsKeySettings] = jsonEncode({
        'themeMode': 'dark',
        'transportMode': 'demo',
        'confirmPowerActions': true,
        'pinLockEnabled': true,
      });

      final (container, _, _, _) = await _boot(
        prefsStore: prefsStore,
        secureStore: secureStore,
        hashIterations: 5000,
      );
      addTearDown(container.dispose);

      final st = container.read(karenControllerProvider);
      expect(st.settings.pinLockEnabled, isTrue);
      expect(st.requiresUnlock, isTrue);
      expect(st.pinRecoveryRequired, isFalse);
      expect(st.failedPinAttempts, 2);

      // Unlocking migrates legacy hash to PBKDF2-HMAC-SHA256 and clears attempts
      final unlock = await container
          .read(karenControllerProvider.notifier)
          .verifyPin('4826');
      expect(unlock.isUnlocked, isTrue);
      expect(unlock.hashMigrated, isTrue);
      expect(
        secureStore.data[AppConstants.secureKeyAppPinHash],
        startsWith('pbkdf2_sha256\$5000\$32\$'),
      );
    });
  });
}
