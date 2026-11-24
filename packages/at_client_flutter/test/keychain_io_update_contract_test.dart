import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

/// The update contract every `WrittenAtKeysIo` keeps: a change that returns
/// false or throws leaves the store as it was, whatever it did to the keys it
/// was handed, and one that returns true is stored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        MethodChannel('dev.fluttercommunity.plus/package_info'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getAll') {
            return {
              'appName': 'test',
              'packageName': 'test',
              'version': '1.0.0',
              'buildNumber': '1',
            };
          }
          return false;
        },
      );

  final alice = '@alice'.toAtsign();

  group('Given a KeychainAtKeysIo holding keys for @alice', () {
    late KeychainAtKeysIo io;

    /// The keychain blob, as a plain string the mock reads and writes.
    String? blob;

    setUp(() async {
      KeychainStorage.isWindows = false;
      blob = null;
      final storage = MockBiometricStorage();
      final file = MockBiometricStorageFile();
      when(
        () => storage.getStorage(any(), options: any(named: 'options')),
      ).thenAnswer((_) async => file);
      when(() => file.read()).thenAnswer((_) async => blob);
      when(() => file.write(any())).thenAnswer((invocation) async {
        blob = invocation.positionalArguments[0] as String;
      });
      io = KeychainAtKeysIo(
        keychainStorage: KeychainStorage()..biometricStorage = storage,
      );
      await io.write(
        '@alice',
        AtKeys.legacy(
          apkamPublicKey: base64Encode(utf8.encode('apkam')),
          selfEncryptionKey: base64Encode(utf8.encode('self')),
          enrollmentId: 'e-@alice',
        ),
      );
    });

    CryptographicMaterial key({String value = 'YWRkZWQ='}) =>
        CryptographicMaterial(
          keyId: 'added',
          role: CryptographicMaterialRole.symmetricEncryption,
          algorithm: CryptographicMaterialAlgorithm.aes256,
          bytes: AtBytes.fromString(value),
          createdAt: DateTime.utc(2026, 1, 1),
        );

    bool holdsAdded(AtKeys keys) => keys.atSignKeysForKeyId('added').isNotEmpty;

    void addKey(AtKeys keys) {
      keys.addKey(key());
      expect(
        holdsAdded(keys),
        isTrue,
        reason: 'control: the change added the key to the keys it was handed',
      );
    }

    test(
      'when an update adds a key and returns false, then a read does not hold '
      'the key',
      () async {
        await io.update(alice, (keys) {
          addKey(keys);
          return false;
        });

        expect(holdsAdded(await io.read('@alice')), isFalse);
      },
    );

    test(
      'when an update adds a key and then throws, then the throw reaches the '
      'caller and a read does not hold the key',
      () async {
        await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            throw _Refused();
          }),
          throwsA(isA<_Refused>()),
        );

        expect(holdsAdded(await io.read('@alice')), isFalse);
      },
    );

    test(
      'when an update adds one key and a second add throws, then a read holds '
      'neither key',
      () async {
        await expectLater(
          io.update(alice, (keys) {
            addKey(keys);
            keys.addKey(key(value: 'b3RoZXI='));
            return true;
          }),
          throwsA(isA<ArgumentError>()),
          reason: 'the keys refuse a second key with the same id and role',
        );

        expect(holdsAdded(await io.read('@alice')), isFalse);
      },
    );

    test(
      'when an update adds a key and returns true, then a read holds the key',
      () async {
        await io.update(alice, (keys) {
          addKey(keys);
          return true;
        });

        final read = await io.read('@alice');
        expect(holdsAdded(read), isTrue);
        expect(read.atsign, alice);
      },
    );
  });
}

class _Refused implements Exception {}
