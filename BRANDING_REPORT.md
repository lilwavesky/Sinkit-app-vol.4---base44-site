# Sinkit — Branding Rename Report

Base: the corrected v2.2.0 tree (`karen-fixed-v2.2.0.zip`). Branding only; no logic touched.

## Files changed (8 modified, 1 added)

| File | Change |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | `android:label="کارن هوشمند"` → `android:label="@string/app_name"` |
| `android/app/src/main/res/values/strings.xml` | **NEW** — `<string name="app_name">Sinkit</string>` |
| `lib/core/constants/app_constants.dart` | `appNameFa` → `'Sinkit'`, `appNameEn` → `'Sinkit'` |
| `lib/app/app.dart` | `MaterialApp.router(title: …)` now `AppConstants.appNameEn` (+ import) |
| `lib/features/splash/splash_screen.dart` | Removed the duplicated Latin sub-line (see note) |
| `lib/features/home/home_screen.dart` | AppBar title `'کارن الکترونیک'` → `AppConstants.appNameFa` (+ import) |
| `lib/features/security/pin_lock_screen.dart` | `'ورود امن به کارن الکترونیک'` → `'ورود امن به Sinkit'` |
| `test/widget/karen_app_widget_test.dart` | Expected title text `'کارن الکترونیک'` → `'Sinkit'` |
| `pubspec.yaml` | `description` reworded to Sinkit; `name: karen_next` untouched |

## Where the user-facing name now comes from

Single source of truth — `AppConstants.appNameFa` / `appNameEn` — rendered at:

1. **Launcher label** — `@string/app_name` = `Sinkit`.
2. **Splash screen** — large brand text.
3. **Home AppBar title**.
4. **Device drawer header** (already used the constant).
5. **PIN lock screen heading** — "ورود امن به Sinkit".
6. **OS task-switcher / window title** — `MaterialApp.title`.
7. **Widget test** asserting the visible app title.

No notification channel exists in this app (no `flutter_local_notifications`, no `NotificationChannel`), so there was no notification display name to change.

## Splash: one line removed

The splash showed the Persian name large and the Latin name letter-spaced beneath it. With a
single Latin brand ("Sinkit" / "Sinkit") that would print the same word twice. The sub-line was
removed rather than given invented copy. Layout, gradient, logo mark, animation and the rest of
the visual identity are untouched.

## Deliberately preserved

**Package / namespace:** `applicationId = "ir.bestdroid.karen"`, `namespace = "ir.bestdroid.karen"`,
`AppConstants.appPackageId` — verified unchanged.

**Storage keys** — all untouched, so existing installs keep their data:
`karen_app_settings_v2`, `karen_active_device_id_v2`, `karen_devices_v2`, `karen_command_logs_v2`,
`karen_protocol_templates_v2`, `karen_sec_devices_v2`, `karen_sec_command_logs_v2`,
`karen_sec_protocol_templates_v2`, `karen_sec_pin_hash_v2`, `karen_sec_pin_lockout_v2_1`,
`karen_sec_pin_journal_v2_2`.

**Technical identifiers:** Dart package `karen_next` (renaming it breaks every import),
`KarenNextApp`, `KarenLogoMark`, `karen_providers.dart`, `karen_models.dart`, `karen_widgets.dart`,
route paths, provider names.

**Hardware brand references** — "دستگاه کارن" (the Karen device), "سخت‌افزار کارن" (Karen hardware),
the protocol-template screens and the `[UNVERIFIED]` guard. These name the **physical GSM controller**
this app drives, not the app itself. Renaming them would misdescribe the hardware.

**Historical / developer docs:** `CHANGELOG.md`, `README.md`, `SECURITY_AUDIT_REPORT.md`,
`FIX_REPORT.md`, code comments citing "the original KAREN 1.0.0 APK".

**`codemagic.yaml`** — untouched. Its workflow label "KAREN NEXT - Android Debug APK" is a CI job
name, not app branding, and §2 says not to change build configuration unless required. Its
static package-id checks still pass unchanged.

**PIN / hashing / recovery / SMS / navigation / providers / architecture / dependencies:** no edits.
`material_ui` and `cupertino_ui` migration from the previous round is intact.

## Verification actually performed

Static, on the real tree:

- `grep -rn "الکترونیک" lib/ test/ android/` → **0 results**.
- `grep -rn "Karen Electronic" lib/ --include=*.dart` → only 2 code comments about the original 1.0.0 APK.
- `AndroidManifest.xml` label → `@string/app_name`; `strings.xml` → `Sinkit`.
- `grep applicationId|namespace android/app/build.gradle` → `ir.bestdroid.karen` (both).
- All 11 storage keys re-read from `app_constants.dart` → byte-identical.
- Remaining `کارن` occurrences reviewed one by one: all are hardware/device references (9 sites).
- Import paths for the two new `app_constants.dart` imports checked against the file tree.
- Edited regions re-read in place; no duplicated or orphaned `SizedBox`/`Text` left in the splash.

## NOT run — do not treat as green

- `flutter analyze` — **not run**
- `flutter test` — **not run**
- `flutter test --coverage` — **not run**
- Debug APK build / `aapt2` label inspection — **not run**

No Flutter SDK, Dart SDK, Java or Gradle exists in the environment this patch was prepared in
(`which flutter dart java gradle` → nothing). `pubspec.lock` is still absent and must be regenerated.

To finish:

```bash
flutter pub get
flutter analyze
flutter test
cd android && ./gradlew assembleDebug
# then confirm the label on the artifact:
aapt2 dump badging app/build/outputs/apk/debug/app-debug.apk | grep application-label
```

## Logo update (added after the rename)

Supplied artwork: `FuturisticSinkitNeonLogo.png`, 1254x1254 RGB. Tile measured at
x 85-1194 / y 34-1168 (1135 px), corner radius 253 px (22.3%), cropped square to the tile
and masked to an antialiased rounded rect so the corners are transparent, not black.

| Output | Size |
|---|---|
| `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` | 48 / 72 / 96 / 144 / 192 |
| `mipmap-*/ic_launcher_round.png` | same as above |
| `mipmap-*/ic_launcher_foreground.png` | 108 / 162 / 216 / 324 / 432, logo at 66% centred |
| `assets/branding/sinkit_logo.png` | 512x512 (in-app) |

- `values/colors.xml`: `ic_launcher_background` `#1E1038` → `#000000` to match the artwork backdrop.
- `KarenLogoMark` now renders `assets/branding/sinkit_logo.png`; the old hand-drawn purple "K"
  painter (`_KarenLogoPainter`) was deleted, not left dead. The class name and its four call sites
  (splash 108, PIN 72, home 46, drawer 42) are unchanged.
- `assets/branding/karen_logo.svg` (old K mark, referenced by nothing) deleted.
- `assets/branding/` was already declared in `pubspec.yaml`, so no pubspec change was needed.

Verified by decoding the written files: launcher 192x192 with corner alpha 0 and centre alpha 255;
foreground 432x432 with the logo occupying exactly 66.0% and transparent margins; artwork content
17.8% bright pixels, 6.1% purple glow, max channel 255 — i.e. the crop is real, not empty.

## Remaining issues / notes

1. The launcher label is Latin "Sinkit" inside an otherwise Persian RTL UI, as specified. If a Persian
   rendering is wanted later, change only `strings.xml`.
2. Existing installations keep their data (keys and package id unchanged), but the launcher will show
   "Sinkit" immediately after update — expected for a rename.
3. The Play Store listing title, screenshots and store description are outside the APK and must be
   updated in the console separately.
4. `pubspec.lock` still needs to be generated and committed.
5. The launcher icon is generated from a 1254 px raster. No vector source exists for the new mark,
   so there is no SVG to add — if one is produced later, the PNG set can be regenerated from it.
