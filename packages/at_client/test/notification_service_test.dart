// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
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
import 'package:at_client/src/decryption_service/shared_with_me_decryption.dart';
import 'package:uuid/uuid.dart';

String? lastNotificationJson;

class MockSecondaryKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

class MockLocalSecondary extends Mock implements LocalSecondary {
  @override
  AtKeyValueStore<String, AtData, AtMetaData?>? keyStore =
      MockSecondaryKeyStore();
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtClientImpl extends Mock implements AtClientImpl {
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

class MockAtKeyDecryptionManager extends Mock
    implements AtKeyDecryptionManager {}

// Mock class without implementation to throw exceptions
class MockSharedKeyEncryption extends Mock implements SharedKeyEncryption {}

// Mock class with implementation to populate metadata on encrypting value
class MockSharedKeyEncryptionImpl extends Mock implements SharedKeyEncryption {
  @override
  Future encrypt(AtKey atKey, value) async {
    //Set encryptionMetadata to atKey metadata
    atKey.metadata = Metadata();
    atKey.metadata.sharedKeyEnc = 'sharedKeyEnc';
    atKey.metadata.pubKeyCS = 'publicKeyCS';

    return 'encryptedValue';
  }
}

class MockSharedKeyDecryption extends Mock implements SharedWithMeDecryption {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockAtKeyEncryptionManager extends Mock
    implements AtKeyEncryptionManager {}

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class FakeNotifyVerbBuilder extends Fake implements NotifyVerbBuilder {}

class FakeNotifyFetchVerbBuilder extends Fake
    implements NotifyFetchVerbBuilder {}

class FakeAtKey extends Fake implements AtKey {}

void main() {
  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  AtKeyDecryptionManager mockDecryptionManager = MockAtKeyDecryptionManager();
  SharedWithMeDecryption mockSharedKeyDecryption = MockSharedKeyDecryption();
  AtClientManager mockAtClientManager = MockAtClientManager();
  FakeMonitor fakeMonitor = FakeMonitor();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  AtKeyEncryptionManager mockEncryptionManager = MockAtKeyEncryptionManager();
  AtLookupImpl mockAtLookupImpl = MockAtLookupImpl();
  group('A group of test to validate notification request transformer', () {
    var value = '+91908909933';
    late SharedKeyEncryption mockSharedKeyEncryptionImpl;
    setUp(() {
      mockSharedKeyEncryptionImpl = MockSharedKeyEncryptionImpl();
    });

    group('Tests with simple namespace in AtClientPrefs', () {
      test('Notification request without namespace but with namespace in prefs',
          () async {
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'wavi',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'wavi',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'wavi',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'wavi',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'foo.bar.baz',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.foo.bar.baz@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'foo.bar.baz',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = true);
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'foo.bar.baz',
                SharedKeyEncryption(mockAtClientImpl))
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
        var notificationParams = NotificationParams.forUpdate(
            AtKey.fromString('@bob:phone.my_app@alice')
              ..metadata.namespaceAware = false);
        var notifyVerbBuilder = await NotificationRequestTransformer(
                '@alice',
                AtClientPreference()..namespace = 'foo.bar.baz',
                SharedKeyEncryption(mockAtClientImpl))
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
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build());
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              SharedKeyEncryption(mockAtClientImpl))
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      expect(notifyVerbBuilder.atKey.key, 'phone');
      expect(notifyVerbBuilder.atKey.namespace, 'wavi');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.high);
      expect(notifyVerbBuilder.strategy, StrategyEnum.latest);
      expect(notifyVerbBuilder.value, 'encryptedValue');
      expect(notifyVerbBuilder.atKey.metadata.sharedKeyEnc, 'sharedKeyEnc');
      expect(notifyVerbBuilder.notifier, 'test-notifier');
      expect(notifyVerbBuilder.latestN, 2);
      expect(notifyVerbBuilder.ttln, Duration(minutes: 1).inMilliseconds);
    });

    test(
        'A test to validate notification request with text return verb builder',
        () async {
      var notificationParams =
          NotificationParams.forText('Hi How are you', '@bob');
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      //upper case should be preserved in forText notifications
      expect(notifyVerbBuilder.atKey.key, 'Hi How are you');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      // ignore: deprecated_member_use
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.text);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
    });

    test(
        'A test to validate notification request with text with shouldEncrypt set to true return verb builder',
        () async {
      var notificationParams = NotificationParams.forText(
          'Hi How are you', '@bob',
          shouldEncrypt: true);
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      expect(notifyVerbBuilder.atKey.key, 'encryptedValue');
      expect(notifyVerbBuilder.atKey.sharedWith, '@bob');
      // ignore: deprecated_member_use
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.text);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
    });

    test(
        'A test to verify notification is not sent when encryption service throws exception',
        () async {
      registerFallbackValue(FakeAtKey());
      SharedKeyEncryption mockSharedKeyEncryption = MockSharedKeyEncryption();
      when(() => mockSharedKeyEncryption.encrypt(any(), any())).thenAnswer(
          (_) => throw SecondaryConnectException(
              'Unable to connect to secondary server'));
      var notificationParams = NotificationParams.forText(
          'Hi How are you', '@bob',
          shouldEncrypt: true);

      var notificationRequestTransformer = NotificationRequestTransformer(
          '@alice',
          AtClientPreference()..namespace = 'wavi',
          mockSharedKeyEncryption);
      expect(
          () async => await notificationRequestTransformer
              .transform(notificationParams),
          throwsA(predicate((dynamic e) =>
              e is SecondaryConnectException &&
              e.message == 'Unable to connect to secondary server')));
    });

    test(
        'A test to validate encrypted value and shared encryption key is set in verb builder when isEncrypted is set to true in metadata',
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      expect(notifyVerbBuilder.value, 'encryptedValue');
      expect(notifyVerbBuilder.atKey.metadata.sharedKeyEnc, 'sharedKeyEnc');
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      expect(notifyVerbBuilder.value, value);
    });
  });

  group('A group of test to validate notification response transformer', () {
    setUp(() {
      registerFallbackValue(FakeAtKey());
      mockDecryptionManager = MockAtKeyDecryptionManager();
      when(() => mockSharedKeyDecryption.decrypt(any(), 'encryptedValue'))
          .thenAnswer((_) => Future.value('decryptedValue'));
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
          value: 'encryptedValue');
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.value, 'decryptedValue');
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
          value: 'encryptedValue');
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.value, 'decryptedValue');
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
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

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
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

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
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

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
      var notificationResponseTransformer = NotificationResponseTransformer(
          mockAtClientImpl,
          decrypterManager: mockDecryptionManager);
      when(() => mockDecryptionManager.get(any()))
          .thenReturn(mockSharedKeyDecryption);

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
    late SharedKeyEncryption mockSharedKeyEncryption;
    setUp(() {
      mockSharedKeyEncryption = MockSharedKeyEncryption();
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()..namespace = 'wavi');
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
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
      when(() => mockEncryptionManager.get(atKey, currentAtSign))
          .thenAnswer((_) => mockSharedKeyEncryption);
      when(() => mockSharedKeyEncryption.encrypt(atKey, value)).thenThrow(
          AtPublicKeyNotFoundException(
              'Failed to fetch public key of ${atKey.sharedWith}')
            ..stack(AtChainedException(
                Intent.shareData,
                ExceptionScenario.keyNotFound,
                'public:publickey@bob does not exist in keystore')));
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);

      var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              monitor: fakeMonitor,
              secondaryAddressFinder: mockSecondaryAddressFinder)
          as NotificationServiceImpl;

      notificationServiceImpl.atKeyEncryptionManager = mockEncryptionManager;

      var notificationResult = await notificationServiceImpl.notify(
          NotificationParams.forUpdate(atKey, value: value),
          checkForFinalDeliveryStatus: false);
      expect(notificationResult.atClientException,
          isA<AtPublicKeyNotFoundException>());
      expect(notificationResult.atClientException!.getTraceMessage(),
          'Failed to notifyData caused by\nFailed to encrypt the data caused by\npublic:publickey@bob does not exist in keystore');
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
      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
      when(() => mockEncryptionManager.get(atKey, currentAtSign))
          .thenAnswer((_) => mockSharedKeyEncryption);
      when(() => mockSharedKeyEncryption.encrypt(atKey, value))
          .thenAnswer((_) => Future.value('encrypted_value'));
      when(() => mockAtClientImpl.getRemoteSecondary())
          .thenAnswer((_) => remoteSecondary);
      registerFallbackValue(FakeNotifyVerbBuilder());
      when(() => mockAtLookupImpl.executeVerb(any()))
          .thenThrow(AtLookUpException('AT0013', 'Invalid syntax exception'));

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          secondaryAddressFinder: mockSecondaryAddressFinder,
          monitor: fakeMonitor) as NotificationServiceImpl;

      notificationServiceImpl.atKeyEncryptionManager = mockEncryptionManager;

      var notificationResult = await notificationServiceImpl.notify(
          NotificationParams.forUpdate(atKey, value: value),
          checkForFinalDeliveryStatus: false);
      expect(notificationResult.atClientException, isA<AtClientException>());
      expect(notificationResult.atClientException?.getTraceMessage(),
          'Failed to notifyData caused by\nInvalid syntax exception');
      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.undelivered);
    });

    test('A test to verify buffer over flow exception for messageType key',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

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

    test('A test to verify buffer over flow exception for messageType text',
        () async {
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()..maxDataSize = 1);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      NotificationParams notificationParams =
          NotificationParams.forText('Hello bob', '@bob');
      NotifyVerbBuilder notifyVerbBuilder = NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..atKey.key = '@bob:Hello bob';

      expect(
          () => notificationServiceImpl.notificationValueValidation(
              notificationParams, notifyVerbBuilder),
          throwsA(predicate((dynamic e) => e is BufferOverFlowException)));
    });

    test(
        'A test to verify unauthorized exception is thrown when sharedBy atSign is different from currentAtSign',
        () async {
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
      when(() => mockSecondaryAddressFinder.findSecondary('@colin'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientImpl.notifyStatus(any()))
          .thenAnswer((_) => Future.value('data:delivered'));

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

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
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = false
            ..monitorAutoStart = false);

      registerFallbackValue(AtKey());
      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);
    });

    test('Verify lastReceipt', () async {
      DateTime testStartTime = DateTime.now().toUtc();

      var ns = await NotificationServiceImpl.create(mockAtClientImpl,
          atClientManager: mockAtClientManager) as NotificationServiceImpl;

      var atNotification = AtNotification(
          '124',
          '@bob:some.thing.lolz.app@alice',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          false,
          value: 'Got it');

      String fromAtServer =
          'notification: ${jsonEncode(atNotification.toJson())}\n'
          '@${mockAtClientImpl.getCurrentAtSign()}@';
      await ns.monitor.onSocketDataReceipt(fromAtServer.codeUnits);

      expect(ns.lastReceipt, isNotNull);
      expect(ns.lastReceipt!.microsecondsSinceEpoch,
          lessThan(DateTime.now().microsecondsSinceEpoch));
      expect(ns.lastReceipt!.microsecondsSinceEpoch,
          greaterThan(testStartTime.microsecondsSinceEpoch));
    });

    test('Verify monitor delivers notification', () async {
      var ns = await NotificationServiceImpl.create(mockAtClientImpl,
          atClientManager: mockAtClientManager) as NotificationServiceImpl;

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

      String fromAtServer =
          'notification: ${jsonEncode(atNotification.toJson())}\n'
          '@${mockAtClientImpl.getCurrentAtSign()}@';
      await ns.monitor.onSocketDataReceipt(fromAtServer.codeUnits);

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
        atClientManager: mockAtClientManager,
        monitor: fakeMonitor,
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
        atClientManager: mockAtClientManager,
        monitor: fakeMonitor,
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

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
        'NotificationService subscribe returns an existing stream for a same regex',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var notificationStream = notificationServiceImpl.subscribe(
          regex: '.wavi', shouldDecrypt: false);
      notificationStream.listen((event) async {
        print(event);
      });

      var notificationStream1 = notificationServiceImpl.subscribe(
          regex: '.wavi', shouldDecrypt: true);
      notificationStream1.listen((event) {
        print(event);
      });
      expect(notificationServiceImpl.getStreamListenersCount(), 1);
      notificationServiceImpl.stopAllSubscriptions();
    });
  });

  group('A group of tests to validate notification fetch', () {
    test('A test to verify notification fetch for non-existing notification',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      var remoteSecondary = RemoteSecondary('@alice', AtClientPreference());
      remoteSecondary.atLookUp = mockAtLookupImpl;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((_) => Future.value(SecondaryAddress('dummyhost', 9001)));
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenAnswer((_) => mockSecondaryAddressFinder);
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
        'getLastNotificationTime() returns null if checkOfflineNotifications is set to false',
        () async {
      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = false);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      notificationServiceImpl.stopAllSubscriptions();
      expect(await notificationServiceImpl.getLastNotificationTime(), null);
    });

    test(
        'getLastNotificationTime() returns null if checkOfflineNotifications is true but there is no stored value',
        () async {
      registerFallbackValue(FakeAtKey());

      when(() => mockAtClientImpl.getPreferences())
          .thenAnswer((_) => AtClientPreference()
            ..namespace = 'wavi'
            ..fetchOfflineNotifications = true);

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.exists(any()))
          .thenAnswer((_) async => true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      notificationServiceImpl.stopAllSubscriptions();

      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

      // #1942 — the legacy-key migration may call delete; stub it so
      // the mock doesn't throw when no legacy keys are present.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      expect(await notificationServiceImpl.getLastNotificationTime(), null);
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.get(any(that: StatsAtKeyMatcher())))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any()))
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any()))
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
          atClientManager: mockAtClientManager,
          monitor: fakeMonitor) as NotificationServiceImpl;

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

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

      // #1942 migration cleanup may call delete on legacy keys.
      when(() => mockAtClientImpl.delete(any())).thenAnswer((_) async => true);

      expect(
          await notificationServiceImpl.getLastNotificationTime(), epochMillis);
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
          atClientManager: mockAtClientManager) as NotificationServiceImpl;

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
      when(() => mockAtClientImpl.put(any(), any()))
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
      when(() => mockAtClientManager.secondaryAddressFinder)
          .thenReturn(MockSecondaryAddressFinder());
      final notificationService = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager) as NotificationServiceImpl;

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
