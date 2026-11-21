import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show
        AtKeysSourceAbsentException,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtAuthenticator, AtLookupImpl, AtLookupMuxable;
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';
import 'loopback_flows.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class _MockAtLookUp extends Mock implements AtLookupImpl {}

/// The level and message of every record logged.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) =>
      records.add((level: '${record.level}', message: record.message));
}

/// A keychain the platform refuses to read, or whose one document does not
/// parse, is refused as unreadable, and nothing is written or sent.
///
/// Catalogue: features/at_client_flutter/keychain_entry_not_json.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const atSign = '@alice';
  const current = '@atsigns:test';
  const legacy = '@atsigns_test';
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        (MethodCall methodCall) async => methodCall.method == 'getAll'
            ? {
                'appName': 'test',
                'packageName': 'test',
                'version': '1.0.0',
                'buildNumber': '1',
              }
            : null,
      );

  late Directory support;
  late List<String> changed;
  late List<String> built;

  /// The lookups an activation built, each answering nothing but close.
  late List<_MockAtLookUp> builtLookUps;

  final logs = _RecordedLogs();

  setUpAll(() {
    KeychainStorage.isWindows = false;
    // NOTE: before anything logs; a logger binds the handler on first use.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'all';
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('keychain_unreadable_');
    PathProviderPlatform.instance = FakePathProvider(support.path);
    changed = [];
    built = [];
    builtLookUps = [];
  });

  tearDown(() => support.deleteSync(recursive: true));

  /// A keychain whose store named in [stores] answers a read as its function
  /// does, every other store holding nothing; each store written to or
  /// deleted is recorded in [changed].
  KeychainStorage keychain(Map<String, Future<String?> Function()> stores) {
    final biometricStorage = _MockBiometricStorage();
    when(
      () => biometricStorage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final name = invocation.positionalArguments.first as String;
      final file = _MockBiometricStorageFile();
      when(file.read).thenAnswer((_) => (stores[name] ?? () async => null)());
      when(() => file.write(any())).thenAnswer((_) async => changed.add(name));
      when(file.delete).thenAnswer((_) async => changed.add(name));
      return file;
    });
    return KeychainStorage(biometricStorage: biometricStorage);
  }

  Future<String?> refused() async => throw PlatformException(
    code: 'AuthError:UserCanceled',
    message: 'User canceled the operation.',
  );

  /// Builds a lookup that answers nothing but close, keeping it in
  /// [builtLookUps].
  AtLookupMuxable silentLookUps({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) {
    final lookUp = _MockAtLookUp();
    when(lookUp.close).thenAnswer((_) async {});
    builtLookUps.add(lookUp);
    return lookUp;
  }

  /// Expects the lookups an activation built to have been sent nothing.
  void expectNothingSent() {
    for (final lookUp in builtLookUps) {
      verify(lookUp.close).called(1);
      verifyNoMoreInteractions(lookUp);
    }
  }

  /// Records each connection it is asked for, and builds none.
  AtLookupMuxable recordingLookUps({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) {
    built.add(atSign);
    throw StateError('no connection was expected for $atSign');
  }

  Matcher unreadable({required Matcher message, Matcher error = anything}) =>
      isA<AtKeysUnusableException>()
          .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
          .having((e) => e.source, 'source', "this device's keychain")
          .having((e) => e.message, 'message', message)
          .having((e) => e.error, 'error', error);

  group('a legacy keychain store the platform refuses to read, the current '
      'store empty', () {
    test('control: with the legacy store empty too, the keys are absent', () {
      expect(
        KeychainAtKeysIo(keychainStorage: keychain({})).read(atSign),
        throwsA(isA<AtKeysSourceAbsentException>()),
      );
    });

    test('reading the keys throws what the platform threw', () {
      expect(
        KeychainAtKeysIo(
          keychainStorage: keychain({legacy: refused}),
        ).read(atSign),
        throwsA(isA<PlatformException>()),
      );
    });

    test('open refuses them as unreadable, before connecting', () async {
      await expectLater(
        const LoopbackFlows().open(
          atSign,
          keys: KeychainAtKeysIo(keychainStorage: keychain({legacy: refused})),
          preference: await loopbackPreference(),
          lookUps: recordingLookUps,
        ),
        throwsA(
          unreadable(
            message: allOf(
              startsWith(
                "The keys for $atSign in this device's keychain could not be "
                'read: ',
              ),
              isNot(contains('Every Atsign')),
            ),
            error: isA<PlatformException>(),
          ),
        ),
      );
      expect(built, isEmpty, reason: 'no connection is built');
    });

    test('adding keys throws, and writes nothing', () async {
      await expectLater(
        keychain({
          legacy: refused,
        }).appendAtKeysToKeychain(keys: AtKeys()..atsign = '@bob'.toAtsign()),
        throwsA(isA<PlatformException>()),
      );
      expect(changed, isEmpty, reason: 'nothing is written');
    });

    test('removing an atSign throws, and writes nothing', () async {
      await expectLater(
        keychain({legacy: refused}).removeAtsignFromKeychain(atSign),
        throwsA(isA<PlatformException>()),
      );
      expect(changed, isEmpty, reason: 'nothing is written');
    });
  });

  group('Activation refuses unusable keys with AtKeysUnusableException', () {
    test('a legacy keychain store the platform refuses to read', () async {
      await expectLater(
        const LoopbackFlows().activate(
          atSign,
          cramSecret: 'cram-secret-6d1f0b',
          keys: KeychainAtKeysIo(keychainStorage: keychain({legacy: refused})),
          preference: await loopbackPreference(),
          lookUps: silentLookUps,
        ),
        throwsA(
          unreadable(
            message: isNot(contains('Every Atsign')),
            error: isA<PlatformException>(),
          ),
        ),
      );
      expectNothingSent();
      expect(changed, isEmpty, reason: 'nothing is written or deleted');
    });
  });

  group("a keychain whose document does not parse affects every Atsign", () {
    Future<void> refusedSaying(String document, String reason) async {
      await expectLater(
        const LoopbackFlows().open(
          atSign,
          keys: KeychainAtKeysIo(
            keychainStorage: keychain({current: () async => document}),
          ),
          preference: await loopbackPreference(),
          lookUps: recordingLookUps,
        ),
        throwsA(
          unreadable(
            message: equals(
              "The keys for $atSign in this device's keychain could not be "
              'read: $reason. Every Atsign stored there is affected.',
            ),
            error: isA<AtKeysFormatException>(),
          ),
        ),
      );
      expect(built, isEmpty, reason: 'no connection is built');
    }

    test('text that is not JSON', () async {
      await refusedSaying(
        '{"keys":[',
        'it is not valid JSON: Unexpected end of input (at character 10)',
      );
    });

    test('JSON that is not an object', () async {
      await refusedSaying('[]', 'it is not a JSON object');
    });

    test('activation says the same', () async {
      await expectLater(
        const LoopbackFlows().activate(
          atSign,
          cramSecret: 'cram-secret-6d1f0b',
          keys: KeychainAtKeysIo(
            keychainStorage: keychain({current: () async => '[]'}),
          ),
          preference: await loopbackPreference(),
          lookUps: silentLookUps,
        ),
        throwsA(
          unreadable(
            message: equals(
              "The keys for $atSign in this device's keychain could not be "
              'read: it is not a JSON object. Every Atsign stored there is '
              'affected.',
            ),
          ),
        ),
      );
      expectNothingSent();
      expect(changed, isEmpty, reason: 'nothing is written or deleted');
    });
  });

  group('Given a keyfile, not the keychain, whose text is not JSON', () {
    test('when it is opened through AtsignFlows, then the refusal says '
        'nothing of every Atsign', () async {
      final path = '${support.path}/${atSign}_key.atKeys';
      File(path).writeAsStringSync('{"keys":[');

      await expectLater(
        const LoopbackFlows().open(
          atSign,
          keys: FileAtKeysIo(filePath: (_) => path),
          preference: await loopbackPreference(),
          lookUps: recordingLookUps,
        ),
        throwsA(
          isA<AtKeysUnusableException>()
              .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
              .having((e) => e.source, 'source', path)
              .having((e) => e.error, 'error', isA<AtKeysFormatException>())
              .having(
                (e) => e.message,
                'message',
                isNot(contains('Every Atsign')),
              ),
        ),
      );
      expect(built, isEmpty, reason: 'no connection is built');
    });
  });

  group('JSON that is not an object is refused on every keychain path', () {
    test('reading', () {
      expect(
        keychain({current: () async => '[]'}).readAtKeysData(),
        throwsA(
          isA<AtKeysFormatException>().having(
            (e) => e.reason,
            'reason',
            'not a JSON object',
          ),
        ),
      );
    });

    test('adding keys, which writes nothing', () async {
      await expectLater(
        keychain({
          current: () async => '[]',
        }).appendAtKeysToKeychain(keys: AtKeys()..atsign = '@bob'.toAtsign()),
        throwsA(isA<AtKeysFormatException>()),
      );
      expect(changed, isEmpty);
    });

    test('removing an atSign, which writes nothing', () async {
      await expectLater(
        keychain({current: () async => '[]'}).removeAtsignFromKeychain(atSign),
        throwsA(isA<AtKeysFormatException>()),
      );
      expect(changed, isEmpty);
    });

    test('migrating the legacy store, which writes nothing', () async {
      await expectLater(
        keychain({legacy: () async => '[]'}).readAtKeysData(),
        throwsA(isA<AtKeysFormatException>()),
      );
      expect(changed, isEmpty);
    });
  });

  test('removing an atSign from an empty keychain writes nothing', () async {
    await keychain({}).removeAtsignFromKeychain(atSign);
    expect(changed, isEmpty);
  });

  group('On Windows', () {
    late Map<String, String> held;

    /// The name of the store whose next write fails, once.
    String? failNextWriteOf;

    /// The names of stores whose read throws while they hold something.
    late Set<String> unreadableStores;

    /// The names of stores whose delete returns and leaves them in place.
    late Set<String> undeletableStores;

    /// The names of stores whose read answers null whatever they hold, as
    /// Windows answers a read that fails.
    late Set<String> absentStores;

    /// Every store name the keychain asked for.
    late List<String> touched;

    setUp(() {
      KeychainStorage.isWindows = true;
      addTearDown(() => KeychainStorage.isWindows = false);
      held = {};
      failNextWriteOf = null;
      unreadableStores = {};
      undeletableStores = {};
      absentStores = {};
      touched = [];
      logs.records.clear();
    });

    /// A keychain whose stores hold what is written to them, in [held].
    KeychainStorage windowsKeychain() {
      final biometricStorage = _MockBiometricStorage();
      when(
        () =>
            biometricStorage.getStorage(any(), options: any(named: 'options')),
      ).thenAnswer((invocation) async {
        final name = invocation.positionalArguments.first as String;
        touched.add(name);
        final file = _MockBiometricStorageFile();
        when(file.read).thenAnswer((_) async {
          if (absentStores.contains(name)) return null;
          if (unreadableStores.contains(name) && held.containsKey(name)) {
            throw PlatformException(code: 'ReadFailed');
          }
          return held[name];
        });
        when(() => file.write(any())).thenAnswer((invocation) async {
          if (failNextWriteOf == name) {
            failNextWriteOf = null;
            throw PlatformException(code: 'WriteFailed');
          }
          held[name] = invocation.positionalArguments.first as String;
        });
        when(file.delete).thenAnswer((_) async {
          if (!undeletableStores.contains(name)) held.remove(name);
        });
        return file;
      });
      return KeychainStorage(biometricStorage: biometricStorage);
    }

    /// Keys for [atSign] holding one key of [bytes] bytes.
    AtKeys keysOf(String atSign, int bytes) => AtKeys()
      ..atsign = atSign.toAtsign()
      ..addKey(
        CryptographicMaterial(
          keyId: 'enc:rsa2048:1',
          role: CryptographicMaterialRole.of('publicEncryption'),
          algorithm: CryptographicMaterialAlgorithm.of('rsa2048'),
          bytes: AtBytes.fromString(base64Encode(List.filled(bytes, 7))),
          createdAt: DateTime.utc(2026),
        ),
      );

    /// Keys for [atSign] whose entry spans several Windows segments.
    AtKeys largeKeys(String atSign) => keysOf(atSign, 6000);

    /// The segments of the current entry held, by name.
    Iterable<String> segmentsHeld() =>
        held.keys.where((name) => name.startsWith('${current}_segment_'));

    /// The segment count the current entry's header records.
    int headerCount() => jsonDecode(held[current]!)['segmentCount'] as int;

    test('removing an atSign leaves no segment of the longer entry', () async {
      final storage = windowsKeychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      await storage.appendAtKeysToKeychain(keys: largeKeys('@bob'));
      final longer = headerCount();

      await storage.removeAtsignFromKeychain('@bob');

      expect(headerCount(), lessThan(longer), reason: 'the control');
      expect(segmentsHeld(), hasLength(headerCount()));
      expect((await storage.readAtKeysData())!.keys.map((k) => '${k.atsign}'), [
        atSign,
      ]);
    });

    test('undoing a failed longer write leaves no segment of it', () async {
      final storage = windowsKeychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      final shorter = headerCount();
      failNextWriteOf = '${current}_segment_${shorter + 1}';

      await expectLater(
        storage.appendAtKeysToKeychain(keys: largeKeys('@bob')),
        throwsA(isA<PlatformException>()),
      );

      expect(headerCount(), shorter);
      expect(segmentsHeld(), hasLength(shorter));
    });

    test('deleting every atSign\'s keys clears the segments of an entry whose '
        'header does not parse', () async {
      final storage = windowsKeychain();
      await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
      expect(segmentsHeld(), isNotEmpty, reason: 'the control');
      held[current] = '{bad';

      await storage.deleteAllAtKeysData();

      expect(held, isEmpty);
    });

    group('segments are found and deleted the same way', () {
      /// The highest segment index any store asked for named.
      int highestIndexTouched() => touched
          .map((name) => RegExp(r'_(\d+)$').firstMatch(name))
          .whereType<RegExpMatch>()
          .map((m) => int.parse(m[1]!))
          .fold(-1, (a, b) => a > b ? a : b);

      Iterable<String> severeLogs() =>
          logs.records.where((r) => r.level == 'SEVERE').map((r) => r.message);

      test('a delete-all whose read of one segment throws still deletes every '
          'segment the header names', () async {
        held[current] = '{"segmentCount":3}';
        for (var i = 0; i < 3; i++) {
          held['${current}_segment_$i'] = 'part$i';
        }
        unreadableStores.add('${current}_segment_1');

        await windowsKeychain().deleteAllAtKeysData();

        expect(held, isEmpty, reason: 'the header and all 3 segments go');
      });

      test('a delete-all whose header cannot be read still deletes the '
          'segments present', () async {
        held[current] = '{"segmentCount":2}';
        held['${current}_segment_0'] = 'a';
        held['${current}_segment_1'] = 'b';
        unreadableStores.add(current);

        await windowsKeychain().deleteAllAtKeysData();

        expect(held, isEmpty);
        expect(severeLogs(), isNotEmpty, reason: 'the failure is logged');
      });

      test('an empty segment does not end the search for the next', () async {
        held[current] = '{bad';
        held['${current}_segment_0'] = '';
        held['${current}_segment_1'] = 'kept?';

        await windowsKeychain().deleteAllAtKeysData();

        expect(held, isEmpty);
      });

      test('a delete-all whose segment stays stored logs it at severe and '
          'still deletes the header', () async {
        held[current] = '{"segmentCount":2}';
        held['${current}_segment_0'] = 'a';
        held['${current}_segment_1'] = 'b';
        undeletableStores.add('${current}_segment_1');

        await windowsKeychain().deleteAllAtKeysData();

        expect(held.keys, contains('${current}_segment_1'));
        expect(held, isNot(contains(current)), reason: 'the header is gone');
        expect(severeLogs(), isNotEmpty);
      });

      test('a rewrite deletes the stale trailing segments, an empty one '
          'among them', () async {
        final storage = windowsKeychain();
        await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
        final live = headerCount();
        held['${current}_segment_$live'] = '';
        held['${current}_segment_${live + 1}'] = 'stale';

        await storage.updateAtKeysInKeychain(
          atSign: atSign,
          keys: largeKeys(atSign),
        );

        expect(segmentsHeld(), hasLength(headerCount()));
        expect(held.values, isNot(contains('stale')));
      });

      test('a rewrite whose stale segment stays stored logs it at severe, '
          'and the write stands', () async {
        final storage = windowsKeychain();
        await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
        final live = headerCount();
        held['${current}_segment_$live'] = 'stale';
        undeletableStores.add('${current}_segment_$live');
        logs.records.clear();

        await storage.updateAtKeysInKeychain(
          atSign: atSign,
          keys: largeKeys(atSign),
        );

        expect(severeLogs(), isNotEmpty);
        expect(headerCount(), live);
      });

      test('a rewrite deletes every segment the old header names, one that '
          'reads as absent included', () async {
        final storage = windowsKeychain();
        await storage.appendAtKeysToKeychain(keys: keysOf(atSign, 3000));
        expect(headerCount(), 2, reason: 'the control: two segments');
        held['${current}_segment_2'] = held.remove('${current}_segment_1')!;
        held['${current}_segment_1'] = 'unread';
        held[current] = '{"segmentCount":3}';
        absentStores.add('${current}_segment_1');
        expect(
          '${(await storage.readAtKeysData())!.keys.single.atsign}',
          atSign,
          reason: "the control: the 3 segments read as @alice's keys",
        );

        await storage.updateAtKeysInKeychain(
          atSign: atSign,
          keys: keysOf(atSign, 100),
        );

        expect(headerCount(), 1, reason: 'the control: one segment written');
        expect(
          held.keys,
          isNot(
            anyOf(
              contains('${current}_segment_1'),
              contains('${current}_segment_2'),
            ),
          ),
        );
      });

      test('a rewrite over a legacy header deletes only the segments it '
          'names', () async {
        final storage = windowsKeychain();
        await storage.appendAtKeysToKeychain(keys: keysOf(atSign, 3000));
        expect(headerCount(), 2, reason: 'the control: two segments');
        held[current] = '2';
        for (var i = 0; i < 2; i++) {
          held['test_data_$i'] = held.remove('${current}_segment_$i')!;
        }
        held['test_data_2'] = 'third';
        expect(
          '${(await storage.readAtKeysData())!.keys.single.atsign}',
          atSign,
          reason: "the control: the 2 legacy segments read as @alice's keys",
        );

        await storage.updateAtKeysInKeychain(
          atSign: atSign,
          keys: keysOf(atSign, 3000),
        );

        expect(held.keys.where((name) => name.startsWith('test_data_')), [
          'test_data_2',
        ]);
      });

      for (final bad in ['2561', '-1', 'abc']) {
        test('a legacy header "$bad" is refused on read', () async {
          held[current] = bad;

          await expectLater(
            windowsKeychain().readAtKeysData(),
            throwsA(
              isA<AtKeysFormatException>().having(
                (e) => e.reason,
                'reason',
                'a legacy segment header whose segmentCount is not a whole '
                    'number from 0 to 2560',
              ),
            ),
          );
          expect(highestIndexTouched(), lessThan(2560));
        });
      }

      test('a delete over an oversized legacy header clears what is there '
          'and looks at no segment past the bound', () async {
        held[current] = '2561';
        held['${current}_segment_0'] = 'a';

        await windowsKeychain().deleteAllAtKeysData();

        expect(held, isEmpty);
        expect(highestIndexTouched(), lessThan(2560));
        expect(severeLogs(), isNotEmpty);
      });

      test('a write over an oversized legacy header succeeds and looks at '
          'no segment past the bound', () async {
        const spp = '@alice_@spp';
        held[spp] = '2561';

        await windowsKeychain().saveSpp(atSign, Passcode('code', null));

        expect(jsonDecode(held[spp]!)['segmentCount'], 1);
        expect(highestIndexTouched(), lessThan(2560));
      });
    });

    test('a header with no segment count is refused as not the keychain\'s '
        'format, for every Atsign', () async {
      held[current] = '{"x":1}';
      final storage = windowsKeychain();

      await expectLater(
        storage.readAtKeysData(),
        throwsA(
          isA<AtKeysFormatException>().having(
            (e) => e.reason,
            'reason',
            'a JSON object whose segmentCount is not a whole number from 0 '
                'to 2560',
          ),
        ),
      );
      await expectLater(
        const LoopbackFlows().open(
          atSign,
          keys: KeychainAtKeysIo(keychainStorage: storage),
          preference: await loopbackPreference(),
          lookUps: recordingLookUps,
        ),
        throwsA(
          unreadable(
            message: equals(
              "The keys for $atSign in this device's keychain could not be "
              'read: it is a JSON object whose segmentCount is not a whole '
              'number from 0 to 2560. Every Atsign stored there is affected.',
            ),
          ),
        ),
      );
      expect(built, isEmpty, reason: 'no connection is built');
    });

    for (final (name, count) in const [
      ('-1', '-1'),
      ('one over the bound', '2561'),
      ('the string "3"', '"3"'),
      ('2.0', '2.0'),
    ]) {
      group('Given a header whose segment count is $name', () {
        test(
          'when the keychain is read, then it is refused as '
          'AtKeysFormatException holding none of the entry\'s text',
          () async {
            const headerMark = 'header-5f1c9e2a7b';
            const segmentMark = 'segment-8d3a6c0e4f';
            final storage = windowsKeychain();
            await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
            held[current] = '{"segmentCount":$count,"mark":"$headerMark"}';
            held['${current}_segment_0'] =
                '$segmentMark${held['${current}_segment_0']}';

            final Object? error = await storage.readAtKeysData().then(
              (_) => null,
              onError: (Object e) => e,
            );

            expect(
              error,
              isA<AtKeysFormatException>()
                  .having((e) => e.isJson, 'isJson', isTrue)
                  .having((e) => e.reason, 'reason', contains('segmentCount')),
            );
            final format = error as AtKeysFormatException;
            for (final text in ['$format', format.message, format.reason]) {
              expect(
                text,
                allOf(
                  isNot(contains(headerMark)),
                  isNot(contains(segmentMark)),
                  isNot(contains(count)),
                ),
              );
            }
          },
        );
      });
    }

    /// The current entry's text, its segments joined.
    String entryHeld() => [
      for (var i = 0; i < headerCount(); i++) held['${current}_segment_$i']!,
    ].join();

    /// Moves the current entry to the legacy store and its segments, under a
    /// header of [count].
    void heldAsLegacy(String count) {
      final segments = headerCount();
      held.remove(current);
      for (var i = 0; i < segments; i++) {
        held['test_data_$i'] = held.remove('${current}_segment_$i')!;
      }
      held[legacy] = count;
    }

    for (final (name, count) in const [
      ('-1', '-1'),
      ('one over the bound', '2561'),
      ('not a whole number', 'two'),
    ]) {
      group('Given a legacy header whose segment count is $name', () {
        test(
          'when the keychain is read, then it is refused as '
          'AtKeysFormatException holding none of the entry\'s text',
          () async {
            final storage = windowsKeychain();
            await storage.appendAtKeysToKeychain(keys: largeKeys(atSign));
            final entry = entryHeld();
            heldAsLegacy('${headerCount()}');
            expect(
              '${(await storage.readAtKeysData())!.keys.single.atsign}',
              atSign,
              reason: 'the control: the legacy entry reads under its count',
            );
            held.removeWhere((name, _) => name.startsWith(current));
            held[legacy] = count;

            final Object? error = await storage.readAtKeysData().then(
              (_) => null,
              onError: (Object e) => e,
            );

            expect(error, isA<AtKeysFormatException>());
            final format = error as AtKeysFormatException;
            for (final text in ['$format', format.message, format.reason]) {
              expect(
                text,
                allOf(
                  isNot(contains(count)),
                  predicate<String>(
                    (t) => !Iterable.generate(
                      entry.length - 15,
                      (i) => entry.substring(i, i + 16),
                    ).any(t.contains),
                    'no 16-character run of the entry',
                  ),
                ),
              );
            }
          },
        );
      });
    }

    group('Given a legacy header whose segment count is over the bound', () {
      test('when every atSign\'s keys are deleted, then no more segments '
          'than the bound are deleted', () async {
        held[legacy] = '2561';
        for (var i = 0; i <= 2560; i++) {
          held['test_data_$i'] = 'segment $i';
        }
        final storage = windowsKeychain();

        await storage.deleteAllAtKeysData();

        expect(held.keys, ['test_data_2560']);
      });
    });
  });
}
