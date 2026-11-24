import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBiometricStorage extends Mock implements BiometricStorage {}

class _MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

/// The keychain holds one entry per Atsign.
///
/// Catalogue: features/at_client_flutter/keychain_one_entry_per_atsign.feature
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  late _MockBiometricStorage storage;
  late KeychainAtKeysIo io;

  /// The keychain blob, as a plain string the mock reads and writes.
  String? blob;

  /// How many times the blob has been read.
  late int reads;

  /// How many times the blob has been written.
  late int writes;

  setUp(() {
    KeychainStorage.isWindows = false;
    blob = null;
    reads = 0;
    writes = 0;
    storage = _MockBiometricStorage();
    final file = _MockBiometricStorageFile();
    when(
      () => storage.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => file);
    when(() => file.read()).thenAnswer((_) async {
      reads++;
      return blob;
    });
    when(() => file.write(any())).thenAnswer((invocation) async {
      writes++;
      blob = invocation.positionalArguments[0] as String;
    });
    io = KeychainAtKeysIo(
      keychainStorage: KeychainStorage()..biometricStorage = storage,
    );
  });

  KeychainStorage keychain() => KeychainStorage()..biometricStorage = storage;

  /// A keychain whose stores hold [held], by name, each read and written on
  /// its own.
  KeychainStorage keychainOf(Map<String, String> held) {
    final stores = _MockBiometricStorage();
    when(
      () => stores.getStorage(any(), options: any(named: 'options')),
    ).thenAnswer((invocation) async {
      final name = invocation.positionalArguments.first as String;
      final file = _MockBiometricStorageFile();
      when(file.read).thenAnswer((_) async => held[name]);
      when(() => file.write(any())).thenAnswer((invocation) async {
        held[name] = invocation.positionalArguments.first as String;
      });
      return file;
    });
    return KeychainStorage()..biometricStorage = stores;
  }

  /// Keys with no typed key material that name no Atsign.
  AtKeys bare(String enrollmentId) => AtKeys.legacy(
    apkamPublicKey: base64Encode(utf8.encode('apkam-$enrollmentId')),
    selfEncryptionKey: base64Encode(utf8.encode('self-$enrollmentId')),
    enrollmentId: enrollmentId,
  );

  /// Keys for [atSign] with enrollment id [enrollmentId], carrying the owner
  /// as `KeychainAtKeysIo` stamps it.
  AtKeys keysFor(String atSign, [String? enrollmentId]) =>
      bare(enrollmentId ?? 'e-$atSign')
        ..atsign = atSign.toAtsign()
        ..metadata['atsign'] = atSign;

  CryptographicMaterial material(String keyId) => CryptographicMaterial(
    keyId: keyId,
    role: CryptographicMaterialRole.symmetricEncryption,
    algorithm: CryptographicMaterialAlgorithm.aes256,
    bytes: AtBytes.fromString(base64Encode(utf8.encode(keyId))),
    createdAt: DateTime.utc(2026, 1, 1),
  );

  /// A keychain document holding [keys], in order.
  String documentOf(List<Map<String, dynamic>> keys) =>
      jsonEncode({'keys': keys});

  /// The entries the keychain holds, in order, as stored.
  List<Map<String, dynamic>> entries() => [
    for (final entry
        in (jsonDecode(blob!) as Map<String, dynamic>)['keys'] as List)
      entry as Map<String, dynamic>,
  ];

  int entryCount() => entries().length;

  /// How many entries the keychain holds for [atSign].
  int entriesFor(String atSign) =>
      entries().where((entry) => entry['atsign'] == atSign).length;

  test(
    'Appending keys for an Atsign the keychain already holds is refused',
    () async {
      final keys = keychain();
      await keys.appendAtKeysToKeychain(keys: keysFor('@alice', 'first'));
      final before = blob;
      final writesBefore = writes;

      await expectLater(
        keys.appendAtKeysToKeychain(keys: keysFor('@alice', 'second')),
        throwsA(
          isA<AtKeysFileOverwriteException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"@alice"'),
              contains('nothing was added'),
              contains('KeychainAtKeysIo.update'),
            ),
          ),
        ),
      );

      expect(writes, writesBefore, reason: 'a refused append writes nothing');
      expect(blob, before);
      expect(entries(), hasLength(1));
      expect(entriesFor('@alice'), 1);
      expect(
        (await keys.getAtsign('@alice'))!.storedEnrollmentId,
        'first',
        reason: 'the entry the keychain holds is the first keys',
      );
    },
  );

  test('Appending keys for another Atsign adds them', () async {
    final keys = keychain();
    final alice = keysFor('@alice', 'e-alice');
    final bob = keysFor('@bob', 'e-bob');
    await keys.appendAtKeysToKeychain(keys: alice);

    await keys.appendAtKeysToKeychain(keys: bob);

    expect(entries(), hasLength(2));
    expect(entriesFor('@alice'), 1);
    expect(entriesFor('@bob'), 1);
    for (final (atSign, written) in [('@alice', alice), ('@bob', bob)]) {
      expect(
        jsonEncode((await keys.getAtsign(atSign))!.toJson()),
        jsonEncode(written.toJson()),
        reason: '$atSign reads back as it was written',
      );
    }
  });

  test('Two appends for one Atsign at once add one entry', () async {
    final outcomes = await Future.wait([
      for (final enrollmentId in ['first', 'second'])
        keychain()
            .appendAtKeysToKeychain(keys: keysFor('@alice', enrollmentId))
            .then(
              (_) => 'completed',
              onError: (Object e) =>
                  e is AtKeysFileOverwriteException ? 'refused' : throw e,
            ),
    ]);

    expect(
      outcomes,
      unorderedEquals(['completed', 'refused']),
      reason:
          'two appends that each read the keychain before the other wrote '
          'would both complete, and one set of keys would be lost',
    );
    expect(entries(), hasLength(1));
    expect(entriesFor('@alice'), 1);
  });

  test(
    'Appending keys that name their Atsign only in the typed field files them '
    'under that Atsign',
    () async {
      final keys = keychain();
      await keys.appendAtKeysToKeychain(
        keys: bare('first')..atsign = '@alice'.toAtsign(),
      );

      expect(
        (await keys.getAtsign('@alice'))?.storedEnrollmentId,
        'first',
        reason: 'reading @alice returns them',
      );
      await expectLater(
        keys.appendAtKeysToKeychain(
          keys: bare('second')..atsign = '@alice'.toAtsign(),
        ),
        throwsA(isA<AtKeysFileOverwriteException>()),
        reason: 'a second append for @alice is refused',
      );
      expect(entries(), hasLength(1));
    },
  );

  test(
    'Appending keys whose typed Atsign and metadata name different Atsigns is '
    'refused',
    () async {
      final keys = keychain();
      await keys.appendAtKeysToKeychain(keys: keysFor('@bob', 'bob'));
      final before = blob;
      reads = 0;
      writes = 0;
      final conflicting = bare('conflicting')
        ..atsign = '@alice'.toAtsign()
        ..metadata['atsign'] = '@bob';

      await expectLater(
        keys.appendAtKeysToKeychain(keys: conflicting),
        throwsA(
          isA<AtKeysValidationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"@alice"'), contains('"@bob"')),
          ),
        ),
      );

      expect(reads, 0, reason: 'it is refused before the keychain is read');
      expect((writes, blob), (0, before), reason: 'the keychain is unchanged');
      expect('${conflicting.atsign}', '@alice');
      expect(conflicting.metadata, {
        'atsign': '@bob',
      }, reason: 'the keys are unchanged');
    },
  );

  test(
    'Appending keys with no typed key material that name no Atsign adds them',
    () async {
      final keys = keychain();

      await keys.appendAtKeysToKeychain(keys: bare('first'));
      await keys.appendAtKeysToKeychain(keys: bare('second'));

      expect(entries().map((entry) => entry['enrollmentId']), [
        'first',
        'second',
      ], reason: 'both appends complete');
    },
  );

  test(
    "Changing an Atsign's keys with keys that name another Atsign is refused",
    () async {
      final keys = keychain();
      await keys.appendAtKeysToKeychain(keys: keysFor('@alice', 'first'));
      final before = blob;
      reads = 0;
      writes = 0;

      await expectLater(
        keys.updateAtKeysInKeychain(
          atSign: '@carol',
          keys: keysFor('@alice', 'second'),
        ),
        throwsA(
          isA<AtKeysValidationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"@alice"'), contains('"@carol"')),
          ),
        ),
      );

      expect(reads, 0, reason: 'it is refused before the keychain is read');
      expect((writes, blob), (0, before), reason: 'the keychain is unchanged');
    },
  );

  test(
    "Changing an Atsign's keys with keys that name no Atsign files them under "
    'that Atsign',
    () async {
      final keys = keychain();
      await keys.appendAtKeysToKeychain(keys: keysFor('@alice', 'first'));

      await keys.updateAtKeysInKeychain(atSign: '@alice', keys: bare('second'));

      expect(
        (await keys.getAtsign('@alice'))?.storedEnrollmentId,
        'second',
        reason: 'reading @alice returns the new keys',
      );
      expect(entries(), hasLength(1));
    },
  );

  test('Writing keys whose metadata names another Atsign is refused', () async {
    final written = bare('written')..metadata['atsign'] = '@alice';

    await expectLater(
      io.write('@carol', written),
      throwsA(isA<AtKeysValidationException>()),
    );

    expect((writes, blob), (0, null), reason: 'the keychain is unchanged');
    expect(
      written.atsign,
      isNull,
      reason: 'the keys are refused before they are stamped for @carol',
    );
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

  test('a keychain that already holds two entries for one Atsign reads the '
      'first and removes both', () async {
    blob = documentOf([
      keysFor('@alice', 'first').toJson(),
      keysFor('@bob', 'bob').toJson(),
      keysFor('@alice', 'second').toJson(),
    ]);
    final keys = keychain();

    expect(
      (await keys.getAtsign('@alice'))?.storedEnrollmentId,
      'first',
      reason: 'a reader takes the first entry',
    );
    expect((await io.read('@alice')).storedEnrollmentId, 'first');
    await expectLater(
      keys.appendAtKeysToKeychain(keys: keysFor('@alice', 'third')),
      throwsA(isA<AtKeysFileOverwriteException>()),
    );

    await keys.removeAtsignFromKeychain('@alice');

    expect(entries().map((entry) => entry['enrollmentId']), [
      'bob',
    ], reason: 'a removal takes both');
  });

  test('an append for an Atsign held only in the legacy-named store is '
      'refused, and only the copy of that store is written', () async {
    const current = '@atsigns:test';
    const legacy = '@atsigns_test';
    final held = {
      legacy: documentOf([keysFor('@alice', 'first').toJson()]),
    };
    final legacyBefore = held[legacy];

    await expectLater(
      keychainOf(
        held,
      ).appendAtKeysToKeychain(keys: keysFor('@alice', 'second')),
      throwsA(
        isA<AtKeysFileOverwriteException>().having(
          (e) => e.message,
          'message',
          contains('nothing was added'),
        ),
      ),
    );

    expect(held[legacy], legacyBefore);
    expect(
      [
        for (final entry
            in (jsonDecode(held[current]!) as Map<String, dynamic>)['keys']
                as List)
          (entry as Map<String, dynamic>)['enrollmentId'],
      ],
      ['first'],
      reason: 'the current store holds the copied keys and nothing added',
    );
  });

  test('an Atsign named only by the legacy `name` metadata entry is held, '
      'whichever way the appended keys name it', () async {
    blob = documentOf([
      {...bare('first').toJson(), 'name': '@alice'},
    ]);
    final keys = keychain();

    for (final (how, named) in [
      ('by the name entry', bare('second')..metadata['name'] = '@alice'),
      ('by the typed field', bare('second')..atsign = '@alice'.toAtsign()),
      ('by the atsign entry', bare('second')..metadata['atsign'] = '@alice'),
    ]) {
      await expectLater(
        keys.appendAtKeysToKeychain(keys: named),
        throwsA(isA<AtKeysFileOverwriteException>()),
        reason: 'keys naming @alice $how',
      );
    }
    expect(entryCount(), 1);
  });

  test('a metadata `atsign` entry that is empty or not a string names no '
      'Atsign', () async {
    for (final value in <Object?>['', null, 42]) {
      blob = null;
      final keys = keychain();
      final typed = bare('typed')
        ..atsign = '@alice'.toAtsign()
        ..metadata['atsign'] = value;

      await keys.appendAtKeysToKeychain(keys: typed);
      await keys.appendAtKeysToKeychain(
        keys: bare('first')..metadata['atsign'] = value,
      );
      await keys.appendAtKeysToKeychain(
        keys: bare('second')..metadata['atsign'] = value,
      );

      expect(
        (await keys.getAtsign('@alice'))?.storedEnrollmentId,
        'typed',
        reason: 'typed keys are stamped over a metadata atsign of $value',
      );
      expect(
        entryCount(),
        3,
        reason: 'keys naming nothing but $value are each appended',
      );
    }
  });

  test('one Atsign spelled two ways across the typed field and the metadata '
      'is not a conflict', () async {
    final keys = keychain();
    final spelled = bare('first')
      ..atsign = '@alice'.toAtsign()
      ..metadata['atsign'] = '@Alice';

    await keys.appendAtKeysToKeychain(keys: spelled);
    await keys.updateAtKeysInKeychain(atSign: 'alice', keys: spelled);

    expect(spelled.metadata['atsign'], '@Alice', reason: 'kept as spelled');
    expect((await keys.getAtsign('@alice'))?.storedEnrollmentId, 'first');
    expect(entryCount(), 1);
  });

  test('keys with typed key material whose typed Atsign and metadata name '
      'different Atsigns are refused too', () async {
    final conflicting = AtKeys(atsign: '@alice'.toAtsign())
      ..addKey(material('nskey.wavi'))
      ..metadata['atsign'] = '@bob';

    await expectLater(
      keychain().appendAtKeysToKeychain(keys: conflicting),
      throwsA(isA<AtKeysValidationException>()),
    );

    expect((reads, writes, blob), (0, 0, null));
  });

  test('keys with typed key material and no typed Atsign are refused when '
      'serialised', () async {
    await expectLater(
      keychain().appendAtKeysToKeychain(
        keys: AtKeys()..addKey(material('nskey.wavi')),
      ),
      throwsA(
        isA<AtKeysValidationException>().having(
          (e) => e.message,
          'message',
          contains('atsign is required'),
        ),
      ),
    );

    expect((writes, blob), (0, null));
  });

  test('getAllAtsigns lists an Atsign stored under two spellings once, in the '
      'spelling stored first', () async {
    blob = documentOf([
      for (final (atSign, enrollmentId) in [
        ('@colin.constable', 'c1'),
        ('@bob', 'b'),
        ('@colinconstable', 'c2'),
        (null, 'none'),
        ('@al ice', 'm1'),
        ('@al ice', 'm2'),
      ])
        {...bare(enrollmentId).toJson(), 'atsign': ?atSign},
    ]);

    expect(await keychain().getAllAtsigns(), [
      '@colin.constable',
      '@bob',
      '@al ice',
    ]);
  });

  test('getAllAtsigns lists no Atsign for an entry whose metadata `atsign` is '
      'empty', () async {
    blob = documentOf([
      {...bare('empty-1').toJson(), 'atsign': ''},
      {...bare('empty-2').toJson(), 'atsign': ''},
      keysFor('@alice').toJson(),
    ]);

    expect(await keychain().getAllAtsigns(), ['@alice']);
  });

  test('keys whose metadata `atsign` and `name` entries name different '
      'Atsigns are refused', () async {
    final conflicting = bare('conflicting')
      ..metadata['atsign'] = '@alice'
      ..metadata['name'] = '@bob';

    await expectLater(
      keychain().appendAtKeysToKeychain(keys: conflicting),
      throwsA(
        isA<AtKeysValidationException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"@alice"'), contains('"@bob"'), contains('name')),
        ),
      ),
    );

    expect(
      (reads, writes, blob),
      (0, 0, null),
      reason: 'it is refused before the keychain is read',
    );
    expect(conflicting.metadata, {'atsign': '@alice', 'name': '@bob'});
  });

  test('accepted keys stay updatable after their first typed store', () async {
    final outcomes = <String, String>{};
    for (final (shape, metadata) in <(String, Map<String, Object?>)>[
      ('no name', {}),
      ('the atsign entry', {'atsign': '@alice'}),
      ('the name entry', {'name': '@alice'}),
      (
        'both entries, spelled two ways',
        {'atsign': '@Alice', 'name': '@ALICE'},
      ),
      (
        'an empty atsign entry and the name entry',
        {'atsign': '', 'name': '@alice'},
      ),
      (
        'the atsign entry and another name entry',
        {'atsign': '@alice', 'name': '@bob'},
      ),
      (
        'a non-string atsign entry and another name entry',
        {'atsign': 42, 'name': '@bob'},
      ),
    ]) {
      blob = null;
      try {
        await io.write('@alice', bare(shape)..metadata.addAll(metadata));
      } on AtKeysValidationException {
        outcomes[shape] = 'refused';
        continue;
      }
      try {
        for (final keyId in ['nskey.one', 'nskey.two']) {
          await io.update('@alice'.toAtsign(), (stored) {
            stored.addKey(material(keyId));
            return true;
          });
        }
        final reread = await io.read('@alice');
        outcomes[shape] =
            reread.getAtSignKey(
                  'nskey.two',
                  CryptographicMaterialRole.symmetricEncryption,
                ) ==
                null
            ? 'lost'
            : 'updatable';
      } on AtKeysValidationException catch (e) {
        outcomes[shape] = 'stuck: ${e.message}';
      }
    }

    expect(
      outcomes,
      {
        'no name': 'updatable',
        'the atsign entry': 'updatable',
        'the name entry': 'updatable',
        'both entries, spelled two ways': 'updatable',
        'an empty atsign entry and the name entry': 'updatable',
        'the atsign entry and another name entry': 'refused',
        'a non-string atsign entry and another name entry': 'refused',
      },
      reason:
          'keys a write accepts stay updatable once a typed store folds their '
          'metadata atsign entry into the typed field, and keys naming two '
          'Atsigns are refused at the write',
    );
  });

  test('a refused append or update leaves the caller\'s keys as they '
      'were', () async {
    final keys = keychain();
    final added = bare('added')..atsign = '@alice'.toAtsign();
    await keys.appendAtKeysToKeychain(keys: added);
    expect(added.metadata, {
      'atsign': '@alice',
    }, reason: 'the control: keys that are added are stamped');

    for (final (what, refused, refusal, thrown)
        in <(String, AtKeys, Future<void> Function(AtKeys), Matcher)>[
          (
            'an append for a held Atsign',
            bare('appended')..atsign = '@alice'.toAtsign(),
            (refused) => keys.appendAtKeysToKeychain(keys: refused),
            isA<AtKeysFileOverwriteException>(),
          ),
          (
            'an update of an Atsign the keychain does not hold',
            bare('absent'),
            (refused) => keys.updateAtKeysInKeychain(
              atSign: '@carol',
              keys: refused,
              requireExisting: true,
            ),
            isA<AtKeysSourceAbsentException>(),
          ),
          (
            'an update its assurance refuses',
            bare('assured'),
            (refused) => keys.updateAtKeysInKeychain(
              atSign: '@alice',
              keys: refused,
              assureUpdate: (_) => throw StateError('refused'),
            ),
            isA<StateError>(),
          ),
        ]) {
      final typedBefore = refused.atsign;
      await expectLater(refusal(refused), throwsA(thrown), reason: what);
      expect(
        refused.metadata,
        isEmpty,
        reason: '$what leaves the keys unstamped',
      );
      expect(refused.atsign, typedBefore, reason: what);
    }
  });
}
