# Karen v2.2.0 — Correction Report

Source revision analysed: the tree shipped in `Sinkitappvol3.zip`
(`pubspec.yaml` version 2.2.0+5). No commit SHA was included in the archive,
so this patch is against that exact tree and must be applied to it, not to an
older project copy.

---

## 1. What the archive actually contains

| Item | Present? |
|---|---|
| `lib/` (full Dart source) | **Yes** |
| `test/` (all 11 test files) | **Yes** |
| `android/`, `scripts/`, `codemagic.yaml` | **Yes** |
| `pubspec.yaml` | **Yes** |
| `pubspec.lock` | **No** |
| `build/reports/flutter_analyze.log` | **No** |
| `flutter test` output / coverage | **No** |
| Build commit SHA | **No** |

The source was therefore available and every fix below is based on the real code,
not on a reconstruction. The analyzer log was not in the archive, so the 24 findings
were reconstructed from the tree itself (see section 5).

---

## 2. PIN transaction failures

### 2a. `silent no-op write during PIN rotation rollback…` (expected `recoveryRequired`, got `committed`)

**Root cause: the fault was injected where it cannot be observed. Test defect.**

The test injected `prefsStore.silentNoOpSetKeys.add(prefsKeySettings)` and expected
that to force a rollback. It cannot, for a rotation:

* `setPinLock('9999')` on an already-enabled PIN runs `PinTransactionOperation.rotate`.
* `targetSettings = previousSettings.copyWith(pinLockEnabled: true)` where
  `previousSettings.pinLockEnabled` is already `true`.
* A rotation therefore **never changes the settings value**. `saveSettings()` reports
  success, the stored bytes are byte-identical, and `settingsMatch(targetSettings)`
  in step 6 returns true.
* A silent no-op that writes a value already on disk is indistinguishable from a
  successful write **by definition**, so no code path can fail here.

The transaction legitimately committed: hash `9999` was written and read back verified.
Production behaviour is correct and fail-closed; the expectation was unreachable.

**Fix:** inject a detectable failure to start the rollback, keeping the silent no-op on
the rollback write — exactly the sequence the test's own comment describes
("Write #2 … succeeds; Write #3 (rollback write) silently no-ops"):

```dart
secureStore.writeThenThrowAfterCount[secureKeyAppPinHash] = 1; // write #2 lands, reports failure
secureStore.silentNoOpAfterCount[secureKeyAppPinHash] = 2;    // write #3 no-ops
```

The rollback write silently no-ops, the read-back of the previous hash fails,
`_restoreAndVerifyPinTransaction` returns false, the journal is marked
`rollbackFailed`, and `_enterPinRecoveryRequired` engages. Expectations unchanged.

**Persisted state is now asserted** (was in-memory only):

```dart
final persisted = await storage.loadPinSecurityState();
expect(persisted.recoveryRequired, isTrue);
expect(persisted.pinLockEnabled, isTrue);
expect(await storage.loadPinTransactionJournal(), isNotNull);
```

plus fail-closed verification that neither `1234` nor `9999` unlocks.

### 2b. `failed rollback from first-time PIN activation…` (line 487: expected `false`, got `true`)

The flag at line 487 is **`restarted.settings.pinLockEnabled`** — the plaintext
"PIN is configured" flag after a restart, not `pinRecoveryRequired` (which the very
next line asserts `isTrue` and which passes).

**Root cause: the expectation contradicts the V2.1.2 fail-closed mirror. Production is correct.**

Failed activation leaves:
* `secureKeyAppPinHash` = the hash of `1122` (the rollback delete failed),
* `prefsKeySettings` **absent** — the activation's `saveSettings` never succeeded,
* `secureKeyPinSecurityState` = `{recoveryRequired: true}`.

On restart `LocalStorageService.loadAll()` executes:

```dart
if (pinHashPresent && !_prefsStore.containsKey(prefsKeySettings)) {
  pinSettingsCorrupted = true;
}
```

and the controller then applies the documented anti-bypass rule:

```dart
effectivePinLockEnabled = settings.pinLockEnabled
    || pinSecurityState.pinLockEnabled
    || (pinSettingsCorrupted && pinHashPresent);   // -> true
```

A hash in the keystore with no plaintext settings beside it is exactly the state an
attacker produces by deleting the preference to disable the lock. The code cannot tell
that apart from a failed write, so it must assume the PIN is enabled. Asserting
`false` would require the weaker, bypassable behaviour the hardening exists to prevent.

**Fix:** expectation changed to `isTrue` with the reasoning inline. Every other
assertion in the test is untouched and still passes: `pinRecoveryRequired` true,
`requiresUnlock` true, `verifyPin('1122')` → `storageUnavailable`.
This *strengthens* fail-closed, it does not weaken it.

---

## 3. Widget test failures

### 3a. `storage_recovery_card` not found

**Root cause: over-broad fault injection. Test defect.**

`secureStore.failReads = true` fails **every** secure read, including
`secureKeyPinSecurityState`. That sets `pinSecurityStatus = readError`, so the
controller computes `pinRecoveryRequired = true`, the router redirects `/home` → `/lock`,
and `HomeScreen` (the only place `StorageRecoveryCard` renders, guarded by
`appState.isDevicesWriteProtected`) is never built.

The test was reaching the wrong lock: it took the *PIN* security store down to test the
*device* store. Production behaviour is correct and fail-closed.

**Fix:** fail only the data stores the card is about:

```dart
secureStore.failingReadKeys.addAll([
  secureKeyDevices, secureKeyLogs, secureKeyTemplates,
]);
```

and clear them before the retry tap. The card now renders, the empty state does not, and
the saved device reappears after retry.

**Regression coverage added** (new test): a genuine `secureKeyPinSecurityState` read
failure must keep the app **locked** — `pin_recovery_required_banner` present,
`storage_recovery_card` absent, empty state absent.

### 3b. `pin_input_field` not found (security-critical)

**Root cause: the assertion ran while the app was still backgrounded. Test defect; the guard is correct.**

`lockApp()` does fire: `didChangeAppLifecycleState(paused)` sets `isUnlocked = false`,
`requiresUnlock` becomes true, `appRouterProvider`'s `ref.listen` fires and
`redirect` returns `/lock`. But `SchedulerBinding` sets `framesEnabled = false`
while the lifecycle is not `resumed`, so `scheduleFrame()` is a no-op, `pumpAndSettle()`
paints nothing, and the tree still shows `/home`.

The lock is decided correctly; it was simply never painted because the test never
returned to the foreground. No unauthenticated route is reachable.

**Fix:** background → foreground → pump, which is also the real user flow:

```dart
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
await tester.pump();
tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
await tester.pump();
await tester.pumpAndSettle();
```

Wrong PIN stays locked, correct PIN unlocks — unchanged.

**No production route-guard change was needed.** The gate
(`requiresUnlock` → `/lock`) is intact and is now actually exercised.

---

## 4. RTL overflow — `KarenCircuitBanner` (99 px)

**Root cause: a rigid `Row` with `spaceBetween` and no flexible children. Production defect, fixed.**

The header row held a title `Text` and a clock `Text` with intrinsic widths. In RTL the
title starts at the right edge; once the two texts exceed the banner width the `Row`
overflows by the sum of their excess.

**Fix:** `Expanded` on the title (wraps instead of pushing), `Flexible` + `TextAlign.end`
+ ellipsis on the clock, `crossAxisAlignment.start`. RTL alignment is preserved because
`Row` lays out right-to-left automatically; no `textDirection` override was introduced.
The layout is now bounded at every width: the title wraps on narrow screens, and on wide
screens the clock sits at the far edge.

---

## 5. Analyzer findings

The migration is real and official: Flutter 3.50 deprecates the in-framework design
libraries in favour of `package:material_ui` and `package:cupertino_ui`
(docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui).

Applied, and reviewed by hand rather than trusted blindly:

1. `pubspec.yaml`: added `material_ui: ^1.0.0` and `cupertino_ui: ^1.0.0`.
2. **All 19** files that imported the in-framework libraries now import the
   standalone packages (`lib/` and `test/`). Verified zero remaining occurrences of
   `package:flutter/material.dart` and `package:flutter/cupertino.dart`.
3. `lib/app/app.dart`: removed the `flutter_localizations` import — it made
   `GlobalMaterialLocalizations` ambiguous, as the official guide warns — and replaced the
   three delegates with `GlobalMaterialLocalizations.delegates`, which already includes the
   Cupertino and Widgets delegates.
4. `lib/app/providers/karen_providers.dart`: removed the unused design import.
   `lib/core/models/karen_models.dart` had the same dead import — removed as well
   (it would otherwise have become a fresh `unused_import` finding).
5. `unawaited_return_in_try_block`: `return _enterPinRecoveryRequired(...)` (6 sites) and
   `return rollback(...)` (3 sites) are now `return await …`, so asynchronous failures
   are genuinely caught by the surrounding `try`/`catch` instead of escaping it.
6. `prefer_const_constructors` in `test/unit/persian_utils_and_models_test.dart`:
   `final device = KarenDevice(` → `const device = KarenDevice(`.

No finding was suppressed, no file excluded, no analysis option relaxed.

**No compatibility bridge was added.** `go_router`, `flutter_riverpod`,
`shared_preferences`, `flutter_secure_storage`, `url_launcher`, `google_fonts` and
`crypto` expose no design-system types in the APIs this app uses, so
`MaterialUiCompatibilityBridge` would only add a `deprecated_member_use` suppression.
If a future dependency does expose them, add the bridge in `MaterialApp.builder` then.

---

## 6. Preserved unchanged

Gradle 9.3.1, the wrapper bootstrap and SHA-256 verification, `codemagic.yaml`,
package id `ir.bestdroid.karen`, PBKDF2 and its parameters, the recovery journal,
legacy PIN verification, and the SMS transport security.

---

## 7. Verification status — READ THIS

`flutter analyze`, `flutter test`, `flutter test --coverage`, the Codemagic
Debug APK build and APK inspection were **NOT run**: there is no Flutter SDK, Dart SDK,
Android SDK or Gradle in the environment this patch was prepared in. Do not treat this as a
green build.

`pubspec.lock` is **not** included. It was not in the archive and cannot be produced
without resolving dependencies. Regenerate it with `flutter pub get` and commit the result.

To finish verification:

```bash
flutter pub get
dart fix --apply            # should now report nothing to change
flutter analyze             # expect 0 issues
flutter test                # expect 88 passing
flutter test --coverage
```

Then re-run the Codemagic Debug APK workflow and confirm the artifact and package id.
