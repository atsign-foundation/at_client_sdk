import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/change_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() async {
  late ChangeServiceImpl changeServiceImpl;

  group('A group of positive tests related to delete', () {
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

    test('Delete a cached key', () {
      var metaData = Metadata()..isCached = true;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metaData;
      changeServiceImpl.delete(atKey);
    });

    test('Delete a public key', () {
      var metaData = Metadata()..isPublic = true;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metaData;
      changeServiceImpl.delete(atKey);
    });

    test('Delete a key-sharedWith and sharedBy populated', () {
      var metaData = Metadata()..isPublic = true;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice'
        ..metadata = metaData;
      changeServiceImpl.delete(atKey);
    });

    test('Delete a key with nameSpaceAware is set to false', () {
      var metaData = Metadata()..namespaceAware = true;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice'
        ..metadata = metaData;
      changeServiceImpl.delete(atKey);
    });

    tearDown(() {
      var isExists = Directory('test/hive').existsSync();
      if (isExists) {
        Directory('test/hive').deleteSync(recursive: true);
      }
    });
  });
}
