import 'dart:async';
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
/// The keychain is one of the two homes the never-lose contract binds, the
/// other being the `.atKeys` file, and `read` scans its list front-to-back —
/// so an entry appended beside an existing one is unreachable.
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

  /// The keychain blob, as a plain string the mock reads and writes.
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

  AtKeys keysFor(String atSign) => AtKeys.legacy(
    apkamPublicKey: base64Encode(utf8.encode('apkam')),
    selfEncryptionKey: base64Encode(utf8.encode('self')),
    enrollmentId: 'e-$atSign',
  );

  CryptographicMaterial material(String keyId) => CryptographicMaterial(
    keyId: keyId,
    role: CryptographicMaterialRole.symmetricEncryption,
    algorithm: CryptographicMaterialAlgorithm.aes256,
    bytes: AtBytes.fromString(base64Encode(utf8.encode(keyId))),
    createdAt: DateTime.utc(2026, 1, 1),
  );

  test(
    'read of an atSign the keychain does not hold says the source is absent',
    () async {
      // The type is what an enrollment reads to tell "no keys yet" from "keys
      // this process cannot read": it starts on the first and refuses on the
      // second, so the keychain has to answer the way the file store does.
      await expectLater(
        () => io.read('@nobody'),
        throwsA(isA<AtKeysSourceAbsentException>()),
      );
      await io.write('@alice', keysFor('@alice'));
      await expectLater(
        () => io.read('@nobody'),
        throwsA(isA<AtKeysSourceAbsentException>()),
        reason: 'an entry for another atSign does not make @nobody present',
      );
      expect(
        (await io.read('@alice')).storedEnrollmentId,
        'e-@alice',
        reason: 'the control: the atSign the keychain holds reads back',
      );
    },
  );

  test('write refuses an atSign that already has an entry', () async {
    await io.write('@alice', keysFor('@alice'));
    expect(entryCount(), 1);

    await expectLater(
      io.write('@alice', keysFor('@alice')),
      throwsA(isA<AtKeysFileOverwriteException>()),
      reason:
          'appending a second entry would leave the newer keys unreachable '
          'behind the older ones, which is a silent loss rather than a write',
    );
    expect(entryCount(), 1, reason: 'and nothing was appended');
  });

  test('write still appends a DIFFERENT atSign', () async {
    await io.write('@alice', keysFor('@alice'));
    await io.write('@bob', keysFor('@bob'));

    expect(entryCount(), 2);
    expect((await io.read('@alice')).storedEnrollmentId, 'e-@alice');
    expect((await io.read('@bob')).storedEnrollmentId, 'e-@bob');
  });

  test('flush creates the entry when the atSign has none', () async {
    await io.flush('@alice'.toAtsign(), keysFor('@alice'));

    expect(entryCount(), 1);
    expect((await io.read('@alice')).storedEnrollmentId, 'e-@alice');
  });

  test(
    'flush REPLACES rather than appends, and the new state is what reads',
    () async {
      final keys = keysFor('@alice');
      await io.write('@alice', keys);

      keys.addKey(material('nskey.wavi'));
      await io.flush('@alice'.toAtsign(), keys);

      expect(
        entryCount(),
        1,
        reason:
            'a flush that appended would leave read() answering with the '
            'pre-flush entry forever',
      );
      final reread = await io.read('@alice');
      expect(
        reread
            .getAtSignKey(
              'nskey.wavi',
              CryptographicMaterialRole.symmetricEncryption,
            )
            ?.bytes
            .toString(),
        base64Encode(utf8.encode('nskey.wavi')),
      );
    },
  );

  test('flush leaves other atSigns\' entries alone', () async {
    await io.write('@alice', keysFor('@alice'));
    await io.write('@bob', keysFor('@bob'));

    final alice = await io.read('@alice');
    alice.addKey(material('nskey.wavi'));
    await io.flush('@alice'.toAtsign(), alice);

    expect(entryCount(), 2);
    expect((await io.read('@bob')).storedEnrollmentId, 'e-@bob');
  });

  test(
    'flush refuses a candidate that drops material, and writes nothing',
    () async {
      final keys = keysFor('@alice');
      keys.addKey(material('nskey.wavi'));
      await io.write('@alice', keys);
      final before = blob;

      await expectLater(
        io.flush('@alice'.toAtsign(), keysFor('@alice')),
        throwsA(isA<AtKeysAssuranceException>()),
      );
      expect(blob, before, reason: 'a refused flush must not have written');
    },
  );

  /// Holds the next keychain write until [release] completes, answering once
  /// it is held: its writer has read the keychain and its write has not
  /// landed.
  Future<void> parkNextWrite(Future<void> release) {
    final held = Completer<void>();
    when(() => file.write(any())).thenAnswer((invocation) async {
      if (!held.isCompleted) {
        held.complete();
        await release;
      }
      blob = invocation.positionalArguments[0] as String;
    });
    return held.future;
  }

  bool holdsWavi(AtKeys keys) =>
      keys.getAtSignKey(
        'nskey.wavi',
        CryptographicMaterialRole.symmetricEncryption,
      ) !=
      null;

  test(
    'two concurrent updates, through two instances, each keep what the other '
    'added',
    () async {
      await io.write('@alice', keysFor('@alice'));
      final gate = Completer<void>();

      final first = io.update('@alice'.toAtsign(), (keys) async {
        await gate.future;
        keys.addKey(material('nskey.wavi'));
        return true;
      });
      final second =
          KeychainAtKeysIo(
            keychainStorage: KeychainStorage()..biometricStorage = storage,
          ).update('@alice'.toAtsign(), (keys) {
            keys.addKey(material('nskey.buzz'));
            return true;
          });
      await pumpEventQueue();
      gate.complete();
      await Future.wait([first, second]);

      final reread = await io.read('@alice');
      expect(
        reread.getAtSignKey(
          'nskey.buzz',
          CryptographicMaterialRole.symmetricEncryption,
        ),
        isNotNull,
        reason:
            'an update that read before the other wrote would write back keys '
            'missing its addition, which the never-lose check refuses, so one '
            'of the two would fail',
      );
      expect(holdsWavi(reread), isTrue);
    },
  );

  /// Runs [other] while an update adding `nskey.wavi` to @alice has read the
  /// keychain and not yet written it, then lets both finish.
  Future<void> duringAliceUpdate(Future<void> Function() other) async {
    final release = Completer<void>();
    final held = parkNextWrite(release.future);
    final updating = io.update('@alice'.toAtsign(), (keys) {
      keys.addKey(material('nskey.wavi'));
      return true;
    });
    await held;
    final running = other();
    await pumpEventQueue();
    release.complete();
    await Future.wait([updating, running]);
  }

  test(
    'a flush for one atSign is not undone by an update of another',
    () async {
      await io.write('@alice', keysFor('@alice'));
      await io.write('@bob', keysFor('@bob'));
      final bob = await io.read('@bob');
      bob.addKey(material('nskey.wavi'));

      await duringAliceUpdate(() => io.flush('@bob'.toAtsign(), bob));

      expect(holdsWavi(await io.read('@alice')), isTrue);
      expect(
        holdsWavi(await io.read('@bob')),
        isTrue,
        reason:
            'the keychain keeps every atSign in one entry, so a write that '
            'read it before another landed puts back the entry without that '
            'one, and the never-lose check only compares its own atSign',
      );
    },
  );

  test(
    'a write for one atSign is not undone by an update of another',
    () async {
      await io.write('@alice', keysFor('@alice'));

      await duringAliceUpdate(() => io.write('@bob', keysFor('@bob')));

      expect(holdsWavi(await io.read('@alice')), isTrue);
      expect(
        entryCount(),
        2,
        reason:
            'an atSign onboarded while another\'s keys are being written '
            'must not be dropped from the keychain',
      );
    },
  );

  test(
    'keys appended to the keychain directly are not undone by an update',
    () async {
      await io.write('@alice', keysFor('@alice'));

      await duringAliceUpdate(
        () => io.keychainStorage.appendAtKeysToKeychain(
          keys: keysFor('@bob')..atsign = '@bob'.toAtsign(),
        ),
      );

      expect(holdsWavi(await io.read('@alice')), isTrue);
      expect(
        entryCount(),
        2,
        reason: 'an app may append through the storage itself',
      );
    },
  );

  test(
    'an atSign removed while another\'s keys are being written stays removed',
    () async {
      await io.write('@alice', keysFor('@alice'));
      await io.write('@bob', keysFor('@bob'));

      await duringAliceUpdate(
        () => io.keychainStorage.removeAtsignFromKeychain('@bob'),
      );

      expect(holdsWavi(await io.read('@alice')), isTrue);
      await expectLater(
        io.read('@bob'),
        throwsA(isA<AtKeysSourceAbsentException>()),
        reason:
            'a write that read the keychain before the removal puts the '
            'removed atSign back, and removing it is how a device gives up '
            'its credential',
      );
    },
  );

  test(
    'deleting every atSign\'s keys while one is being written leaves none',
    () async {
      when(() => file.delete()).thenAnswer((_) async => blob = null);
      await io.write('@alice', keysFor('@alice'));

      await duringAliceUpdate(() => io.keychainStorage.deleteAllAtKeysData());

      expect(
        blob,
        isNull,
        reason: 'a write already under way must not put the keys back',
      );
    },
  );

  test('two writes of one atSign at once leave one entry', () async {
    final outcomes = await Future.wait([
      for (var i = 0; i < 2; i++)
        io
            .write('@alice', keysFor('@alice'))
            .then(
              (_) => 'written',
              onError: (Object e) =>
                  e is AtKeysFileOverwriteException ? 'refused' : throw e,
            ),
    ]);

    expect(
      entryCount(),
      1,
      reason:
          'both would find no entry before either appended, and the second '
          'entry appended is one read never reaches',
    );
    expect(outcomes, unorderedEquals(['written', 'refused']));
  });

  test(
    'an update refuses to put back a keychain emptied before it writes',
    () async {
      await io.write('@alice', keysFor('@alice'));

      await expectLater(
        io.update('@alice'.toAtsign(), (keys) {
          blob = null;
          keys.addKey(material('nskey.wavi'));
          return true;
        }),
        throwsA(isA<AtKeysSourceAbsentException>()),
      );
      expect(
        blob,
        isNull,
        reason:
            'an update is a change to keys that exist, and keys deleted from '
            'outside this isolate\'s lock stay deleted',
      );
    },
  );

  test(
    'an update refuses to put back an atSign removed before it writes',
    () async {
      await io.write('@bob', keysFor('@bob'));
      final bobOnly = blob;
      await io.write('@alice', keysFor('@alice'));

      await expectLater(
        io.update('@alice'.toAtsign(), (keys) {
          blob = bobOnly;
          keys.addKey(material('nskey.wavi'));
          return true;
        }),
        throwsA(isA<AtKeysSourceAbsentException>()),
      );
      expect(
        blob,
        bobOnly,
        reason:
            'an update is a change to keys that exist, and an atSign removed '
            'from outside this isolate\'s lock stays removed',
      );
    },
  );

  test('an entry stored under the legacy `name` metadata key is found, '
      'replaced and removed by the same predicate', () async {
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

  test('an atSign is one entry however the caller spells it', () async {
    // NOTE: `read`/`write` are handed the caller's raw string while `flush`
    // is handed `toAtsign()`, so both spellings must resolve to one entry.
    await io.write('@Alice', keysFor('@alice'));

    expect(
      (await io.read('@Alice')).storedEnrollmentId,
      'e-@alice',
      reason: 'the spelling that wrote the entry must find it again',
    );
    expect((await io.read('@alice')).storedEnrollmentId, 'e-@alice');
    expect(
      (await io.read('alice')).storedEnrollmentId,
      'e-@alice',
      reason: 'toAtsign() supplies the missing @',
    );
    await expectLater(
      io.write('alice', keysFor('@alice')),
      throwsA(isA<AtKeysFileOverwriteException>()),
      reason: 'a second spelling is not a second atSign',
    );
    expect(entryCount(), 1);
  });

  test('a stored spelling that differs from its normal form is replaced, '
      'not appended beside', () async {
    // NOTE: `@colin.constable` normalizes to `@colinconstable` — dots in the
    // right-hand side are decoration — so a stored spelling can differ from
    // the one `flush` matches on.
    blob = jsonEncode({
      'keys': [
        {
          'atsign': '@colin.constable',
          'aesPkamPublicKey': base64Encode(utf8.encode('apkam')),
          'selfEncryptionKey': base64Encode(utf8.encode('self')),
          'enrollmentId': 'e-@colinconstable',
        },
      ],
    });
    final keychain = KeychainStorage()..biometricStorage = storage;
    final legacyIo = KeychainAtKeysIo(keychainStorage: keychain);

    final keys = await legacyIo.read('@colin.constable');
    keys.addKey(material('nskey.wavi'));
    await legacyIo.flush('@colin.constable'.toAtsign(), keys);

    expect(entryCount(), 1, reason: 'replaced in place, not appended beside');
    expect(
      (await legacyIo.read('@colinconstable')).getAtSignKey(
        'nskey.wavi',
        CryptographicMaterialRole.symmetricEncryption,
      ),
      isNotNull,
      reason: 'and the flushed material is what reads back',
    );

    await keychain.removeAtsignFromKeychain('@colinconstable');
    expect(entryCount(), 0, reason: 'removal matches the same way');
  });
}
