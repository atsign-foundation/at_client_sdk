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

    // create bob client
    await AtClientImpl.createClient(
        bobAtSign, 'wavi', TestUtil.getBobPreference());
    var bobClient = await (AtClientImpl.getClient(bobAtSign));

    // alice - listen for notification
    final aliceNotificationService = await NotificationServiceImpl.create(aliceClient!);
    aliceNotificationService.subscribe().listen((notification) {
      _notificationCallback(notification);
    });
    // bob - notify to alice
    final bobNotificationService = await NotificationServiceImpl.create(bobClient!);
    var notificationKey = AtKey()
      ..key = 'phone'
      ..sharedWith = aliceAtSign;
    await bobNotificationService
        .notify(NotificationParams.forUpdate(notificationKey));
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void _notificationCallback(AtNotification notification) {
  print('alice notification received: ${notification.toString()}');
}
