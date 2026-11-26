import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/app.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/security/pin_hasher.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/in_memory_secure_store.dart';

Future<ProviderScope> _buildApp({
  bool enablePin = false,
  TransportMode initialTransport = TransportMode.demo,
  InMemorySecureStore? secureStore,
  SharedPreferences? prefs,
}) async {
  final effectivePrefs = prefs ??
      await (() async {
        SharedPreferences.setMockInitialValues({});
        return SharedPreferences.getInstance();
      })();
  final effectiveSecure = secureStore ?? InMemorySecureStore();
  final storage = LocalStorageService(effectivePrefs, effectiveSecure);

  if (initialTransport != TransportMode.demo || enablePin) {
    await storage.saveSettings(
      AppSettings(
        transportMode: initialTransport,
        pinLockEnabled: enablePin,
      ),
    );
  }

  final initialData = await storage.loadAll();

  return ProviderScope(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      initialAppDataProvider.overrideWithValue(initialData),
      pinHashIterationsProvider.overrideWithValue(1000),
      demoTransportProvider.overrideWithValue(
        const DemoCommandTransport(latency: Duration.zero),
      ),
      smsTransportProvider.overrideWithValue(
        SmsComposerCommandTransport(launcher: (_) async => true),
      ),
    ],
    child: const KarenNextApp(useGoogleFonts: false),
  );
}

void main() {
  testWidgets('boots to RTL Home, loads demo device, and navigates all 3 tabs', (
    tester,
  ) async {
    final app = await _buildApp();
    await tester.pumpWidget(app);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    // Verify RTL Directionality is enforced
    final dirWidget = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(dirWidget.textDirection, TextDirection.rtl);

    expect(find.text('هنوز دستگاهی ثبت نشده است'), findsOneWidget);

    await tester.tap(find.text('بارگذاری دستگاه نمونه (حالت دمو)'));
    await tester.pumpAndSettle();

    expect(find.text('روشن و خاموش کردن دستگاه'), findsOneWidget);
    expect(find.byKey(const Key('btn_power_on')), findsOneWidget);

    // Navigate to Schedules tab
    await tester.tap(find.text('بارگذاری روزها'));
    await tester.pumpAndSettle();
    expect(find.text('تنظیم روز'), findsOneWidget);

    // Navigate to Reports tab
    await tester.tap(find.text('گزارشگیری'));
    await tester.pumpAndSettle();
    expect(find.text('گزارشگیری کلی'), findsOneWidget);
  });

  testWidgets('shows unverified protocol warning banner in Live SMS mode', (
    tester,
  ) async {
    final app = await _buildApp(
      initialTransport: TransportMode.liveSmsComposer,
    );
    await tester.pumpWidget(app);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unverified_protocol_banner')), findsOneWidget);
  });

  testWidgets('shows StorageRecoveryCard (NOT empty state) on device-store read error and recovers on retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureStore();
    final storage = LocalStorageService(prefs, secureStore);

    // Save real device first
    await storage.saveDevices([
      KarenDevice(
        id: 'dev_saved',
        title: 'پمپ ذخیره شده',
        phoneNumber: '09123456789',
        weeklySchedules: KarenDevice.defaultWeeklySchedules(),
      ),
    ]);

    // Simulate a keystore outage that affects ONLY the device/log/template
    // stores. failReads = true would also take PIN security storage down,
    // which correctly puts the app into its fail-closed recovery lock instead
    // of showing the storage-recovery card (covered by the test below).
    secureStore.failingReadKeys.addAll([
      AppConstants.secureKeyDevices,
      AppConstants.secureKeyLogs,
      AppConstants.secureKeyTemplates,
    ]);
    final app = await _buildApp(secureStore: secureStore, prefs: prefs);
    await tester.pumpWidget(app);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage_recovery_card')), findsOneWidget);
    expect(find.text('هنوز دستگاهی ثبت نشده است'), findsNothing);

    // Restore keystore and tap Retry -> real device reappears intact!
    secureStore.failingReadKeys.clear();
    await tester.tap(find.byKey(const Key('btn_retry_storage')));
    await tester.pumpAndSettle();

    expect(find.text('پمپ ذخیره شده'), findsOneWidget);
  });

  testWidgets('enforces PIN lock route guard and relocks when app moves to background', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureStore();
    final storage = LocalStorageService(prefs, secureStore);
    final initialData = await storage.loadAll();

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          initialAppDataProvider.overrideWithValue(initialData),
          pinHashIterationsProvider.overrideWithValue(1000),
          demoTransportProvider.overrideWithValue(
            const DemoCommandTransport(latency: Duration.zero),
          ),
        ],
        child: Consumer(
          builder: (_, ref, __) {
            capturedRef = ref;
            return const KarenNextApp(useGoogleFonts: false);
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    // Enable PIN lock
    final pinRes = await capturedRef
        .read(karenControllerProvider.notifier)
        .setPinLock('2468');
    expect(pinRes.succeeded, isTrue);

    // Simulate app going to background, then returning to the foreground.
    // While the lifecycle is paused the binding suppresses frame scheduling,
    // so the redirect to /lock is decided but not painted. The foreground is
    // what the user actually sees, and the lock must already be in place.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pin_input_field')), findsOneWidget);

    // Wrong PIN stays locked
    await tester.enterText(find.byKey(const Key('pin_input_field')), '1111');
    await tester.tap(find.byKey(const Key('btn_verify_pin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin_input_field')), findsOneWidget);

    // Correct PIN unlocks and returns to Home
    await tester.enterText(find.byKey(const Key('pin_input_field')), '2468');
    await tester.tap(find.byKey(const Key('btn_verify_pin')));
    await tester.pumpAndSettle();
    expect(find.text('کارن الکترونیک'), findsOneWidget);
  });

  testWidgets('a genuine PIN security-storage read failure keeps the app locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureStore();
    final storage = LocalStorageService(prefs, secureStore);

    // A real PIN was committed, then the PIN security state became unreadable.
    await storage.saveSettings(const AppSettings(pinLockEnabled: true));
    await storage.savePinSecurityState(
      const PinSecurityState(pinLockEnabled: true),
    );
    secureStore.failingReadKeys.add(AppConstants.secureKeyPinSecurityState);

    final app = await _buildApp(secureStore: secureStore, prefs: prefs);
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    // Fail closed: the PIN gate is shown, never the unlocked home screen and
    // never the generic storage-recovery card.
    expect(
      find.byKey(const Key('pin_recovery_required_banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pin_input_field')), findsOneWidget);
    expect(find.byKey(const Key('storage_recovery_card')), findsNothing);
    expect(find.text('هنوز دستگاهی ثبت نشده است'), findsNothing);
  });
}
