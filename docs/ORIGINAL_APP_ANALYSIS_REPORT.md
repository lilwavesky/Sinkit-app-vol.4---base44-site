# KAREN 1.0.0 — Complete Forensic Analysis Report

## 1. Confirmed Application Purpose
KAREN 1.0.0 (`ir.bestdroid.karen`, branded **کارن الکترونیک / Karen Electronic**) is an offline-first Persian RTL **SMS-based GSM Power & Daily Schedule Controller** built with Flutter, GetX, and Hive. It manages controller SIM numbers, dispatches ON/OFF power commands, uploads daily/hourly schedules, configures power-outage alerts and operating modes, defines admins/users, and requests status reports.

## 2. Complete Confirmed Screen & Route Inventory
- `/splash` — Launch screen
- `/root` — 3-tab RTL bottom navigation shell (`صفحه اصلی`, `بارگذاری روزها`, `گزارشگیری`)
- `/home` — Top bar (Drawer, Add Device `+`, Settings gear) + center `روشن و خاموش کردن دستگاه` (`روشن` / `خاموش`)
- Drawer (`لیست دستگاه ها`) — Registered device list + hardcoded red `Version: 1.0.1` footer
- Modal `ثبت شماره جدید` — Form with `عنوان`, `شماره همراه`, `تایید`
- Modal Settings — 5 buttons: `قطع کردن اخطار قطع برق`, `غیر فعال کردن اخطار قطع برق`, `تنظیمات حالت کارکرد`, `تعریف مدیر`, `تعریف کاربر`
- `/uploadReviews` (`بارگذاری روزها` — misnamed in original codebase) — 3 buttons: `تنظیم روز`, `تنظیم ساعات روز`, `تنظیم روزانه`
- `/houseDaily` & `/houseDaily2` — Duplicated v1/v2 daily hour configuration modules (likely misspelling of `hours_daily`)
- `/reporting` (`گزارشگیری`) — 3 buttons: `گزارشگیری کلی` (`generalReporting`), `تنظیم ساعت`, `بازیابی زمان روزها`
- `/user` & `add_users` — Authorized user/admin management modules
- `/setting` — Settings controller/view
- `/hiveExample` — Developer example/debug route accidentally shipped in production

## 3. Identified Bugs, Technical Debt & Weaknesses
1. **Dead Template Bloat (~2.2+ MB):** Unused "Sanjak / Konkoor 1403" educational assets (`sanjak_logo.png`, `banner.png`, `book_image.png`, `academy.svg`, `login_image.png`, `verify_code_image.png`, `male.png`, `female.png`) shipped in release APK.
2. **Unregistered Bundled Fonts:** 6 font files bundled in `AssetManifest.json` (`IRANSansX*`, `Vazir-Medium`), but only 2 registered in `FontManifest.json` (4 fonts—including all `FaNum` fonts—are unused bloat).
3. **Version Mismatch:** `AndroidManifest.xml` declares `versionName="1.0.0"`, while the Drawer footer displays `Version: 1.0.1`.
4. **Over-Requested Permissions & Missing SMS Receiver:** Declares `SEND_SMS`, `READ_SMS`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, yet contains no `SMS_RECEIVED` BroadcastReceiver in `AndroidManifest.xml`.
5. **Poor Visibility of Active Device State:** Home screen displays ON/OFF buttons without showing which device is currently active, its phone number, or its power/mode status.
6. **Blank Empty States:** Empty `لیست دستگاه ها` drawer provides no guidance or add-device CTA.
7. **Unverified Proprietary SMS Protocol:** Exact plaintext SMS strings sent to Karen hardware were not exposed by static metadata and must be confirmed via runtime capture or official hardware documentation.
