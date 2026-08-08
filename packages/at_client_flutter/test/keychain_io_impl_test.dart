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

/// `KeychainAtKeysIo` as a *bootstrap store*.
///
/// The keychain is one of the two homes the never-lose contract binds — the
/// other being the `.atKeys` file — and until now it implemented only half of
/// the interface. `flush` fell through to `WrittenAtKeysIo`'s throwing default,
/// so on Flutter the nskey-private filing path and the signing-root store both
/// hit `UnimplementedError` on a store that is the platform's own default.
/// `write` was the mirror-image problem: it appended unconditionally to a list
/// `read` scans front-to-back, so writing an atSign twice left the newer keys
/// permanently unreachable behind the older ones.
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

  late MockBiometricStorage storage;
  late MockBiometricStorageFile file;
  late KeychainAtKeysIo io;

  /// The keychain blob, as a plain string the mock reads and writes. Real
  /// enough for these tests: what is under examination is the read-modify-write
  /// the io layer performs, not the platform channel underneath it.
  String? blob;

  setUp(() {
    KeychainStorage.isWindows = false;
    blob = null;
    storage = MockBiometricStorage();
    file = MockBiometricStorageFile();
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
  });

  int entryCount() =>
      ((jsonDecode(blob!) as Map<String, dynamic>)['keys'] as List).length;

  AtKeys keysFor(String atSign) => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(base64Encode(utf8.encode('apkam')))
    ..defaultSelfEncryptionKey =
        AtBytes.fromString(base64Encode(utf8.encode('self')))
    ..enrollmentId = 'e-$atSign';

  AtKeysMaterial material(String keyId) => AtKeysMaterial(
    keyId: keyId,
    keyPartType: CryptographicKeyType.symmetricEncryption,
    keyAlgorithmType: KeyAlgorithmType.aes256,
    bytes: AtBytes.fromString(base64Encode(utf8.encode(keyId))),
    createdAt: DateTime.utc(2026, 1, 1),
  );

  test('write refuses an atSign that already has an entry', () async {
    await io.write('@alice', keysFor('@alice'));
    expect(entryCount(), 1);

    await expectLater(
      io.write('@alice', keysFor('@alice')),
      throwsA(isA<AtKeysFileOverwriteException>()),
      reason: 'appending a second entry would leave the newer keys unreachable '
          'behind the older ones, which is a silent loss rather than a write',
    );
    expect(entryCount(), 1, reason: 'and nothing was appended');
  });

  test('write still appends a DIFFERENT atSign', () async {
    await io.write('@alice', keysFor('@alice'));
    await io.write('@bob', keysFor('@bob'));

    expect(entryCount(), 2);
    expect((await io.read('@alice')).enrollmentId, 'e-@alice');
    expect((await io.read('@bob')).enrollmentId, 'e-@bob');
  });

  test('flush creates the entry when the atSign has none', () async {
    await io.flush('@alice'.toAtsign(), keysFor('@alice'));

    expect(entryCount(), 1);
    expect((await io.read('@alice')).enrollmentId, 'e-@alice');
  });

  test('flush REPLACES rather than appends, and the new state is what reads',
      () async {
    final keys = keysFor('@alice');
    await io.write('@alice', keys);

    keys.addKey(material('nskey.wavi'));
    await io.flush('@alice'.toAtsign(), keys);

    expect(entryCount(), 1,
        reason: 'a flush that appended would leave read() answering with the '
            'pre-flush entry forever');
    final reread = await io.read('@alice');
    expect(
      reread
          .getKey('nskey.wavi', CryptographicKeyType.symmetricEncryption)
          ?.bytes
          .toString(),
      base64Encode(utf8.encode('nskey.wavi')),
    );
  });

  test('flush leaves other atSigns\' entries alone', () async {
    await io.write('@alice', keysFor('@alice'));
    await io.write('@bob', keysFor('@bob'));

    final alice = await io.read('@alice');
    alice.addKey(material('nskey.wavi'));
    await io.flush('@alice'.toAtsign(), alice);

    expect(entryCount(), 2);
    expect((await io.read('@bob')).enrollmentId, 'e-@bob');
  });

  test('flush refuses a candidate that drops material, and writes nothing',
      () async {
    final keys = keysFor('@alice');
    keys.addKey(material('nskey.wavi'));
    await io.write('@alice', keys);
    final before = blob;

    // The same atSign, without the key it already had. The never-lose contract
    // is what makes a bootstrap store safe to flush from several places.
    await expectLater(
      io.flush('@alice'.toAtsign(), keysFor('@alice')),
      throwsA(isA<AtKeysAssuranceException>()),
    );
    expect(blob, before, reason: 'a refused flush must not have written');
  });

  test('an entry stored under the legacy `name` metadata key is found, '
      'replaced and removed by the same predicate', () async {
    // What a keychain written by an older release looks like: the atSign lives
    // under `name`, not `atsign`. Reading it worked; `getAllAtsigns` threw on
    // it (a non-bool used as a condition) and `removeAtsignFromKeychain`
    // silently kept it.
    blob = jsonEncode({
      'keys': [
        {
          'name': '@alice',
          'aesPkamPublicKey': base64Encode(utf8.encode('apkam')),
          'selfEncryptionKey': base64Encode(utf8.encode('self')),
          'enrollmentId': 'e-@alice',
        },
      ],
      'defaultAtsign': '@alice',
    });
    final keychain = KeychainStorage()..biometricStorage = storage;

    expect(await keychain.getAllAtsigns(), ['@alice']);

    final legacyIo = KeychainAtKeysIo(keychainStorage: keychain);
    final keys = await legacyIo.read('@alice');
    keys.addKey(material('nskey.wavi'));
    await legacyIo.flush('@alice'.toAtsign(), keys);
    expect(entryCount(), 1, reason: 'replaced in place, not appended beside');

    await keychain.removeAtsignFromKeychain('@alice');
    expect(entryCount(), 0);
  });
}
