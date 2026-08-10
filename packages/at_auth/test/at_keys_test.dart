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

    test('equality compares metadata structurally, not by identity', () {
      // Two jsonDecode calls produce distinct nested map instances.
      final first = AtKeys()
        ..metadata = jsonDecode('{"nested": {"a": 1, "list": [1, 2]}}');
      final same = AtKeys()
        ..metadata = jsonDecode('{"nested": {"a": 1, "list": [1, 2]}}');
      final different = AtKeys()
        ..metadata = jsonDecode('{"nested": {"a": 2, "list": [1, 2]}}');

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
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
      final publicMaterial = pair.firstWhere(
          (m) => m.keyPartType == CryptographicKeyType.publicEncryption);
      final privateMaterial = pair.firstWhere(
          (m) => m.keyPartType == CryptographicKeyType.privateDecryption);

      expect(
        atKeys.getKey('shared-pair', CryptographicKeyType.publicEncryption),
        same(publicMaterial),
      );
      expect(
        atKeys.getKey('shared-pair', CryptographicKeyType.privateDecryption),
        same(privateMaterial),
      );
    });

    test('getKey returns null when the keyId has no material of that type', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(
        atKeys.getKey('shared-id', CryptographicKeyType.privateDecryption),
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

    test('unknown keyPartType/keyAlgorithmType tokens round-trip unmodified',
        () {
      // keyPartType and keyAlgorithmType are open Strings: a reader must
      // hold and re-emit tokens it does not recognise, so a keyfile written
      // by a newer client survives a read-modify-flush by an older one.
      final futuristic = AtKeysMaterial(
        keyId: 'from-the-future',
        keyPartType: 'somethingNotInventedYet',
        keyAlgorithmType: 'slhdsa128s',
        bytes: AtBytes.fromString('ZnV0dXJl'),
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final atKeys = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [futuristic, symmetricKey('familiar')],
      );

      final reparsed = AtKeys.fromJson(atKeys.toJson());
      expect(
        reparsed.getKey('from-the-future', 'somethingNotInventedYet'),
        futuristic,
      );
      expect(reparsed, atKeys);
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
            .getKey('pair', CryptographicKeyType.publicEncryption)!
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

  group('AtKeys fileApkamMaterial', () {
    test('files both halves under one apkam:<enrollmentId> keyId', () {
      final atKeys = AtKeys();

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-9',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'cHVibGljLWhhbGY=',
          privateKey: 'cHJpdmF0ZS1oYWxm');

      final filed = atKeys.keysForKeyId('apkam:enroll-9').toList();
      expect(filed, hasLength(2));
      expect(
        atKeys
            .getKey('apkam:enroll-9', CryptographicKeyType.privateSigning)!
            .bytes
            .toString(),
        'cHJpdmF0ZS1oYWxm',
      );
      expect(
        atKeys
            .getKey('apkam:enroll-9', CryptographicKeyType.publicVerification)!
            .bytes
            .toString(),
        'cHVibGljLWhhbGY=',
      );
      expect(filed.map((m) => m.enrollmentId), everyElement('enroll-9'));
      expect(filed.map((m) => m.keyAlgorithmType),
          everyElement(KeyAlgorithmType.mlDsa65));
      // One mint is one event: both halves carry the same timestamp.
      expect(filed.first.createdAt, filed.last.createdAt);
    });

    test('the filed enrollment resolves its own signing algorithm', () {
      final atKeys = AtKeys();

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-9',
          algorithm: KeyAlgorithmType.rsa2048,
          publicKey: 'cHVibGljLWhhbGY=',
          privateKey: 'cHJpdmF0ZS1oYWxm');

      expect(atKeys.keysForEnrollment('enroll-9'), hasLength(2));
      expect(atKeys.signingAlgorithmForEnrollment('enroll-9'),
          SigningAlgoType.rsa2048);
    });
  });

  group('AtKeys adoptMaterials', () {
    test('re-tags the enrollment id and changes nothing else', () {
      final built = DateTime.utc(2026, 3, 4, 5, 6, 7);
      final source = AtKeys(keysList: [
        symmetricKey('kem:xwing',
            value: 'c2VjcmV0',
            enrollmentId: 'the-old-enrollment',
            createdAt: built),
      ]);
      final target = AtKeys();

      target.adoptMaterials(source.keys, enrollmentId: 'the-new-enrollment');

      final adopted = target.keysForKeyId('kem:xwing').single;
      expect(adopted.enrollmentId, 'the-new-enrollment');
      expect(adopted.keyId, 'kem:xwing');
      expect(adopted.keyPartType, CryptographicKeyType.symmetricEncryption);
      expect(adopted.keyAlgorithmType, KeyAlgorithmType.aes256);
      expect(adopted.bytes.toString(), 'c2VjcmV0');
      // The builder's own timestamp, not the adoption's.
      expect(adopted.createdAt, built);
      // The source keeps its own tag: adoption copies, it does not move.
      expect(source.keysForKeyId('kem:xwing').single.enrollmentId,
          'the-old-enrollment');
    });

    test('carries a non-default status and operations across', () {
      final source = AtKeys(keysList: [
        AtKeysMaterial(
            keyId: 'kem:xwing',
            enrollmentId: 'the-old-enrollment',
            keyPartType: CryptographicKeyType.privateDecapsulation,
            keyAlgorithmType: KeyAlgorithmType.xWing,
            bytes: AtBytes.fromString('c2VjcmV0'),
            operations: const ['decapsulate'],
            createdAt: DateTime.utc(2026, 3, 4),
            status: KeyPartStatus.retired),
      ]);
      final target = AtKeys();

      target.adoptMaterials(source.keys, enrollmentId: 'the-new-enrollment');

      final adopted = target.keysForKeyId('kem:xwing').single;
      expect(adopted.status, KeyPartStatus.retired);
      expect(adopted.operations, ['decapsulate']);
      expect(adopted.keyAlgorithmType, KeyAlgorithmType.xWing);
    });

    test('adopts every material of a multi-part keyId', () {
      final source = AtKeys(keysList: [
        ...rsaKeyPair('pair', enrollmentId: 'the-old-enrollment'),
      ]);
      final target = AtKeys();

      target.adoptMaterials(source.keys, enrollmentId: 'the-new-enrollment');

      expect(target.keysForEnrollment('the-new-enrollment'), hasLength(2));
      expect(target.keysForEnrollment('the-old-enrollment'), isEmpty);
    });

    test('refuses to adopt onto a keyId another enrollment already holds', () {
      final target = AtKeys(keysList: [
        symmetricKey('kem:xwing', enrollmentId: 'the-sitting-enrollment'),
      ]);
      final source = AtKeys(keysList: [
        AtKeysMaterial(
            keyId: 'kem:xwing',
            enrollmentId: 'the-old-enrollment',
            keyPartType: CryptographicKeyType.privateDecapsulation,
            keyAlgorithmType: KeyAlgorithmType.xWing,
            bytes: AtBytes.fromString('c2VjcmV0'),
            createdAt: DateTime.utc(2026, 3, 4)),
      ]);

      expect(
        () => target.adoptMaterials(source.keys,
            enrollmentId: 'the-new-enrollment'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
