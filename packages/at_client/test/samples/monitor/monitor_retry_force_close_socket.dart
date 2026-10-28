import 'package:at_client/at_client.dart';
import '../test_util.dart';
import '../../test_utils/hive_store.dart';
import '../../test_utils/no_keys.dart';

void main() async {
  try {
    final aliceAtSign = '@alice🛠';
    final atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: TestUtil.getAlicePreference(),
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, TestUtil.getAlicePreference())));

    atClientManager.atClient.notificationService
        .subscribe()
        .listen((notification) {
      _notificationCallback(notification);
    });
    atClientManager.atClient.notificationService
        .subscribe(regex: '.wavi')
        .listen((notification) {
      _notificationCallback(notification);
    });
    print('stopping monitor');
    Future.delayed(
        Duration(seconds: 5),
        () => atClientManager.atClient.notificationService
            .stopAllSubscriptions());
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('notification received: ${notification.toString()}');
}
