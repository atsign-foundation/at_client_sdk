import 'dart:convert';

import 'package:at_client/at_client.dart';
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

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {}

class MockLocalSecondary extends Mock implements LocalSecondary {
  @override
  SecondaryKeyStore? keyStore = MockSecondaryKeyStore();
}

class MockAtClientImpl extends Mock implements AtClientImpl {
  AtClientPreference mockPreferences = AtClientPreference()..namespace = 'wavi';

  @override
  AtClientPreference getPreferences() {
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
  MockMonitor mockMonitor = MockMonitor();
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
      var notifyVerbBuilder = await NotificationRequestTransformer(
              '@alice',
              AtClientPreference()..namespace = 'wavi',
              SharedKeyEncryption(mockAtClientImpl))
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
      //UPPER_CASE in the forText() method will be preserved
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
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);
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
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);
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
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);
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
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);
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
      var notificationResponseTransformer =
          NotificationResponseTransformer(mockAtClientImpl);
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

      var transformedNotification =
          await notificationResponseTransformer.transform(Tuple()
            ..one = atNotification
            ..two = (NotificationConfig()..regex = '.*'));
      expect(transformedNotification.id, '124');
      expect(transformedNotification.key, 'key-1');
    });

    test('A test to verify the reserved key is not decrypted', () async {
      var isEncrypted = true;
      var atNotification = at_notification.AtNotification(
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
      notificationResponseTransformer.atKeyDecryption = mockSharedKeyDecryption;

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
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);

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
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(any())).thenAnswer((_) => true);

      notificationServiceImpl.stopAllSubscriptions();

      mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = false;

      expect(await notificationServiceImpl.getLastNotificationTime(), null);
    });

    test(
        'getLastNotificationTime() returns null if checkOfflineNotifications is true but there is no stored value',
        () async {
      registerFallbackValue(FakeAtKey());
      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      notificationServiceImpl.stopAllSubscriptions();

      mockAtClientImpl.getPreferences()!.fetchOfflineNotifications = true;

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(any())).thenAnswer((_) => true);

      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

      expect(await notificationServiceImpl.getLastNotificationTime(), null);
    });

    /// The test case verifies the following:
    /// When a new key (local:lastReceivedNotification) exists and return null,
    /// fetch the data from the old key return epochMillis.
    test(
        'getLastNotificationTime() returns the stored value from old key if checkOfflineNotifications is true and there is a stored value',
        () async {
      //mimic the old latestNotificationIdKey
      String lastNotificationKey = '_latestNotificationIdv2.wavi@alice';
      AtKey oldNotificationAtKey = AtKey.fromString(lastNotificationKey);

      registerFallbackValue(oldNotificationAtKey);
      int epochMillis = DateTime.now().millisecondsSinceEpoch;
      var atNotification = at_notification.AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.get(oldNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(any())).thenAnswer((_) => true);

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
      var atNotification = at_notification.AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl
              .get(notificationServiceImpl.lastReceivedNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(any())).thenAnswer((_) => true);

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
      var atNotification = at_notification.AtNotification(
          Uuid().v4(), '', '@bob', '@alice', epochMillis, 'update', true);

      var notificationServiceImpl = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: mockAtClientManager,
          monitor: mockMonitor) as NotificationServiceImpl;

      when(() => mockAtClientImpl.getLocalSecondary()!.keyStore!.isKeyExists(
              notificationServiceImpl.lastReceivedNotificationAtKey.toString()))
          .thenAnswer((_) => false);

      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(lastNotificationKey)).thenAnswer((_) => true);

      when(() => mockAtClientImpl.get(lastNotificationAtKey))
          .thenAnswer((_) async => Future.value(AtValue()
            ..value = jsonEncode(atNotification)
            ..metadata = Metadata()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);

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
          'local:lastReceivedNotification.wavi@alice'.toLowerCase());
    });

    test('test to verify lastNotificationReceived fromString', () {
      var lastReceivedNotification =
          AtKey.fromString('local:lastReceivedNotification.wavi@alice');
      expect(lastReceivedNotification.key,
          NotificationServiceImpl.lastReceivedNotificationKey);
      expect(lastReceivedNotification.namespace, 'wavi');
      expect(lastReceivedNotification.isLocal, true);
    });
  });

  group('Tests for monitorRetry', () {
    setUpAll(() {
      when(() => mockAtClientManager.atClient)
          .thenAnswer((_) => mockAtClientImpl);
      when(() => mockAtClientImpl
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(any())).thenAnswer((_) => true);

      registerFallbackValue(FakeAtKey());
      when(() => mockAtClientImpl.get(any()))
          .thenAnswer((_) async => Future.value(AtValue()));

      when(() => mockAtClientImpl.put(any(), any()))
          .thenAnswer((_) async => true);
    });

    test('Test initial state related to monitorRetry', () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;
      expect(notificationServiceImpl.callsToMonitorRetry, 0);
      expect(notificationServiceImpl.monitorRestartQueued, false);
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 0);
    });

    test(
        'Test that _monitorRetry will queue a call to Monitor.start if monitorRestartQueued is false',
        () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

      // Set monitorIsPaused to false, since it isn't explicitly set to false
      // until NotificationServiceImpl._init runs.
      notificationServiceImpl.monitorIsPaused = false;

      notificationServiceImpl.monitorRetryInterval = Duration(milliseconds: 50);
      notificationServiceImpl.monitorRetry();
      expect(notificationServiceImpl.callsToMonitorRetry, 1);
      expect(notificationServiceImpl.monitorRestartQueued, true);
      // Let's also verify that Monitor.start hasn't yet been actually called.
      await (Future.delayed(Duration(milliseconds: 10)));
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 0);
      // Let's wait for monitorRetryInterval
      await (Future.delayed(notificationServiceImpl.monitorRetryInterval));
      // The call to monitor.start() should now have happened
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 1);
    });

    test(
        'Test that _monitorRetry will NOT queue a call to Monitor.start if monitorRestartQueued is true',
        () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

      // Set monitorIsPaused to false, since it isn't explicitly set to false
      // until NotificationServiceImpl._init runs.
      notificationServiceImpl.monitorIsPaused = false;

      expect(notificationServiceImpl.monitorRestartQueued, false);

      // First call to monitorRetry should queue a call to Monitor.start and therefore return true
      expect(notificationServiceImpl.monitorRetry(), true);
      expect(notificationServiceImpl.callsToMonitorRetry, 1);
      // and monitorRestartQueued should now be true
      expect(notificationServiceImpl.monitorRestartQueued, true);

      // Now let's call monitorRetry() again. This time, as there is already a call queued, it should return false
      expect(notificationServiceImpl.monitorRetry(), false);
      expect(notificationServiceImpl.callsToMonitorRetry, 2);
      // monitorRestartQueued should still be true
      expect(notificationServiceImpl.monitorRestartQueued, true);
    });

    test(
        'Test that _monitorRetry will NOT queue a call to Monitor.start if the monitor has been paused',
        () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

      // Set monitorIsPaused to false, since it isn't explicitly set to false
      // until NotificationServiceImpl._init runs.
      notificationServiceImpl.monitorIsPaused = false;

      expect(notificationServiceImpl.monitorIsPaused, false);
      expect(notificationServiceImpl.monitorRestartQueued, false);

      // NotificationServiceImpl sets monitorIsPaused to true when all of its subscriptions are stopped
      notificationServiceImpl.stopAllSubscriptions();

      expect(notificationServiceImpl.monitorIsPaused, true);
      expect(notificationServiceImpl.monitorRestartQueued, false);

      // let's call monitorRetry(). Since the notification service's monitor is paused, monitorRetry
      // will return false, and will not try to queue a monitor restart
      expect(notificationServiceImpl.monitorRetry(), false);
      expect(notificationServiceImpl.callsToMonitorRetry, 1);
      // monitorRestartQueued should still be true
      expect(notificationServiceImpl.monitorRestartQueued, false);
    });

    test(
        'Test that the delayed future will NOT call Monitor.start if the monitor has since been paused',
        () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

      // Set monitorIsPaused to false, since it isn't explicitly set to false
      // until NotificationServiceImpl._init runs.
      notificationServiceImpl.monitorIsPaused = false;

      notificationServiceImpl.monitorRetryInterval = Duration(milliseconds: 50);

      expect(notificationServiceImpl.monitorIsPaused, false);
      expect(notificationServiceImpl.monitorRestartQueued, false);

      expect(notificationServiceImpl.monitorRetry(), true);

      // NotificationServiceImpl sets monitorIsPaused to true when all of its subscriptions are stopped
      notificationServiceImpl.stopAllSubscriptions();

      expect(notificationServiceImpl.monitorIsPaused, true);
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 0);
      expect(notificationServiceImpl.monitorRestartQueued, true);

      // Let's wait for slightly longer than monitorRetryInterval
      await (Future.delayed(notificationServiceImpl.monitorRetryInterval +
          Duration(milliseconds: 10)));
      //
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 0);
      expect(notificationServiceImpl.monitorRestartQueued, false);
    });

    test(
        'Test that _monitorRetry will reset monitorRestartQueued to false when it finally makes its call to Monitor.start',
        () async {
      NotificationServiceImpl notificationServiceImpl =
          await NotificationServiceImpl.create(mockAtClientImpl,
              atClientManager: mockAtClientManager,
              monitor: mockMonitor) as NotificationServiceImpl;

      // Set monitorIsPaused to false, since it isn't explicitly set to false
      // until NotificationServiceImpl._init runs.
      notificationServiceImpl.monitorIsPaused = false;

      notificationServiceImpl.monitorRetryInterval = Duration(milliseconds: 50);

      notificationServiceImpl.monitorRetry();
      expect(notificationServiceImpl.callsToMonitorRetry, 1);
      expect(notificationServiceImpl.monitorRestartQueued, true);

      notificationServiceImpl.monitorRetry();
      expect(notificationServiceImpl.callsToMonitorRetry, 2);
      expect(notificationServiceImpl.monitorRestartQueued, true);

      // Let's wait for monitorRetryInterval
      await (Future.delayed(notificationServiceImpl.monitorRetryInterval));
      // We should have had one call to Monitor.start()
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 1);
      // And we should have no calls queued
      expect(notificationServiceImpl.monitorRestartQueued, false);

      // Let's wait for monitorRetryInterval again
      await (Future.delayed(notificationServiceImpl.monitorRetryInterval));
      // We should still only have had one call to Monitor.start()
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 1);
      // And we should have no calls queued
      expect(notificationServiceImpl.monitorRestartQueued, false);

      // Let's request another retry
      notificationServiceImpl.monitorRetry();
      expect(notificationServiceImpl.callsToMonitorRetry, 3);
      expect(notificationServiceImpl.monitorRestartQueued, true);
      // Let's wait for monitorRetryInterval
      await (Future.delayed(notificationServiceImpl.monitorRetryInterval));
      // We should have had one more call to Monitor.start()
      expect(notificationServiceImpl.monitorRetryCallsToMonitorStart, 2);
      // And we should have no calls queued
      expect(notificationServiceImpl.monitorRestartQueued, false);
    });
  });
}