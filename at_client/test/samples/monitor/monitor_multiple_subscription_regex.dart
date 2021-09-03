import 'package:at_client/at_client.dart';
import '../test_util.dart';

void main() async {
  try {
    final aliceAtSign = '@alice🛠';
    // create alice client
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(aliceAtSign, 'wavi', TestUtil.getAlicePreference());
    // alice - listen for notification
    atClientManager.notificationService
        .subscribe(regex: '.wavi')
        .listen((notification) {
      _waviCallback(notification);
    });
    atClientManager.notificationService
        .subscribe(regex: '.buzz')
        .listen((notification) {
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
