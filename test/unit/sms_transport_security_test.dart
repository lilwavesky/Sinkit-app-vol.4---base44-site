import 'package:flutter_test/flutter_test.dart';
import 'package:karen_next/core/models/karen_models.dart';
import 'package:karen_next/core/transport/command_transport.dart';
import 'package:karen_next/core/transport/protocol_templates.dart';

void main() {
  final sampleDevice = KarenDevice(
    id: 'dev_1',
    title: 'تابلو پمپ',
    phoneNumber: '09123456789',
    weeklySchedules: KarenDevice.defaultWeeklySchedules(),
  );

  group('ProtocolTemplates validation', () {
    test('all default templates are marked unverified and blocked for Live SMS', () {
      final defaults = ProtocolTemplates.unverifiedDefaults();
      expect(defaults.hasAnyUnverified, isTrue);
      expect(defaults.verifiedCount, 0);
      expect(defaults.unverifiedCount, defaults.totalCount);

      for (final key in ProtocolTemplates.labelsFa.keys) {
        expect(defaults.isPlaceholder(key), isTrue);
        expect(defaults.isVerified(key), isFalse);
        expect(
          defaults.validateForLiveSms(key, defaults.render(key)),
          isNotNull,
        );
      }
    });

    test('rejects empty or [UNVERIFIED] user template edits', () {
      expect(ProtocolTemplates.validateUserTemplateInput(''), isNotNull);
      expect(ProtocolTemplates.validateUserTemplateInput('   '), isNotNull);
      expect(
        ProtocolTemplates.validateUserTemplateInput('[UNVERIFIED:ON]'),
        isNotNull,
      );
      expect(
        ProtocolTemplates.validateUserTemplateInput('unverified:test'),
        isNotNull,
      );
      expect(ProtocolTemplates.validateUserTemplateInput('CUSTOM_ON_CODE'), isNull);
    });
  });

  group('SmsComposerCommandTransport security gates', () {
    test('strictly blocks [UNVERIFIED:...] payloads and never launches SMS app', () async {
      var launchCalled = false;
      final transport = SmsComposerCommandTransport(
        launcher: (_) async {
          launchCalled = true;
          return true;
        },
      );

      final result = await transport.dispatch(
        CommandDispatchRequest(
          device: sampleDevice,
          actionKey: ProtocolTemplates.keyPowerOn,
          actionTitle: 'روشن کردن دستگاه',
          category: CommandCategory.power,
          rawTemplate: '[UNVERIFIED:POWER_ON]',
          payload: '[UNVERIFIED:POWER_ON]',
          isPlaceholderTemplate: true,
        ),
      );

      expect(launchCalled, isFalse);
      expect(result.dispatched, isFalse);
      expect(result.isSimulatedExecution, isFalse);
      expect(result.isPendingConfirmation, isFalse);
      expect(result.status, CommandLogStatus.blockedUnverified);
    });

    test('strictly blocks empty or whitespace-only command templates', () async {
      var launchCalled = false;
      final transport = SmsComposerCommandTransport(
        launcher: (_) async {
          launchCalled = true;
          return true;
        },
      );

      final result = await transport.dispatch(
        CommandDispatchRequest(
          device: sampleDevice,
          actionKey: ProtocolTemplates.keyPowerOn,
          actionTitle: 'روشن کردن دستگاه',
          category: CommandCategory.power,
          rawTemplate: '   ',
          payload: '   ',
          isPlaceholderTemplate: false,
        ),
      );

      expect(launchCalled, isFalse);
      expect(result.dispatched, isFalse);
      expect(result.status, CommandLogStatus.blockedUnverified);
    });

    test('strictly blocks unresolved template parameters like {phone}', () async {
      var launchCalled = false;
      final transport = SmsComposerCommandTransport(
        launcher: (_) async {
          launchCalled = true;
          return true;
        },
      );

      final result = await transport.dispatch(
        CommandDispatchRequest(
          device: sampleDevice,
          actionKey: ProtocolTemplates.keyDefineAdmin,
          actionTitle: 'تعریف مدیر',
          category: CommandCategory.userAccess,
          rawTemplate: 'ADMIN={phone}',
          payload: 'ADMIN={phone}',
          isPlaceholderTemplate: false,
        ),
      );

      expect(launchCalled, isFalse);
      expect(result.dispatched, isFalse);
      expect(result.status, CommandLogStatus.blockedUnverified);
    });

    test('verified template opens sms: URI and reports pendingConfirmation (NOT hardware success)', () async {
      Uri? launchedUri;
      final transport = SmsComposerCommandTransport(
        launcher: (uri) async {
          launchedUri = uri;
          return true;
        },
      );

      final result = await transport.dispatch(
        CommandDispatchRequest(
          device: sampleDevice,
          actionKey: ProtocolTemplates.keyPowerOn,
          actionTitle: 'روشن کردن دستگاه',
          category: CommandCategory.power,
          rawTemplate: 'USER_VERIFIED_CMD_1',
          payload: 'USER_VERIFIED_CMD_1',
          isPlaceholderTemplate: false,
        ),
      );

      expect(launchedUri, isNotNull);
      expect(launchedUri!.scheme, 'sms');
      expect(launchedUri!.path, '09123456789');
      expect(launchedUri!.queryParameters['body'], 'USER_VERIFIED_CMD_1');
      expect(result.dispatched, isTrue);
      expect(result.isSimulatedExecution, isFalse);
      expect(result.isPendingConfirmation, isTrue);
      expect(result.status, CommandLogStatus.pendingConfirmation);
    });

    test('DemoCommandTransport formats multiline general report safely and simulates execution', () async {
      const transport = DemoCommandTransport(latency: Duration.zero);
      final result = await transport.dispatch(
        CommandDispatchRequest(
          device: sampleDevice,
          actionKey: ProtocolTemplates.keyGeneralReport,
          actionTitle: 'گزارشگیری کلی',
          category: CommandCategory.report,
          rawTemplate: '[UNVERIFIED:GENERAL_REPORT]',
          payload: '[UNVERIFIED:GENERAL_REPORT]',
          isPlaceholderTemplate: true,
        ),
      );

      expect(result.dispatched, isTrue);
      expect(result.isSimulatedExecution, isTrue);
      expect(result.isPendingConfirmation, isFalse);
      expect(result.status, CommandLogStatus.simulatedSuccess);
      expect(result.simulatedReplyFa, contains('گزارش شبیه‌سازی دمو'));
      expect(result.simulatedReplyFa, contains('\n'));
    });
  });
}
