# KAREN NEXT 2.2.0 — Technical Architecture Documentation

## Architecture Pattern
Clean Feature-First Flutter Architecture powered by **Riverpod** (`NotifierProvider`), **GoRouter** (`StatefulShellRoute.indexedStack` + reactive PIN lock/recovery redirect guard), immutable Dart 3 models, encrypted Android Keystore-backed persistence, and strictly separated Demo vs. Live SMS transport layers.

## Package & Module Map (`ir.bestdroid.karen`)
- `lib/app/`: App root (`WidgetsBindingObserver` background relock), `GoRouter` redirect guard, Material 3 Persian RTL Vazirmatn + `NotoSansArabic` theme, `KarenController` state & FIFO PIN mutex.
- `lib/core/security/`: `PinHasher` (RFC 2898 PBKDF2-HMAC-SHA256, strict metadata validation, legacy V2.0 migration, Android benchmark), `PinSecurityState`, `PinTransactionJournal`.
- `lib/core/storage/`: `LocalStorageService` splitting non-sensitive preferences (`PreferencesKeyValueStore`) from encrypted sensitive stores (`SecureKeyValueStore`), startup journal recovery, write protection on storage failure, and verified emergency wipe.
- `lib/core/transport/`: `ProtocolTemplates` (`[UNVERIFIED:...]` safety placeholders), `DemoCommandTransport`, and `SmsComposerCommandTransport` (strictly blocks empty/unverified/unresolved templates and reports `pendingConfirmation`).
- `lib/features/`: `splash`, `security`, `home`, `devices`, `schedules`, `reports`, `users`, `settings`.
