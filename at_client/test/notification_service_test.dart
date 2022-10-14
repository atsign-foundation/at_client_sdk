import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:uuid/uuid.dart';

String? lastNotificationJson;

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {
  @override
  bool isKeyExists(String key) {
    if (! key.contains(NotificationServiceImpl.notificationIdKey)) {
      throw IllegalArgumentException("This mock client only understands how to get, put and delete ${NotificationServiceImpl.notificationIdKey}");
    }
    return (lastNotificationJson != null);
  }
}

class MockLocalSecondary extends Mock implements LocalSecondary  {
  @override
  SecondaryKeyStore? keyStore = MockSecondaryKeyStore();

}

class MockAtClientImpl extends Mock implements AtClientImpl {
  AtClientPreference mockPreferences = AtClientPreference()..namespace = 'wavi';
  @override
  AtClientPreference getPreferences() {
    mockPreferences.fetchOfflineNotifications = true;
    return mockPreferences;
  }

  @override
  String? getCurrentAtSign() {
    return '@alice';
  }

  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  @override
  LocalSecondary? getLocalSecondary() {
    return mockLocalSecondary;
  }

  @override
  Future<AtValue> get(AtKey atKey,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    if (atKey.key != NotificationServiceImpl.notificationIdKey) {
      throw IllegalArgumentException("This mock client only understands how to get, put and delete ${NotificationServiceImpl.notificationIdKey}");
    }
    if (lastNotificationJson != null) {
      return AtValue()..value = lastNotificationJson;
    } else {
      return AtValue();
    }
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value,
      {bool isDedicated = false}) async {
    if (atKey.key != NotificationServiceImpl.notificationIdKey) {
      throw IllegalArgumentException("This mock client only understands how to get, put and delete ${NotificationServiceImpl.notificationIdKey}");
    }
    lastNotificationJson = value;
    return true;
  }

  @override
  Future<bool> delete(AtKey atKey, {bool isDedicated = false}) async {
    if (atKey.key != NotificationServiceImpl.notificationIdKey) {
      throw IllegalArgumentException("This mock client only understands how to get, put and delete ${NotificationServiceImpl.notificationIdKey}");
    }
    if (lastNotificationJson == null) {
      return false;
    } else {
      lastNotificationJson = null;
      return true;
    }
  }
}

class MockMonitor extends Mock implements Monitor {
  @override
  MonitorStatus status = MonitorStatus.started;

  @override
  Future<void> start({int? lastNotificationTime}) async {
    print('Monitor started');
  }

  @override
  MonitorStatus getStatus() {
    return status;
  }
}

// Mock class without implementation to throw exceptions
class MockSharedKeyEncryption extends Mock implements SharedKeyEncryption {}

// Mock class with implementation to populate metadata on encrypting value
class MockSharedKeyEncryptionImpl extends Mock implements SharedKeyEncryption {
  @override
  Future encrypt(AtKey atKey, value) async {
    //Set encryptionMetadata to atKey metadata
    atKey.metadata = Metadata()
      ..sharedKeyEnc = 'sharedKeyEnc'
      ..pubKeyCS = 'publicKeyCS';
    return 'encryptedValue';
  }
}

class MockSharedKeyDecryption extends Mock implements SharedKeyDecryption {}

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
  SharedKeyDecryption mockSharedKeyDecryption = MockSharedKeyDecryption();
  AtClientManager mockAtClientManager = MockAtClientManager();
  Monitor mockMonitor = MockMonitor();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  AtKeyEncryptionManager mockAtKeyEncryptionManager =
      MockAtKeyEncryptionManager();
  AtLookupImpl mockAtLookupImpl = MockAtLookupImpl();

  group('A group of test to validate notification request processor', () {
    var value = '+91908909933';
    late SharedKeyEncryption mockSharedKeyEncryptionImpl;
    setUp(() {
      mockSharedKeyEncryptionImpl = MockSharedKeyEncryptionImpl();
    });
    test(
        'A test to validate notification request without value return verb builder',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build());
      var notifyVerbBuilder = await NotificationRequestTransformer('@alice',
              AtClientPreference()..namespace = 'wavi', SharedKeyEncryption())
          .transform(notificationParams);
      expect(notifyVerbBuilder.atKey, 'phone.wavi');
      expect(notifyVerbBuilder.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
    });

    test(
        'A test to validate notification request with value return verb builder',
        () async {
      var notificationParams = NotificationParams.forUpdate(
          (AtKey.shared('phone', namespace: 'wavi')..sharedWith('@bob'))
              .build(),
          value: value);
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              mockSharedKeyEncryptionImpl)
          .transform(notificationParams);
      expect(notifyVerbBuilder.atKey, 'phone.wavi');
      expect(notifyVerbBuilder.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.key);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
      expect(notifyVerbBuilder.value, 'encryptedValue');
      expect(notifyVerbBuilder.sharedKeyEncrypted, 'sharedKeyEnc');
      expect(notifyVerbBuilder.pubKeyChecksum, 'publicKeyCS');
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
      expect(notifyVerbBuilder.atKey, 'Hi How are you');
      expect(notifyVerbBuilder.sharedWith, '@bob');
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
      expect(notifyVerbBuilder.atKey, 'encryptedValue');
      expect(notifyVerbBuilder.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.text);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
    });
  });

  group('A group of test to validate notification response transformer', () {
    setUp(() {
      registerFallbackValue(FakeAtKey());
      when(() => mockSharedKeyDecryption.decrypt(any(), 'encryptedValue'))
          .thenAnswer((_) => Future.value('decryptedValue'));
    });
    test(
        'A test to verify notification text is decrypted when isEncrypted is set to true',
        () async {
      var isEncrypted = true;
      var atNotification = at_notification.AtNotification(
          '124',
          '@bob:encryptedValue',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.text.toString(),
          isEncrypted);
      var notificationResponseTransformer = NotificationResponseTransformer();
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.key, '@bob:decryptedValue');
    });

    test(
        'A test to verify notification text is not decrypted when isEncrypted is set to false',
        () async {
      var isEncrypted = false;
      var atNotification = at_notification.AtNotification(
          '124',
          '@bob:encryptedValue',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.text.toString(),
          isEncrypted);
      var notificationResponseTransformer = NotificationResponseTransformer();
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.key, '@bob:encryptedValue');
    });

    test(
        'A test to verify notification key is decrypted when shouldDecrypt is set to true',
        () async {
      var isEncrypted = false;
      var atNotification = at_notification.AtNotification(
          '124',
          'key-1',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: 'encryptedValue');
      var notificationResponseTransformer = NotificationResponseTransformer();
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));
      expect(transformedNotification.value, 'decryptedValue');
    });

    test(
        'A test to verify notification key is not decrypted when shouldDecrypt is set to false',
        () async {
      var isEncrypted = false;
      var atNotification = at_notification.AtNotification(
          '124',
          'key-1',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted,
          value: 'encryptedValue');
      var notificationResponseTransformer = NotificationResponseTransformer();
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

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
      var atNotification = at_notification.AtNotification(
          '124',
          'key-1',
          '@alice',
          '@bob',
          DateTime.now().millisecondsSinceEpoch,
          MessageTypeEnum.key.toString(),
          isEncrypted);
      var notificationResponseTransformer = NotificationResponseTransformer();
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()..regex = '.*'));
      expect(transformedNotification.id, '124');
      expect(transformedNotification.key, 'key-1');
    });
  });

  group('A group of tests to validate notification exception chaining', () {
    late SharedKeyEncryption mockSharedKeyEncryption;
    setUp(() {
      mockSharedKeyEncryption = MockSharedKeyEncryption();
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
      when(() => mockAtKeyEncryptionManager.get(atKey, currentAtSign))
          .thenAnswer((_) => mockSharedKeyEncryption);
      when(() => mockSharedKeyEncryption.encrypt(atKey, value)).thenThrow(
          AtPublicKeyNotFoundException(
              'Failed to fetch public key of ${atKey.sharedWith}')
            ..stack(AtChainedException(
                Intent.shareData,
                ExceptionScenario.keyNotFound,
                'public:publickey@bob does not exist in keystore')));

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      notificationServiceImpl.atKeyEncryptionManager =
          mockAtKeyEncryptionManager;

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
      when(() => mockAtKeyEncryptionManager.get(atKey, currentAtSign))
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
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      notificationServiceImpl.atKeyEncryptionManager =
          mockAtKeyEncryptionManager;

      var notificationResult = await notificationServiceImpl.notify(
          NotificationParams.forUpdate(atKey, value: value),
          checkForFinalDeliveryStatus: false);
      expect(notificationResult.atClientException, isA<AtClientException>());
      expect(notificationResult.atClientException?.getTraceMessage(),
          'Failed to notifyData caused by\nInvalid syntax exception');
      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.undelivered);
    });
  });

  group('A group of tests to validate notification subscribe method', () {
    test('NotificationService subscribe returns a new stream for a new regex',
        () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

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
          monitor: mockMonitor) as NotificationServiceImpl;

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
          monitor: mockMonitor) as NotificationServiceImpl;

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
          monitor: mockMonitor) as NotificationServiceImpl;

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
      expect(
          atNotification.epochMillis,
          DateTime.parse('2022-10-03 18:34:58.601')
              .millisecondsSinceEpoch);
      expect(atNotification.value, '+445 112 3434');
      expect(atNotification.operation, 'OperationType.update');
      expect(atNotification.status, 'NotificationStatus.delivered');
    });

    test('A test to verify remote secondary timeouts to respond', () async {
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

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
          monitor: mockMonitor) as NotificationServiceImpl;

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
          'AT0021', 'Secondary Connect Exception'));
      // The errorCode AT0021 results to SecondaryConnectException. Since SecondaryConnectException is
      // not a sub-class of AtClientException, the exception is converted to AtClientException and returned.`
      expect(() async => await notificationServiceImpl.fetch('123'),
          throwsA(predicate((dynamic e) => e is AtClientException)));
    });

  group('Tests of getLastNotificationTime()', () {
    setUpAll(() {
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);
    });

    test('getLastNotificationTime() returns null if checkOfflineNotifications is set to false',
            () async {
          var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

          notificationServiceImpl.stopAllSubscriptions();

          mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = false;

          expect(await notificationServiceImpl.getLastNotificationTime(), null);
        });

    test(
        'getLastNotificationTime() returns null if checkOfflineNotifications is true but there is no stored value',
            () async {
              var notificationServiceImpl = await NotificationServiceImpl.create(
                  mockAtClientImpl,
                  atClientManager: mockAtClientManager,
                  monitor: mockMonitor) as NotificationServiceImpl;

              notificationServiceImpl.stopAllSubscriptions();

              mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = true;

              await mockAtClientImpl.delete(AtKey()..key = NotificationServiceImpl.notificationIdKey);

              expect(await notificationServiceImpl.getLastNotificationTime(), null);
        });

    test(
        'getLastNotificationTime() returns the stored value if checkOfflineNotifications is true and there is a stored value',
            () async {
          var notificationServiceImpl = await NotificationServiceImpl.create(
              mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

          notificationServiceImpl.stopAllSubscriptions();

          mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = true;

          int epochMillis = DateTime.now().millisecondsSinceEpoch;
          var atNotification = at_notification.AtNotification(Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);
          await mockAtClientImpl.put(AtKey()..key = NotificationServiceImpl.notificationIdKey,
              jsonEncode(atNotification.toJson()));

          expect(await notificationServiceImpl.getLastNotificationTime(), epochMillis);
        });
  });
}
