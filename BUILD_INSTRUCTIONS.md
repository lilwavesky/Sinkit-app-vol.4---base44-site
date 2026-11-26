# KAREN NEXT 2.2.0 — Build & Release Instructions

## Prerequisites
- **Flutter SDK:** `>= 3.27.0` (Dart SDK `>= 3.6.0 <4.0.0`)
- **Android Studio:** Ladybug / Meerkat or newer
- **Android SDK:** `compileSdk = 36` (required by plugins), `targetSdk = 35`, `minSdk = 21`
- **Gradle / AGP / Kotlin:** Gradle 9.3.1, Android Gradle Plugin 9.1.1, Kotlin Gradle Plugin 2.2.10 (`android.builtInKotlin=false`, `android.newDsl=false` per Flutter's migration path)
- **JDK:** Java 17

## Step 1 — Unpack Source Archive
```bash
unzip KAREN_NEXT_FINAL_SOURCE.zip
cd karen_next
```

## Step 2 — Generate the Official Gradle 9.3.1 Wrapper (Non-Destructive, Idempotent)
The repository intentionally ships **no** `gradlew`, `gradlew.bat` or `gradle-wrapper.jar` unless you commit them (the earlier hand-written `gradlew` stub was removed because it was not an official Gradle file). The script reads the version from `android/gradle/wrapper/gradle-wrapper.properties`, downloads the official Gradle distribution, verifies its published SHA-256, runs the real `gradle wrapper` task inside a temporary **valid Gradle build** (Gradle 9 aborts with "Directory ... does not contain a Gradle build" if that directory has no `settings.gradle`), installs the three files atomically, makes `gradlew` executable, and finally checks that `./gradlew --version` prints `Gradle 9.3.1`. `gradle-wrapper.properties` is never modified; an already valid wrapper is left untouched.
```bash
# Linux / macOS:
./scripts/bootstrap_android_wrapper.sh

# Windows PowerShell:
.\scripts\bootstrap_android_wrapper.ps1
```
**Two different checksums are involved; do not mix them up.**
- `distributionSha256Sum` in `android/gradle/wrapper/gradle-wrapper.properties` is the SHA-256 of the archive named by `distributionUrl` (**`gradle-9.3.1-all.zip`**). It is **required**: the bootstrap refuses to run without it (exit 2), cross-checks it against the checksum Gradle publishes for that exact archive (`https://services.gradle.org/distributions/gradle-9.3.1-all.zip.sha256`) before downloading anything large (exit 4 on mismatch, with a hint if it is the `-bin.zip` checksum), passes it to the wrapper task as `--gradle-distribution-sha256-sum`, and the generated wrapper enforces it when it downloads the `-all` archive. If you change `distributionUrl` (version or `all`/`bin`), update this value from https://gradle.org/release-checksums/ in the same commit.
- `GRADLE_BIN_DISTRIBUTION_SHA256` (optional environment variable) pins the **`gradle-9.3.1-bin.zip`** the bootstrap downloads only to run the generator. (`GRADLE_DISTRIBUTION_SHA256` is a deprecated alias.)

Other options (environment variables): `FORCE_WRAPPER_REGENERATE=1` (regenerate anyway), `GRADLE_DISTRIBUTIONS_BASE=<url>` (mirror). Requires Java 17+, `curl` and `unzip` (macOS/Linux).

Exit codes: `2` configuration (including a missing or malformed `distributionSha256Sum`), `3` network/download, `4` checksum mismatch (any checksum), `5` archive extraction, `6` wrapper generation, `7` installation/permissions, `8` verification, `9` missing prerequisite (e.g. Java < 17).

Offline regression test of the bootstrap logic (uses a Gradle-9-strict test double in a temp directory; does not touch `android/`):
```bash
bash scripts/test_bootstrap_android_wrapper.sh
```
Commit the generated `android/gradlew`, `android/gradlew.bat` and `android/gradle/wrapper/gradle-wrapper.jar` if you want them in git, and mark the launcher executable: `git update-index --chmod=+x android/gradlew`. `gradle-wrapper.properties` is never modified by the bootstrap; it checks that the file is byte-for-byte unchanged after the run.

## Step 3 — (Optional) Bundle Vazirmatn Fonts Offline
The app uses `google_fonts: ^6.2.1` (Vazirmatn Regular/Medium/Bold) with bundled SIL-OFL `NotoSansArabic-{Regular,Medium,Bold}.ttf` as an immediate offline fallback. For 100% offline first-launch Vazirmatn rendering:
```bash
./scripts/fetch_vazirmatn_offline.sh   # Windows: .\scripts\fetch_vazirmatn_offline.ps1
```

## Step 4 — Generate `pubspec.lock`, Analyze & Run All Tests
```bash
flutter pub get
flutter analyze
flutter test
flutter test --coverage
```
Commit the generated `pubspec.lock`.

## Step 5 — Build Debug APK
```bash
flutter build apk --debug -v
# NOTE: the debug APK keeps the real application ID ir.bestdroid.karen (no .debug suffix).
# Artifact: build/app/outputs/flutter-apk/app-debug.apk
# Optional rename: cp build/app/outputs/flutter-apk/app-debug.apk KAREN_NEXT_FINAL_DEBUG.apk
```

## Step 6 — Build Signed Release APK & Android App Bundle (AAB)
`android/app/build.gradle` blocks release builds without a real keystore (never falls back to the debug key):
1. Copy `android/key.properties.example` to `android/key.properties`.
2. Fill in `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`.
3. Build release artifacts:
```bash
flutter build apk --release
# Artifact: build/app/outputs/flutter-apk/app-release.apk

flutter build appbundle --release
# Artifact: build/app/outputs/bundle/release/app-release.aab
```

## Step 7 — On-Device Verification Checklist
1. Verify splash screen, Persian RTL alignment, Jalali dates, and Light/Dark themes.
2. Test Demo Mode end-to-end (add/edit/switch/delete devices, ON/OFF confirmation, add/edit/delete schedules & multi-slot routines, add/edit/delete users, reports & manual clock sync).
3. Test PIN setup, background relock, 5-attempt lockout across cold app restart, PIN rotation, PIN deactivation, and Settings → «آزمون سرعت رمزنگاری (PBKDF2)».
4. Confirm Live SMS mode blocks `[UNVERIFIED:...]` templates until verified Karen Electronic hardware command codes are entered.
