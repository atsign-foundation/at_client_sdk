import 'dart:io';

import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getAlicePreference();
    var atsign = '@alice🛠';
    //1.
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    await Future.delayed(Duration(seconds: 5));
    var file1 = File('test/data/hello.txt');
    var file2 = File('test/data/cat.jpeg');
    var fileList = <File>[file1, file2];
    var sharedTo = <String>['@bob🛠'];
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
