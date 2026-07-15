import 'dart:convert';
import 'dart:io';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  String filePath = 'test/data/@alice🛠_key.atKeys';
  final atKeysString = File(filePath).readAsStringSync();
  Map<String, dynamic> encryptedAtKeysMap = jsonDecode(atKeysString);

  // Factory function to always produce a fresh AtKeys instance
  AtKeys createKeys() => AtKeys()
    ..apkamPublicKey =
        AtBytes.fromString(encryptedAtKeysMap[auth_constants.apkamPublicKey])
    ..apkamPrivateKey =
        AtBytes.fromString(encryptedAtKeysMap[auth_constants.apkamPrivateKey])
    ..defaultEncryptionPublicKey = AtBytes.fromString(
        encryptedAtKeysMap[auth_constants.defaultEncryptionPublicKey])
    ..defaultEncryptionPrivateKey = AtBytes.fromString(
        encryptedAtKeysMap[auth_constants.defaultEncryptionPrivateKey])
    ..defaultSelfEncryptionKey = AtBytes.fromString(
        encryptedAtKeysMap[auth_constants.defaultSelfEncryptionKey])
    ..apkamSymmetricKey =
        AtBytes.fromString(encryptedAtKeysMap[auth_constants.apkamSymmetricKey])
    ..enrollmentId = encryptedAtKeysMap['enrollmentId']
    // The fixture's non-schema trailer entry lands in metadata.
    ..metadata = {'@alice🛠': encryptedAtKeysMap['@alice🛠']};

  group('AtKeys legacy json transformers', () {
    test('toJson -> emits the legacy flat shape for a legacy-only AtKeys',
        () async {
      expect(createKeys().toJson(), equals(encryptedAtKeysMap));
    });

    test('toJson -> legacy fields are nullable', () async {
      AtKeys nulledKeys = AtKeys();
      var map = nulledKeys.toJson();
      for (var entry in map.entries) {
        expect(entry.value, isNull);
      }
    });

    test('toJson -> passes legacy metadata through', () async {
      AtKeys keys = createKeys();
      keys.metadata = {'atsign': "@vforreal"};
      var json = keys.toJson();
      var metadata = json['atsign'];
      expect(metadata, equals('@vforreal'));
    });

    test('fromJson -> populates legacy metadata', () async {
      // Copy the map so we don't pollute the shared encryptedAtKeysMap
      final localMap = Map<String, dynamic>.from(encryptedAtKeysMap);
      localMap['atsign'] = "@shabonaganmcsideburns";
      var atKeys = AtKeys.fromJson(localMap);
      expect(atKeys.metadata, isNotEmpty);
    });

    test('fromJson falls back to legacy for json without a version field', () {
      expect(AtKeys.fromJson(encryptedAtKeysMap), equals(createKeys()));
    });

    test('fromJson throws on an unsupported version', () {
      expect(
        () => AtKeys.fromJson({'version': 2, 'atsign': '@alice', 'keys': []}),
        throwsA(isA<AtKeysUnsupportedVersionException>()),
      );
    });
  });

  group('AtKeys AtChops transformers', () {
    late AtKeys apkam;
    late AtKeys mpkam;

    setUp(() {
      apkam = createKeys();
      mpkam = createKeys()..apkamSymmetricKey = null;
    });

    test('Preapproval state for APKAM AtKeys to AtChopsImpl', () {
      apkam.defaultEncryptionPrivateKey = null;
      apkam.defaultSelfEncryptionKey = null;
      var chops = apkam.toAtChops();
      expect(chops, isNotNull);
    });

    test('Postapproval state for APKAM AtKeys to AtChopsImpl', () {
      apkam = createKeys();
      expect(apkam.toAtChops(), isA<AtChopsImpl>());
    });

    test('MPKAM AtKeys to AtChopsImpl', () {
      expect(mpkam.toAtChops(), isA<AtChopsImpl>());
    });

    test('MPKAM AtKeys to AtChopsImpl -> throws', () {
      mpkam.defaultEncryptionPrivateKey = null;
      expect(() => mpkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('APKAM AtKeys to AtChopsImpl -> throws', () {
      apkam.apkamPublicKey = null;
      apkam.defaultEncryptionPrivateKey = null;
      apkam.apkamSymmetricKey = null;
      expect(() => apkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('APKAM AtKeys with a null apkamPublicKey -> throws', () {
      // apkamSymmetricKey is set, so this routes through the APKAM path, which
      // must throw (not fall through to a null-deref) when apkamPublicKey is null.
      apkam.apkamPublicKey = null;
      expect(() => apkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('MPKAM AtKeys with a null apkamPublicKey -> throws', () {
      mpkam.apkamPublicKey = null;
      expect(() => mpkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('MPKAM AtKeys with a null defaultEncryptionPublicKey -> throws', () {
      mpkam.defaultEncryptionPublicKey = null;
      expect(() => mpkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('MPKAM AtKeys with a null defaultSelfEncryptionKey -> throws', () {
      mpkam.defaultSelfEncryptionKey = null;
      expect(() => mpkam.toAtChops(), throwsA(isA<AtException>()));
    });
  });

  group('AtKeys typed key lookup', () {
    test('equality includes atsign and typed key material', () {
      final first = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [
          symmetricKey('shared'),
        ],
      );
      final same = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [
          symmetricKey('shared'),
        ],
      );
      final differentKey = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [
          symmetricKey('shared', value: 'b3RoZXI='),
        ],
      );
      final differentAtsign = AtKeys(
        atsign: '@bob'.toAtsign(),
        keysList: [
          symmetricKey('shared'),
        ],
      );

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(differentKey));
      expect(first, isNot(differentAtsign));
    });

    test('equality ignores the order materials were added in', () {
      final pair = rsaKeyPair('pair');
      final forward = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [symmetricKey('solo'), ...pair],
      );
      final reversed = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [...pair.reversed, symmetricKey('solo')],
      );

      expect(forward, reversed);
      expect(forward.hashCode, reversed.hashCode);
    });

    test('getKey disambiguates materials of the same keyId by type', () {
      final pair = rsaKeyPair('shared-pair');
      final atKeys = AtKeys(keysList: pair);
      final publicMaterial = pair.firstWhere((m) =>
          m.keyPartType == CryptographicKeyType.classicalPublicEncryption);
      final privateMaterial = pair.firstWhere((m) =>
          m.keyPartType == CryptographicKeyType.classicalPrivateDecryption);

      expect(
        atKeys.getKey(
            'shared-pair', CryptographicKeyType.classicalPublicEncryption),
        same(publicMaterial),
      );
      expect(
        atKeys.getKey(
            'shared-pair', CryptographicKeyType.classicalPrivateDecryption),
        same(privateMaterial),
      );
    });

    test('getKey returns null when the keyId has no material of that type', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(
        atKeys.getKey(
            'shared-id', CryptographicKeyType.classicalPrivateDecryption),
        isNull,
      );
    });

    test('keysForKeyId returns empty for an unknown keyId', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(atKeys.keysForKeyId('nope'), isEmpty);
    });

    test('addKey rejects a duplicate keyId', () {
      final atKeys = AtKeys();
      atKeys.addKey(symmetricKey('dupe'));

      expect(
        () => atKeys.addKey(symmetricKey('dupe', value: 'b3RoZXI=')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'addKey rejects a second material of the same type for one enrollment '
        'even across keyIds', () {
      // The read-side invariant (validateKeyMaterials) must hold in memory
      // too, otherwise write() persists a file that read() rejects.
      final atKeys = AtKeys(keysList: [
        symmetricKey('first', enrollmentId: 'enroll-1'),
      ]);

      expect(
        () => atKeys.addKey(symmetricKey('second', enrollmentId: 'enroll-1')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addKey rejects an enrollmentId mismatch within a keyId group', () {
      final atKeys = AtKeys(
        keysList: [rsaKeyPair('pair', enrollmentId: 'enroll-1').first],
      );
      final mismatched = rsaKeyPair('pair', enrollmentId: 'enroll-2').last;

      expect(
        () => atKeys.addKey(mismatched),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('keysForEnrollment returns only keys tagged with that enrollment', () {
      final atKeys = AtKeys(keysList: [
        ...rsaKeyPair('enrolled-pair', enrollmentId: 'enroll-1'),
        symmetricKey('other-enroll', enrollmentId: 'enroll-2'),
        symmetricKey('untagged'),
      ]);

      final enrolled = atKeys.keysForEnrollment('enroll-1');
      expect(enrolled, hasLength(2));
      expect(enrolled.map((m) => m.keyId).toSet(), {'enrolled-pair'});
      expect(atKeys.keysForEnrollment('unknown'), isEmpty);
    });
  });

  group('AtKeys retireKey', () {
    test('marks every material of the group, leaving other fields intact', () {
      final atKeys = AtKeys(keysList: [...rsaKeyPair('pair')]);

      atKeys.retireKey('pair');

      final retired = atKeys.keysForKeyId('pair').toList();
      expect(retired, hasLength(2));
      expect(retired.map((m) => m.status), everyElement(KeyPartStatus.retired));
      expect(
        atKeys
            .getKey('pair', CryptographicKeyType.classicalPublicEncryption)!
            .bytes
            .toString(),
        rsaKeyPair('pair').first.bytes.toString(),
      );
    });

    test('is idempotent for the same status', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      atKeys.retireKey('solo');
      atKeys.retireKey('solo');

      expect(
        atKeys.keysForKeyId('solo').single.status,
        KeyPartStatus.retired,
      );
    });

    test('moves a retired key forward to dead', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      atKeys.retireKey('solo');
      atKeys.retireKey('solo', to: KeyPartStatus.dead);

      expect(atKeys.keysForKeyId('solo').single.status, KeyPartStatus.dead);
    });

    test('throws on a backward transition', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);
      atKeys.retireKey('solo', to: KeyPartStatus.dead);

      expect(
        () => atKeys.retireKey('solo'),
        throwsA(isA<ArgumentError>()),
      );
      expect(atKeys.keysForKeyId('solo').single.status, KeyPartStatus.dead);
    });

    test('throws for an unknown keyId', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireKey('nope'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects KeyPartStatus.active as a target', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireKey('solo', to: KeyPartStatus.active),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
