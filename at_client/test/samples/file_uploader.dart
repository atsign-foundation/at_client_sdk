import 'dart:io';

import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getAlicePreference();
    var atsign = '@alice🛠';
    //1.
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await(AtClientImpl.getClient(atsign));
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    await Future.delayed(Duration(seconds: 5));
    var file1 = File('test/data/hello.txt');
    var file2 = File('test/data/cat.jpeg');
    var fileList = <File>[]..add(file1)..add(file2);
    var sharedTo = <String>[]..add('@bob🛠');
    var fileTransferResult = await atClient.uploadFile(fileList, sharedTo);
    fileTransferResult.forEach((key, value) {
      print('atsign: $key');
      print('result: $value');
    });
    await Future.delayed(Duration(seconds: 10));
    print('upload done');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void onDone(var sync) {
  print('sync done');
}

void onError(var sync, var error) {
  print('sync done');
}
