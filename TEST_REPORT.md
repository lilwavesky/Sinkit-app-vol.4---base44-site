# KAREN NEXT 2.2.0 — Test & Static Verification Report

## 1. Honest Execution Disclosure
This container has **Python 3, Bash, and Java runtime**, but **does NOT have Flutter, Dart, Android SDK, Gradle, or internet access (`NO_EGRESS`)**.

### Commands NOT Executed in This Environment
| Command | Status | Exit Code | Reason |
| :--- | :--- | :--- | :--- |
| `flutter pub get` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK not installed |
| `flutter analyze` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK not installed |
| `flutter test` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK not installed |
| `flutter test --coverage` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter SDK not installed |
| `flutter build apk --debug` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter & Android SDK not installed |
| `flutter build apk --release` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter & Android SDK not installed |
| `flutter build appbundle --release` | **NOT EXECUTED** | N/A (`flutter` not found) | Flutter & Android SDK not installed |
| `./android/gradlew --version` | **NOT EXECUTED** | N/A (`gradle-wrapper.jar` absent) | Offline sandbox cannot download the Gradle 9.3.1 distribution to generate the wrapper |

### Verification Checks ACTUALLY Executed in This Environment
| Check | Scope | Result |
| :--- | :--- | :--- |
| Dart structural lexer & import scan | All 35 `.dart` files | Passed (0 unterminated strings/comments, 0 delimiter mismatches, 0 broken relative/`package:karen_next/` imports, 0 stray citations) |
| Android package ID consistency scan | All Android Gradle/Kotlin/XML/ProGuard files | Passed (`ir.bestdroid.karen` everywhere; 0 `ir.karen.next` references) |
| YAML structural validation | `pubspec.yaml`, `analysis_options.yaml` | Passed (no tabs, valid indentation, required sections verified) |
| XML well-formedness (`xml.etree.ElementTree`) | All 8 Android `.xml` files | Passed |
| PNG binary integrity (`PIL.Image.verify`) | All 15 mipmap `.png` launcher icons | Passed |
| TrueType font validation (`fontTools.TTFont`) | All 3 bundled `NotoSansArabic-*.ttf` files | Passed |
| Shell script syntax check (`bash -n`) | `bootstrap_android_wrapper.sh`, `fetch_vazirmatn_offline.sh` | Passed (exit code 0) |
| Shell script syntax check (`bash -n`), session 2026-11-23 | `bootstrap_android_wrapper.sh`, `test_bootstrap_android_wrapper.sh`, all 8 script blocks embedded in `codemagic.yaml` | Passed |
| Bootstrap regression test against the OLD script (`SCRIPT_UNDER_TEST=<old>`) | `scripts/test_bootstrap_android_wrapper.sh`, Gradle-9-strict test double | **Reproduced** the Codemagic error (`Directory '.../gen' does not contain a Gradle build.`); 39 of 58 checks failed (the first, fatal one being the generation step) |
| Bootstrap regression test against the NEW script | `scripts/test_bootstrap_android_wrapper.sh` (Linux, bash 5.2, test double, not real Gradle) | Passed: 58 passed, 0 failed (1 skipped note: read-only-directory check is skipped when run as root) |
| Bootstrap regression test against the NEW script (after distributionSha256Sum work) | `scripts/test_bootstrap_android_wrapper.sh` (Linux, bash 5.2, test double, not real Gradle) | Passed: **125 passed, 0 failed** (original 58 unchanged and passing + 67 new checksum checks) |
| Same harness against the PREVIOUS commit's script (mutation check) | `SCRIPT_UNDER_TEST=<previous>` | 41 checks fail, i.e. the new checks detect missing checksum handling |
| codemagic.yaml step logic with fake `flutter` / `aapt2` | test step (pass / test fail / analyze fail / no `--file-reporter`), APK step (correct / wrong package id / no aapt2 / changed applicationId), quality gate | Behaved as designed; no real Flutter or Gradle involved |
| `codemagic.yaml` parse + quality-gate logic | PyYAML load; gate step executed with pass/fail/missing inputs | Passed (gate exits 0 only when every recorded exit code is 0) |
| `bootstrap_android_wrapper.ps1` | Brace/paren balance and pure-ASCII check only | **Not executed** (no PowerShell in the sandbox) |
| ZIP archive CRC integrity (`zipfile.testzip`) | `KAREN_NEXT_FINAL_SOURCE.zip` | Passed (`None` = 0 CRC errors) |

> **Important Note:** The Python structural scan checks lexical balance and import paths only; it is **not** the Dart compiler or `flutter analyze` and does not prove runtime test pass status.

## 2. Automated Test Suite Inventory (10 Test Files Ready for `flutter test`)
| File | Coverage |
| :--- | :--- |
| `test/unit/recovery_journal_fault_injection_test.dart` | **NEW:** Journal cleanup & zero plaintext PIN storage; crash/restart during unfinished rotation (restores old hash + failed attempts + lockout); crash/restart during unfinished deactivation (restores enabled PIN); crash/restart with committed journal; corrupted & unreadable journal Fail-Closed; journal write failure before write; post-write exception on journal; Step 8 journal delete failure; delete-then-throw on PIN hash; multiple consecutive failures + successful retry; V2.1.1 legacy compatibility & migration. |
| `test/unit/features_schedule_user_clock_test.dart` | **NEW:** In-place TimeSlot editing, edit overlap rejection, slot deletion, multi-slot working-day routine upload, AuthorizedUser editing, manual clock sync. |
| `test/unit/v2_1_2_pin_transactions_test.dart` | PIN deactivation, rotation rollback, post-write/post-delete exceptions, corrupted preferences + secure mirror, legacy pre-mirror compatibility, recovery-required lock across restarts, concurrent PIN operations. |
| `test/unit/v2_1_1_security_hardening_test.dart` | Fail-closed lockout persistence on write & silent no-op failures, PBKDF2 DoS/bound/salt/key/hex validation, settings persistence failures & rollbacks, 5 concurrent `verifyPin` serialization, expired lockout recovery. |
| `test/unit/emergency_wipe_and_storage_recovery_test.dart` | Complete/partial/silent emergency wipe failures, keystore outage write protection, corrupted JSON recovery, retry restoration. |
| `test/unit/pin_security_and_state_test.dart` | RFC 2898 PBKDF2-HMAC-SHA256 vectors (1, 2, 4096 iter), unique random salts, V2.0 -> PBKDF2 migration, persistent restart lockout, Demo vs. Live SMS device state honesty. |
| `test/unit/sms_transport_security_test.dart` | Blocks `[UNVERIFIED:...]`, empty templates, unresolved `{param}` tokens; SMS composer `pendingConfirmation`; Demo multiline report. |
| `test/unit/persistence_test.dart` | Full encrypted persistence round-trip; asserts zero sensitive leakage into plaintext `SharedPreferences`. |
| `test/unit/persian_utils_and_models_test.dart` | Iranian phone normalization/validation, Jalali conversion, `TimeSlot` overlap checks, `KarenDevice` JSON round-trip. |
| `test/widget/karen_app_widget_test.dart` | RTL enforcement, splash->home, 3-tab navigation, Live SMS warning banner, `StorageRecoveryCard` retry recovery, GoRouter PIN lock redirect & background relock. |
