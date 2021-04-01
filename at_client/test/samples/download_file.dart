import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    var atSign = '@bob🛠';
    await AtClientImpl.createClient(
        atSign, 'atmosphere', TestUtil.getBobPreference());
    AtClientImpl atClient = await AtClientImpl.getClient(atSign);
    await atClient.getSyncManager().init( atSign, TestUtil.getBobPreference(),
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    await atClient.downloadFile('hello.txt', '@alice🛠',downloadPath: '/home/murali/work/2021/@/file_upload/decrypted/');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
