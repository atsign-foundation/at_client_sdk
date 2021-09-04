import 'package:at_client/at_client.dart';
import '../test_util.dart';

void main() async {
  try {
    final aliceAtSign = '@alice🛠';
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(aliceAtSign, 'wavi', TestUtil.getAlicePreference());

    atClientManager.notificationService.subscribe().listen((notification) {
      _notificationCallback(notification);
    });
    atClientManager.notificationService
        .subscribe(regex: '.wavi')
        .listen((notification) {
      _notificationCallback(notification);
    });
    print('stopping monitor');
    Future.delayed(Duration(seconds: 5),
        () => atClientManager.notificationService.stopAllSubscriptions());
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('notification received: ${notification.toString()}');
}
