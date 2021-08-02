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
    var _remoteSecondary = RemoteSecondary(atSign, preferences);
    var _localSecondary = LocalSecondary(atSign, preferences);
    atClient!
        .getSyncManager()!
        .init(atSign, preferences, _remoteSecondary, _localSecondary);
    changeServiceImpl = ChangeServiceImpl(atClient);
  });

  group('A group of positive tests related to metadata', () {
    test('Update a key with TTL metadata', () {
      var metaData = Metadata()..ttl = 60000;
      var atKey = AtKey()
        ..key = 'phone'
        ..metadata = metaData;
      changeServiceImpl.putMeta(atKey);
    });

    test('Update a key with TTB metadata', () {
      var metaData = Metadata()..ttb = 60000;
      var atKey = AtKey()
        ..key = 'phone'
        ..metadata = metaData;
      changeServiceImpl.putMeta(atKey);
    });
  });

  group('A group of negative tests related to metadata', () {
    test('Update a key with invalid TTL', () {
      var metaData = Metadata()..ttl = -1;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metaData;
      expect(
          () => changeServiceImpl.putMeta(atKey),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.errorMessage ==
                  'Invalid TTL value: ${metaData.ttl}. TTL value cannot be less than 0')));
    });

    test('Update a key with invalid TTB', () {
      var metaData = Metadata()..ttb = -1;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metaData;
      expect(
              () => changeServiceImpl.putMeta(atKey),
          throwsA(predicate((dynamic e) =>
          e is AtKeyException &&
              e.errorMessage ==
                  'Invalid TTB value: ${metaData.ttb}. TTB value cannot be less than 0')));
    });

    test('Update a key with invalid TTR', () {
      var metaData = Metadata()..ttr = -2;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metaData;
      expect(
              () => changeServiceImpl.putMeta(atKey),
          throwsA(predicate((dynamic e) =>
          e is AtKeyException &&
              e.errorMessage ==
                  'Invalid TTR value: ${metaData.ttr}. valid values for TTR are -1 and greater than or equal to 1')));
    });
  });

  tearDown(() {
    var isExists = Directory('test/hive').existsSync();
    if (isExists) {
      Directory('test/hive').deleteSync(recursive: true);
    }
  });
}
