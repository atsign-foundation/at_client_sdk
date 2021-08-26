import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';

import '../test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'wavi', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient('@alice🛠'));

    final notificationService = NotificationServiceImpl(atClient!);
    notificationService.subscribe().listen((notification) {
      _notificationCallback(notification);
    });
    notificationService.subscribe(regex: '.wavi').listen((notification) {
      _notificationCallback(notification);
    });
    print('stopping monitor');
    Future.delayed(Duration(seconds: 5), () => notificationService.stop());
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('notification received: ${notification.toString()}');
}
