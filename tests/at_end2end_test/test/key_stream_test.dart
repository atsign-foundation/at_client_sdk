// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/key_stream/key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_iterable_base.dart';
import 'package:at_client/src/key_stream/key_stream_map_base.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late AtClientManager atClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
  });

  group('KeyStreamMixin group', () {
    late KeyStreamImpl<String> keyStream;
    var uuid;
    var randomValue, randomValue2;
    var key, key2;
    var keySuffix;

    setUpAll(() {
      uuid = Uuid();
      keySuffix = uuid.v4();
      randomValue = uuid.v4();
      randomValue2 = uuid.v4();
      key = AtKey()
        ..key = randomValue + keySuffix
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      key2 = AtKey()
        ..key = randomValue2 + keySuffix
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      keyStream = KeyStreamImpl<String>(
        regex: keySuffix + '.' + namespace + '@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
      keyStream.disposeOnAtsignChange = false;
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      expect(keyStream, isA<KeyStreamMixin<String?>>());
      expect(keyStream.isPaused, false);
    });

    test('pause notifications', () {
      keyStream.pause();
      expect(keyStream.isPaused, true);
    });

    test('resume notifications', () {
      keyStream.resume();
      expect(keyStream.isPaused, false);
    });

    test('getKeys', () async {
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(currentAtSign, namespace,
              TestPreferences.getInstance().getPreference(currentAtSign));
      await Future.wait([
        atClientManager.atClient.put(key, randomValue),
        atClientManager.atClient.put(key2, randomValue2)
      ]);

      await E2ESyncService.getInstance()
          .syncData(atClientManager.atClient.syncService);

      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      await keyStream.getKeys();
      expect(keyStream, emitsInAnyOrder([randomValue, randomValue2]));
    });

    test('dispose', () async {
      await keyStream.dispose();
      expect(keyStream.controller.isClosed, true);
    });
  });

  group('KeyStream', () {
    late KeyStreamImpl<String> keyStream;
    var uuid;
    var randomValue;
    var key;

    setUpAll(() async {
      uuid = Uuid();
      randomValue = uuid.v4();
      key = AtKey()
        ..key = randomValue
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));
      keyStream = KeyStreamImpl(
        regex: '$namespace@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(
          key, AtValue()..value = randomValue, 'update');
      await Future.delayed(Duration(milliseconds: 500));
      keyStream.handleNotification(key, AtValue(), 'delete');
      expect(keyStream, emitsInOrder([randomValue, null]));
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  group('KeyStreamIterable group', () {
    late IterableKeyStream<String> keyStream;
    var uuid;
    var randomValue;
    var key;

    setUpAll(() async {
      uuid = Uuid();
      randomValue = uuid.v4();
      key = AtKey()
        ..key = randomValue
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));
      keyStream = IterableKeyStream<String>(
        regex: '$namespace@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      expect(keyStream, isA<KeyStreamIterableBase<String, Iterable<String>>>());
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(
          key, AtValue()..value = randomValue, 'update');
      keyStream.handleNotification(key, AtValue(), 'delete');
      expect(
        keyStream,
        emitsInOrder([
          allOf(TypeMatcher<Iterable>(), containsAll([randomValue])),
          allOf(TypeMatcher<Iterable>(), isEmpty),
        ]),
      );
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  group('KeyStreamMap group', () {
    late MapKeyStream<String, String> keyStream;
    var uuid;
    var randomValue;
    var key;

    setUpAll(() async {
      uuid = Uuid();
      randomValue = uuid.v4();
      key = AtKey()
        ..key = randomValue
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));
      keyStream = MapKeyStream<String, String>(
        regex: '$namespace@',
        convert: (key, value) => MapEntry(key.key, value.value),
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      expect(keyStream,
          isA<KeyStreamMapBase<String, String, Map<String, String>>>());
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(
          key, AtValue()..value = randomValue, 'update');
      keyStream.handleNotification(key, AtValue(), 'delete');
      expect(
        keyStream,
        emitsInOrder([
          allOf(isMap, containsPair(randomValue, randomValue)),
          allOf(isMap, isEmpty),
        ]),
      );
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  group('Switch atsigns group', () {
    var currentAtSign, sharedWithAtSign;
    var namespace = 'keyStream';
    late KeyStreamImpl<String> keyStream, keyStream2, keyStream3;
    var uuid;
    var randomValue2, randomValue3;
    var key2, key3;

    setUpAll(() async {
      uuid = Uuid();
      randomValue2 = uuid.v4();
      randomValue3 = uuid.v4();
      key2 = AtKey()
        ..key = randomValue2
        ..sharedWith = currentAtSign
        ..namespace = namespace
        ..sharedBy = sharedWithAtSign;
      key3 = AtKey()
        ..key = randomValue3
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
      sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
      // Create atClient instance for currentAtSign
      await AtClientManager.getInstance()
          .setCurrentAtSign(currentAtSign, namespace,
              TestPreferences.getInstance().getPreference(currentAtSign));

      // Create atClient instance for atSign2
      await AtClientManager.getInstance()
          .setCurrentAtSign(sharedWithAtSign, namespace,
              TestPreferences.getInstance().getPreference(sharedWithAtSign));
      // Set Encryption Keys for sharedWithAtSign
      keyStream = KeyStreamImpl(
        regex: '$namespace@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('', () async {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          sharedWithAtSign);
      expect(keyStream, isA<KeyStreamMixin<String?>>());
      expect(keyStream.isPaused, false);

      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(currentAtSign));
      await Future.delayed(Duration(milliseconds: 1));
      expect(keyStream.controller.isClosed, true);

      keyStream2 = KeyStreamImpl(
        regex: '$namespace@',
        convert: (key, value) => value.value ?? '',
        sharedBy: sharedWithAtSign,
        sharedWith: currentAtSign,
        shouldGetKeys: false,
      );
      keyStream2.handleNotification(
          key2, AtValue()..value = randomValue2, 'update');
      expect(keyStream2, emitsInOrder([randomValue2]));

      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));
      await Future.delayed(Duration(milliseconds: 1));
      expect(keyStream2.controller.isClosed, true);
      expect(keyStream.controller.isClosed, true);

      keyStream3 = KeyStreamImpl(
        regex: '$namespace@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );

      keyStream3.handleNotification(
          key3, AtValue()..value = randomValue3, 'update');
      expect(keyStream3, emitsInOrder([randomValue3]));
      await keyStream3.dispose();
    }, timeout: Timeout(Duration(minutes: 7)));
  });
}
