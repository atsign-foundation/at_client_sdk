import 'dart:convert';

import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/util/network_util.dart';
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

class MockNetworkConnectivityChecker extends Mock
    implements NetworkConnectivityChecker {
  @override
  Future<bool> isNetworkAvailable() async {
    return false;
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

void main() {
  AtClientManager atClientManager = AtClientManager.getInstance();

  AtClientImpl mockAtClientImpl = MockAtClientImpl();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
  Monitor mockMonitor = MockMonitor();
  NetworkConnectivityChecker mockNetworkConnectivityChecker =
      MockNetworkConnectivityChecker();
  SharedKeyEncryption mockSharedKeyEncryption = MockSharedKeyEncryption();

  setUp(() {
    registerFallbackValue(AtKey());
    when(() => mockAtClientImpl.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);

    when(() => mockLocalSecondary.keyStore)
        .thenAnswer((_) => mockSecondaryKeyStore);

    when(() => mockSecondaryKeyStore.isKeyExists(
        '_latestNotificationIdv2.wavi@alice')).thenAnswer((_) => true);
  });

  group('A group of test to notification service', () {
    test('A test to verify network failure return exception', () async {
      var notificationService = await NotificationServiceImpl.create(
          mockAtClientImpl,
          atClientManager: atClientManager,
          monitor: mockMonitor,
          networkConnectivityChecker: mockNetworkConnectivityChecker);

      var notificationResponse = await notificationService.notify(
          NotificationParams.forUpdate((AtKey.shared('phone', namespace: 'wavi')
                ..sharedWith('@bob'))
              .build()));

      expect(notificationResponse.notificationStatusEnum,
          NotificationStatusEnum.undelivered);
      expect(notificationResponse.atClientException?.message,
          'No network availability');
      assert(notificationResponse.atClientException is AtClientException);
    });
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
}
