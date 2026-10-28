import 'package:at_client/at_client_io.dart';
import '../test_util.dart';
import '../../test_utils/hive_store.dart';
import '../../test_utils/no_keys.dart';
import '../../test_utils/transport.dart';

void main() async {
  try {
    final aliceAtSign = '@alice🛠';
    // create alice client
    final atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: TestUtil.getAlicePreference(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(TestUtil.getAlicePreference()),
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, TestUtil.getAlicePreference())));
    // alice - listen for notification
    atClientManager.atClient.notificationService
        .subscribe(regex: '.wavi')
        .listen((notification) {
      _waviCallback(notification);
    });
    atClientManager.atClient.notificationService
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
