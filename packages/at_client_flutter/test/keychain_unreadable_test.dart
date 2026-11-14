import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show AtKeysParseException, AtKeysSourceAbsentException;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtAuthenticator, AtLookupImpl, AtLookupMuxable;
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

/// A keychain the platform refuses to read, or whose one document does not
/// parse, is refused as unreadable, and nothing is written or sent.
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

  setUpAll(() => KeychainStorage.isWindows = false);

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
            message: startsWith(
              "The keys for $atSign in this device's keychain could not be "
              'read: ',
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
        throwsA(unreadable(message: anything, error: isA<PlatformException>())),
      );
      expectNothingSent();
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

  test('a Windows header whose segmentCount is not a number is refused, '
      'holding none of it', () async {
    KeychainStorage.isWindows = true;
    addTearDown(() => KeychainStorage.isWindows = false);
    const count = 'seventeen-segments-6d1f0b';

    await expectLater(
      keychain({
        current: () async => '{"segmentCount": "$count"}',
      }).readAtKeysData(),
      throwsA(
        isA<AtKeysParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('segmentCount'), isNot(contains(count))),
        ),
      ),
    );
    expect(changed, isEmpty);
  });

  test('removing an atSign from an empty keychain writes nothing', () async {
    await keychain({}).removeAtsignFromKeychain(atSign);
    expect(changed, isEmpty);
  });
}
