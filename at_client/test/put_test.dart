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

  group('A group of tests related to invalid key', () {
    test('Throws AtKeyException when key contains spaces', () {
      var atKey = AtKey()..key = 'pho ne';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == 'Key cannot contain whitespaces')));
    });

    test('Throws AtKeyException when key contains @', () {
      var atKey = AtKey()..key = '@phone';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException && e.message == 'Key cannot contain @')));
    });

    test(
        'Throws AtKeyException when updating a cached key - isCached in metadata is true',
        () {
      var metadata = Metadata()..isCached = true;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metadata;
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == 'Cannot update a cached key.')));
    });

    test(
        'Throws AtKeyException when updating a cached key - key starts with cached',
        () {
      var atKey = AtKey()..key = 'cached:phone';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == 'Cannot update a cached key.')));
    });
  });

  group('A group of tests related to invalid metadata', () {
    test('Test to verify invalid ttl value', () {
      var metadata = Metadata()..ttl = -100;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metadata;
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTL value: ${metadata.ttl}. TTL value cannot be less than 0')));
    });

    test('Test to verify invalid ttb value', () {
      var metadata = Metadata()..ttb = -100;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metadata;
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTB value: ${metadata.ttb}. TTB value cannot be less than 0')));
    });

    test('Test to verify invalid ttr value', () {
      var metadata = Metadata()..ttr = -100;
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..metadata = metadata;
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid TTR value: ${metadata.ttr}. valid values for TTR are -1 and greater than or equal to 1')));
    });
  });
  group('A group of tests related to invalid sharedWith atSign', () {
    test('Test to verify the invalid sharedWith atSign - no more than one @',
        () {
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@b@b';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == AtMessage.moreThanOneAt.text)));
    });
    test('Test to verify the invalid sharedWith atSign - whitespace in atSign',
        () {
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob ross';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == AtMessage.whiteSpaceNotAllowed.text)));
    });
    test(
        'Test to verify the invalid sharedWith atSign - reserved characters not allowed',
        () {
      var atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob\$';
      var value = '+1 234 999 9999';
      expect(
          () => changeServiceImpl.put(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtKeyException &&
              e.message == AtMessage.reservedCharacterUsed.text)));
    });
  });

  tearDown(() {
    var isExists = Directory('test/hive').existsSync();
    if (isExists) {
      Directory('test/hive').deleteSync(recursive: true);
    }
  });
}
