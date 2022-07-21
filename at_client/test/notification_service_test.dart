import 'dart:convert';

import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

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

  var atKey = AtKey.fromString('_latestNotificationIdv2.wavi@alice');

  @override
  Future<AtValue> get(atKey,
      {GetRequestOptions? getRequestOptions, bool isDedicated = false}) async {
    var atNotificationMap = at_notification.AtNotification(
            '123',
            '@bob:phone@alice',
            '@bob',
            '@alice',
            DateTime.now().millisecondsSinceEpoch,
            'MessageType.key',
            false)
        .toJson();
    AtValue atValue = AtValue()..value = jsonEncode(atNotificationMap);
    return atValue;
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

class MockSharedKeyEncryption extends Mock implements SharedKeyEncryption {
  @override
  Future encrypt(AtKey atKey, value) async {
    //Set encryptionMetadata to atKey metadata
    atKey.metadata = Metadata()
      ..sharedKeyEnc = 'sharedKeyEnc'
      ..pubKeyCS = 'publicKeyCS';
    return 'encryptedValue';
  }
}

class MockSharedKeyDecryption extends Mock implements SharedKeyDecryption {
  @override
  Future decrypt(AtKey atKey, encryptedValue) async {
    return 'decryptedValue';
  }
}

void main() {
  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
  SharedKeyEncryption mockSharedKeyEncryption = MockSharedKeyEncryption();
  SharedKeyDecryption mockSharedKeyDecryption = MockSharedKeyDecryption();

  setUp(() {
    registerFallbackValue(AtKey());
    when(() => mockAtClientImpl.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);

    when(() => mockLocalSecondary.keyStore)
        .thenAnswer((_) => mockSecondaryKeyStore);

    when(() => mockSecondaryKeyStore.isKeyExists(
        '_latestNotificationIdv2.wavi@alice')).thenAnswer((_) => true);
  });

  group('a group of test to validate notification request processor', () {
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
          value: '+91908909933');
      var notifyVerbBuilder = await NotificationRequestTransformer('@alice',
              AtClientPreference()..namespace = 'wavi', mockSharedKeyEncryption)
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
      var notifyVerbBuilder = await NotificationRequestTransformer('@alice',
              AtClientPreference()..namespace = 'wavi', mockSharedKeyEncryption)
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
      var notifyVerbBuilder = await NotificationRequestTransformer('@alice',
              AtClientPreference()..namespace = 'wavi', mockSharedKeyEncryption)
          .transform(notificationParams);
      expect(notifyVerbBuilder.atKey, 'encryptedValue');
      expect(notifyVerbBuilder.sharedWith, '@bob');
      expect(notifyVerbBuilder.messageType, MessageTypeEnum.text);
      expect(notifyVerbBuilder.priority, PriorityEnum.low);
      expect(notifyVerbBuilder.strategy, StrategyEnum.all);
    });
  });

  group('A group of test to validate notification response transformer', () {
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
}
