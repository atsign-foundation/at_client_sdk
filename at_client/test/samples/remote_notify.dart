import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getAlicePreference();
    var atSign = '@alice';
    await AtClientImpl.createClient(atSign, null, preference);
    var atClient = await AtClientImpl.getClient(atSign);
    var atKey = AtKey()
      ..key = 'test_key'
      ..sharedWith = '@bob'
      ..sharedBy = atSign;
    var notificationId;
    await atClient.notify(atKey, 'test_value', OperationEnum.append,
        (String id) {
      notificationId = id;
      print('id : $id');
    }, (String e) {
      print('exception : $e');
    });
    if (notificationId != null) {
      await atClient.notifyStatus(notificationId, (String status) {
        print('notification status : $status');
      }, (String e) {
        print('exception : $e');
      });
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
