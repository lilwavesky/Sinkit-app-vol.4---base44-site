# KAREN NEXT 2.2.0 — Security Audit Report

## 1. Persistent Recovery Journal Architecture (`PinTransactionJournal`)
Every PIN security mutation (`activate`, `rotate`, `deactivate`) executes inside a FIFO async mutex (`KarenController._runPinOperationSerialized`) using an explicit 8-step write-ahead journal stored in encrypted secure storage (`karen_sec_pin_journal_v2_2`):

1. **Read & Validate Current State:** Loads existing journal, `secureKeyAppPinHash`, and `PinSecurityState`. Any existing unfinished journal, `recoveryRequired == true`, or missing hash when `pinLockEnabled == true` fails closed immediately.
2. **Snapshot Complete Prior Valid State:** Captures `previousHash`, `previousPinLockEnabled`, `previousFailedAttempts`, `previousLockoutUntilUtc`, and target hash/flag (never plaintext PINs).
3. **Persist Recovery Journal:** Writes uncommitted `PinTransactionJournal(committed: false)` to encrypted storage.
4. **Verify Journal Read-Back:** Reads back and compares equality (`readBack == journal`). If write throws, explicitly inspects disk to detect post-write exceptions and cleans up any residual journal before aborting.
5. **Apply Intended Changes Under Durable Lock Flag:** Writes `inFlightSecurityState(recoveryRequired: true, pinLockEnabled: previousSettings.pinLockEnabled)`, writes target hash (or deletes hash on deactivation), and persists target `AppSettings`.
6. **Read-Back Validate New State:** Independently verifies stored hash and exact `settingsMatch(targetSettings)`.
7. **Mark Committed:** Persists & verifies final `PinSecurityState(recoveryRequired: false, pinLockEnabled: targetPinLockEnabled)` and marks journal `committed = true` with read-back verification.
8. **Remove Journal Only After Verified Commit:** Deletes `secureKeyPinJournal` and verifies absence.

### Failure & Restart Behavior (Strictly Fail-Closed)
- **Runtime Failure Before Commit:** Restores `previousHash`, `previousSettings`, and `previousSecurityState` (preserving failed attempts & lockout timestamps), verifies every component via read-back (never assuming an exception meant nothing was written), and deletes the journal only after verified restoration. If rollback fails or cannot be verified, marks `journal.markRollbackFailed()` and enters `pinRecoveryRequired = true`, `isUnlocked = false`.
- **Process Restart During Unfinished Transaction:** `LocalStorageService.loadAll()` inspects `secureKeyPinJournal` before exposing app state:
  - `rollbackFailed == true` → Refuses auto-unlock; stays locked in `pinRecoveryRequired = true`.
  - `committed == false` → Deterministically restores prior hash, settings, failed attempts, and lockout state, verifies read-back, removes the journal, and boots locked if `previousPinLockEnabled == true`.
  - `committed == true` → Verifies target state is intact on disk and removes the stale journal (or fails closed on mismatch).
  - Corrupted/unreadable journal → Sets `pinJournalStatus` error, forcing `pinRecoveryRequired = true`, `isUnlocked = false`.

## 2. PBKDF2-HMAC-SHA256 Validation & OWASP Review
- **Implementation (`lib/core/security/pin_hasher.dart`):** Pure RFC 2898 PBKDF2-HMAC-SHA256 using `package:crypto` (`Hmac(sha256, ...)`), unique 16-byte `Random.secure()` salt, 32-byte derived key, constant-time digest comparison, and self-describing format `pbkdf2_sha256$<iterations>$32$<32hexSalt>$<64hexKey>`.
- **Strict Input/Metadata Bounds:** Rejects malformed records before running KDF: strict unsigned integer regex, bounded iterations `[1,000, 600,000]`, exact 16-byte salt length, exact 32-byte key length, strict hex validation. No plaintext PINs are persisted or logged.
- **Legacy Compatibility:** Transparently verifies legacy V2.0 (`<saltHex>:<sha256_1000_hex>`) and lower-iteration PBKDF2 records and migrates them to current PBKDF2 parameters upon verified unlock.
- **OWASP Guidance Disclosure:** OWASP's Password Storage Cheat Sheet prefers **Argon2id** generally and recommends **600,000 iterations** for PBKDF2-HMAC-SHA256 (e.g., FIPS-140 scenarios), paired with target-hardware benchmarking. Karen Next 2.2.0 retains **100,000 iterations** as the pure-Dart mobile default (layered with Android Keystore encryption and persistent 5-attempt 30-second lockout) and must **not** be presented as equivalent to OWASP's 600,000-iteration PBKDF2/FIPS recommendation until benchmarked on real target Android devices via Settings → «آزمون سرعت رمزنگاری (PBKDF2)». A native FFI Argon2id migration can be introduced later without breaking existing users via a `$argon2id$...` header.

## 3. Encrypted Storage & Emergency Wipe Audit
- Sensitive entities (`devices`, `logs`, `templates`, `appPinHash`, `pinSecurityState`, `pinJournal`) are stored in `FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))`; legacy plaintext `SharedPreferences` keys are migrated and deleted.
- Storage read errors and JSON corruption are distinguished from genuinely empty databases and activate write protection (`StorageRecoveryCard`) to prevent accidental data loss.
- Emergency wipe deletes and read-back verifies every sensitive key (including the recovery journal) before deleting the PIN hash and verifying `pinLockEnabled == false`. Any partial, complete, or silent deletion failure aborts and keeps the app strictly locked.

## 4. Live SMS & Hardware Safety Audit
- Proprietary Karen Electronic SMS commands are **unverified** and remain `[UNVERIFIED:...]` placeholders.
- `SmsComposerCommandTransport` strictly blocks empty templates, `[UNVERIFIED:...]` markers, and unresolved `{param}` variables before constructing an `sms:` URI.
- Opening Android's external SMS composer records `CommandLogStatus.pendingConfirmation` and `SyncStatus.pendingConfirmation` without claiming hardware execution or mutating simulated power states.
