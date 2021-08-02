import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/change_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() async {
  late ChangeServiceImpl changeServiceImpl;
  setUp(() async {
    var atSign = '@alice';
    var preferences = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/commit'
      ..privateKey = '1234'
      ..syncStrategy = SyncStrategy.ONDEMAND
      ..isLocalStoreRequired = true;
    await AtClientImpl.createClient(atSign, 'me', preferences);
    var atClient = await (AtClientImpl.getClient(atSign));
    changeServiceImpl = ChangeServiceImpl(atClient!);
  });

  group('A group of positive tests related to delete', () {
    test('Delete a private key', () {
      var atKey = AtKey()..key = 'phone';
      changeServiceImpl.delete(atKey);
    });

    test('Delete a sharedWith key', () {
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob';
      changeServiceImpl.delete(atKey);
    });
  });

  tearDown(() {
    var isExists = Directory('test/hive').existsSync();
    if (isExists) {
      Directory('test/hive').deleteSync(recursive: true);
    }
  });
}
