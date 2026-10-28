import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

/// Catalogue: features/at_auth/released_keyfile.feature
void main() {
  const atsign = '@alice🛠';
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('released_keyfile_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  String released(String release, String file) =>
      'test/data/released/at_auth-$release/$file';

  /// A copy of [release]'s fixture [name] in this test's directory.
  String copyOf(String release, String name) {
    final copy = '${dir.path}/$name.atKeys';
    File(released(release, '$name.atKeys')).copySync(copy);
    return copy;
  }

  /// What [release]'s own reader returned for its fixture [name], recorded
  /// when the fixture was captured.
  Map<String, Object?> readBackOf(String release, String name) {
    final recorded = jsonDecode(
            File(released(release, '$name.read_back.json')).readAsStringSync())
        as Map<String, dynamic>;
    return {for (final field in _readFields) field: recorded[field]};
  }

  String passphraseOf(String release, String name) {
    final provenance = jsonDecode(
            File(released(release, 'provenance.json')).readAsStringSync())
        as Map<String, dynamic>;
    final fixture = (provenance['fixtures'] as List).cast<Map>().singleWhere(
        (fixture) => (fixture['keyfile'] as Map)['name'] == '$name.atKeys');
    return fixture['passphrase'] as String;
  }

  /// Fails, naming them, on top-level fields of [path]'s document that are
  /// neither read into [keys] nor kept in its metadata.
  void expectEveryFieldRead(String path, AtKeys keys) {
    final document =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final unread = document.keys
        .where((field) =>
            !_legacyFieldsRead.contains(field) &&
            !_structureFields.contains(field) &&
            !keys.metadata.containsKey(field))
        .toList();
    expect(unread, isEmpty,
        reason: 'every top-level field is one FileAtKeysIo reads or kept in '
            'metadata');
  }

  for (final release in ['3.3.0', '3.2.0']) {
    final is330 = release == '3.3.0';

    group(
        'A keyfile the previous published at_auth wrote still reads and '
        'updates: at_auth $release', () {
      test('The current build reads every value at_auth $release wrote',
          () async {
        final path = copyOf(release, 'alice_key');

        final keys = await FileAtKeysIo(filePath: (_) => path).read(atsign);

        expect(_valuesOf(keys), readBackOf(release, 'alice_key'),
            reason: 'each key, the enrollment id and the apkam symmetric key '
                'equal what at_auth $release read');
        expectEveryFieldRead(path, keys);
        if (is330) {
          expect(keys.atsign, atsign.toAtsign(),
              reason: 'the atsign field at_auth 3.3.0 wrote is read');
        }
      });

      test(
          is330
              ? 'Flushing it back unchanged keeps every value'
              : 'Flushing the keyfile at_auth 3.2.0 wrote back unchanged '
                  'keeps every value', () async {
        final path = copyOf(release, 'alice_key');
        final io = FileAtKeysIo(filePath: (_) => path);

        await io.update(atsign.toAtsign(), (keys) => true);

        expect(
            _valuesOf(await io.read(atsign)), readBackOf(release, 'alice_key'),
            reason: 'reading it back gives every value at_auth $release read');
      });

      test(
          is330
              ? 'Filing typed key material keeps every value'
              : 'Filing typed key material in the keyfile at_auth 3.2.0 wrote '
                  'keeps every value', () async {
        final path = copyOf(release, 'alice_key');
        final original = File(path).readAsBytesSync();
        final io = FileAtKeysIo(filePath: (_) => path);
        late String enrollmentId;

        await io.update(atsign.toAtsign(), (keys) {
          enrollmentId = keys.enrollmentId!;
          keys.addKey(symmetricKey('typed', enrollmentId: enrollmentId));
          return true;
        });

        final back = await io.read(atsign);
        expect(_valuesOf(back), readBackOf(release, 'alice_key'),
            reason: 'reading it back gives every value at_auth $release read');
        expect(
            back.getKey(enrollmentId, 'typed',
                CryptographicMaterialRole.symmetricEncryption),
            isNotNull,
            reason: 'and the new material');
        if (!is330) {
          expect(
              File('$path${FileAtKeysIo.legacyShapeBackupSuffix}')
                  .readAsBytesSync(),
              original,
              reason: 'the .pre-v1 copy holds the 3.2.0 document byte for '
                  'byte');
        }
      });
    });
  }

  group(
      'A keyfile the previous published at_auth wrote still reads and '
      'updates: at_auth 3.3.0 only', () {
    test('The fixture is not a document this build writes', () async {
      final path = copyOf('3.3.0', 'alice_key');
      final keys = await FileAtKeysIo(filePath: (_) => path).read(atsign);
      final rewritten = '${dir.path}/rewritten.atKeys';

      await FileAtKeysIo(filePath: (_) => rewritten).write(atsign, keys);

      expect(jsonDecode(File(rewritten).readAsStringSync()),
          isNot(jsonDecode(File(path).readAsStringSync())),
          reason: 'the fixture holds what at_auth 3.3.0 wrote, which is not '
              'what this build writes for the same keys');
    });

    test(
        'A typed keyfile with no typed key material is rewritten in the flat '
        'shape', () async {
      final path = copyOf('3.3.0', 'alice_key');
      final before =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(
          before,
          allOf(containsPair('version', 1), containsPair('atsign', atsign),
              containsPair('keys', isEmpty)),
          reason: 'the Given: version 1, its atSign and an empty keys array');
      expect(before.keys,
          isNot(anyOf(contains('enrollments'), contains('atsignKeys'))),
          reason: 'the Given: no typed key material');
      final io = FileAtKeysIo(filePath: (_) => path);

      await io.update(atsign.toAtsign(), (keys) => true);

      final after =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(
          after.keys,
          isNot(
              anyOf(contains('version'), contains('atsign'), contains('keys'))),
          reason: 'the keyfile is written in the flat shape');
      expect({
        for (final field in _legacyFieldsRead) field: after[field]
      }, {
        for (final field in _legacyFieldsRead) field: before[field]
      }, reason: 'with every value it held, as it was at rest');
      expect(_valuesOf(await io.read(atsign)), readBackOf('3.3.0', 'alice_key'),
          reason: 'with every value it held, as at_auth 3.3.0 read it');
    });

    test('A keyfile naming another atSign is still refused', () async {
      final path = copyOf('3.3.0', 'alice_key');
      final document =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      File(path)
          .writeAsStringSync(jsonEncode({...document, 'atsign': '@bob🛠'}));

      await expectLater(
          FileAtKeysIo(filePath: (_) => path).update(atsign.toAtsign(), (keys) {
            keys.atsign = atsign.toAtsign();
            return true;
          }),
          throwsA(isA<AtKeysAssuranceException>()
              .having((e) => e.message, 'message', contains('map.atsign'))),
          reason: 'a keyfile whose atsign field names another atSign is not '
              'rewritten for $atsign, even with keys that name $atsign');
    });

    test(
        'The current build reads every value at_auth 3.3.0 wrote under a '
        'passphrase', () async {
      final path = copyOf('3.3.0', 'alice_key_passphrase');

      final keys = await FileAtKeysIo(
              filePath: (_) => path,
              passPhrase: passphraseOf('3.3.0', 'alice_key_passphrase'))
          .read(atsign);

      expect(_valuesOf(keys), readBackOf('3.3.0', 'alice_key_passphrase'),
          reason: 'each key, the enrollment id and the apkam symmetric key '
              'equal what at_auth 3.3.0 read');
    });
  });

  group(
      'A keyfile the previous published at_auth wrote still reads and '
      'updates: a keyfile holding only pending content', () {
    final pendingContent = <(String, AtKeys Function(Atsign owner))>[
      (
        'a pending enrollment',
        (owner) => AtKeys(atsign: owner)
          ..addKey(symmetricKey('pending', enrollmentId: 'e-1')
              .withStatus(CryptographicMaterialStatus.pending))
      ),
      (
        'an enrollment with no keys yet',
        (owner) => AtKeys(atsign: owner)
          ..recordEnrollmentSnapshot('e-1', appName: 'app')
      ),
      (
        'pending keys of its own atSign',
        (owner) => AtKeys(atsign: owner)
          ..addKey(symmetricKey('pending')
              .withStatus(CryptographicMaterialStatus.pending))
      ),
    ];

    /// Writes a keyfile for [owner] holding [content], at a path every
    /// atSign shares.
    Future<String> keyfileFor(String owner, AtKeys content) async {
      final path = '${dir.path}/shared.atKeys';
      await FileAtKeysIo(filePath: (_) => path).write(owner, content);
      final written =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(written,
          allOf(containsPair('version', 1), containsPair('atsign', owner)),
          reason: 'the Given: a typed keyfile whose atsign field names $owner');
      expect(
          written.keys, anyOf(contains('enrollments'), contains('atsignKeys')),
          reason: 'the Given: it holds pending content');
      expect([
        written['aesPkamPrivateKey'],
        written['aesEncryptPrivateKey'],
        written['selfEncryptionKey'],
      ], everyElement(isNull), reason: 'the Given: it holds no credential');
      return path;
    }

    for (final (shape, content) in pendingContent) {
      test(
          'A keyfile naming another atSign and holding only pending content '
          'is still refused: $shape', () async {
        final path = await keyfileFor('@bob🛠', content('@bob🛠'.toAtsign()));
        final before = File(path).readAsStringSync();

        await expectLater(
            FileAtKeysIo(filePath: (_) => path)
                .flush(atsign.toAtsign(), legacyAtKeys()),
            throwsA(isA<AtKeysAssuranceException>()
                .having((e) => e.message, 'message', contains('map.atsign'))),
            reason: 'a keyfile whose atsign field names another atSign is not '
                'rewritten for $atsign, whatever pending content it holds');
        expect(File(path).readAsStringSync(), before,
            reason: 'the keyfile is left as it was');
      });

      test(
          'A keyfile holding only its own pending content is rewritten in '
          'the flat shape: $shape', () async {
        final path = await keyfileFor(atsign, content(atsign.toAtsign()));
        final io = FileAtKeysIo(filePath: (_) => path);

        await io.flush(atsign.toAtsign(), legacyAtKeys());

        final after =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        expect(after.keys, isNot(contains('version')),
            reason: 'the keyfile is written in the flat shape');
        expectLegacyAtKeys(await io.read(atsign), legacyAtKeys());
      });
    }

    test(
        'A keyfile naming another atSign and holding only pending content is '
        'still refused: as when it holds nothing typed', () async {
      final path = '${dir.path}/shared.atKeys';
      File(path).writeAsStringSync(
          jsonEncode({'version': 1, 'atsign': '@bob🛠', 'keys': <Object?>[]}));

      await expectLater(
          FileAtKeysIo(filePath: (_) => path)
              .flush(atsign.toAtsign(), legacyAtKeys()),
          throwsA(isA<AtKeysAssuranceException>()
              .having((e) => e.message, 'message', contains('map.atsign'))),
          reason: 'a keyfile whose atsign field names another atSign is not '
              'rewritten for $atsign');
    });
  });

  group(
      'A keyfile the previous published at_auth wrote still reads and '
      'updates: a flat keyfile holding no credential', () {
    /// Writes a flat keyfile whose atsign field names [owner] and that holds
    /// no credential, at a path every atSign shares.
    Future<String> flatKeyfileFor(String owner) async {
      final path = '${dir.path}/shared.atKeys';
      await FileAtKeysIo(filePath: (_) => path)
          .write(owner, AtKeys()..metadata['atsign'] = owner);
      final written =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(written.keys, isNot(contains('version')),
          reason: 'the Given: a flat keyfile');
      expect(written, containsPair('atsign', owner),
          reason: 'the Given: its atsign field names $owner');
      expect([
        written['aesPkamPrivateKey'],
        written['aesEncryptPrivateKey'],
        written['selfEncryptionKey'],
      ], everyElement(isNull), reason: 'the Given: it holds no credential');
      return path;
    }

    test(
        'A flat keyfile naming another atSign and holding no credential is '
        'still refused', () async {
      final path = await flatKeyfileFor('@bob🛠');
      final before = File(path).readAsStringSync();

      await expectLater(
          FileAtKeysIo(filePath: (_) => path)
              .flush(atsign.toAtsign(), legacyAtKeys()),
          throwsA(isA<AtKeysAssuranceException>()
              .having((e) => e.message, 'message', contains('map.atsign'))),
          reason: 'a flat keyfile whose atsign field names another atSign is '
              'not rewritten for $atsign');
      expect(File(path).readAsStringSync(), before,
          reason: 'the keyfile is left as it was');
    });

    test(
        'A flat keyfile holding no credential is rewritten for the atSign it '
        'names', () async {
      final path = await flatKeyfileFor(atsign);
      final io = FileAtKeysIo(filePath: (_) => path);

      await io.flush(atsign.toAtsign(), legacyAtKeys());

      expectLegacyAtKeys(await io.read(atsign), legacyAtKeys());
    });
  });
}

/// The values a released reader's read-back records, by field name.
const _readFields = [
  'apkamPublicKey',
  'apkamPrivateKey',
  'defaultEncryptionPublicKey',
  'defaultEncryptionPrivateKey',
  'defaultSelfEncryptionKey',
  'apkamSymmetricKey',
  'enrollmentId',
];

/// The at-rest names of the legacy fields FileAtKeysIo reads into [AtKeys].
const _legacyFieldsRead = {
  'aesPkamPublicKey',
  'aesPkamPrivateKey',
  'aesEncryptPublicKey',
  'aesEncryptPrivateKey',
  'selfEncryptionKey',
  'apkamSymmetricKey',
  'enrollmentId',
};

/// The typed document's own fields: its version, its atSign and the key
/// list at_auth 3.3.0 wrote.
const _structureFields = {'version', 'atsign', 'keys'};

Map<String, Object?> _valuesOf(AtKeys keys) => {
      'apkamPublicKey': keys.apkamPublicKey?.toString(),
      'apkamPrivateKey': keys.apkamPrivateKey?.toString(),
      'defaultEncryptionPublicKey': keys.defaultEncryptionPublicKey?.toString(),
      'defaultEncryptionPrivateKey':
          keys.defaultEncryptionPrivateKey?.toString(),
      'defaultSelfEncryptionKey': keys.defaultSelfEncryptionKey?.toString(),
      'apkamSymmetricKey': keys.apkamSymmetricKey?.toString(),
      'enrollmentId': keys.enrollmentId,
    };
