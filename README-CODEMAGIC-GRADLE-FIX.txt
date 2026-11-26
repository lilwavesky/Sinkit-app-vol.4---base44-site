KAREN NEXT — Codemagic Gradle compatibility patch

Reason
------
The failed Codemagic build used Gradle 8.7, while the Flutter Gradle plugin in the selected stable Flutter SDK requires at least Gradle 9.3.1.

Files in this patch must replace the corresponding files in the GitHub repository (same paths):
- codemagic.yaml
- android/settings.gradle
- android/gradle.properties
- android/gradle/wrapper/gradle-wrapper.properties

Version alignment
-----------------
- Gradle Wrapper: 9.3.1
- Android Gradle Plugin: 9.1.1
- Kotlin Gradle Plugin: 2.2.10
- JDK: 17

The Flutter compatibility flags android.builtInKotlin=false and android.newDsl=false are intentionally set to preserve this project's existing Kotlin Gradle Plugin and legacy Android Gradle DSL during the AGP 9 upgrade. This is the migration path documented by Flutter for existing projects.

After replacing these files, commit the changes to the same GitHub branch (main), then start a new Codemagic build using the existing workflow.

Important
---------
This patch addresses the specific Gradle/AGP compatibility failure shown in build 6b0363118f52ca27512a4d94. It does not prove the full application will compile; the next build may reveal additional independent dependency or source errors. Do not add --android-skip-build-dependency-validation.

Update 2026-11-23 — wrapper bootstrap failure (build 6b036ee58f52ca27512a5365)
------------------------------------------------------------------------------
Symptom: after the Gradle 9.3.1 download and SHA-256 check succeeded, step "Toolchain report and official Gradle wrapper" failed with
"Directory '.../gen' does not contain a Gradle build."
Cause: the bootstrap scripts ran `gradle wrapper` in an empty temporary directory; Gradle 9 needs a settings.gradle[.kts|.dcl] there.
Fix: scripts/bootstrap_android_wrapper.sh and .ps1 create a valid (settings.gradle + empty build.gradle) generator build first, validate the
generated files, install them atomically and verify `./gradlew --version`. See CHANGELOG.md. Regression test: scripts/test_bootstrap_android_wrapper.sh.
codemagic.yaml now has separate steps for toolchain report, bootstrap self-test, wrapper generation, dependencies, analyze/test, APK build and quality gate.
Still true: none of this proves that the app compiles; read the first failing step of the next build.

Update 2026-11-24 - wrapper distribution checksum
-------------------------------------------------
The generated wrapper downloads gradle-9.3.1-ALL.zip (distributionUrl), but earlier only the -bin.zip used as generator was verified.
android/gradle/wrapper/gradle-wrapper.properties now has distributionSha256Sum (checksum of the -all.zip). The bootstrap requires it, cross-checks it
against Gradle's published gradle-9.3.1-all.zip.sha256 BEFORE downloading, passes it via --gradle-distribution-sha256-sum, and never rewrites the
properties file. If a build stops with exit 4 "does not match the checksum Gradle publishes", correct the value from https://gradle.org/release-checksums/.
GRADLE_BIN_DISTRIBUTION_SHA256 (optional) pins the generator's -bin.zip only.
