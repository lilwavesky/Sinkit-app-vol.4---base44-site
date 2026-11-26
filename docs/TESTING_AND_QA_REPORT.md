# Karen Next 2.1.2 — Testing, Validation & Remaining Limitations Report

## 1. Honest Execution Disclosure (Executed vs. Not Executed)

This project was edited and audited inside an offline Linux container (`NO_EGRESS`) that contains **Python 3 and a Java runtime**, but **does NOT have Flutter, Dart, Android SDK, or Gradle installed**.

### Commands NOT Executed in This Sandbox (Exact Status)
| Command | Status | Exit Code | Reason |
| :--- | :--- | :--- | :--- |
| `flutter pub get` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK is not installed in this container |
| `flutter analyze` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK is not installed in this container |
| `flutter test` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK is not installed in this container |
| `flutter build apk --debug` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter & Android SDKs are not installed in this container |
| `./android/gradlew --version` | **NOT EXECUTED** | N/A (`gradle-wrapper.jar` absent) | Offline sandbox (`NO_EGRESS`) cannot download the official Gradle distribution (historical note: this report predates the Gradle 9.3.1 migration) |

### Structural Checks ACTUALLY Executed in This Sandbox
- **Dart source structural scan (33 `.dart` files):** Checked balanced `()[]{}` delimiters, closed string/comment regions, and resolved all relative and `package:karen_next/...` project imports. Result: **0 structural/import findings**. This is a lightweight source scan, not a Dart parser and not a replacement for `dart analyze` or Flutter compilation.
- **YAML validation:** Parsed `pubspec.yaml` successfully with PyYAML. This confirms YAML syntax only; it does not resolve package versions.
- **Android XML validation (8 `.xml` files):** Parsed all manifests, styles, colors, drawables, and adaptive icons with Python's XML parser. Result: **8/8 valid**.
- **Asset binary verification (15 `.png` + 3 `.ttf`):** Verified PNG and TrueType signatures for the bundled launcher icons and `NotoSansArabic-{Regular,Medium,Bold}.ttf`. Result: **18/18 signatures valid**.

## 2. Automated Test Suite (8 Test Files — Not Executed in This Environment)
| Test File | Key Scenarios Covered |
| :--- | :--- |
| `test/unit/v2_1_2_pin_transactions_test.dart` | PIN deactivation delete failure and delete-then-throw rollback; settings write failures before persistence, after persistence with `false`, and after persistence with an exception; successful deactivation and restart; rotation rollback when the new hash is written then throws; rollback when restoring the old hash writes then throws; final security-state commit that persists then throws; settings/security-state failures; failed rollback and final journal-clear no-op; persistent recovery lock after first-time activation rollback failure with `pinLockEnabled=false`; backward-compatible security-state parsing; malformed recovery flag; corrupted security state; secure PIN-enabled mirror against malformed preferences; V2.1.1 hash-based PIN-gate recovery when old settings are malformed or missing; explicit recovery when malformed settings have no recoverable hash or an enabled PIN has no stored hash; full failed-attempt/lockout snapshot rollback; concurrent PIN operations. |
| `test/unit/v2_1_1_security_hardening_test.dart` | Fail-closed on lockout write failure & silent no-op writes; PBKDF2 DoS/min/salt/key/hex validation; malformed hash fail-closed; low-iter PBKDF2 migration; settings persistence failures & rollbacks; 5 concurrent `verifyPin` serialization; expired lockout recovery. |
| `test/unit/emergency_wipe_and_storage_recovery_test.dart` | Complete, partial, and silent no-op delete failures on emergency wipe; write-protected storage recovery on Keystore outage and corrupted JSON; retry restoration preserving real devices. |
| `test/unit/pin_security_and_state_test.dart` | RFC 2898 PBKDF2 vectors, unique random salts, legacy V2.0 -> PBKDF2 migration, full restart lockout persistence, fail-closed on null/throwing keystore, Demo vs. Live SMS honesty. |
| `test/unit/sms_transport_security_test.dart` | Blocks `[UNVERIFIED:...]` placeholders, empty templates, and unresolved `{param}` tokens; SMS composer `pendingConfirmation`; Demo multiline report. |
| `test/unit/persistence_test.dart` | Device + schedule + log + template reload round-trip; asserts zero sensitive leakage into plaintext `SharedPreferences`. |
| `test/unit/persian_utils_and_models_test.dart` | Iranian phone normalization/validation, Jalali calendar conversion, `TimeSlot` overlap/bounds checks, `KarenDevice` serialization. |
| `test/widget/karen_app_widget_test.dart` | RTL enforcement, splash->home, 3-tab navigation, Live SMS unverified warning banner, `StorageRecoveryCard` & retry recovery, GoRouter PIN lock redirect & background relock. |

## 3. Exact List of Remaining Limitations
1. **`android/gradle/wrapper/gradle-wrapper.jar` Not Bundled:** The official Gradle wrapper JAR is not present (an attempt to retrieve the exact upstream Gradle 8.7.0 artifact failed in this network-restricted runtime). It was not fabricated. Run `./scripts/bootstrap_android_wrapper.sh` (or `.ps1`) on a network-enabled development machine to retrieve the official JAR, then check `./android/gradlew --version`.
2. **`pubspec.lock` Not Generated:** It cannot be generated or validated without the Flutter/Dart toolchain and package resolution. Run `flutter pub get` locally to create the real lockfile; do not hand-author it.
3. **Debug APK Not Compiled & Flutter CLI Validation Not Yet Executed:** No Flutter analyzer, test runner, Android Gradle build, or APK build was executed in this container. On a configured machine, run `flutter pub get && flutter analyze && flutter test && flutter build apk --debug`.
4. **Offline Vazirmatn `.ttf` Binaries Not Bundled:** The bundled NotoSansArabic files remain the offline fallback. Run `./scripts/fetch_vazirmatn_offline.sh` (or `.ps1`) on a network-enabled machine to add Vazirmatn TTFs under `assets/google_fonts/`.
5. **Android Device PBKDF2 Benchmark Pending:** Run Settings → «آزمون سرعت رمزنگاری (PBKDF2)» on representative target Android hardware before raising default iterations from `100,000` toward OWASP's `600,000` or adopting a native FFI Argon2id library.
6. **Proprietary Karen Electronic Hardware SMS Protocol Unverified:** All command templates remain `[UNVERIFIED:...]` and blocked in Live SMS mode until official Karen Electronic protocol documentation or live SMS captures from `karen_1.0.0.apk` are verified.
7. **Release Signing Keystore:** Copy `android/key.properties.example` to `android/key.properties` with your release `.jks` keystore before building a release APK.
