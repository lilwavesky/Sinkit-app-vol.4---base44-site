# Karen Next 2.1.2 — Security Audit & Cryptography Rationale Report

## 1. Critical PIN Transaction Hardening in V2.1.2

### Durable Recovery Journal
- `PinSecurityState` now includes backward-compatible `recoveryRequired` and `pinLockEnabled` booleans, persisted in the encrypted secure store. Records created by earlier 2.1.x builds do not contain these fields and are interpreted as `false`; invalid field types are treated as corrupted security state. The effective PIN gate is enabled when either secure state or the existing setting says it is enabled.
- Before changing the PIN hash or preferences, `setPinLock()` persists and verifies `recoveryRequired=true`. That marker remains active through all intermediate mutations and is cleared only as the final verified commit operation.
- Startup treats a persisted recovery marker, or an unreadable/corrupt PIN security record, as a lock condition. It also reads the secure PIN hash at bootstrap: the secure PIN-enabled mirror protects new installs, while a V2.1.1 record without that mirror still activates the gate when the plaintext preference is malformed but a hash exists. A malformed preference with no recoverable hash enters explicit recovery instead of defaulting silently to PIN-disabled. This closes both the first-time activation gap and the legacy-preference corruption bypass.

### Complete Snapshot Rollback
- Each operation snapshots the prior encrypted PIN hash, the full `PinSecurityState` (failed attempts, lockout timestamp, and recovery flag), and `AppSettings`.
- Rollback restores the prior PIN hash and verifies read-back; restores `AppSettings` and checks the exact stored snapshot; then restores the prior security state last, clearing the journal only after the other components match.
- The rollback path explicitly handles a preferences adapter that writes the new value and then returns `false` or throws. A reported write failure is not treated as proof that the value was not persisted.
- Deactivation is now a full transaction: persist journal and secure PIN-enabled mirror, delete and verify the hash, reset attempts while retaining the journal, persist and verify `pinLockEnabled=false`, then clear and verify the journal and secure PIN-enabled mirror. It no longer commits the disabled setting while leaving stale PIN material as a cleanup warning.
- If any part of rollback is uncertain, the journal is deliberately retained and the app enters `pinRecoveryRequired=true`, `isUnlocked=false`. This state survives a full process restart and blocks PIN verification and PIN setting changes.

### Fault-Injection Coverage Added
- Secure-store deletion that fails before deletion and deletion that deletes then throws.
- PIN-hash writes that persist the new hash and then throw; rollback writes that persist the old hash and then throw, followed by successful read-back verification.
- Final security-state commit writes that persist and then throw, with restoration of the prior PIN hash/settings/security state.
- Full previous attempt-count and lockout-timestamp snapshot restoration after a failed rotation.
- Legacy V2.1.1 security records combined with malformed or removed preferences, both when a prior hash exists and when no recoverable hash exists; enabled settings with a missing PIN hash also enter recovery at startup.
- Preferences writes that fail before persistence, persist then return `false`, and persist then throw.
- Failure of the final transaction-journal clear and failure/no-op while restoring the prior security state.
- Recovery marker loaded after restart while `pinLockEnabled=false`.
- Backward compatibility for old security-state records without `recoveryRequired`, and rejection of malformed recovery flag values.
- Existing concurrent PIN-operation serialization, malformed hash, lockout, and recovery tests remain in the suite.

## 2. PBKDF2-HMAC-SHA256 Security Review & OWASP Guidance

Primary reference: [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) (checked 2026-11-20).

### Current OWASP Password Storage Cheat Sheet Guidance
- **Primary OWASP Recommendation:** **Argon2id** (minimums such as `m=47104 KiB (46 MiB), t=1, p=1` or `m=19456 KiB (19 MiB), t=2, p=1` or `m=12288 KiB (12 MiB), t=3, p=1`), because memory-hardness dramatically increases GPU/ASIC cracking cost compared to CPU-only KDFs.
- **OWASP PBKDF2-HMAC-SHA256 Recommendation:** **600,000 iterations** (or **220,000 iterations** for PBKDF2-HMAC-SHA512) when PBKDF2 is chosen for FIPS-140 compliance or portability, paired with the explicit operational directive to **benchmark on target hardware** and keep single-hash verification responsive (typically ~100–300 ms, never exceeding 1 second).

### Karen Next 2.1.2 Parameter Decision & Rationale
1. **Default Iterations (`100,000`) & Ceiling (`600,000`):**
   - Pure-Dart `package:crypto` PBKDF2 runs without native C/SIMD acceleration. On entry-level Android ARM devices (common in target markets), 600,000 pure-Dart iterations can block the UI thread for >1 second unless measured and/or offloaded.
   - Because a 4-digit PIN has only $10^4$ combinations, offline resistance against a stolen unencrypted hash is inherently bounded by PIN entropy; Karen Next therefore layers **Android Keystore hardware-backed encryption (`EncryptedSharedPreferences`)** + **persisted fail-closed 5-attempt lockout** as primary defenses, with salted PBKDF2-HMAC-SHA256 (`100,000` iterations, unique 16-byte salt, 32-byte key) as defense-in-depth at rest.
   - `maxAcceptableIterations = 600,000` matches OWASP's PBKDF2-HMAC-SHA256 target while rejecting DoS-scale tampered records (e.g., `999,999,999` iterations) before running the KDF.
2. **Real-Device Android Benchmarking Built In:**
   - Settings → **«آزمون سرعت رمزنگاری (PBKDF2)»** benchmarks both **100,000** and **600,000** iterations on the user's actual Android device and reports millisecond latency against the `< 300 ms` mobile UI responsiveness target.
3. **Path to Native Argon2id (Future Milestone):**
   - A native FFI Argon2id library (e.g., C `libargon2` via `dart:ffi` or an audited native Flutter plugin) is strictly superior to pure-Dart PBKDF2 for GPU resistance at low latency (~150–250 ms at 19–46 MiB on Android).
   - We intentionally did **not** add an uncompiled/untested native FFI dependency in this offline sandbox. Because `PinHasher` stores self-describing `$`-delimited algorithm headers (`pbkdf2_sha256$...`), a future native Argon2id release (`$argon2id$...`) can migrate existing PBKDF2 hashes automatically on unlock without breaking existing users.
