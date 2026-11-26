import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/security/pin_hasher.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';

import '../test_helpers/in_memory_secure_store.dart';

Future<(ProviderContainer, InMemoryPreferencesStore, InMemorySecureStore, LocalStorageService)>
    _bootSession({
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
  group('V2.1.2 Critical Issue 1 — PIN Deactivation Transaction', () {
    test('PIN deletion failure rolls back the full prior state; restart still enforces the old PIN', () async {
      final (c1, prefsStore, secureStore, storage1) = await _bootSession();
      final n1 = c1.read(karenControllerProvider.notifier);

      expect((await n1.setPinLock('1234')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];
      expect(oldHash, isNotNull);

      // Hash deletion fails after the transaction journal has been persisted.
      secureStore.failingDeleteKeys.add(AppConstants.secureKeyAppPinHash);
      final res = await n1.setPinLock(null);

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(res.pinLockEnabledAfter, isTrue);
      expect(c1.read(karenControllerProvider).settings.pinLockEnabled, isTrue);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(
        await storage1.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
      expect(storage1.loadSettings().pinLockEnabled, isTrue);
      c1.dispose();

      // Restart continues enforcing the same PIN; no half-committed disable.
      secureStore.failingDeleteKeys.clear();
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('1234'))
            .isUnlocked,
        isTrue,
      );
    });

    test('PIN deactivation fails at settings commit: process restart STILL enforces enabled PIN', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final n1 = c1.read(karenControllerProvider.notifier);

      expect((await n1.setPinLock('2580')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      // Block settings commit during deactivation
      prefsStore.returnFalseOnSet = true;
      final res = await n1.setPinLock(null);
      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(c1.read(karenControllerProvider).settings.pinLockEnabled, isTrue);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      c1.dispose();

      // Full process restart MUST start locked and enforce '2580'
      prefsStore.returnFalseOnSet = false;
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).settings.pinLockEnabled, isTrue);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);

      final wrong =
          await c2.read(karenControllerProvider.notifier).verifyPin('0000');
      expect(wrong.isUnlocked, isFalse);

      final ok =
          await c2.read(karenControllerProvider.notifier).verifyPin('2580');
      expect(ok.isUnlocked, isTrue);
    });

    test('clean PIN disable followed by application restart leaves app unlocked and old hash deleted', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final n1 = c1.read(karenControllerProvider.notifier);

      expect((await n1.setPinLock('1357')).succeeded, isTrue);
      final disableRes = await n1.setPinLock(null);
      expect(disableRes.status, PinTransactionStatus.committed);
      expect(disableRes.cleanupSucceeded, isTrue);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNull);
      c1.dispose();

      // Simulate full application restart
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).settings.pinLockEnabled, isFalse);
      expect(c2.read(karenControllerProvider).requiresUnlock, isFalse);
      expect(c2.read(karenControllerProvider).isUnlocked, isTrue);
    });

    test('delete that removes the PIN hash and then throws restores the old hash', () async {
      final (container, _, secureStore, storage) = await _bootSession();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('6248')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      secureStore.deleteThenThrowKeys.add(AppConstants.secureKeyAppPinHash);
      final result = await notifier.setPinLock(null);

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(storage.loadSettings().pinLockEnabled, isTrue);
      expect(
        await storage.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
    });

    test('settings write that persists and then returns false is rolled back safely during deactivation', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final notifier = c1.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('8642')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      // The deactivation setting is written to storage, but the adapter reports
      // failure. Rollback must inspect and restore the prior snapshot.
      prefsStore.writeThenReturnFalseAfterCount[
        AppConstants.prefsKeySettings
      ] = prefsStore.setCounts[AppConstants.prefsKeySettings]!;
      final result = await notifier.setPinLock(null);

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(c1.read(karenControllerProvider).settings.pinLockEnabled, isTrue);
      expect(
        await c1.read(localStorageProvider).loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
      c1.dispose();

      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('8642'))
            .isUnlocked,
        isTrue,
      );
    });

    test('settings write that persists and then throws is rolled back during PIN activation', () async {
      final (c1, prefsStore, secureStore, storage) = await _bootSession();
      final notifier = c1.read(karenControllerProvider.notifier);
      prefsStore.writeThenThrowAfterCount[AppConstants.prefsKeySettings] = 0;

      final result = await notifier.setPinLock('7531');
      expect(result.status, PinTransactionStatus.rolledBack);
      expect(c1.read(karenControllerProvider).settings.pinLockEnabled, isFalse);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], isNull);
      expect(storage.loadSettings().pinLockEnabled, isFalse);
      expect(await storage.loadPinSecurityState(), const PinSecurityState());
      c1.dispose();

      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(c2.read(karenControllerProvider).requiresUnlock, isFalse);
      expect(c2.read(karenControllerProvider).isUnlocked, isTrue);
    });
  });

  group('V2.1.2 Critical Issue 2 — PIN Rotation Rollback & Recovery-Required State', () {
    test('PIN rotation writes new hash, then settings persistence fails -> restores & verifies OLD hash across restart', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final n1 = c1.read(karenControllerProvider.notifier);

      expect((await n1.setPinLock('1111')).succeeded, isTrue);
      final originalHash = secureStore.data[AppConstants.secureKeyAppPinHash]!;

      // Inject settings write failure during rotation from '1111' -> '2222'
      prefsStore.returnFalseOnSet = true;
      final rotRes = await n1.setPinLock('2222');

      expect(rotRes.succeeded, isFalse);
      expect(rotRes.status, PinTransactionStatus.rolledBack);
      expect(rotRes.recoveryRequired, isFalse);
      expect(
        secureStore.data[AppConstants.secureKeyAppPinHash],
        originalHash,
      );
      expect(c1.read(karenControllerProvider).pinRecoveryRequired, isFalse);
      c1.dispose();

      // Simulate full restart: OLD PIN '1111' MUST work, failed NEW PIN '2222' MUST fail!
      prefsStore.returnFalseOnSet = false;
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      final n2 = c2.read(karenControllerProvider.notifier);

      expect((await n2.verifyPin('2222')).isUnlocked, isFalse);
      expect((await n2.verifyPin('1111')).isUnlocked, isTrue);
    });

    test('rotation rollback restores the previous failed-attempt security snapshot', () async {
      final (container, prefsStore, secureStore, storage) = await _bootSession();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('5656')).succeeded, isTrue);

      final previousSecurityState = PinSecurityState(
        failedAttempts: 2,
        lockoutUntilUtc: DateTime.utc(2026, 11, 19, 12),
        pinLockEnabled: true,
      );
      await storage.savePinSecurityState(previousSecurityState);
      final previousHash = secureStore.data[AppConstants.secureKeyAppPinHash];
      prefsStore.returnFalseOnSet = true;

      final result = await notifier.setPinLock('7878');

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(await storage.loadPinSecurityState(), previousSecurityState);
      expect(
        container.read(karenControllerProvider).failedPinAttempts,
        previousSecurityState.failedAttempts,
      );
      expect(
        container.read(karenControllerProvider).pinLockoutUntil,
        previousSecurityState.lockoutUntilUtc,
      );
      expect(
        secureStore.data[AppConstants.secureKeyAppPinHash],
        previousHash,
      );
    });

    test('PIN rotation restores old hash when new hash is written and then throws', () async {
      final (c1, prefsStore, secureStore, storage) = await _bootSession();
      final notifier = c1.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('3141')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      // The keystore persists the new hash, then reports an exception. The
      // transaction must inspect/restore the old snapshot rather than assume
      // that a thrown write left storage untouched.
      secureStore.writeThenThrowAfterCount[
        AppConstants.secureKeyAppPinHash
      ] = secureStore.writeCounts[AppConstants.secureKeyAppPinHash]!;
      final result = await notifier.setPinLock('5926');

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(storage.loadSettings().pinLockEnabled, isTrue);
      expect(
        await storage.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
      c1.dispose();

      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      final restarted = c2.read(karenControllerProvider.notifier);
      expect((await restarted.verifyPin('5926')).isUnlocked, isFalse);
      expect((await restarted.verifyPin('3141')).isUnlocked, isTrue);
    });

    test('rollback accepts old hash that persisted before the keystore threw', () async {
      final (container, prefsStore, secureStore, storage) = await _bootSession();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('1212')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      // Rotation writes the new hash first. The rollback write then persists
      // the old hash but throws; read-back is the deciding evidence.
      secureStore.writeThenThrowAfterCount[
        AppConstants.secureKeyAppPinHash
      ] = (secureStore.writeCounts[AppConstants.secureKeyAppPinHash] ?? 0) + 1;
      prefsStore.returnFalseOnSet = true;
      final result = await notifier.setPinLock('3434');

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(storage.loadSettings().pinLockEnabled, isTrue);
      expect(
        await storage.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
    });

    test('final PIN transaction-state write that persists then throws rolls back the rotation', () async {
      final (container, prefsStore, secureStore, storage) = await _bootSession();
      addTearDown(container.dispose);
      final notifier = container.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('7070')).succeeded, isTrue);
      final oldHash = secureStore.data[AppConstants.secureKeyAppPinHash];

      // With the dedicated recovery journal key (`secureKeyPinJournal`), each
      // transaction writes `secureKeyPinSecurityState` twice: in-flight and
      // final committed state. Trigger a post-write exception on the final write (+ 1).
      secureStore.writeThenThrowAfterCount[
        AppConstants.secureKeyPinSecurityState
      ] = (secureStore.writeCounts[AppConstants.secureKeyPinSecurityState] ?? 0) + 1;
      final result = await notifier.setPinLock('8080');

      expect(result.status, PinTransactionStatus.rolledBack);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], oldHash);
      expect(storage.loadSettings().pinLockEnabled, isTrue);
      expect(
        await storage.loadPinSecurityState(),
        const PinSecurityState(pinLockEnabled: true),
      );
      notifier.lockApp();
      expect((await notifier.verifyPin('7070')).isUnlocked, isTrue);
    });

    test('PIN rotation writes new hash, then PIN security-state persistence fails -> restores & verifies OLD hash across restart', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final n1 = c1.read(karenControllerProvider.notifier);

      expect((await n1.setPinLock('3333')).succeeded, isTrue);
      final originalHash = secureStore.data[AppConstants.secureKeyAppPinHash]!;

      // Inject failure on saving PinSecurityState during rotation '3333' -> '4444'
      secureStore.failingWriteKeys.add(AppConstants.secureKeyPinSecurityState);
      final rotRes = await n1.setPinLock('4444');

      expect(rotRes.succeeded, isFalse);
      expect(rotRes.status, PinTransactionStatus.rolledBack);
      expect(
        secureStore.data[AppConstants.secureKeyAppPinHash],
        originalHash,
      );
      c1.dispose();

      // Simulate full restart after keystore recovers: OLD PIN '3333' works, '4444' fails
      secureStore.failingWriteKeys.remove(AppConstants.secureKeyPinSecurityState);
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      final n2 = c2.read(karenControllerProvider.notifier);

      expect((await n2.verifyPin('4444')).isUnlocked, isFalse);
      expect((await n2.verifyPin('3333')).isUnlocked, isTrue);
    });

    test('PIN hash restoration fails during rotation rollback -> enters locked recovery-required state', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      addTearDown(c1.dispose);
      final n1 = c1.read(karenControllerProvider.notifier);

      // Write #1 to secureKeyAppPinHash succeeds (enabling '1234')
      expect((await n1.setPinLock('1234')).succeeded, isTrue);

      // Write #2 (new hash '5678') succeeds, Write #3 (rollback to '1234') FAILS!
      secureStore.failWriteAfterCount[AppConstants.secureKeyAppPinHash] = 2;
      // Trigger rollback by failing settings write
      prefsStore.returnFalseOnSet = true;

      final rotRes = await n1.setPinLock('5678');

      expect(rotRes.succeeded, isFalse);
      expect(rotRes.status, PinTransactionStatus.recoveryRequired);
      expect(rotRes.recoveryRequired, isTrue);

      final st = c1.read(karenControllerProvider);
      expect(st.pinRecoveryRequired, isTrue);
      expect(st.isUnlocked, isFalse);
      expect(st.requiresUnlock, isTrue);

      // Verification MUST fail closed in recovery-required state (neither PIN unlocks)
      expect((await n1.verifyPin('1234')).status, PinVerificationStatus.storageUnavailable);
      expect((await n1.verifyPin('5678')).status, PinVerificationStatus.storageUnavailable);
    });

    test('silent no-op write during PIN rotation rollback triggers recovery-required locked state', () async {
      final (c1, _, secureStore, storage) = await _bootSession();
      addTearDown(c1.dispose);
      final n1 = c1.read(karenControllerProvider.notifier);

      // Write #1: initial PIN '1234'
      expect((await n1.setPinLock('1234')).succeeded, isTrue);
      // Write #2 stores the new hash and then reports failure. That ambiguous
      // keystore write is what starts the rollback. A silent no-op on the
      // settings write CANNOT trigger a rollback during a rotation: rotating
      // never changes pinLockEnabled, so targetSettings equals previousSettings
      // and settingsMatch() cannot tell a no-op apart from a successful write.
      secureStore.writeThenThrowAfterCount[AppConstants.secureKeyAppPinHash] = 1;
      // Write #3 (the rollback write of the previous hash) silently no-ops.
      secureStore.silentNoOpAfterCount[AppConstants.secureKeyAppPinHash] = 2;

      final rotRes = await n1.setPinLock('9999');

      expect(rotRes.status, PinTransactionStatus.recoveryRequired);
      expect(c1.read(karenControllerProvider).pinRecoveryRequired, isTrue);
      expect(c1.read(karenControllerProvider).isUnlocked, isFalse);
      expect(c1.read(karenControllerProvider).requiresUnlock, isTrue);

      // The recovery lock must be DURABLE, not merely held in memory: the
      // security state on disk must say recoveryRequired, and the failed
      // rollback journal must survive so a restart cannot lift the lock.
      final persisted = await storage.loadPinSecurityState();
      expect(persisted.recoveryRequired, isTrue);
      expect(persisted.pinLockEnabled, isTrue);
      expect(await storage.loadPinTransactionJournal(), isNotNull);

      // Fail closed: neither the old nor the new PIN may unlock.
      expect(
        (await n1.verifyPin('1234')).status,
        PinVerificationStatus.storageUnavailable,
      );
      expect(
        (await n1.verifyPin('9999')).status,
        PinVerificationStatus.storageUnavailable,
      );
    });

    test('silent no-op write on initial new PIN hash aborts cleanly without activating PIN lock', () async {
      final (c1, _, secureStore, storage) = await _bootSession();
      addTearDown(c1.dispose);
      final n1 = c1.read(karenControllerProvider.notifier);

      secureStore.silentNoOpWriteKeys.add(AppConstants.secureKeyAppPinHash);
      final res = await n1.setPinLock('1234');

      expect(res.succeeded, isFalse);
      expect(res.status, PinTransactionStatus.rolledBack);
      expect(c1.read(karenControllerProvider).settings.pinLockEnabled, isFalse);
      expect(storage.loadSettings().pinLockEnabled, isFalse);
    });

    test('failed rollback from first-time PIN activation persists recovery lock across restart', () async {
      final (c1, prefsStore, secureStore, storage) = await _bootSession();
      final notifier = c1.read(karenControllerProvider.notifier);

      // Activation writes a new hash, then settings commit fails. Rollback
      // cannot delete the just-written hash, so the secure journal must remain.
      prefsStore.returnFalseOnSet = true;
      secureStore.failingDeleteKeys.add(AppConstants.secureKeyAppPinHash);
      final result = await notifier.setPinLock('1122');

      expect(result.status, PinTransactionStatus.recoveryRequired);
      expect(c1.read(karenControllerProvider).requiresUnlock, isTrue);
      expect(
        (await storage.loadPinSecurityState()).recoveryRequired,
        isTrue,
      );
      c1.dispose();

      // The plaintext preference store was never updated by the failed
      // activation. The durable secure journal must nevertheless force a
      // recovery lock after a full restart.
      prefsStore.returnFalseOnSet = false;
      secureStore.failingDeleteKeys.clear();
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      final restarted = c2.read(karenControllerProvider);
      // The activation never committed, but the PIN hash it wrote is still in
      // secure storage while the plaintext settings key is absent. loadAll()
      // classifies that as a corrupted-settings state, and the fail-closed
      // mirror (pinSettingsCorrupted && pinHashPresent) therefore reports the
      // PIN as enabled. Expecting false here would require the weaker,
      // bypassable behaviour that the V2.1.2 hardening exists to prevent.
      expect(restarted.settings.pinLockEnabled, isTrue);
      expect(restarted.pinRecoveryRequired, isTrue);
      expect(restarted.requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('1122'))
            .status,
        PinVerificationStatus.storageUnavailable,
      );
    });

    test('secure PIN-enabled mirror prevents a corrupted plaintext preference from disabling the lock', () async {
      final (c1, prefsStore, secureStore, _) = await _bootSession();
      final notifier = c1.read(karenControllerProvider.notifier);
      expect((await notifier.setPinLock('8046')).succeeded, isTrue);
      expect(
        (await secureStore.read(AppConstants.secureKeyPinSecurityState)),
        isNotNull,
      );
      c1.dispose();

      // AppSettings is in SharedPreferences; its corruption must not erase the
      // secure-store mirror created by a successfully committed PIN setup.
      prefsStore.data[AppConstants.prefsKeySettings] = '{malformed-json';
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      final state = c2.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('8046'))
            .isUnlocked,
        isTrue,
      );
    });

    test('corrupted pre-mirror V2.1.1 preference cannot bypass an existing PIN hash', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      secureStore.data[AppConstants.secureKeyAppPinHash] =
          PinHasher.createSaltedHash('2468', iterations: 1000);
      // V2.1.1 security-state format: no pinLockEnabled mirror field.
      secureStore.data[AppConstants.secureKeyPinSecurityState] =
          '{"failedAttempts":0,"lockoutUntilUtc":null}';
      prefsStore.data[AppConstants.prefsKeySettings] = '{malformed-settings';

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(state.pinRecoveryRequired, isFalse);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await container
                .read(karenControllerProvider.notifier)
                .verifyPin('2468'))
            .isUnlocked,
        isTrue,
      );
    });

    test('removed legacy PIN preferences cannot bypass an existing secure hash', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      secureStore.data[AppConstants.secureKeyAppPinHash] =
          PinHasher.createSaltedHash('1359', iterations: 1000);
      secureStore.data[AppConstants.secureKeyPinSecurityState] =
          '{"failedAttempts":0,"lockoutUntilUtc":null}';

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(state.pinRecoveryRequired, isFalse);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await container
                .read(karenControllerProvider.notifier)
                .verifyPin('1359'))
            .isUnlocked,
        isTrue,
      );
    });

    test('corrupted PIN preferences with no recoverable hash require explicit recovery', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      prefsStore.data[AppConstants.prefsKeySettings] = '{malformed-settings';
      secureStore.data[AppConstants.secureKeyPinSecurityState] =
          '{"failedAttempts":0,"lockoutUntilUtc":null}';

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.isUnlocked, isFalse);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await container
                .read(karenControllerProvider.notifier)
                .verifyPin('2468'))
            .status,
        PinVerificationStatus.storageUnavailable,
      );
    });

    test('enabled PIN setting without a stored hash enters recovery at startup', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);
      await storage.saveSettings(
        storage.loadSettings().copyWith(pinLockEnabled: true),
      );

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isTrue);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.isUnlocked, isFalse);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await container
                .read(karenControllerProvider.notifier)
                .verifyPin('1234'))
            .status,
        PinVerificationStatus.storageUnavailable,
      );
    });

    test('persisted recovery journal forces lock even when PIN setting is false', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);
      await storage.savePinSecurityState(
        const PinSecurityState(recoveryRequired: true),
      );

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isFalse);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.isUnlocked, isFalse);
      expect(state.requiresUnlock, isTrue);
    });
  });

  group('V2.1.2 Corrupted Security-State & Concurrent PIN Operations', () {
    test('corrupted persisted PinSecurityState fails closed on verifyPin and aborts setPinLock safely', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      final storage = LocalStorageService.withStores(prefsStore, secureStore);

      final validHash = PinHasher.createSaltedHash('2468', iterations: 1000);
      secureStore.data[AppConstants.secureKeyAppPinHash] = validHash;
      // Corrupt persisted security-state JSON
      secureStore.data[AppConstants.secureKeyPinSecurityState] =
          '{"failedAttempts":"not_an_int"}';
      await storage.saveSettings(
        storage.loadSettings().copyWith(pinLockEnabled: true),
      );

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);

      final state = container.read(karenControllerProvider);
      expect(state.pinSecurityStorageStatus, StorageLoadStatus.corruptedData);
      expect(state.requiresUnlock, isTrue);

      final notifier = container.read(karenControllerProvider.notifier);
      final verifyRes = await notifier.verifyPin('2468');
      expect(verifyRes.isUnlocked, isFalse);
      expect(verifyRes.status, PinVerificationStatus.storageUnavailable);

      // Attempting setPinLock while locked is rejected
      final setRes = await notifier.setPinLock('9999');
      expect(setRes.status, PinTransactionStatus.rejected);
      expect(secureStore.data[AppConstants.secureKeyAppPinHash], validHash);
    });

    test('legacy security-state records default to recoveryRequired=false', () {
      final legacy = PinSecurityState.fromJson({
        'failedAttempts': 2,
        'lockoutUntilUtc': null,
      });
      expect(legacy.failedAttempts, 2);
      expect(legacy.recoveryRequired, isFalse);
      expect(legacy.pinLockEnabled, isFalse);
    });

    test('malformed persisted recovery flag fails closed even when PIN setting is disabled', () async {
      final prefsStore = InMemoryPreferencesStore();
      final secureStore = InMemorySecureStore();
      secureStore.data[AppConstants.secureKeyPinSecurityState] =
          '{"failedAttempts":0,"lockoutUntilUtc":null,"recoveryRequired":"false"}';

      final (container, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(container.dispose);
      final state = container.read(karenControllerProvider);
      expect(state.settings.pinLockEnabled, isFalse);
      expect(state.pinSecurityStorageStatus, StorageLoadStatus.corruptedData);
      expect(state.pinRecoveryRequired, isTrue);
      expect(state.requiresUnlock, isTrue);
      expect(
        (await container
                .read(karenControllerProvider.notifier)
                .verifyPin('1234'))
            .status,
        PinVerificationStatus.storageUnavailable,
      );
    });

    test('concurrent PIN rotation and verification requests are serialized cleanly without race corruption', () async {
      final (container, prefsStore, secureStore, _) = await _bootSession();
      final notifier = container.read(karenControllerProvider.notifier);

      expect((await notifier.setPinLock('1111')).succeeded, isTrue);
      secureStore.artificialWriteDelay = const Duration(milliseconds: 5);

      // Fire rotation ('1111' -> '2222') followed immediately by lockApp and verifyPin calls
      final rotationFuture = notifier.setPinLock('2222');
      final secondRotationFuture = notifier.setPinLock('3333');
      final results = await Future.wait([rotationFuture, secondRotationFuture]);

      expect(results[0].status, PinTransactionStatus.committed);
      expect(results[1].status, PinTransactionStatus.committed);

      // Now lock and fire concurrent verification + blocked setPinLock attempt
      notifier.lockApp();
      final t0 = DateTime.utc(2026, 11, 19, 18, 0, 0);
      final vWrong = notifier.verifyPin('1111', nowOverride: t0);
      final blockedChange = notifier.setPinLock('4444');
      final vRight = notifier.verifyPin('3333', nowOverride: t0);

      final rWrong = await vWrong;
      final rChange = await blockedChange;
      final rRight = await vRight;

      expect(rWrong.status, PinVerificationStatus.invalidPin);
      expect(rChange.status, PinTransactionStatus.rejected);
      expect(rRight.isUnlocked, isTrue);
      container.dispose();

      // Restart verifies final committed PIN '3333' is durably persisted
      secureStore.artificialWriteDelay = null;
      final (c2, _, _, _) = await _bootSession(
        prefsStore: prefsStore,
        secureStore: secureStore,
      );
      addTearDown(c2.dispose);
      expect(
        (await c2.read(karenControllerProvider.notifier).verifyPin('3333'))
            .isUnlocked,
        isTrue,
      );
    });
  });
}
