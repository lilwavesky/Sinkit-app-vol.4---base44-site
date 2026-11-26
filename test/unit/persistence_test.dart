import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/app/providers/karen_providers.dart';
import 'package:karen_next/core/constants/app_constants.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/storage/local_storage_service.dart';
import 'package:karen_next/core/transport/command_transport.dart';
import 'package:karen_next/core/transport/protocol_templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/in_memory_secure_store.dart';

void main() {
  test('persists sensitive devices, schedules, logs, and templates in encrypted store (NOT plaintext SharedPreferences)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = InMemorySecureStore();
    final storage = LocalStorageService(prefs, secureStore);
    final initial = await storage.loadAll();

    final container1 = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        initialAppDataProvider.overrideWithValue(initial),
        pinHashIterationsProvider.overrideWithValue(1000),
        demoTransportProvider.overrideWithValue(
          const DemoCommandTransport(latency: Duration.zero),
        ),
      ],
    );

    final notifier1 = container1.read(karenControllerProvider.notifier);
    await notifier1.addOrUpdateDevice(
      title: 'موتورخانه اصلی',
      phoneNumber: '09128889900',
      locationLabel: 'تهران',
    );
    await notifier1.setPower(true);
    final slotErr = await notifier1.addTimeSlotLocal(
      0,
      const TimeSlot(
        id: 'slot_persist_1',
        startHour: 6,
        startMinute: 0,
        endHour: 8,
        endMinute: 30,
      ),
    );
    expect(slotErr, isNull);
    await notifier1.updateProtocolTemplate(
      ProtocolTemplates.keyPowerOn,
      'CUSTOM_PWR_ON',
    );
    container1.dispose();

    // Verify phone numbers and command payloads are NOT stored in plaintext SharedPreferences
    for (final key in prefs.getKeys()) {
      final val = prefs.get(key).toString();
      expect(val, isNot(contains('09128889900')));
      expect(val, isNot(contains('CUSTOM_PWR_ON')));
    }

    // Verify encrypted store holds the sensitive payloads
    expect(
      secureStore.data[AppConstants.secureKeyDevices],
      contains('09128889900'),
    );
    expect(
      secureStore.data[AppConstants.secureKeyTemplates],
      contains('CUSTOM_PWR_ON'),
    );
    expect(secureStore.data[AppConstants.secureKeyLogs], isNotEmpty);

    // Reload into a brand new ProviderContainer to confirm full persistence round-trip
    final reloadedData = await storage.loadAll();
    final container2 = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        initialAppDataProvider.overrideWithValue(reloadedData),
      ],
    );
    addTearDown(container2.dispose);

    final state2 = container2.read(karenControllerProvider);
    expect(state2.devices.length, 1);
    expect(state2.devices.first.title, 'موتورخانه اصلی');
    expect(state2.devices.first.phoneNumber, '09128889900');
    expect(state2.devices.first.powerState, DevicePowerState.on);
    expect(state2.devices.first.weeklySchedules[0].slots.length, 1);
    expect(state2.devices.first.weeklySchedules[0].slots.first.endMinute, 30);
    expect(state2.logs.length, 1);
    expect(
      state2.templates.rawTemplate(ProtocolTemplates.keyPowerOn),
      'CUSTOM_PWR_ON',
    );
  });
}
