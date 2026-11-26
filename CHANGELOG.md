# Changelog

## [Unreleased] — 2026-11-23 (official Gradle wrapper bootstrap fix; branch `fix/official-gradle-wrapper`)
> Not compiled or run against a real Gradle/Flutter toolchain in the authoring environment (no Flutter/Dart/Android SDK, no network). The bootstrap logic was exercised offline against a strict test double (58 checks, `scripts/test_bootstrap_android_wrapper.sh`). See `DEVELOPMENT_STATUS.md`.
### Fixed
- **Codemagic build `6b036ee58f52ca27512a5365`**: `scripts/bootstrap_android_wrapper.{sh,ps1}` ran `gradle wrapper` inside an *empty* temporary directory `gen`. Gradle 9 refuses to run any task outside a valid Gradle build (`Directory '.../gen' does not contain a Gradle build`). The generation directory now contains a `settings.gradle` (and an empty `build.gradle`) before the real `gradle wrapper` task runs.
- `scripts/bootstrap_android_wrapper.ps1`: a failing `gradle wrapper` skipped `Pop-Location`, so the `finally` block tried to delete the current directory; native stderr could also become a terminating error in Windows PowerShell 5.1, and the `.sha256` response could be read as `byte[]`. Rewritten (try/finally with a single exit-code path, checksum file downloaded and read as text).
- `android/app/build.gradle`: replaced the legacy `kotlinOptions { jvmTarget = "17" }` DSL (deprecated since Kotlin 2.0, rejected by newer Kotlin Gradle Plugins; this project uses KGP 2.2.10) with `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }`. Preventive change, not yet confirmed by a build.
### Security (supply chain)
- `android/gradle/wrapper/gradle-wrapper.properties` now carries `distributionSha256Sum=17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`, the SHA-256 of **`gradle-9.3.1-all.zip`** (the archive named by `distributionUrl`). Before, the bootstrap verified only the `-bin.zip` it uses as generator, while the generated wrapper then downloaded the `-all.zip` with no checksum at all.
  - **This value was supplied by the project owner and could NOT be verified independently in the authoring environment (no network).** The bootstrap therefore fails closed: it fetches Gradle's published `gradle-9.3.1-all.zip.sha256`, requires it to equal the configured value (exit 4 otherwise, with both values in the message and a hint if it is the `-bin.zip` checksum), and does so before the ~130 MB download. The wrapper itself enforces the same sum when it downloads the `-all` archive.
  - Both bootstrap scripts require `distributionSha256Sum` (exit 2 if missing / not 64 lowercase hex), pass it to the wrapper task with `--gradle-distribution-sha256-sum`, compare the generated `gradle-wrapper.properties` (checksum + archive file name) with the committed one, never overwrite the committed properties, and fail if that file changed during the run.
  - The optional generator pin is now `GRADLE_BIN_DISTRIBUTION_SHA256` (explicitly the `-bin.zip`); `GRADLE_DISTRIBUTION_SHA256` remains as a deprecated alias with a warning.
- `scripts/test_bootstrap_android_wrapper.sh`: 67 new checks (125 total; the original 58 are unchanged and still pass): checksum required and strictly formatted, bin/all confusion in both directions, wrong-but-well-formed value, fail-closed when the published checksum is unavailable or malformed, flag forwarded exactly once in both URL modes (mirror and default `services.gradle.org` via a curl shim), properties byte-identical after generation / idempotent run / forced regeneration / repair, generated-properties drift, and acceptance of the repository's real properties file.
### CI
- `codemagic.yaml`: `flutter test` degrades gracefully if `--file-reporter` is unavailable (tests still run and are enforced); the `applicationId` static guard prints an error message; checksum documentation updated.
### Build infrastructure
- Bootstrap scripts rewritten: version and distribution type are read from `gradle-wrapper.properties` (single source of truth); published SHA-256 validated for format and compared, optional pin via `GRADLE_DISTRIBUTION_SHA256`; archive integrity test; Java >= 17 pre-check; writability check before the ~130 MB download; isolated `GRADLE_USER_HOME`; generated jar validated as a real archive containing `org/gradle/wrapper/*`; atomic staged install; `chmod +x gradlew`; final `gradlew --version` must print `Gradle <version>`; distinct exit codes (2 config, 3 network, 4 checksum, 5 extract, 6 generate, 7 install, 8 verify, 9 prerequisite); idempotent (a structurally valid wrapper is not rewritten).
- New `scripts/test_bootstrap_android_wrapper.sh`: offline regression test with a Gradle-9-strict test double confined to a temp directory (never installs anything into `android/`). It reproduces the original failure against the previous script and passes 58 checks against the new one.
- `codemagic.yaml`: toolchain report, bootstrap self-test, wrapper generation and `./gradlew --version` are separate steps; `flutter test` now also writes a JSON report published through `test_report` (Codemagic test-results view); the built APK's package id is verified (`ir.bestdroid.karen`); the final quality gate also enforces the self-test and treats missing status entries as failure; `test-results/**` added to the artifacts.

## [Unreleased] — 2026-11-22 (Codemagic build-blocker fixes; branch `fix/build-blockers`)
> Not compiled or tested in the authoring environment (no Flutter/Dart/Android SDK, no network). See `DEVELOPMENT_STATUS.md`.
### Fixed
- `lib/core/security/pin_hasher.dart`: `_computeLegacyV2Digest` declared `var bytes = utf8.encode(...)`, which current Dart infers as `Uint8List`, so `bytes = sha256.convert(bytes).bytes` (a `List<int>`) failed to compile. The variable is now an explicit `List<int>`. The hashed bytes are unchanged, so legacy V2.0 PIN records still verify. The PBKDF2 loop (`derivePbkdf2HmacSha256`) already used `List<int>` and was not the source of the error; its algorithm was re-checked against published PBKDF2-HMAC-SHA256 vectors with an independent Python port.
- `android/app/build.gradle`: `compileSdk` 35 -> 36 (plugins require API 36).
- `android/app/build.gradle`: removed the debug-only `applicationIdSuffix ".debug"` so debug APKs keep the application ID `ir.bestdroid.karen`.
### Build infrastructure
- Removed the hand-written `android/gradlew` / `gradlew.bat` stubs (they were not official Gradle files). `scripts/bootstrap_android_wrapper.{sh,ps1}` now generate the official wrapper from the SHA-256-verified Gradle 9.3.1 distribution.
- `codemagic.yaml`: official wrapper generation, toolchain report, `flutter analyze --no-fatal-infos` and `flutter test --coverage` results are recorded to `build/reports/`, the debug APK is built with `-v`, and a final quality-gate step fails the build if analysis or tests failed (previously both were ignored). `pubspec.lock`, coverage, logs and the generated wrapper files are published as artifacts.
- `.gitattributes`: binary/EOL rules for jar, fonts, images, shell scripts and `gradlew`.

## [2.2.0+5] — 2026-11-20 (Master Hardening & Feature Completion Pass)
### Security
- Added dedicated persistent write-ahead recovery journal (`PinTransactionJournal` stored at `karen_sec_pin_journal_v2_2`) implementing an 8-step verified commit/rollback lifecycle for PIN activation, rotation, and deactivation.
- Implemented automatic Fail-Closed startup recovery in `LocalStorageService.loadAll()` for interrupted uncommitted/committed journals while honoring `rollbackFailed = true`.
- Fixed a latent bug from `v2_1_2_hardened` where in-flight first-time PIN activation set `PinSecurityState.pinLockEnabled = true`, conflicting with post-restart expectations on failed rollback.
- Added `secureKeyPinJournal` to verified emergency wipe key list.
### Features & UI/UX
- Added in-place **Edit TimeSlot** support, weekly summary card, Iranian working-day presets, and multi-slot daily routines in `SchedulesScreen`.
- Added in-place **Edit AuthorizedUser** support in `AuthorizedUsersScreen`.
- Added phone/manual **Clock Sync** selector sheet, last synced clock timestamp, `کاربران` log filter chip, and confirmation-guarded history clearing in `ReportsScreen`.
- Added quick multi-device switcher chips and recent activity preview on `HomeScreen`, responsive `maxWidth: 680` layout across main screens, keystore retry button on `PinLockScreen`, and Persian digits in the PBKDF2 benchmark dialog.
### Android Infrastructure & Tests
- Restored original package ID `ir.bestdroid.karen` across `android/app/build.gradle`, `MainActivity.kt`, and `proguard-rules.pro`.
- Added `test/unit/recovery_journal_fault_injection_test.dart` and `test/unit/features_schedule_user_clock_test.dart` (10 test files total).
- Added full final delivery documentation (`FINAL_DELIVERY_REPORT.md`, `SECURITY_AUDIT_REPORT.md`, `TEST_REPORT.md`, `BUILD_INSTRUCTIONS.md`, `CHANGELOG.md`, `DEVELOPMENT_STATUS.md`).

## [2.1.2+4] — Hardened Baseline (`v2_1_2_hardened`)
- Added secure-store `pinLockEnabled` mirror, corrupted-preference startup detection, post-write/post-delete fault injection helpers, and OWASP PBKDF2 benchmark UI.

## [2.1.1+3] — Security Hardening
- Removed best-effort lockout persistence (fail-closed read-back verification), enforced PBKDF2 parameter bounds & hex validation, verified `SharedPreferences` writes, and serialized concurrent PIN operations.

## [2.1.0+2] — Resilience & Persian Typography
- Replaced custom SHA-256 loop with RFC 2898 PBKDF2-HMAC-SHA256 + legacy migration, persisted brute-force lockout, added verified emergency wipe & write-protected `StorageRecoveryCard`, and applied Vazirmatn + bundled `NotoSansArabic` fallback.

## [2.0.0+1] — Initial Karen Next Rebuild
- Clean Feature-First Riverpod + GoRouter Persian RTL rebuild inspired by verified KAREN 1.0.0 (`ir.bestdroid.karen`) screens, with Demo Simulator and strict Live SMS `[UNVERIFIED:...]` safety blocking.
