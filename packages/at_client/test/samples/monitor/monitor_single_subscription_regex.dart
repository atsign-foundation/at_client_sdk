import 'package:at_client/at_client.dart';
import '../test_util.dart';

void main() async {
  try {
    final aliceAtSign = '@alice🛠';
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(aliceAtSign, 'wavi', TestUtil.getAlicePreference());

    // alice - listen for notification
    atClientManager.notificationService
        .subscribe(regex: '.wavi')
        .listen((notification) {
      _notificationCallback(notification);
    });
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('alice notification received: ${notification.toString()}');
}
