import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
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

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {}

class MockAtClientImpl extends Mock implements AtClientImpl {
  @override
  AtClientPreference getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }

  @override
  String? getCurrentAtSign() {
    return '@alice';
  }
}

class MockLocalSecondary extends Mock implements LocalSecondary {}

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
}
