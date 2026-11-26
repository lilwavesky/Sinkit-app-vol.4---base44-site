# KAREN NEXT 2.2.0 — Karen Electronic Smart GSM Controller

A complete, Persian RTL Flutter Android application for managing **KAREN Electronic** (`ir.bestdroid.karen`) GSM electrical control devices via SMS-based communication, featuring an offline Demo Simulator, strict Live SMS safety blocking for unverified hardware commands, and Fail-Closed transactional PIN security backed by a persistent encrypted recovery journal.

> **Release Status:** `PARTIALLY COMPLETE` (Source-level implementation and static verification are complete; local Flutter SDK / Android SDK compilation, automated test execution, `pubspec.lock` generation, and official Gradle 9.3.1 wrapper generation must be run on a workstation with Flutter `>= 3.27.0` and internet access. See `FINAL_DELIVERY_REPORT.md` and `BUILD_INSTRUCTIONS.md`.)

## Core Capabilities
- **Device Management:** Add, edit, delete, select, and quickly switch registered Karen Electronic devices (`عنوان` + validated Iranian mobile number + optional location) with encrypted local persistence.
- **Device Control (`صفحه اصلی`):** Active device dashboard, ON/OFF controls with optional accidental-tap confirmation, recent activity preview, quick device switcher, and strict separation between **Demo Mode (`حالت دمو`)** and **SMS Composer Mode (`حالت پیامک`)**.
- **Scheduling (`بارگذاری روزها`):** Per-day enable/disable, per-day multi-slot hours with **Add / Edit / Delete** and overlap prevention, plus multi-slot daily routines with Iranian working-day presets (`شنبه تا چهارشنبه`, `همه روزهای هفته`, `آخر هفته`).
- **Reports & Clock Sync (`گزارشگیری`):** `گزارشگیری کلی`, `تنظیم ساعت` (instant phone clock sync OR manual time selection), `بازیابی زمان روزها`, manual incoming SMS reply logging, category filtering (including `کاربران`), and confirmation-guarded history clearing.
- **Users & Settings:** Power-outage alert muting/toggling, operating mode selection, Admin & User management with **Add / Edit / Delete** + avatar badges, Light/Dark themes, Vazirmatn Persian typography with bundled offline `NotoSansArabic` fallback, and PBKDF2 hardware benchmarking.
- **Fail-Closed PIN Security:** 4-digit PBKDF2-HMAC-SHA256 PIN lock (`100,000` iterations default, `600,000` ceiling, 16-byte random salt, 32-byte key), persistent encrypted `PinTransactionJournal` with automatic interrupted-transaction recovery on restart, persistent 5-attempt 30-second lockout, and background relock.

## Documentation Index
- `FINAL_DELIVERY_REPORT.md` — Overall delivery status, completed work, and exact remaining blockers
- `SECURITY_AUDIT_REPORT.md` — PIN recovery journal architecture, PBKDF2 OWASP review, and SMS safety gates
- `TEST_REPORT.md` — Complete 10-file test suite inventory and honest executed vs. unexecuted command results
- `BUILD_INSTRUCTIONS.md` — Exact local setup, official Gradle 9.3.1 wrapper generation, test, and APK/AAB build steps
- `CHANGELOG.md` — Version history from KAREN 1.0.0 analysis through KAREN NEXT 2.2.0
- `DEVELOPMENT_STATUS.md` — Checkpoint log of completed items and remaining local/hardware tasks
