import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';

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
    aliceNotificationService.subscribe(regex: '.wavi').listen((notification) {
      _waviCallback(notification);
    });
    aliceNotificationService.subscribe(regex: '.buzz').listen((notification) {
      _buzzCallBack(notification);
    });
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _waviCallback(AtNotification notification) {
  print('wavi notification received: ${notification.toString()}');
}

void _buzzCallBack(AtNotification notification) {
  print('buzz notification received: ${notification.toString()}');
}
