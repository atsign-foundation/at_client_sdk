import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_commons.dart';

import '../test_util.dart';

void main() async {
  try {
    var aliceAtSign = '@alice🛠', bobAtSign = '@bob🛠';
    // create alice client
    await AtClientImpl.createClient(
        aliceAtSign, 'wavi', TestUtil.getAlicePreference());
    var aliceClient = await (AtClientImpl.getClient(aliceAtSign));
    aliceClient!.getSyncManager()!.init(
        aliceAtSign,
        TestUtil.getAlicePreference(),
        aliceClient.getRemoteSecondary(),
        aliceClient.getLocalSecondary());

    // create bob client
    await AtClientImpl.createClient(
        bobAtSign, 'wavi', TestUtil.getBobPreference());
    var bobClient = await (AtClientImpl.getClient(bobAtSign));
    bobClient!.getSyncManager()!.init(bobAtSign, TestUtil.getBobPreference(),
        bobClient.getRemoteSecondary(), bobClient.getLocalSecondary());
    // alice - listen for notification
    final aliceNotificationService = NotificationServiceImpl(aliceClient);
    aliceNotificationService.listen(_notificationCallback, regex: '.wavi');
    // bob - notify to alice.two keys. 1 without namespace. 1 with namespace
    final bobNotificationService = NotificationServiceImpl(bobClient);
    var notificationKey = AtKey()
      ..key = 'phone'
      ..sharedWith = aliceAtSign;
    ;
    var notificationResult = await bobNotificationService
        .notify(NotificationParams.forUpdate(notificationKey));
    print('notification result: $notificationResult');
    final metaData = Metadata()..namespaceAware = true;
    ;
    var notificationKeyWithNamespace = AtKey()
      ..key = 'email'
      ..sharedWith = aliceAtSign
      ..namespace = 'wavi'
      ..metadata = metaData;
    var notificationResultNamespace = await bobNotificationService
        .notify(NotificationParams.forUpdate(notificationKeyWithNamespace));
    print('notification with namespace result: $notificationResultNamespace');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('alice notification received: ${notification.toString()}');
}
