import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:at_client/src/key_stream/key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_iterable_base.dart';
import 'package:at_client/src/key_stream/key_stream_map_base.dart';
import 'package:at_client/src/key_stream/collection/map_key_stream_impl.dart' hide castTo;
import 'package:at_client/src/key_stream/collection/iterable_key_stream_impl.dart' hide castTo;
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:at_utils/at_logger.dart';

import 'test_utils.dart';

void main() {
  var currentAtSign, sharedWithAtSign;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'keyStream';

  setUpAll(() async {
    AtSignLogger.root_level = 'all';
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    // Create atClient instance for atSign2
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    // Set Encryption Keys for sharedWithAtSign
    await TestUtils.setEncryptionKeys(sharedWithAtSign);
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
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
      key = AtKey()
        ..key = randomValue + keySuffix
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      randomValue2 = uuid.v4();
      key2 = AtKey()
        ..key = randomValue2 + keySuffix
        ..sharedWith = sharedWithAtSign
        ..namespace = namespace
        ..sharedBy = currentAtSign;
      keyStream = KeyStreamImpl<String>(
        regex: keySuffix + '\\.' + namespace + '@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(), sharedWithAtSign);
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
      setUp(() async {
        await AtClientManager.getInstance()
            .setCurrentAtSign(currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
        await Future.wait([
          currentAtSignClientManager!.atClient.put(key, randomValue),
          currentAtSignClientManager!.atClient.put(key2, randomValue2)
        ]);
        await AtClientManager.getInstance()
            .setCurrentAtSign(sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
      });
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(), sharedWithAtSign);
      await keyStream.getKeys();
      expect(keyStream, emitsInAnyOrder([randomValue, randomValue2]));
    }, timeout: Timeout.factor(2));

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
      await AtClientManager.getInstance()
          .setCurrentAtSign(sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
      keyStream = KeyStreamImpl(
        regex: namespace + '@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(), sharedWithAtSign);
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(key, AtValue()..value = randomValue, 'update');
      keyStream.handleNotification(AtKey()..key = randomValue, AtValue(), 'delete');
      expect(keyStream, emitsInOrder([randomValue, null]));
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  group('KeyStreamIterable group', () {
    late IterableKeyStreamImpl<String> keyStream;
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
      await AtClientManager.getInstance()
          .setCurrentAtSign(sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
      keyStream = IterableKeyStreamImpl<String>(
        regex: namespace + '@',
        convert: (key, value) => value.value ?? '',
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(), sharedWithAtSign);
      expect(keyStream, isA<KeyStreamIterableBase<String, Iterable<String>>>());
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(key, AtValue()..value = randomValue, 'update');
      keyStream.handleNotification(AtKey()..key = randomValue, AtValue(), 'delete');
      expect(
        keyStream,
        emitsInOrder([
          allOf(TypeMatcher<Iterable>(), contains(randomValue)),
          allOf(TypeMatcher<Iterable>(), isEmpty),
        ]),
      );
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  group('KeyStreamMap group', () {
    late MapKeyStreamImpl<String, String> keyStream;
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
      await AtClientManager.getInstance()
          .setCurrentAtSign(sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
      keyStream = MapKeyStreamImpl<String, String>(
        regex: namespace + '@',
        convert: (key, value) => MapEntry(key.key!, value.value),
        sharedBy: currentAtSign,
        sharedWith: sharedWithAtSign,
        shouldGetKeys: false,
      );
    });

    test('init', () {
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(), sharedWithAtSign);
      expect(keyStream, isA<KeyStreamMapBase<String, String, Map<String, String>>>());
      expect(keyStream.isPaused, false);
    });

    test('handleNotification', () async {
      keyStream.handleNotification(key, AtValue()..value = randomValue, 'update');
      keyStream.handleNotification(AtKey()..key = randomValue, AtValue(), 'delete');
      expect(
        keyStream,
        emitsInOrder([
          allOf(isMap, containsPair(key, randomValue)),
          allOf(isMap, isEmpty),
        ]),
      );
    });

    tearDownAll(() async {
      await keyStream.dispose();
    });
  });

  tearDownAll(() {
    AtSignLogger.root_level = 'info';
  });
}
