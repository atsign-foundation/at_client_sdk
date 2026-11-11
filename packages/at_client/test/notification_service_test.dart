// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    hide AtNotification;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_crypto_provider.dart';
import 'test_utils/transport.dart';

String? lastNotificationJson;

class MockSecondaryKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

class MockLocalSecondary extends Mock implements LocalSecondary {
  @override
  AtKeyValueStore<String, AtData, AtMetaData?>? keyStore =
      MockSecondaryKeyStore();
}

class MockAtClientImpl extends Mock implements AtClientImpl {
  // NOTE: the same erasure: an unstubbed `lookUps` answers null into a
  // non-nullable function type, and the services read it off the impl.
  @override
  final AtLookUpFactory lookUps = secureSocketLookUps();
  // NOTE: `implements` erases the concrete getter AtClientImpl carries, and an
  // unstubbed mocktail getter answers null, which the runtime refuses for the
  // non-nullable AtConnection; a Monitor built from this mock reads it.
  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice',
      attempt: (_) async =>
          AtConnectionState.offline(AtConnectionCause.unattempted));
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;

  @override
  String? getCurrentAtSign() {
    return '@alice';
  }

  @override
  Atsign get atSign => getCurrentAtSign()!.toAtsign();

  LocalSecondary mockLocalSecondary = MockLocalSecondary();

  @override
  LocalSecondary? getLocalSecondary() {
    return mockLocalSecondary;
  }
}

class FakeMonitor extends Fake implements Monitor {
  @override
  Future<void> close() async {}

  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;

  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;

  @override
  void start() {
    currentState = NotificationListenerState.listening;
    targetState = NotificationListenerState.listening;
  }

  @override
  Future<void> stop() async {
    currentState = NotificationListenerState.notConnected;
    targetState = NotificationListenerState.notConnected;
  }
}

class FakeNotifyVerbBuilder extends Fake implements NotifyVerbBuilder {}

class FakeNotifyFetchVerbBuilder extends Fake
    implements NotifyFetchVerbBuilder {}

/// Keeps the [AtKey] it was handed, so a test can assert which namespace the
/// encryption was scoped to.
class RecordingProvider extends CryptoProvider {
  @override
  final String id = 'recording-provider';

  AtKey? seen;

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    seen = atKey;
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return 'enc:$value';
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value.substring(4);
}

// NOTE: send() asks the atServer's info before it notifies; the notify
// command is what these tests are about.
bool _isNotify(dynamic command) => '$command'.startsWith('notify:');

void main() {
  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  AtClientManager mockAtClientManager = MockAtClientManager();
  FakeMonitor fakeMonitor = FakeMonitor();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  AtLookupImpl mockAtLookupImpl = MockAtLookupImpl();
  setUpAll(() {});
  group('A group of test to validate notification request transformer', () {
    var value = '+91908909933';
    setUp(() {
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          // Notifications with no override route to the 'legacy' provider;
          // register a CipherProvider under that id so the runtime resolves it
          // and produces the expected 'abc...' ciphertext.
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            providers: [CipherProvider('legacy')],
          ),
      );
      when(() => mockAtClientImpl.preference!.namespace).thenReturn('wavi');
    });

    group('Tests with simple namespace in AtClientPrefs', () {
      test('Notification request without namespace but with namespace in prefs',
          () async {
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone');
        expect(notifyVerbBuilder.atKey.namespace, 'wavi');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'Notification request with namespace and with same namespace in prefs',
          () async {
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.wavi@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone');
        expect(notifyVerbBuilder.atKey.namespace, 'wavi');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'Notification request with a namespace but a different namespace in prefs',
          () async {
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone.my_app');
        expect(notifyVerbBuilder.atKey.namespace, 'wavi');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'with namespace and different namespace in prefs but not namespace aware',
          () async {
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = false);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone');
        expect(notifyVerbBuilder.atKey.namespace, 'my_app');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });
    });

    group('Tests with multipart namespace in AtClientPrefs', () {
      test(
          'Notification request without namespace but with multi-part namespace in prefs',
          () async {
        when(() => mockAtClientImpl.getPreferences())
            .thenReturn(AtClientPreference()..namespace = 'foo.bar.baz');
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone.foo.bar');
        expect(notifyVerbBuilder.atKey.namespace, 'baz');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'Notification request with namespace and with same namespace in prefs',
          () async {
        when(() => mockAtClientImpl.getPreferences())
            .thenReturn(AtClientPreference()..namespace = 'foo.bar.baz');
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.foo.bar.baz@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone.foo.bar');
        expect(notifyVerbBuilder.atKey.namespace, 'baz');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'Notification request with a namespace but a different namespace in prefs',
          () async {
        when(() => mockAtClientImpl.getPreferences())
            .thenReturn(AtClientPreference()..namespace = 'foo.bar.baz');
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone.my_app.foo.bar');
        expect(notifyVerbBuilder.atKey.namespace, 'baz');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });

      test(
          'with namespace and different namespace in prefs but not namespace aware',
          () async {
        when(() => mockAtClientImpl.getPreferences())
            .thenReturn(AtClientPreference()..namespace = 'foo.bar.baz');
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = false);
        var notifyVerbBuilder =
            await NotificationRequestTransformer(mockAtClientImpl)
                .transform(notificationParams);
        expect(notifyVerbBuilder.atKey.key, 'phone');
        expect(notifyVerbBuilder.atKey.namespace, 'my_app');
        expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
        expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
        expect(notifyVerbBuilder.priority, PriorityEnum.low);
        expect(notifyVerbBuilder.strategy, StrategyEnum.all);
        // The default duration is 24 hours - converted into milliseconds
        expect(notifyVerbBuilder.ttln, 86400000);
      });
    });

    test(
        'A test to validate notification request without value return verb builder',
        () async {
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()..namespace = 'wavi',
      );
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build());
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.atKey.key, 'phone');
      expect(notifyVerbBuilder.atKey.namespace, 'wavi');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
      // The default duration is 24 hours - converted into milliseconds
      expect(notifyVerbBuilder.ttln, 86400000);
    });

    test(
        'A test to validate notification request with unencrypted value return verb builder',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build(),
          value: value,
          priority: PriorityEnum.high,
          strategy: StrategyEnum.latest,
          notifier: 'test-notifier',
          latestN: 2,
          notificationExpiry: Duration(minutes: 1));
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.atKey.key, 'phone');
      expect(notifyVerbBuilder.atKey.namespace, 'wavi');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.high);
      expect(notifyVerbBuilder.strategy, StrategyEnum.latest);
      expect(notifyVerbBuilder.value, value);
      expect(notifyVerbBuilder.notifier, 'test-notifier');
      expect(notifyVerbBuilder.latestN, 2);
      expect(notifyVerbBuilder.ttln, Duration(minutes: 1).inMilliseconds);
    });

    test(
        'A test to validate notification request with encrypted value return verb builder',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build(),
          value: value,
          priority: PriorityEnum.high,
          strategy: StrategyEnum.latest,
          notifier: 'test-notifier',
          latestN: 2,
          notificationExpiry: Duration(minutes: 1));
      notificationParams.atKey.metadata.isEncrypted = true;
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.atKey.key, 'phone');
      expect(notifyVerbBuilder.atKey.namespace, 'wavi');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.high);
      expect(notifyVerbBuilder.strategy, StrategyEnum.latest);
      expect(notifyVerbBuilder.value, 'abc$value');
      expect(notifyVerbBuilder.atKey.metadata.sharedKeyEnc, 'sharedKeyEnc');
      expect(notifyVerbBuilder.notifier, 'test-notifier');
      expect(notifyVerbBuilder.latestN, 2);
      expect(notifyVerbBuilder.ttln, Duration(minutes: 1).inMilliseconds);
    });

    test(
        'A test to validate encrypted value and shared encryption key is set in verb builder when isEncrypted is set to true in metadata',
        () async {
      var notificationParams = NotificationParams.forUpdate(
        (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob')).build(),
        value: value,
        priority: PriorityEnum.high,
        strategy: StrategyEnum.latest,
        notifier: 'test-notifier',
        latestN: 2,
        notificationExpiry: Duration(minutes: 1),
        cryptoProviderId: 'test_provider',
      );
      notificationParams.atKey.metadata.isEncrypted = true;
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            providers: [CipherProvider('test_provider')],
          ),
      );
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.value, 'abc$value');
      expect(notifyVerbBuilder.atKey.metadata.sharedKeyEnc, 'sharedKeyEnc');
      expect(notifyVerbBuilder.atKey.metadata.appMetadata,
          notificationParams.atKey.metadata.appMetadata);
    });
    test(
        'A test to validate notification encryption uses preference default crypto provider',
        () async {
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'default-provider',
            providers: [CipherProvider('default-provider')],
          ),
      );
      var notificationParams = NotificationParams.forUpdate(
        (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob')).build(),
        value: value,
      );
      notificationParams.atKey.metadata.isEncrypted = true;

      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);

      expect(notifyVerbBuilder.value, 'abc$value');
      expect(notifyVerbBuilder.atKey.metadata.appMetadata?.providerId,
          'default-provider');
    });
    test('A test to validate notification params override crypto provider',
        () async {
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'default-provider',
            providers: [
              CipherProvider('default-provider'),
              CipherProvider('override-provider'),
            ],
          ),
      );
      var notificationParams = NotificationParams.forUpdate(
        (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob')).build(),
        value: value,
        cryptoProviderId: 'override-provider',
      );
      notificationParams.atKey.metadata.isEncrypted = true;

      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);

      expect(notifyVerbBuilder.value, 'abc$value');
      expect(notifyVerbBuilder.atKey.metadata.appMetadata?.providerId,
          'override-provider');
    });

    group('a send the SDK encrypts takes nothing an earlier send left', () {
      void configureTwoProviders() =>
          when(() => mockAtClientImpl.getPreferences()).thenReturn(
            AtClientPreference()
              ..namespace = 'wavi'
              ..crypto = CryptoConfig(
                defaultProviderId: 'default-provider',
                providers: [
                  CipherProvider('default-provider'),
                  CipherProvider('override-provider'),
                ],
              ),
          );

      AtKey toBob() =>
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build();

      Future<String?> providerOfSend(
          AtKey atKey, String? cryptoProviderId) async {
        final params = NotificationParams.forUpdate(atKey,
            value: value, cryptoProviderId: cryptoProviderId);
        params.atKey.metadata.isEncrypted = true;
        final builder = await NotificationRequestTransformer(mockAtClientImpl)
            .transform(params);
        return builder.atKey.metadata.appMetadata?.providerId;
      }

      test('a provider id written on the key does not choose the provider',
          () async {
        configureTwoProviders();
        final atKey = toBob()
          ..metadata.appMetadata = AppMetadata(providerId: 'override-provider');

        expect(await providerOfSend(atKey, null), 'default-provider',
            reason: 'only cryptoProviderId, or else the default, chooses the '
                'provider of a send the SDK encrypts');
      });

      test('a reused key follows each send\'s own cryptoProviderId', () async {
        configureTwoProviders();
        final atKey = toBob();

        expect(await providerOfSend(atKey, 'override-provider'),
            'override-provider');
        expect(
            await providerOfSend(atKey, 'default-provider'), 'default-provider',
            reason: 'the provider the first send stamped on the key must not '
                'outrank the second send\'s explicit request');
        expect(await providerOfSend(atKey, null), 'default-provider',
            reason: 'nor stand in for the default');
      });

      test('keys sharing one Metadata do not inherit each other\'s provider',
          () async {
        configureTwoProviders();
        final shared = Metadata();
        final first = toBob()..metadata = shared;
        final second = (AtKey.shared('phone', namespace: 'wavi')
              ..sharedWith('@carol'))
            .build()
          ..metadata = shared;

        expect(await providerOfSend(first, 'override-provider'),
            'override-provider');
        expect(await providerOfSend(second, null), 'default-provider',
            reason: 'one Metadata object reused across keys is how AtRpc '
                'sent; the first send\'s stamp must not route the second');
      });
    });
    test(
        'A test to validate unencrypted value is set in verb builder when isEncrypted is set to false in metadata',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build(),
          value: value,
          priority: PriorityEnum.high,
          strategy: StrategyEnum.latest,
          notifier: 'test-notifier',
          latestN: 2,
          notificationExpiry: Duration(minutes: 1));
      notificationParams.atKey.metadata.isEncrypted = false;
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.value, value);
    });
    test(
        'A test to validate unencrypted value is set in verb builder when isEncrypted is NOT set in metadata',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build(),
          value: value,
          priority: PriorityEnum.high,
          strategy: StrategyEnum.latest,
          notifier: 'test-notifier',
          latestN: 2,
          notificationExpiry: Duration(minutes: 1));
      var notifyVerbBuilder =
          await NotificationRequestTransformer(mockAtClientImpl)
              .transform(notificationParams);
      expect(notifyVerbBuilder.value, value);
    });
  });

  group('A group of tests to validate notification send provider selection',
      () {
    test('send cryptoProviderId overrides preference default provider',
        () async {
      final remoteSecondary = MockRemoteSecondary();
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'default-provider',
            providers: [
              CipherProvider('default-provider'),
              CipherProvider('override-provider'),
            ],
          ),
      );
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenReturn(remoteSecondary);
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:ok');

      var notificationServiceImpl = await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: mockSecondaryAddressFinder,
      ) as NotificationServiceImpl;

      await notificationServiceImpl.send(
        to: '@bob'.toAtsign(),
        idAndNamespace: 'note.wavi',
        body: 'hello',
        cryptoProviderId: 'override-provider',
      );

      final command =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .where(_isNotify)
              .single as String;
      // The send routed encryption to the override provider, so the wire
      // appMetadata carries that providerId (not the preference default).
      expect(
        command,
        contains(
          ':${AtConstants.appMetadata}:'
          '${Metadata.encodeAppMetadata(AppMetadata(providerId: 'override-provider'))}',
        ),
      );
      expect(
        command,
        isNot(contains(Metadata.encodeAppMetadata(
            AppMetadata(providerId: 'default-provider')))),
      );
    });

    test('send without cryptoProviderId uses preference default provider',
        () async {
      final remoteSecondary = MockRemoteSecondary();
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'default-provider',
            providers: [CipherProvider('default-provider')],
          ),
      );
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenReturn(remoteSecondary);
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:ok');

      var notificationServiceImpl = await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: mockSecondaryAddressFinder,
      ) as NotificationServiceImpl;

      await notificationServiceImpl.send(
        to: '@bob'.toAtsign(),
        idAndNamespace: 'note.wavi',
        body: 'hello',
      );

      final command =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .where(_isNotify)
              .single as String;
      // With no override, the send routed encryption to the preference default
      // provider, so the wire appMetadata carries that providerId.
      expect(
        command,
        contains(
          ':${AtConstants.appMetadata}:'
          '${Metadata.encodeAppMetadata(AppMetadata(providerId: 'default-provider'))}',
        ),
      );
    });

    test('send answers a notification in the scheme it arrived in', () async {
      final remoteSecondary = MockRemoteSecondary();
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'default-provider',
            providers: [
              CipherProvider('default-provider'),
              CipherProvider('request-provider'),
            ],
          ),
      );
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenReturn(remoteSecondary);
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:ok');
      final notificationServiceImpl = await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: mockSecondaryAddressFinder,
      ) as NotificationServiceImpl;
      final request = AtNotification.empty()
        ..from = '@bob'
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'request-provider'));

      await notificationServiceImpl.send(
        to: request.from.toAtsign(),
        idAndNamespace: 'reply.wavi',
        body: 'answer',
        cryptoProviderId: request.receivedUnder,
      );

      final command =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .where(_isNotify)
              .single as String;
      expect(
        command,
        contains(
          ':${AtConstants.appMetadata}:'
          '${Metadata.encodeAppMetadata(AppMetadata(providerId: 'request-provider'))}',
        ),
        reason: 'the reply goes out under the provider the request arrived '
            'under, not this client\'s default',
      );
    });
  });

  /// `send()`'s name is an id and a namespace joined by a dot, and the split is
  /// at the FIRST dot. Splitting at the last one scopes the encryption to a
  /// namespace the caller never named — or, for a two-segment name, to no
  /// namespace at all, which sends the write to legacy.
  group('send() splits its name into an id and a namespace', () {
    late RecordingProvider recorder;
    late MockRemoteSecondary remoteSecondary;

    setUp(() {
      recorder = RecordingProvider();
      remoteSecondary = MockRemoteSecondary();
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'my_app'
          ..crypto = CryptoConfig(
              defaultProviderId: recorder.id, providers: [recorder]),
      );
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenReturn(remoteSecondary);
      when(() => remoteSecondary.executeCommand(any(), auth: true))
          .thenAnswer((_) async => 'data:ok');
    });

    Future<NotificationServiceImpl> service() async =>
        await NotificationServiceImpl.create(mockAtClientImpl,
                monitor: fakeMonitor,
                secondaryAddressFinder: mockSecondaryAddressFinder)
            as NotificationServiceImpl;

    test('everything after the first dot is the namespace', () async {
      await (await service())
          .send(to: '@bob'.toAtsign(), idAndNamespace: 'a.b.c', body: 'hello');

      expect(recorder.seen!.key, 'a');
      expect(recorder.seen!.namespace, 'b.c',
          reason: 'the last-dot split would say "c" here, and would encrypt '
              'under a namespace the caller never named');

      final command =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .where(_isNotify)
              .single as String;
      // NOTE: the wire name is frozen — the recipient derives the ciphertext's
      // binding from this string, so moving it computes different bytes.
      expect(command, contains(':@bob:a.b.c@alice'));
    });

    test('the built command, pinned', () async {
      final id = await (await service())
          .send(to: '@bob'.toAtsign(), idAndNamespace: 'a.b.c', body: 'hello');

      final command =
          verify(() => remoteSecondary.executeCommand(captureAny(), auth: true))
              .captured
              .where(_isNotify)
              .single as String;

      // NOTE: a frozen wire shape, with only the generated id substituted out
      // — an intended change edits this line, and that edit is the review.
      expect(
          command.replaceFirst(id, '<id>'),
          'notify:id:<id>:notifier:SYSTEM:ttln:900000:isEncrypted:true'
          ':appMetadata:eyJwcm92aWRlcklkIjoicmVjb3JkaW5nLXByb3ZpZGVyIn0='
          ':@bob:a.b.c@alice:enc:hello\n');
    });

    test('a name with no dot is refused at the call site', () async {
      final s = await service();

      await expectLater(
          () => s.send(to: '@bob'.toAtsign(), idAndNamespace: 'wavi'),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('joined by a dot'))),
          reason: 'an id in no namespace cannot be encrypted for a recipient. '
              'Before this, it reached the crypto layer, declined every '
              'post-quantum provider, fell back to the legacy provider and surfaced as a '
              'refusal about encryption — three layers from the mistake');

      expect(recorder.seen, isNull,
          reason: 'and it is refused BEFORE anything is encrypted or sent');
      verifyNever(() => remoteSecondary.executeCommand(any(), auth: true));
    });

    test('an empty id or an empty namespace is refused too', () async {
      final s = await service();
      for (final bad in ['.wavi', 'wavi.']) {
        await expectLater(
            () => s.send(to: '@bob'.toAtsign(), idAndNamespace: bad),
            throwsA(isA<ArgumentError>()),
            reason: '"$bad" has a dot but leaves one half empty, and an empty '
                'namespace declines exactly as a missing one does');
      }
    });
  });

  group('A group of test to validate notification response transformer', () {
    setUp(() {
      registerFallbackValue(FakeAtKey());
      // Notifications here carry no appMetadata.providerId, so decryption
      // routes to the 'legacy' provider; register a CipherProvider under that
      // id so the runtime decrypts via it (substring(3)).
      when(() => mockAtClientImpl.getPreferences()).thenReturn(
        AtClientPreference()
          ..namespace = 'wavi'
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            providers: [CipherProvider('legacy')],
          ),
      );
    });

    test('AtNotification.fromJson decodes app metadata', () {
      final appMetadata = AppMetadata(providerId: 'test_provider');
      final notification = AtNotification.fromJson({
        'id': '124',
        'key': '@bob:key-1.foo@alice',
        'from': '@alice',
        'to': '@bob',
        'epochMillis': DateTime.now().millisecondsSinceEpoch,
        'messageType': MessageTypeEnum.key.toString(),
        AtConstants.isEncrypted: true,
        'metadata': {
          AtConstants.appMetadata: Metadata.encodeAppMetadata(appMetadata),
        },
      });

      expect(notification.metadata?.appMetadata, appMetadata);
    });

    test(
        'A test to verify notification value is decrypted when isEncrypted is set to null',
        () async {
      bool? isEncrypted;
      var atNotification = AtNotification(
          '124',
          '@bob:key-1.foo@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: '123encryptedValue');
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.value, 'encryptedValue');
    });

    test(
        'A test to verify notification value is decrypted when isEncrypted is set to true',
        () async {
      bool isEncrypted = true;
      var atNotification = AtNotification(
          '124',
          '@bob:key-1.foo@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: '123encryptedValue');
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.value, 'encryptedValue');
    });

    test(
        'A test to verify notification value is not decrypted when isEncrypted is set to false',
        () async {
      var isEncrypted = false;
      var atNotification = AtNotification(
          '124',
          '@bob:key-1.foo@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: 'encryptedValue');
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = false));
      expect(transformedNotification.value, 'encryptedValue');
    });

    test(
        'A test to verify notification value is not decrypted when isEncrypted is set to true and should decrypt is false',
        () async {
      var isEncrypted = true;
      var atNotification = AtNotification(
          '124',
          '@bob:key-1.foo@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: 'encryptedValue');
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = false));
      expect(transformedNotification.value, 'encryptedValue');
    });

    test('A test to verify notification is returned as is', () async {
      var isEncrypted = false;
      var atNotification = AtNotification(
          '124',
          '@bob:key-1.foo@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted);
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()..regex = '.*'));
      expect(transformedNotification.id, '124');
      expect(transformedNotification.key, '@bob:key-1.foo@alice');
    });

    test('A test to verify the reserved key is not decrypted', () async {
      var isEncrypted = true;
      var atNotification = AtNotification(
          '124',
          '@bob:shared_key@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: 'encryptedValue');
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.id, '124');
      expect(transformedNotification.value, 'encryptedValue');
    });
  });

  group('A group of tests to validate notification exception chaining', () {
    setUp(() {
      // The notifications here route to the 'legacy' provider (the default).
      // Register an ErrorProvider under that id so encryption throws 'error',
      // exercising the exception-chaining paths.
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..crypto = CryptoConfig(
              defaultProviderId: 'legacy',
              providers: [ErrorProvider('legacy')],
            ));
    });
    test('A test to validate exception chaining on encryption failure',
        () async {
      var currentAtSign = '@alice';
      AtKey atKey =
          (AtKey.shared('phone', namespace: 'wavi', sharedBy: currentAtSign)
                ..sharedWith('@bob')
                ..cache(1000, true))
              .build();
      var value = '91807876564';

      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: mockSecondaryAddressFinder)
          as NotificationServiceImpl;

      var notificationResult = await notificationServiceImpl.notify(
          NotificationParams.forUpdate(atKey, value: value),
          checkForFinalDeliveryStatus: false);
      expect(notificationResult.atClientException, isNotNull);
    });

    test('A test to verify exception from cloud secondary is chained',
        () async {
      var currentAtSign = '@alice';
      AtKey atKey =
          (AtKey.shared('phone', namespace: 'wavi', sharedBy: currentAtSign)
                ..sharedWith('@bob')
                ..cache(1000, true))
              .build();
      var value = '91807876564';
      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference(),
          lookUps: secureSocketLookUps());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyVerbBuilder());

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var notificationResult = await notificationServiceImpl.notify(
          NotificationParams.forUpdate(atKey, value: value),
          checkForFinalDeliveryStatus: false);
      expect(notificationResult.atClientException, isA<AtClientException>());
      //throwing from ErrorProvider, used for testing only
      expect(notificationResult.atClientException?.getTraceMessage(),
          'Failed to notifyData caused by\nerror');
      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.undelivered);
    });

    test('A test to verify buffer over flow exception for messageType key',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()..maxDataSize = 1);

      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@bob')
            ..sharedWith('@alice'))
          .build();
      var value = '+91-9856745453';

      NotificationParams notificationParams =
          NotificationParams.forUpdate(atKey, value: value);
      NotifyVerbBuilder notifyVerbBuilder = NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..atKey = atKey
        ..messageType = MessageTypeEnum.key
        ..value = 'demo-value';

      expect(
          () => notificationServiceImpl.notificationValueValidation(
              notificationParams, notifyVerbBuilder),
          throwsA(predicate((dynamic e) => e is BufferOverFlowException)));
    });

    test(
        'A notification value of exactly maxDataSize is sent, and one longer '
        'is refused with BufferOverFlowException', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()..maxDataSize = 10);
      var atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@bob')
            ..sharedWith('@alice'))
          .build();
      NotifyVerbBuilder builderCarrying(String value) => NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..atKey = atKey
        ..value = value;

      notificationServiceImpl.notificationValueValidation(
          NotificationParams.forUpdate(atKey, value: '0123456789'),
          builderCarrying('0123456789'));
      expect(
          () => notificationServiceImpl.notificationValueValidation(
              NotificationParams.forUpdate(atKey, value: '0123456789a'),
              builderCarrying('0123456789a')),
          throwsA(isA<BufferOverFlowException>()));
    });

    test(
        'A test to verify unauthorized exception is thrown when sharedBy atSign is different from currentAtSign',
        () async {
      when(() => mockSecondaryAddressFinder.findSecondary('@colin'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.notifyStatus(any()))
          .thenAnswer((_) => Future.value('data:delivered'));

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@bob')
                ..sharedWith('@colin'))
              .build());

      var notificationResult =
          await notificationServiceImpl.notify(notificationParams);
      expect(notificationResult.atClientException, isA<AtClientException>());
      expect(notificationResult.atClientException?.message,
          '@bob is not authorized to send notification as @alice');
    });
  });

  group('Verify basic monitor interactions', () {
    setUp(() {
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = false
            ..monitorAutoStart = false);

      registerFallbackValue(AtKey());
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
    });

    test('Verify lastReceipt', () async {
      DateTime testStartTime = DateTime.now().toUtc();

      var ns = await NotificationServiceImpl.create(mockAtClientImpl,
          secondaryAddressFinder: defaultAtDirectory,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      var atNotification = AtNotification(
          '124',
          '@bob:some.thing.lolz.app@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          false,
          value: 'Got it');

      // Delivered as the muxable delivers it: already framed. The byte-level
      // framing that used to be tested here - Monitor.onSocketDataReceipt -
      // now lives in at_lookup's listener and is covered by its own
      // socket_delivery_test.dart.
      await ns.monitor.handleNotification(
          'notification: ${jsonEncode(atNotification.toJson())}');

      expect(ns.lastReceipt, isNotNull);
      expect(ns.lastReceipt!.microsecondsSinceEpoch,
          lessThan(DateTime.now().microsecondsSinceEpoch));
      expect(ns.lastReceipt!.microsecondsSinceEpoch,
          greaterThan(testStartTime.microsecondsSinceEpoch));
    });

    test('Verify monitor delivers notification', () async {
      var ns = await NotificationServiceImpl.create(mockAtClientImpl,
          secondaryAddressFinder: defaultAtDirectory,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      var atNotification = AtNotification(
          '124',
          '@bob:some.thing.lolz.app@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          false,
          value: 'Got it');

      List<AtNotification> received = [];
      var notificationStream =
          ns.subscribe(regex: '.lolz.app', shouldDecrypt: false);
      notificationStream.listen((AtNotification n) async {
        received.add(n);
      });

      // Delivered as the muxable delivers it: already framed. The byte-level
      // framing that used to be tested here - Monitor.onSocketDataReceipt -
      // now lives in at_lookup's listener and is covered by its own
      // socket_delivery_test.dart.
      await ns.monitor.handleNotification(
          'notification: ${jsonEncode(atNotification.toJson())}');

      await Future.delayed(Duration(milliseconds: 1));
      expect(received, isNotEmpty);
      expect(received[0].value, 'Got it');
    });

    test('delayedStartListeningTimer is cancelled when stopListening called',
        () async {
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..monitorAutoStart = true);

      var notificationService = await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: defaultAtDirectory,
      ) as NotificationServiceImpl;

      notificationService.subscribe(regex: 'statsNotification');
      expect(notificationService.delayedStartListeningTimer, isNotNull);

      notificationService.stopListening();
      // Timer cancelled and monitor not started
      expect(notificationService.delayedStartListeningTimer, isNull);
      expect(fakeMonitor.currentState, NotificationListenerState.notConnected);
    });

    test('delayedStartListeningTimer is cancelled with custom Duration',
        () async {
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi_1234'
            ..monitorAutoStart = true);

      var notificationService = await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: defaultAtDirectory,
      ) as NotificationServiceImpl;

      // inject a custom duration of 10 milliseconds
      notificationService.delayedStartListeningTimerDuration =
          Duration(milliseconds: 10);

      // subscribe to statsNotification and ensure that the timer has started
      notificationService.subscribe(regex: 'statsNotification');
      expect(notificationService.delayedStartListeningTimer, isNotNull);
      expect(notificationService.monitor.targetState,
          NotificationListenerState.notConnected);

      // stop NotificationService and ensure the timer is removed
      notificationService.stopAllSubscriptions();
      expect(notificationService.delayedStartListeningTimer, isNull);
      expect(notificationService.monitor.targetState,
          NotificationListenerState.notConnected);

      // await for more time than we set as the delayed start duration
      // validate that the monitor in fact did not start
      await Future.delayed(Duration(milliseconds: 20));
      expect(notificationService.monitor.currentState,
          NotificationListenerState.notConnected);
      expect(notificationService.monitor.targetState,
          NotificationListenerState.notConnected);
    });
  });

  group('A group of tests to validate notification subscribe method', () {
    test('NotificationService subscribe returns a new stream for a new regex',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var notificationStream = notificationServiceImpl.subscribe(
          regex: '.wavi', shouldDecrypt: false);
      notificationStream.listen((event) async {
        print(event);
      });

      var notificationStream1 = notificationServiceImpl.subscribe(
          regex: '.buzz', shouldDecrypt: false);
      notificationStream1.listen((event) {
        print(event);
      });
      expect(notificationServiceImpl.getStreamListenersCount(), 2);
      notificationServiceImpl.stopAllSubscriptions();
    });

    test(
        'NotificationService subscribe gives each listener a subscription of '
        'its own, for the same regex and shouldDecrypt', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var notificationStream = notificationServiceImpl.subscribe(
          regex: '.wavi', shouldDecrypt: true);
      notificationStream.listen((event) async {
        print(event);
      });

      var notificationStream1 = notificationServiceImpl.subscribe(
          regex: '.wavi', shouldDecrypt: true);
      notificationStream1.listen((event) {
        print(event);
      });
      expect(notificationServiceImpl.getStreamListenersCount(), 2,
          reason: 'each listener is a subscription of its own, released when '
              'it cancels');
      notificationServiceImpl.stopAllSubscriptions();
    });

    test(
        'NotificationService subscribe returns a new stream for the same regex '
        'with the other shouldDecrypt', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      notificationServiceImpl
          .subscribe(regex: '.wavi', shouldDecrypt: false)
          .listen((_) {});
      notificationServiceImpl
          .subscribe(regex: '.wavi', shouldDecrypt: true)
          .listen((_) {});
      expect(notificationServiceImpl.getStreamListenersCount(), 2,
          reason: 'a subscription asking for decrypted values must not share '
              'one asking for values as they arrived');
      notificationServiceImpl.stopAllSubscriptions();
    });
  });

  group('A group of tests to validate notification fetch', () {
    test('A test to verify notification fetch for non-existing notification',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference(),
          lookUps: secureSocketLookUps());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyFetchVerbBuilder());
      when(() => mockAtLookupImpl.executeVerb(any())).thenAnswer((_) =>
          Future.value('data:${jsonEncode({
                'id': '123',
                'notificationStatus': 'NotificationStatus.expired'
              })}'));

      var response = await notificationServiceImpl.fetch('123');
      expect(response.id, '123');
      expect(response.status, 'NotificationStatus.expired');
    });

    test('A test to verify notification fetch for an existing notification',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference(),
          lookUps: secureSocketLookUps());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyFetchVerbBuilder());
      when(() => mockAtLookupImpl.executeVerb(any())).thenAnswer((_) =>
          Future.value('data:{"id":"fb948e15-128f-408d-b73f-0ab1372da4a3",'
              '"fromAtSign":"@alice",'
              '"notificationDateTime":"2022-10-03 18:34:58.601",'
              '"toAtSign":"@bob","notification":"@bob:phone@alice",'
              '"type":"NotificationType.sent",'
              '"opType":"OperationType.update",'
              '"messageType":"MessageType.key",'
              '"priority":"NotificationPriority.low",'
              '"notificationStatus":"NotificationStatus.delivered",'
              '"expiresAt":"2022-10-03 13:20:58.565Z",'
              '"atValue":"+445 112 3434"}'));

      var atNotification = await notificationServiceImpl.fetch('123');
      expect(atNotification.id, 'fb948e15-128f-408d-b73f-0ab1372da4a3');
      expect(atNotification.key, '@bob:phone@alice');
      expect(atNotification.from, '@alice');
      expect(atNotification.to, '@bob');
      expect(atNotification.epochMillis,
          DateTime.parse('2022-10-03 18:34:58.601').millisecondsSinceEpoch);
      expect(atNotification.value, '+445 112 3434');
      expect(atNotification.operation, 'OperationType.update');
      expect(atNotification.status, 'NotificationStatus.delivered');
    });

    test('A test to verify remote secondary timeouts to respond', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference(),
          lookUps: secureSocketLookUps());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyFetchVerbBuilder());
      when(() => mockAtLookupImpl.executeVerb(any())).thenAnswer((_) =>
          throw AtLookUpException(
              'AT0023', 'Waited for 10000 millis. No response after 100000'));
      // The errorCode AT0023 results to AtTimeoutException. Since AtTimeoutException is
      // not a sub-class of AtClientException, the exception is converted to AtClientException and returned.`
      expect(() async => await notificationServiceImpl.fetch('123'),
          throwsA(predicate((dynamic e) => e is AtClientException)));
    });

    test('A test to verify remote secondary is not reachable', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference(),
          lookUps: secureSocketLookUps());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyFetchVerbBuilder());
      when(() => mockAtLookupImpl.executeVerb(any())).thenAnswer((_) =>
          throw AtLookUpException('AT0021', 'Secondary Connect Exception'));
      // The errorCode AT0021 results to SecondaryConnectException. Since SecondaryConnectException is
      // not a sub-class of AtClientException, the exception is converted to AtClientException and returned.`
      expect(() async => await notificationServiceImpl.fetch('123'),
          throwsA(predicate((dynamic e) => e is AtClientException)));
    });
  });

  group('Tests of getLastNotificationTime()', () {
    setUpAll(() {
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);
    });

    test(
        'getLastNotificationTime() answers the service\'s creation time, and '
        'ignores the stored watermark, when fetchOfflineNotifications is false',
        () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = false);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      // A watermark from long before this service existed, which a client
      // fetching offline notifications would resume from.
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async =>
          AtValue()..value = jsonEncode({'epochMillis': 1234567890123}));

      final beforeCreate = DateTime.now().millisecondsSinceEpoch;
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      final afterCreate = DateTime.now().millisecondsSinceEpoch;
      notificationServiceImpl.stopAllSubscriptions();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // NOTE: the mock client is shared across this file, so calls other tests
      // made are still recorded on it.
      clearInteractions(mockAtClientImpl);
      expect(
          await notificationServiceImpl.getLastNotificationTime(),
          allOf(greaterThanOrEqualTo(beforeCreate),
              lessThanOrEqualTo(afterCreate)),
          reason: 'nothing received before the service existed, and '
              'everything since — not null, which is delivered nothing sent '
              'before `monitor:` went out');
      verifyNever(() => mockAtClientImpl.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions')));
      verifyNever(() => mockAtClientImpl.get(any()));
    });

    group('with fetchOfflineNotifications false, after a notification arrives',
        () {
      late NotificationServiceImpl service;
      late int createdAtMillis;

      Future<void> receive(String id, int epochMillis,
              {String from = '@alice', String? key}) =>
          service.handleNotificationReceipt('notification: '
              '{"id":"$id","from":"$from","to":"@alice",'
              '"key":"${key ?? '$id.wavi@alice'}","value":null,"operation":"update",'
              '"epochMillis":$epochMillis,'
              '"messageType":"MessageType.key","isEncrypted":false}');

      setUp(() async {
        registerFallbackValue(FakeAtKey());
        when(() => mockAtClientImpl.getPreferences())
            .thenAnswer((_) => AtClientPreference()
              ..namespace = 'wavi'
              ..fetchOfflineNotifications = false);
        when(() =>
                mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
            .thenAnswer((_) async => true);
        when(() => mockAtClientImpl.get(any())).thenAnswer((_) async =>
            AtValue()..value = jsonEncode({'epochMillis': 1234567890123}));
        when(() => mockAtClientImpl.put(any(), any(),
                putRequestOptions: any(named: 'putRequestOptions')))
            .thenAnswer((_) async => true);

        service = await NotificationServiceImpl.create(mockAtClientImpl,
                monitor: fakeMonitor,
                secondaryAddressFinder: defaultAtDirectory)
            as NotificationServiceImpl;
        createdAtMillis = (await service.getLastNotificationTime())!;
      });

      tearDown(() => service.stopAllSubscriptions());

      test(
          'getLastNotificationTime() answers that notification\'s time, '
          'without reading the store', () async {
        await receive('1', createdAtMillis + 5000);
        clearInteractions(mockAtClientImpl);

        expect(await service.getLastNotificationTime(), createdAtMillis + 5000,
            reason: 'a reconnect resumes after what this service has already '
                'delivered, so the atServer replays none of it');
        verifyNever(() => mockAtClientImpl.get(any()));
      });

      test('an earlier notification does not move it back', () async {
        await receive('1', createdAtMillis + 5000);
        await receive('2', createdAtMillis + 2000);

        expect(await service.getLastNotificationTime(), createdAtMillis + 5000);
      });

      test('a stats notification does not move it', () async {
        await receive('-1', createdAtMillis + 5000);

        expect(await service.getLastNotificationTime(), createdAtMillis);
      });

      group('delivery by notification id', () {
        late List<String> delivered;

        setUp(() {
          delivered = [];
          service.subscribe(regex: '.*').listen((n) => delivered.add(n.id));
        });

        test('the same id received twice reaches a subscriber once', () async {
          await receive('1', createdAtMillis + 1000);
          await receive('1', createdAtMillis + 1000);
          await pumpEventQueue();

          expect(delivered, ['1']);
        });

        test('stats notifications all carry id -1 and are never deduped',
            () async {
          await receive('-1', createdAtMillis + 1000);
          await receive('-1', createdAtMillis + 2000);
          await pumpEventQueue();

          expect(delivered, ['-1', '-1']);
        });

        test('the seen-set is bounded: the oldest id is forgotten', () async {
          for (var i = 0; i <= NotificationServiceImpl.seenIdCapacity; i++) {
            await receive('id$i', createdAtMillis + 1000);
          }
          await receive('id0', createdAtMillis + 1000);
          await receive('id2', createdAtMillis + 1000);
          await pumpEventQueue();

          expect(delivered.where((id) => id == 'id0'), hasLength(2),
              reason: 'id0 was evicted, so its replay is delivered again');
          expect(delivered.where((id) => id == 'id2'), hasLength(1),
              reason: 'id2 is still remembered (re-adding id0 evicted id1)');
        });

        test(
            'notifications with the same id from different atSigns are both delivered',
            () async {
          await receive('shared-id', createdAtMillis + 1000, from: '@alice');
          await receive('shared-id', createdAtMillis + 1000, from: '@bob');
          await pumpEventQueue();

          expect(delivered, ['shared-id', 'shared-id']);
        });

        test(
            'notifications with colons in ID are keyed by (from.toAtsign(), id) record and do not collide across senders',
            () async {
          // Sender @bob with id 'X', and sender @alice with id '@bob:X'
          await receive('X', createdAtMillis + 1000, from: '@bob');
          await receive('@bob:X', createdAtMillis + 1000, from: '@alice');
          await pumpEventQueue();

          expect(delivered, ['X', '@bob:X']);

          // A replay of @bob's notification is not re-delivered
          await receive('X', createdAtMillis + 1000, from: '@bob');
          // A replay of @alice's notification is not re-delivered
          await receive('@bob:X', createdAtMillis + 1000, from: '@alice');
          await pumpEventQueue();

          expect(delivered, ['X', '@bob:X']);
        });

        test(
            'a true duplicate replay is ignored quietly and not reported on droppedEvents',
            () async {
          final dropped = <DroppedNotification>[];
          service.droppedEvents.listen(dropped.add);

          await receive('dup-1', createdAtMillis + 1000);
          await receive('dup-1', createdAtMillis + 1000);
          await pumpEventQueue();

          expect(delivered, ['dup-1']);
          expect(dropped, isEmpty);
        });

        test('a true duplicate replay logs quietly at finer and not at warning',
            () async {
          final records = <dynamic>[];
          final sub = service.logger.logger.onRecord.listen(records.add);
          addTearDown(sub.cancel);
          service.logger.level = 'finer';

          await receive('dup-log', createdAtMillis + 1000);
          await receive('dup-log', createdAtMillis + 1000);
          await pumpEventQueue();

          expect(delivered, ['dup-log']);
          final finers = records.where((r) =>
              '${r.level.name}'.toUpperCase() == 'FINER' &&
              '${r.message}'.contains('was already delivered'));
          final warnings = records
              .where((r) => '${r.level.name}'.toUpperCase() == 'WARNING');

          expect(finers, isNotEmpty, reason: 'must log quiet replay at finer');
          expect(warnings, isEmpty,
              reason: 'must not log quiet replay at warning');
        });

        test(
            'duplicate id with conflicting key is dropped and reported on droppedEvents',
            () async {
          final dropped = <DroppedNotification>[];
          service.droppedEvents.listen(dropped.add);

          await receive('conflict-1', createdAtMillis + 1000,
              key: 'first.key@alice');
          await receive('conflict-1', createdAtMillis + 1000,
              key: 'second.key@alice');
          await pumpEventQueue();

          expect(delivered, ['conflict-1']);
          expect(dropped, hasLength(1));
          expect(dropped.first.key, 'second.key@alice');
          expect(
              dropped.first.reason, contains('conflicting key or timestamp'));
        });

        test(
            'duplicate id with conflicting timestamp is dropped and reported on droppedEvents',
            () async {
          final dropped = <DroppedNotification>[];
          service.droppedEvents.listen(dropped.add);

          await receive('conflict-2', createdAtMillis + 1000);
          await receive('conflict-2', createdAtMillis + 2000);
          await pumpEventQueue();

          expect(delivered, ['conflict-2']);
          expect(dropped, hasLength(1));
          expect(
              dropped.first.reason, contains('conflicting key or timestamp'));
        });

        test('a conflicting duplicate logs at warning and not at finer',
            () async {
          final records = <dynamic>[];
          final sub = service.logger.logger.onRecord.listen(records.add);
          addTearDown(sub.cancel);
          service.logger.level = 'finer';

          await receive('conflict-log', createdAtMillis + 1000,
              key: 'first.key@alice');
          await receive('conflict-log', createdAtMillis + 1000,
              key: 'second.key@alice');
          await pumpEventQueue();

          expect(delivered, ['conflict-log']);
          final warnings = records.where((r) =>
              '${r.level.name}'.toUpperCase() == 'WARNING' &&
              '${r.message}'.contains('conflicting key or timestamp'));
          final finers = records.where((r) =>
              '${r.level.name}'.toUpperCase() == 'FINER' &&
              '${r.message}'.contains('was already delivered'));

          expect(warnings, isNotEmpty, reason: 'must log conflict at warning');
          expect(finers, isEmpty, reason: 'must not log conflict at finer');
        });
      });
    });

    test(
        'getLastNotificationTime() answers, and seeds, the service\'s creation '
        'time when there is no stored value', () async {
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);

      final beforeCreate = DateTime.now().millisecondsSinceEpoch;
      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      final afterCreate = DateTime.now().millisecondsSinceEpoch;
      // Long enough that "when it was created" and "when it was asked" are
      // different numbers.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notificationServiceImpl.stopAllSubscriptions();

      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      // #1942 — the legacy-key migration may call delete; stub it so
      // the mock doesn't throw when no legacy keys are present.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      // NOTE: the mock client is shared across this file, so puts other tests
      // made are still recorded on it.
      clearInteractions(mockAtClientImpl);
      final beforeAsk = DateTime.now().millisecondsSinceEpoch;
      final answered = await notificationServiceImpl.getLastNotificationTime();

      expect(
          answered,
          allOf(greaterThanOrEqualTo(beforeCreate),
              lessThanOrEqualTo(afterCreate)),
          reason: 'the creation time: a monitor asking for nothing sent before '
              '`monitor:` misses replies to what the app sent before that');
      expect(answered, lessThan(beforeAsk),
          reason: 'not the time of the call, which is when the monitor '
              'connects');
      final seeded = verify(() => mockAtClientImpl.put(any(), captureAny(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .captured
          .single as String;
      expect((jsonDecode(seeded) as Map)['epochMillis'], answered,
          reason: 'seeded with the same time, so a reconnect before any '
              'notification arrives resumes from the same point');
    });

    test(
        'a resume from the stored watermark does not deliver the '
        'watermark\'s own notification again', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => AtValue()
        ..value = jsonEncode({
          'id': 'stored-1',
          'from': '@alice',
          'epochMillis': 1234567890123
        }));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      final service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(service.stopAllSubscriptions);
      final delivered = <String>[];
      service.subscribe(regex: '.*').listen((n) => delivered.add(n.id));

      expect(await service.getLastNotificationTime(), 1234567890123);
      for (final id in ['stored-1', 'next-2']) {
        await service.handleNotificationReceipt('notification: '
            '{"id":"$id","from":"@alice","to":"@alice",'
            '"key":"$id.wavi@alice","value":null,"operation":"update",'
            '"epochMillis":1234567890123,'
            '"messageType":"MessageType.key","isEncrypted":false}');
      }
      await pumpEventQueue();

      expect(delivered, ['next-2'],
          reason: 'an inclusive since filter re-delivers the watermark\'s '
              'notification, which the previous run already delivered');
    });

    test(
        'a resume from a 4.0.0 watermark (from and id present, idsAtEpochMillis absent) '
        'does not re-deliver the watermark notification', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => AtValue()
        ..value = jsonEncode({
          'id': 'v4-stored',
          'from': '@alice',
          'to': '@bob',
          'key': 'v4-stored.wavi@alice',
          'epochMillis': 1234567890123
        }));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      final service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(service.stopAllSubscriptions);
      final delivered = <String>[];
      service.subscribe(regex: '.*').listen((n) => delivered.add(n.id));

      expect(await service.getLastNotificationTime(), 1234567890123);
      for (final id in ['v4-stored', 'next-v4']) {
        await service.handleNotificationReceipt('notification: '
            '{"id":"$id","from":"@alice","to":"@bob",'
            '"key":"$id.wavi@alice","value":null,"operation":"update",'
            '"epochMillis":1234567890123,'
            '"messageType":"MessageType.key","isEncrypted":false}');
      }
      await pumpEventQueue();

      expect(delivered, ['next-v4'],
          reason:
              '4.0.0 watermark notification is recognized and not re-delivered');
    });

    test(
        'a stored watermark whose id is not a string does not throw out of '
        'getLastNotificationTime', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => AtValue()
        ..value = jsonEncode({
          'id': 12345, // not a String
          'from': '@alice',
          'epochMillis': 1234567890123
        }));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      final service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(service.stopAllSubscriptions);

      expect(await service.getLastNotificationTime(), 1234567890123);
    });

    test(
        'a stored pair whose sender is not an atSign does not throw out of '
        'getLastNotificationTime and skips the entry', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => AtValue()
        ..value = jsonEncode({
          'id': 'valid-1',
          'from': '@alice',
          'epochMillis': 1234567890123,
          'idsAtEpochMillis': [
            ['', 'invalid-sender'],
            ['@alice', 'valid-1'],
          ]
        }));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      final service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(service.stopAllSubscriptions);

      expect(await service.getLastNotificationTime(), 1234567890123);

      final delivered = <String>[];
      service
          .subscribe(regex: '.*')
          .listen((n) => delivered.add('${n.from}:${n.id}'));

      // valid-1 from @alice is in seen, so replay is dropped
      await service.handleNotificationReceipt('notification: '
          '{"id":"valid-1","from":"@alice","to":"@alice",'
          '"key":"valid-1.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":1234567890123,'
          '"messageType":"MessageType.key","isEncrypted":false}');

      // invalid-sender was skipped, but when replayed as valid notification it is delivered
      await service.handleNotificationReceipt('notification: '
          '{"id":"invalid-sender","from":"@alice","to":"@alice",'
          '"key":"invalid-sender.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":1234567890123,'
          '"messageType":"MessageType.key","isEncrypted":false}');

      await pumpEventQueue();
      expect(delivered, ['@alice:invalid-sender']);
    });

    test(
        'a resume from stored pairs with two different senders preserves each sender',
        () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => AtValue()
        ..value = jsonEncode({
          'id': 'watermark-id',
          'from': '@alice',
          'epochMillis': 1234567890123,
          'idsAtEpochMillis': [
            ['@alice', 'id-1'],
            ['@bob', 'id-2'],
          ]
        }));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      final service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(service.stopAllSubscriptions);

      expect(await service.getLastNotificationTime(), 1234567890123);

      final delivered = <String>[];
      service
          .subscribe(regex: '.*')
          .listen((n) => delivered.add('${n.from}:${n.id}'));

      // Replay of (@bob, id-2) must be dropped
      await service.handleNotificationReceipt('notification: '
          '{"id":"id-2","from":"@bob","to":"@alice",'
          '"key":"id-2.wavi@bob","value":null,"operation":"update",'
          '"epochMillis":1234567890123,'
          '"messageType":"MessageType.key","isEncrypted":false}');

      // Notification with same id ('id-2') but from @alice must NOT be dropped,
      // proving that (@bob, id-2) was not recorded as (@alice, id-2)
      await service.handleNotificationReceipt('notification: '
          '{"id":"id-2","from":"@alice","to":"@alice",'
          '"key":"id-2.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":1234567890123,'
          '"messageType":"MessageType.key","isEncrypted":false}');

      await pumpEventQueue();
      expect(delivered, ['@alice:id-2'],
          reason:
              'only @alice:id-2 is delivered; @bob:id-2 was dropped from stored pair');
    });

    test(
        'a resume from the stored watermark delivers none of the notifications '
        'the previous run delivered in the watermark\'s millisecond', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);
      String? stored;
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((i) async {
        stored = i.positionalArguments[1] as String;
        return true;
      });
      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => AtValue()..value = stored);
      String notification(String id, int millis) => 'notification: '
          '{"id":"$id","from":"@alice","to":"@alice",'
          '"key":"$id.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":$millis,'
          '"messageType":"MessageType.key","isEncrypted":false}';

      final first = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      first.subscribe(regex: '.*').listen((_) {});
      for (final n in [
        notification('old', 10),
        notification('A', 20),
        notification('B', 20)
      ]) {
        await first.handleNotificationReceipt(n);
      }
      await first.stop();

      final second = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(second.stopAllSubscriptions);
      final delivered = <String>[];
      second.subscribe(regex: '.*').listen((n) => delivered.add(n.id));

      expect(await second.getLastNotificationTime(), 20);
      for (final id in ['A', 'B', 'C']) {
        await second.handleNotificationReceipt(notification(id, 20));
      }
      await pumpEventQueue();

      expect(delivered, ['C'],
          reason: 'an inclusive since filter re-delivers every notification '
              'stamped in the watermark\'s millisecond, not just its own');
      await second.stop();

      final third = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(third.stopAllSubscriptions);
      final thirdDelivered = <String>[];
      third.subscribe(regex: '.*').listen((n) => thirdDelivered.add(n.id));

      expect(await third.getLastNotificationTime(), 20);
      for (final id in ['A', 'B', 'C', 'D']) {
        await third.handleNotificationReceipt(notification(id, 20));
      }
      await pumpEventQueue();

      expect(thirdDelivered, ['D'],
          reason: 'the second run stored the ids it resumed with alongside '
              'the one it delivered');
    });

    test(
        'a reconnect read during an in-flight watermark write keeps that '
        'write\'s id in the stored watermark', () async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);
      String? stored;
      Completer<void>? held;
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((i) async {
        final value = i.positionalArguments[1] as String;
        if (held != null) await held.future;
        stored = value;
        return true;
      });
      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => AtValue()..value = stored);
      String notification(String id) => 'notification: '
          '{"id":"$id","from":"@alice","to":"@alice",'
          '"key":"$id.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":20,'
          '"messageType":"MessageType.key","isEncrypted":false}';

      final first = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      first.subscribe(regex: '.*').listen((_) {});
      await first.handleNotificationReceipt(notification('A'));
      held = Completer<void>();
      final b = first.handleNotificationReceipt(notification('B'));
      await pumpEventQueue();
      await first.getLastNotificationTime();
      final release = held;
      held = null;
      release.complete();
      await b;
      await first.handleNotificationReceipt(notification('C'));
      await first.stop();

      expect((jsonDecode(stored!) as Map)['idsAtEpochMillis'], [
        ['@alice', 'A'],
        ['@alice', 'B'],
        ['@alice', 'C']
      ]);

      final second = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(second.stopAllSubscriptions);
      final delivered = <String>[];
      second.subscribe(regex: '.*').listen((n) => delivered.add(n.id));
      await second.getLastNotificationTime();
      for (final id in ['A', 'B', 'C']) {
        await second.handleNotificationReceipt(notification(id));
      }
      await pumpEventQueue();

      expect(delivered, isEmpty);
    });

    /// The test case verifies the following:
    /// When a new key (local:lastReceivedNotification) exists and return null,
    /// fetch the data from the old key return epochMillis.
    test(
        'getLastNotificationTime() returns the stored value from old key if checkOfflineNotifications is true and there is a stored value',
        () async {
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);

      int epochMillis = DateTime.now().millisecondsSinceEpoch;
      var atNotification = AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.get(any(that: StatsAtKeyMatcher())))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      // #1942 migration cleanup may call delete on legacy keys.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);

      notificationServiceImpl.stopAllSubscriptions();

      mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = true;

      expect(
          await notificationServiceImpl.getLastNotificationTime(), epochMillis);
    });

    /// The test case verifies that when a new exists, fetch data from the new key and return epochMillis
    test(
        'getLastNotificationTime() returns the stored value from new key - local:lastReceivedNotification',
        () async {
      registerFallbackValue(FakeAtKey());
      int epochMillis = DateTime.now().millisecondsSinceEpoch;
      var atNotification = AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      // #1942 migration cleanup may call delete on legacy keys.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);

      notificationServiceImpl.stopAllSubscriptions();

      mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = true;

      expect(
          await notificationServiceImpl.getLastNotificationTime(), epochMillis);
    });

    test(
        'test the verifies old key value is fetched when new key does not exist',
        () async {
      //mimic the old latestNotificationIdKey
      String lastNotificationKey = '_latestNotificationIdv2.wavi@alice';
      AtKey lastNotificationAtKey = AtKey.fromString(lastNotificationKey);

      registerFallbackValue(lastNotificationAtKey);
      int epochMillis = DateTime.now().millisecondsSinceEpoch;
      var atNotification = AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      // Default: any key NOT explicitly stubbed below is absent.
      // The #1942 migration also probes the intermediate
      // `lastreceivednotification.<ns>@<atSign>` form; this fallback
      // keeps the mock from returning null on that probe.
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => false);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(
              notificationServiceImpl.lastReceivedNotificationAtKey.toString()))
          .thenAnswer((_) async => false);

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .exists(lastNotificationKey)).thenAnswer((_) async => true);

      when(() => mockAtClientImpl.get(lastNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      // #1942 migration cleanup may call delete on legacy keys.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      expect(
          await notificationServiceImpl.getLastNotificationTime(), epochMillis);
    });
  });

  group('notificationReplay chooses where the replay starts', () {
    late NotificationServiceImpl service;
    late DateTime clock;
    late DateTime createdBefore;
    late DateTime createdAfter;

    // Two hours past now, so that a window of one hour starts after the
    // service's creation time and before the clock.
    setUp(() {
      clock = DateTime.now().add(const Duration(hours: 2));
    });

    tearDown(() => service.stopAllSubscriptions());

    // Stores [stored] as the watermark, or nothing when it is null.
    void storeWatermark(DateTime? stored) {
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => stored != null);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async => stored ==
              null
          ? AtValue()
          : (AtValue()
            ..value =
                jsonEncode({'epochMillis': stored.millisecondsSinceEpoch})));
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);
    }

    Future<void> start(NotificationReplay policy, {DateTime? stored}) async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..notificationReplay = policy);
      storeWatermark(stored);
      createdBefore = DateTime.now();
      service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      createdAfter = DateTime.now();
      service.now = () => clock;
      // NOTE: the mock client is shared across this file, so calls other tests
      // made are still recorded on it.
      clearInteractions(mockAtClientImpl);
    }

    Future<void> receive(String id, int epochMillis) =>
        service.handleNotificationReceipt('notification: '
            '{"id":"$id","from":"@alice","to":"@alice",'
            '"key":"$id.wavi@alice","value":null,"operation":"update",'
            '"epochMillis":$epochMillis,'
            '"messageType":"MessageType.key","isEncrypted":false}');

    test(
        'connect answers the creation time and neither reads nor seeds the '
        'store', () async {
      await start(const NotificationReplay.connect(),
          stored: clock.subtract(const Duration(hours: 5)));

      expect(
          await service.getLastNotificationTime(),
          allOf(greaterThanOrEqualTo(createdBefore.millisecondsSinceEpoch),
              lessThanOrEqualTo(createdAfter.millisecondsSinceEpoch)));
      verifyNever(() => mockAtClientImpl.get(any()));
      verifyNever(() => mockAtClientImpl.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions')));
    });

    test('full answers 0 and does not read the store', () async {
      await start(const NotificationReplay.full(),
          stored: clock.subtract(const Duration(hours: 5)));

      expect(await service.getLastNotificationTime(), 0);
      verifyNever(() => mockAtClientImpl.get(any()));
    });

    test(
        'window answers now minus its duration when the stored watermark is '
        'older', () async {
      await start(const NotificationReplay.window(),
          stored: clock.subtract(const Duration(hours: 2)));

      expect(await service.getLastNotificationTime(),
          clock.subtract(const Duration(hours: 1)).millisecondsSinceEpoch);
    });

    test('window answers the stored watermark when it is newer', () async {
      final stored = clock.subtract(const Duration(minutes: 10));
      await start(const NotificationReplay.window(), stored: stored);

      expect(await service.getLastNotificationTime(),
          stored.millisecondsSinceEpoch);
    });

    test(
        'window with nothing stored seeds the store with the creation time, '
        'and starts no earlier than it', () async {
      await start(const NotificationReplay.window());
      final now = createdAfter.add(const Duration(minutes: 1));
      service.now = () => now;

      expect(
          await service.getLastNotificationTime(),
          allOf(greaterThanOrEqualTo(createdBefore.millisecondsSinceEpoch),
              lessThanOrEqualTo(createdAfter.millisecondsSinceEpoch)),
          reason: 'now - 1h is before creation, so the start is creation, not '
              'a moment whose notifications this service never saw');
      final seeded = verify(() => mockAtClientImpl.put(any(), captureAny(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .captured
          .single as String;
      expect(
          (jsonDecode(seeded) as Map)['epochMillis'],
          allOf(greaterThanOrEqualTo(createdBefore.millisecondsSinceEpoch),
              lessThanOrEqualTo(createdAfter.millisecondsSinceEpoch)));
    });

    for (final policy in [
      const NotificationReplay.connect(),
      const NotificationReplay.window(),
      const NotificationReplay.full(),
    ]) {
      test('$policy answers the epochMillis of a receipt after it', () async {
        await start(policy);
        final received = clock.subtract(const Duration(minutes: 30));

        await receive('1', received.millisecondsSinceEpoch);

        expect(await service.getLastNotificationTime(),
            received.millisecondsSinceEpoch);
      });
    }

    test(
        'window answers the same start while nothing is received, as the '
        'clock advances', () async {
      await start(const NotificationReplay.window());
      final first = await service.getLastNotificationTime();

      clock = clock.add(const Duration(minutes: 10));

      expect(await service.getLastNotificationTime(), first,
          reason: 'resolved once per service, so a reconnect during an outage '
              'does not move the start forward and skip the gap');
    });

    test('overlapping calls resolve the window once and seed the store once',
        () async {
      await start(const NotificationReplay.window());
      // Reads that yield, so the two calls overlap in the store.
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        return false;
      });
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        return AtValue();
      });

      final first = service.getLastNotificationTime();
      service.now = () => clock.add(const Duration(minutes: 10));
      final second = service.getLastNotificationTime();
      final results = await Future.wait([first, second]);

      expect(results[0], results[1],
          reason: 'both overlapping calls must answer the same start');
      verify(() => mockAtClientImpl.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).called(1);
    });

    test(
        'window starts no earlier than the creation time, so what arrived '
        'between creation and the first connect is delivered', () async {
      // The clock is two hours after the service was created, so a three-hour
      // window reaches back before creation.
      await start(const NotificationReplay.window(Duration(hours: 3)));

      expect(
          await service.getLastNotificationTime(),
          allOf(greaterThanOrEqualTo(createdBefore.millisecondsSinceEpoch),
              lessThanOrEqualTo(createdAfter.millisecondsSinceEpoch)),
          reason: 'now - 3h is before creation, and everything received since '
              'creation must still be delivered once');
    });

    test('a negative window is treated as zero, not a start in the future',
        () async {
      await start(const NotificationReplay.window(Duration(minutes: -5)));

      final answered = await service.getLastNotificationTime();
      expect(answered, lessThanOrEqualTo(clock.millisecondsSinceEpoch),
          reason: 'a start after now would replay nothing that arrives');
      expect(answered, clock.millisecondsSinceEpoch,
          reason: 'window(0) starts now, which the test clock sets two hours '
              'ahead of creation');
    });

    test('a window longer than a DateTime can hold is clamped to creation',
        () async {
      await start(const NotificationReplay.window(Duration(days: 100000)));

      expect(
          await service.getLastNotificationTime(),
          allOf(greaterThanOrEqualTo(createdBefore.millisecondsSinceEpoch),
              lessThanOrEqualTo(createdAfter.millisecondsSinceEpoch)),
          reason: 'the subtraction must not overflow a DateTime');
    });

    test('a shorter window starts later than a longer one', () async {
      final stored = clock.subtract(const Duration(hours: 3));
      await start(const NotificationReplay.window(Duration(minutes: 90)),
          stored: stored);
      final longer = await service.getLastNotificationTime();
      service.stopAllSubscriptions();

      await start(const NotificationReplay.window(Duration(minutes: 30)),
          stored: stored);
      final shorter = await service.getLastNotificationTime();

      expect(longer,
          clock.subtract(const Duration(minutes: 90)).millisecondsSinceEpoch);
      expect(shorter,
          clock.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch);
      expect(shorter, greaterThan(longer!),
          reason: 'each window measures back from now by its own duration');
    });

    test('a receipt older than the resolved start does not move it back',
        () async {
      final stored = clock.subtract(const Duration(hours: 5));
      await start(const NotificationReplay.resume(), stored: stored);
      expect(await service.getLastNotificationTime(),
          stored.millisecondsSinceEpoch);

      // Older than the stored watermark the start resolved to.
      await receive('old',
          clock.subtract(const Duration(hours: 6)).millisecondsSinceEpoch);

      expect(await service.getLastNotificationTime(),
          stored.millisecondsSinceEpoch,
          reason: 'the later of the policy start and the latest receipt');
    });

    test(
        'a start read that fails is attempted again on the next call, not '
        'reported for the life of the service', () async {
      await start(const NotificationReplay.resume());
      var reads = 0;
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(any())).thenAnswer((_) async {
        if (++reads == 1) throw StateError('the store is not ready');
        return AtValue()..value = jsonEncode({'epochMillis': 1234567890123});
      });

      await expectLater(
          service.getLastNotificationTime(), throwsA(isA<StateError>()));
      expect(await service.getLastNotificationTime(), 1234567890123,
          reason: 'a failed resolution is not kept, so the next connect asks '
              'the store again rather than rethrowing the same error');
    });
  });

  group('notificationReplay preference', () {
    test(
        'fetchOfflineNotifications false sets connect; true sets resume only '
        'from connect', () {
      final preference = AtClientPreference()
        ..fetchOfflineNotifications = false;
      expect(preference.notificationReplay, const NotificationReplay.connect());

      preference.notificationReplay = const NotificationReplay.window();
      preference.fetchOfflineNotifications = true;
      expect(preference.notificationReplay, const NotificationReplay.window(),
          reason: 'true leaves a policy that already fetches as it is');

      preference.notificationReplay = const NotificationReplay.full();
      expect(preference.fetchOfflineNotifications, isTrue);
    });

    test('the getter is false only for connect', () {
      final preference = AtClientPreference();
      preference.notificationReplay = const NotificationReplay.connect();
      expect(preference.fetchOfflineNotifications, isFalse);
      preference.notificationReplay = const NotificationReplay.window();
      expect(preference.fetchOfflineNotifications, isTrue);
    });

    test('true selects resume when, and only when, the policy is connect', () {
      final preference = AtClientPreference()
        ..notificationReplay = const NotificationReplay.connect();

      preference.fetchOfflineNotifications = true;

      expect(preference.notificationReplay, const NotificationReplay.resume());
    });

    test(
        'policies built at run time compare by value, a window by its duration',
        () {
      final five = Duration(minutes: 5);

      expect(NotificationReplay.window(five), NotificationReplay.window(five));
      expect(NotificationReplay.window(five).hashCode,
          NotificationReplay.window(five).hashCode,
          reason: 'equal policies hash equal');
      expect(NotificationReplay.window(five),
          isNot(NotificationReplay.window(Duration(minutes: 6))));
      expect(
          NotificationReplay.window(), isNot(NotificationReplay.window(five)));
    });

    test('the default is resume, and the copy method keeps the policy', () {
      expect(AtClientPreference().notificationReplay,
          const NotificationReplay.resume());

      final preference = AtClientPreference(posture: PqPosture.legacy)
        ..notificationReplay =
            const NotificationReplay.window(Duration(minutes: 5));
      final raised = preference.raisedTo(PqPosture.pqActive);

      expect(identical(raised, preference), isFalse,
          reason: 'the copy path is the one under test');
      expect(raised.notificationReplay,
          const NotificationReplay.window(Duration(minutes: 5)));
    });
  });

  /// The watermark is a `local:` record: never synced to the atServer, and
  /// already encrypted at rest by the keystore. It is written on every
  /// notification and only ever read for one field.
  group('the last-received-notification watermark', () {
    late NotificationServiceImpl service;

    setUp(() async {
      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => false);
      service = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      service.stopAllSubscriptions();
    });

    test('a batch cut by stop() writes no watermark after the stop', () async {
      final park = Completer<bool>();
      var puts = 0;
      when(() => mockAtClientImpl.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((_) {
        puts++;
        return puts == 1 ? park.future : Future.value(true);
      });
      String notification(String id) =>
          '{"id":"$id","from":"@alice","to":"@alice","key":"$id.wavi@alice",'
          '"value":null,"operation":"update","epochMillis":1,'
          '"messageType":"MessageType.key","isEncrypted":false}';
      final live = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;

      final receipt = live.handleNotificationReceipt(
          'notification: ${notification('n1')}notification: ${notification('n2')}');
      await Future.delayed(Duration.zero);
      expect(puts, 1,
          reason: 'the first watermark write is parked, so the stop below '
              'lands mid-batch');

      await live.stop();
      park.complete(true);
      await receipt;
      expect(puts, 1,
          reason: 'the second notification was handled after stop(); its '
              'watermark write would land on a store the stop has closed');
    });

    test('the stored watermark ids list is capped at seenIdCapacity (1024)',
        () async {
      final storedValues = <String>[];
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((i) async {
        storedValues.add(i.positionalArguments[1] as String);
        return true;
      });
      final live = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(live.stopAllSubscriptions);

      const epoch = 50000;
      for (var i = 0; i <= NotificationServiceImpl.seenIdCapacity; i++) {
        await live.handleNotificationReceipt('notification: '
            '{"id":"id$i","from":"@alice","to":"@alice",'
            '"key":"id$i.wavi@alice","value":null,"operation":"update",'
            '"epochMillis":$epoch,'
            '"messageType":"MessageType.key","isEncrypted":false}');
      }
      await pumpEventQueue();

      final lastWatermark = jsonDecode(storedValues.last) as Map;
      final ids =
          (lastWatermark['idsAtEpochMillis'] as List).cast<List<dynamic>>();
      expect(ids.length, NotificationServiceImpl.seenIdCapacity,
          reason: 'watermark id list must be capped at seenIdCapacity (1024)');
      expect(ids.any((p) => p[0] == '@alice' && p[1] == 'id0'), isFalse,
          reason: 'first id should have been evicted when exceeding capacity');
      expect(
          ids.last, ['@alice', 'id${NotificationServiceImpl.seenIdCapacity}']);
    });

    test('the stored watermark ids list resets at a new millisecond', () async {
      final storedValues = <String>[];
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((i) async {
        storedValues.add(i.positionalArguments[1] as String);
        return true;
      });
      final live = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(live.stopAllSubscriptions);

      await live.handleNotificationReceipt('notification: '
          '{"id":"first","from":"@alice","to":"@alice",'
          '"key":"first.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":1000,'
          '"messageType":"MessageType.key","isEncrypted":false}');
      await live.handleNotificationReceipt('notification: '
          '{"id":"second","from":"@alice","to":"@alice",'
          '"key":"second.wavi@alice","value":null,"operation":"update",'
          '"epochMillis":2000,'
          '"messageType":"MessageType.key","isEncrypted":false}');
      await pumpEventQueue();

      final lastWatermark = jsonDecode(storedValues.last) as Map;
      final ids =
          (lastWatermark['idsAtEpochMillis'] as List).cast<List<dynamic>>();
      expect(
          ids,
          [
            ['@alice', 'second']
          ],
          reason: 'ids list resets when epochMillis advances');
    });

    test('is written only after the notification reaches its subscriber',
        () async {
      final events = <String>[];
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async {
        // NOTE: a subscriber's stream delivers on a later microtask, so this
        // yields a turn first: what it then records is whether the
        // notification had been handed to the subscriber before this write.
        await Future.delayed(Duration.zero);
        events.add('watermark');
        return true;
      });
      final live = await NotificationServiceImpl.create(mockAtClientImpl,
              monitor: fakeMonitor, secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      live.subscribe(regex: '.*').listen((n) => events.add('delivered'));

      await live.handleNotificationReceipt('notification: '
          '{"id":"n1","from":"@alice","to":"@alice","key":"n1.wavi@alice",'
          '"value":null,"operation":"update","epochMillis":1,'
          '"messageType":"MessageType.key","isEncrypted":false}');
      await Future.delayed(Duration.zero);

      expect(events, ['delivered', 'watermark'],
          reason: 'a watermark saved first moves past a notification a stop '
              'can then keep from every subscriber, and nothing replays it');
    });

    test('is written unencrypted, without the payload or the metadata',
        () async {
      when(() => mockAtClientImpl.get(service.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => AtValue());
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);

      // NOTE: the mock client is shared across this file, so puts other tests
      // made are still recorded on it.
      clearInteractions(mockAtClientImpl);
      expect(await service.getLastNotificationTime(), isNotNull);

      final captured = verify(() => mockAtClientImpl.put(any(), captureAny(),
          putRequestOptions: captureAny(named: 'putRequestOptions'))).captured;
      final written = jsonDecode(captured[0] as String) as Map<String, dynamic>;

      expect(written['epochMillis'], isNotNull,
          reason: 'the one field that is ever read back');
      expect(written.containsKey('value'), isFalse,
          reason: 'the payload is bounded only by maxDataSize, is rewritten on '
              'every notification, and is held here without value-level '
              'encryption');
      expect(written.containsKey('metadata'), isFalse);
      expect((captured[1] as PutRequestOptions).shouldEncrypt, isFalse,
          reason: 'routing a never-synced record through the shared-data '
              'crypto path is what made it refusable: every post-quantum '
              'provider declines a local key and the fallback is the legacy provider');
    });

    test('a write failure does not escape into the connect sequence', () async {
      when(() => mockAtClientImpl.get(service.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => AtValue());
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenThrow(AtKeyException('keystore unavailable'));

      await expectLater(
          service.getLastNotificationTime(), completion(isNotNull),
          reason: 'seeding the watermark is an optimisation — failing to seed '
              'it costs one replayed window, where letting the failure out '
              'costs the listener entirely');
      verify(() => mockAtClientImpl.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).called(1);
    });

    test('a record written by an older build still reads back', () async {
      final legacyShape = AtNotification(
          Uuid().v4(), 'k', '@bob', '@alice', 1234567890123, 'update', true,
          value: 'a payload an older build persisted', metadata: Metadata());
      // NOTE: with `exists` false this takes the first-call seed branch, and
      // tests the seed rather than the reader.
      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      when(() => mockAtClientImpl.get(service.lastReceivedNotificationAtKey))
          .thenAnswer(
              (_) async => AtValue()..value = jsonEncode(legacyShape.toJson()));

      expect(await service.getLastNotificationTime(), 1234567890123);
    });
  });

  group('A group of tests for lastNotificationReceived key', () {
    test('test to verify lastNotificationReceived toString', () {
      var lastReceivedNotification = AtKey.local(
              NotificationServiceImpl.lastReceivedNotificationKey, '@alIce',
              namespace: 'wAvi')
          .build();
      //calling toString() on an AtKey will convert it to lowercase
      expect(lastReceivedNotification.toString(),
          'local:lastreceivednotification.wavi@alice');
    });

    when(() => mockAtClientImpl.getPreferences())
        .thenReturn(AtClientPreference()..namespace = 'wavi');

    test('test to verify lastNotificationReceived fromString', () async {
      var lastReceivedNotification =
          AtKey.fromString('local:lastReceivedNotification.wavi@alice');

      NotificationServiceImpl service = await NotificationServiceImpl.create(
          mockAtClientImpl,
          secondaryAddressFinder: defaultAtDirectory,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      expect(lastReceivedNotification.toString(),
          service.lastReceivedNotificationAtKey.toString());
      expect(lastReceivedNotification.isLocal, true);
    });
  });

  group('legacy lastReceivedNotification migration (#1942)', () {
    // Verifies the per-startup migration that seeds the canonical
    // `local:lastreceivednotification.<ns>@<atSign>` from any legacy
    // form found, then deletes all legacy forms. The bug fixed in
    // #1942 was that the deletes never happened — bare-form keys
    // lingered in the keystore and accidentally matched AtCollection
    // scans.

    const ns = 'wavi';
    const atSign = '@alice';
    const canonicalStr = 'local:lastreceivednotification.$ns$atSign';
    const intermediateStr = 'lastreceivednotification.$ns$atSign';
    // The original legacy form used by very old releases. The
    // migration code constructs the key as `_latestNotificationIdv2`
    // but `AtKey.fromString().toString()` normalises to lowercase —
    // mock matches must use the post-normalisation form.
    const legacyV2Str = '_latestnotificationidv2.$ns$atSign';

    /// Configures the shared `mockAtClientImpl` for migration tests:
    /// keystore presence comes from `presentKeys`; gets come from
    /// `values` (string → AtValue.value); puts and deletes are
    /// captured into `putCalls` / `deleteCalls`.
    Future<NotificationServiceImpl> setupMigrationMocks({
      required Set<String> presentKeys,
      required Map<String, String?> values,
      required List<MapEntry<String, String?>> putCalls,
      required List<String> deleteCalls,
    }) async {
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()..namespace = ns);
      // `getCurrentAtSign()` and `atSign` are non-stubbable on this
      // mock — MockAtClientImpl overrides them concretely to return
      // `@alice`. Our `atSign` constant must match.
      assert(mockAtClientImpl.getCurrentAtSign() == atSign);

      // AtKey.fromString().toString() lowercases its input; the
      // migration's `isKeyExists` probe uses the constant-case
      // string (e.g. `_latestNotificationIdv2.…`) while
      // `atClient.get`/`atClient.delete` see the normalised
      // (lowercase) form. Compare case-insensitively so test fixtures
      // can specify keys in either casing.
      final presentKeysLower = presentKeys.map((s) => s.toLowerCase()).toSet();
      final valuesLower = <String, String?>{
        for (final e in values.entries) e.key.toLowerCase(): e.value,
      };

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((invocation) async {
        final k = invocation.positionalArguments.first as String;
        return presentKeysLower.contains(k.toLowerCase());
      });
      when(() => mockAtClientImpl.get(any())).thenAnswer((invocation) async {
        final atKey = invocation.positionalArguments.first as AtKey;
        return AtValue()..value = valuesLower[atKey.toString().toLowerCase()];
      });
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((invocation) async {
        final atKey = invocation.positionalArguments[0] as AtKey;
        final value = invocation.positionalArguments[1] as String?;
        putCalls.add(MapEntry(atKey.toString(), value));
        return true;
      });
      when(() => mockAtClientImpl.delete(any())).thenAnswer((invocation) async {
        final atKey = invocation.positionalArguments.first as AtKey;
        deleteCalls.add(atKey.toString());
        return true;
      });

      // The NotificationServiceImpl constructor wires a Monitor with
      // network behaviour we don't want fired in these tests. Pass a
      // FakeMonitor to skip all that.
      return await NotificationServiceImpl.create(
        mockAtClientImpl,
        monitor: fakeMonitor,
        secondaryAddressFinder: defaultAtDirectory,
      ) as NotificationServiceImpl;
    }

    test('seeds canonical from bare-form and deletes both legacy forms',
        () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      final service = await setupMigrationMocks(
        // Canonical absent; both legacy forms present with values.
        presentKeys: {intermediateStr, legacyV2Str},
        values: {
          intermediateStr: '{"epochMillis":111}',
          legacyV2Str: '{"epochMillis":99}',
        },
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );

      final result =
          await service.migrateLegacyLastReceivedNotificationKeysForTest();

      // Bare form wins over _latestNotificationIdv2 (it's the newer
      // intermediate form).
      expect(result?.value, '{"epochMillis":111}');
      // The seed put landed on the canonical local: key.
      expect(putCalls, hasLength(1));
      expect(putCalls.single.key, canonicalStr);
      expect(putCalls.single.value, '{"epochMillis":111}');
      // Both legacy forms are deleted regardless of which one seeded.
      expect(deleteCalls, containsAll([intermediateStr, legacyV2Str]));
    });

    test('a stop while seeding keeps the legacy form it could not copy',
        () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      final service = await setupMigrationMocks(
        presentKeys: {intermediateStr},
        values: {intermediateStr: '{"epochMillis":111}'},
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );
      when(() => mockAtClientImpl.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenThrow(StoppedException('the client has stopped'));

      await expectLater(
          service.migrateLegacyLastReceivedNotificationKeysForTest(),
          throwsA(isA<StoppedException>()),
          reason: 'a seed that failed falls through to deleting the legacy '
              'form, so a stop taken for a failed seed deletes the only copy '
              'of the watermark');
      expect(deleteCalls, isEmpty);
    });

    test('seeds canonical from _latestNotificationIdv2 when bare absent',
        () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      final service = await setupMigrationMocks(
        presentKeys: {legacyV2Str},
        values: {legacyV2Str: '{"epochMillis":42}'},
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );

      final result =
          await service.migrateLegacyLastReceivedNotificationKeysForTest();

      expect(result?.value, '{"epochMillis":42}');
      expect(putCalls, hasLength(1));
      expect(putCalls.single.key, canonicalStr);
      expect(deleteCalls, [legacyV2Str]);
    });

    test('canonical already has value: legacy forms deleted, canonical kept',
        () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      final service = await setupMigrationMocks(
        presentKeys: {canonicalStr, intermediateStr},
        values: {
          canonicalStr: '{"epochMillis":555}',
          intermediateStr: '{"epochMillis":111}',
        },
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );

      final result =
          await service.migrateLegacyLastReceivedNotificationKeysForTest();

      // Canonical wins — no seed put, no overwrite.
      expect(result?.value, '{"epochMillis":555}');
      expect(putCalls, isEmpty);
      // Bare-form still gets cleaned up (the bug from #1942).
      expect(deleteCalls, [intermediateStr]);
    });

    test('no-op when neither canonical nor legacy keys exist', () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      final service = await setupMigrationMocks(
        presentKeys: <String>{},
        values: <String, String?>{},
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );

      final result =
          await service.migrateLegacyLastReceivedNotificationKeysForTest();

      expect(result, isNull);
      expect(putCalls, isEmpty);
      expect(deleteCalls, isEmpty);
    });

    test('idempotent: a second run after a clean DB does nothing', () async {
      final putCalls = <MapEntry<String, String?>>[];
      final deleteCalls = <String>[];
      // After a successful migration, only the canonical exists
      // with a real value — both legacy forms are gone.
      final service = await setupMigrationMocks(
        presentKeys: {canonicalStr},
        values: {canonicalStr: '{"epochMillis":42}'},
        putCalls: putCalls,
        deleteCalls: deleteCalls,
      );

      await service.migrateLegacyLastReceivedNotificationKeysForTest();
      await service.migrateLegacyLastReceivedNotificationKeysForTest();

      expect(putCalls, isEmpty,
          reason: 'no seeding on a clean DB (canonical present)');
      expect(deleteCalls, isEmpty,
          reason: 'no deletes on a clean DB (no legacy forms present)');
    });
  });

  group('validate stop() behaviour', () {
    test('stop() sets isStopped to true', () async {
      final notificationService = await NotificationServiceImpl.create(
          mockAtClientImpl,
          secondaryAddressFinder: defaultAtDirectory,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      await notificationService.stop();
      expect(notificationService.isStopped, true);
      expect(notificationService.currentListenerState,
          NotificationListenerState.notConnected);
      expect(notificationService.monitor.currentState,
          NotificationListenerState.notConnected);
      expect(notificationService.monitor.targetState,
          NotificationListenerState.notConnected);
    });
  });

  /// [AtClientPreference.monitorHeartbeatInterval] and
  /// [AtClientPreference.monitorHeartbeatResponseTimeout] are the only public
  /// controls over the notification connection's liveness probe, and nothing
  /// between them and the socket reads them any more: Monitor holds the
  /// preference but never looks at either field, because the muxable it drives
  /// owns the heartbeat. This constructor is the one place the two values
  /// cross that gap, so it is the only place a test can pin them. at_lookup's
  /// own heartbeat tests set the interval on the implementation directly and
  /// cannot see an AtClientPreference at all.
  group('the heartbeat preferences reach the muxable', () {
    late AtClientPreference preference;

    setUp(() {
      preference = AtClientPreference()
        ..namespace = 'wavi'
        ..monitorAutoStart = false;
      when(() => mockAtClientImpl.getPreferences()).thenReturn(preference);
    });

    test('a tuned interval and response timeout are both carried across',
        () async {
      preference
        ..monitorHeartbeatInterval = Duration(milliseconds: 20)
        ..monitorHeartbeatResponseTimeout = Duration(milliseconds: 7);

      final ns = await NotificationServiceImpl.create(mockAtClientImpl,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      expect(ns.monitor.lookUp.heartbeatInterval, Duration(milliseconds: 20),
          reason: 'an application that tunes monitorHeartbeatInterval must '
              'change how often the notification connection is probed; the '
              'muxable owns the probe now, so a preference that does not '
              'reach it is not overridden, it is silently ignored');
      expect(
          ns.monitor.lookUp.heartbeatResponseTimeout, Duration(milliseconds: 7),
          reason: 'and monitorHeartbeatResponseTimeout decides how long an '
              'unanswered probe waits before the connection is torn down and '
              'rebuilt. Both sides default to 10 seconds, so only a tuned '
              'value can tell a wired field from an unwired one');
    });

    test(
        'an untouched preference gives the documented 59s, not the 30s '
        'underneath', () async {
      final ns = await NotificationServiceImpl.create(mockAtClientImpl,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          lookUps: mockAtClientImpl.lookUps) as NotificationServiceImpl;

      // A raw-literal pin on the default, not a second wiring test: every
      // mutation that reddens this one reddens the test above too.
      expect(ns.monitor.lookUp.heartbeatInterval, Duration(seconds: 59),
          reason: 'the documented default is what a client that never touched '
              'the preference gets, and at_lookup initialises 30 underneath. '
              'Changing that default nearly doubles the idle traffic of '
              'every such client, so this assertion is what an intended '
              'change edits');
    });
  });
}

class StatsAtKeyMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match a legacy '
          'lastReceivedNotification key (`_latestNotificationIdv2.*` or '
          'the intermediate bare `lastreceivednotification.*` form).');

  @override
  bool matches(item, Map matchState) {
    if (item is! AtKey) return false;
    if (item.key.contains('_latestNotificationIdv2')) return true;
    // Intermediate (pre-`local:`) form — added during the #1942 fix
    // when the migration was widened to also clean up bare
    // `lastreceivednotification.<ns>@<atSign>` rows. The matcher
    // accepts only the bare form (rejects the canonical `local:`
    // prefix, which AtKey.fromString preserves on the parsed key).
    if (item.key == 'lastreceivednotification' && !item.isLocal) return true;
    return false;
  }
}
