import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    var atSign = '@alice🛠';
    await AtClientImpl.createClient(
        atSign, 'atmosphere', TestUtil.getAlicePreference());
    AtClientImpl atClient = await AtClientImpl.getClient(atSign);
    await atClient.getSyncManager().init(atSign, TestUtil.getAlicePreference(),
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    var file = File('/home/murali/work/2021/@/file_upload/hello.txt');
    print('uploading');
    var atSignList = <String>[];
    atSignList.add('@bob🛠');
    atSignList.add('@colin🛠');
    await atClient.uploadFileMultiple(file, atSignList);
    print('upload complete');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
