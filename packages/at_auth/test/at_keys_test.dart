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

    test('an atsign alone does not stamp a legacy file with a version', () {
      // The behaviour: file_io sets atsign on every write, so before this a
      // legacy keyfile gained `version: 1` and an empty `keys` array the
      // first time any new build touched it — a diff on a file nobody meant
      // to change.
      final untyped = createKeys()..atsign = '@alice🛠'.toAtsign();

      final json = untyped.toJson();
      expect(json.containsKey('version'), false);
      expect(json.containsKey('keys'), false);
      expect(json['enrollmentId'], encryptedAtKeysMap['enrollmentId']);

      // The control: the marker DOES appear as soon as there is typed
      // material to mark, or this test would pass against a toJson that never
      // emits a version at all.
      untyped.addKey(symmetricKey('now-typed'));
      final typed = untyped.toJson();
      expect(typed['version'], AtKeys.supportedVersion);
      expect(typed['keys'], hasLength(1));
    });

    test('a legacy document round-trips byte-identically through a new build',
        () {
      // Read, change nothing, write. The bytes must match, because a build
      // that rewrites files it only opened makes every upgrade look like a
      // migration.
      final reread = AtKeys.fromJson(Map<String, dynamic>.from(encryptedAtKeysMap))
        ..atsign = '@alice🛠'.toAtsign();
      expect(reread.toJson(), equals(encryptedAtKeysMap));
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

  group('AtKeys authenticationFor', () {
    // The fixture's flat fields are this enrollment's own credentials.
    final flatEnrollmentId = encryptedAtKeysMap['enrollmentId'] as String;
    final flatApkamPublicKey =
        encryptedAtKeysMap[auth_constants.apkamPublicKey] as String;
    const typedApkamPublicKey = 'dHlwZWQtcHVibGlj';
    const typedEnrollmentId = 'the-retrofitted-enrollment';

    String pkamPublicKeyOf(AtChops chops) =>
        (chops as AtChopsImpl).atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

    /// A keyfile carrying the capped legacy enrollment in the flat fields and
    /// a live enrollment's APKAM in the typed section — the one shape that
    /// holds both, and so the only one where resolving the wrong way round is
    /// observable.
    AtKeys retrofitted() => createKeys()
      ..fileApkamMaterial(
          enrollmentId: typedEnrollmentId,
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: typedApkamPublicKey,
          privateKey: 'dHlwZWQtcHJpdmF0ZQ==');

    test('the two sources genuinely differ', () {
      // Without this the tests below would pass on a resolver that always
      // returned the same keypair.
      expect(flatApkamPublicKey, isNot(typedApkamPublicKey));
    });

    test('a legacy keyfile answers from the flat fields, with no algorithm',
        () {
      final resolved = createKeys().authenticationFor(flatEnrollmentId);

      expect(pkamPublicKeyOf(resolved.chops), flatApkamPublicKey);
      // Null leaves at_lookup at its rsa2048 default, which is what the flat
      // fields hold.
      expect(resolved.algorithm, isNull);
    });

    test('a null enrollment id answers from the flat fields', () {
      final resolved = retrofitted().authenticationFor(null);

      expect(pkamPublicKeyOf(resolved.chops), flatApkamPublicKey);
      expect(resolved.algorithm, isNull);
    });

    test('typed material wins for the enrollment that holds it', () {
      final resolved = retrofitted().authenticationFor(typedEnrollmentId);

      expect(pkamPublicKeyOf(resolved.chops), typedApkamPublicKey);
      expect(resolved.algorithm, SigningAlgoType.mldsa65);
    });

    test('the flat fields still answer for the enrollment that owns them', () {
      final resolved = retrofitted().authenticationFor(flatEnrollmentId);

      expect(pkamPublicKeyOf(resolved.chops), flatApkamPublicKey);
      expect(resolved.algorithm, isNull);
    });

    test('an algorithm this build cannot sign with is refused, not fallen '
        'back from', () {
      // A keyfile written by a newer client. Its material is still this
      // enrollment's, so serving the flat fields would authenticate as the
      // enrollment that owns those — and at_lookup's rsa2048 default would
      // sign the wrong key with the wrong routine.
      final futureAlgo = createKeys()
        ..fileApkamMaterial(
            enrollmentId: 'future-algorithm',
            algorithm: 'sphincs-plus-256s',
            publicKey: typedApkamPublicKey,
            privateKey: 'dHlwZWQtcHJpdmF0ZQ==');

      expect(() => futureAlgo.authenticationFor('future-algorithm'),
          throwsA(isA<AtKeyNotFoundException>()));
      // An enrollment the keyfile holds nothing for still gets the flat
      // fields: absent material and unusable material are different answers.
      expect(futureAlgo.authenticationFor('never-held-here').chops, isNotNull);
    });

    test('authenticationAlgorithmFor answers without building an AtChops', () {
      // Only typed material, so toAtChops() has no flat keypair to build from
      // and throws. The algorithm still resolves — which is what lets a caller
      // holding an injected AtChops name the algorithm without paying for one
      // it will discard.
      final typedOnly = AtKeys()
        ..fileApkamMaterial(
            enrollmentId: typedEnrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: typedApkamPublicKey,
            privateKey: 'dHlwZWQtcHJpdmF0ZQ==');

      expect(() => typedOnly.toAtChops(), throwsA(isA<AtException>()));
      expect(typedOnly.authenticationAlgorithmFor(typedEnrollmentId),
          SigningAlgoType.mldsa65);
    });

    test('authenticationAlgorithmFor mirrors the resolution', () {
      expect(createKeys().authenticationAlgorithmFor(flatEnrollmentId), isNull);
      expect(retrofitted().authenticationAlgorithmFor(null), isNull);
      expect(retrofitted().authenticationAlgorithmFor(typedEnrollmentId),
          SigningAlgoType.mldsa65);
      expect(
          retrofitted().authenticationAlgorithmFor(flatEnrollmentId), isNull);
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

    test(
        'an unknown top-level field survives an older client read-modify-flush',
        () {
      // The typed document reserves only version/atsign/keys; every other
      // top-level entry is held in `metadata` and re-emitted on flush. That
      // is what lets a NEWER client add a top-level pointer — the retrofit
      // naming the enrollment an install should now authenticate as, since
      // after a retrofit the file holds material for both the capped
      // enrollment and the fresh one — without an OLDER client dropping it
      // the first time it reads the file, changes something and writes back.
      final written = (AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [symmetricKey('familiar')],
      )..enrollmentId = 'old-capped-enrollment')
          .toJson()
        ..['activeEnrollmentId'] = 'new-pq-enrollment';

      // An older reader, which knows nothing of activeEnrollmentId.
      final reread = AtKeys.fromJson(written);
      expect(reread.metadata['activeEnrollmentId'], 'new-pq-enrollment',
          reason: 'an unrecognised top-level field must be held, not dropped');

      // It changes something unrelated and flushes.
      reread.addKey(symmetricKey('added-by-the-old-client'));
      final reflushed = reread.toJson();

      expect(reflushed['activeEnrollmentId'], 'new-pq-enrollment',
          reason: 'an older client must re-emit a top-level field it does '
              'not recognise, or the pointer is lost on its first write');
      // The deprecated flat field is carried through untouched alongside it.
      expect(reflushed['enrollmentId'], 'old-capped-enrollment');
      expect(
          reread.getKey('familiar', CryptographicKeyType.symmetricEncryption),
          isNotNull);
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
    test('files both halves under one apkam:<enrollmentId>:<generation> keyId',
        () {
      final atKeys = AtKeys();

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-9',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'cHVibGljLWhhbGY=',
          privateKey: 'cHJpdmF0ZS1oYWxm');

      // Raw literal: the generation-suffixed id is the at-rest shape, and a
      // keyfile written with it has to stay readable by every later build.
      final filed = atKeys.keysForKeyId('apkam:enroll-9:1').toList();
      expect(filed, hasLength(2));
      expect(
        atKeys
            .getKey('apkam:enroll-9:1',
                CryptographicKeyType.privateAuthentication)!
            .bytes
            .toString(),
        'cHJpdmF0ZS1oYWxm',
      );
      expect(
        atKeys
            .getKey('apkam:enroll-9:1',
                CryptographicKeyType.publicAuthentication)!
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

  group('AtKeys authentication material and rotation', () {
    AtKeysMaterial authKey(String keyId,
            {required String enrollmentId,
            String value = 'YXV0aA==',
            KeyPartStatus status = KeyPartStatus.active}) =>
        AtKeysMaterial(
            keyId: keyId,
            enrollmentId: enrollmentId,
            keyPartType: CryptographicKeyType.privateAuthentication,
            keyAlgorithmType: KeyAlgorithmType.mlDsa65,
            bytes: AtBytes.fromString(value),
            createdAt: DateTime.utc(2026, 1, 1),
            status: status);

    test('retiring a key frees its slot for a replacement', () {
      // The whole point of making the invariants status-aware. The control is
      // the second half: WITHOUT retiring, the same add must still throw, or
      // this test would pass against an invariant that checks nothing.
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('apkam:E1:1', enrollmentId: 'E1')]);

      expect(
          () => atKeys.addKey(authKey('apkam:E1:2', enrollmentId: 'E1')),
          throwsArgumentError,
          reason: 'two ACTIVE authentication keys for one enrollment must be '
              'refused');

      atKeys.retireKey('apkam:E1:1');
      atKeys.addKey(authKey('apkam:E1:2', enrollmentId: 'E1'));

      expect(atKeys.getKey('apkam:E1:1', CryptographicKeyType.privateAuthentication)!.status,
          KeyPartStatus.retired);
      expect(atKeys.activeEnrollmentId, 'E1');
    });

    test('only one enrollment may hold an active authentication key', () {
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('apkam:E1:1', enrollmentId: 'E1')]);

      expect(() => atKeys.addKey(authKey('apkam:E2:1', enrollmentId: 'E2')),
          throwsArgumentError,
          reason: 'a keyfile has one live enrollment; a second active '
              'authentication key is corruption, not a supported state');

      // Retiring E1's makes room for E2's — which is exactly what a retrofit
      // does, and it must be allowed.
      atKeys.retireKey('apkam:E1:1');
      atKeys.addKey(authKey('apkam:E2:1', enrollmentId: 'E2'));
      expect(atKeys.activeEnrollmentId, 'E2');
    });

    test('several active SIGNING keys for one enrollment are fine', () {
      // The asymmetry that motivates the split: one authentication key, many
      // signing keys, because signature agility means one per algorithm.
      final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
        AtKeysMaterial(
            keyId: 'sign:E1:mldsa65:1',
            enrollmentId: 'E1',
            keyPartType: CryptographicKeyType.privateSigning,
            keyAlgorithmType: KeyAlgorithmType.mlDsa65,
            bytes: AtBytes.fromString('YQ=='),
            createdAt: DateTime.utc(2026, 1, 1)),
      ]);

      atKeys.addKey(AtKeysMaterial(
          keyId: 'sign:E1:rsa2048:1',
          enrollmentId: 'E1',
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: KeyAlgorithmType.rsa2048,
          bytes: AtBytes.fromString('Yg=='),
          createdAt: DateTime.utc(2026, 1, 1)));

      expect(atKeys.keysForEnrollment('E1').length, 2);

      // The control for the widening: per-algorithm uniqueness still bites.
      // A second ACTIVE mldsa65 signing key for the same enrollment is a
      // duplicate, and permitting it would make "which key signs mldsa65"
      // ambiguous.
      expect(
          () => atKeys.addKey(AtKeysMaterial(
              keyId: 'sign:E1:mldsa65:2',
              enrollmentId: 'E1',
              keyPartType: CryptographicKeyType.privateSigning,
              keyAlgorithmType: KeyAlgorithmType.mlDsa65,
              bytes: AtBytes.fromString('Yw=='),
              createdAt: DateTime.utc(2026, 1, 1))),
          throwsArgumentError);

      // ...and retiring the first frees that algorithm's slot, which is what
      // a signing-key rotation within one algorithm needs.
      atKeys.retireKey('sign:E1:mldsa65:1');
      atKeys.addKey(AtKeysMaterial(
          keyId: 'sign:E1:mldsa65:2',
          enrollmentId: 'E1',
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: KeyAlgorithmType.mlDsa65,
          bytes: AtBytes.fromString('Yw=='),
          createdAt: DateTime.utc(2026, 1, 1)));
    });

    test('replaceKey retires and files in one call', () {
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('apkam:E1:1', enrollmentId: 'E1')]);

      atKeys.replaceKey(
          'apkam:E1:1', [authKey('apkam:E1:2', enrollmentId: 'E1', value: 'bmV3')]);

      expect(atKeys.getKey('apkam:E1:1', CryptographicKeyType.privateAuthentication)!.status,
          KeyPartStatus.retired);
      expect(
          atKeys
              .getKey('apkam:E1:2', CryptographicKeyType.privateAuthentication)!
              .bytes
              .toString(),
          'bmV3');
      expect(atKeys.activeEnrollmentId, 'E1');
    });

    test('a refused replacement leaves the outgoing key active', () {
      // Rolling back matters more than the happy path: a rotation that
      // retired the old key and then failed to install the new one would
      // leave the enrollment unable to authenticate at all.
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('apkam:E1:1', enrollmentId: 'E1')]);

      expect(
          () => atKeys.replaceKey('apkam:E1:1', [
                authKey('apkam:E1:2', enrollmentId: 'E1'),
                // Second one collides with the first: same (keyId, type).
                authKey('apkam:E1:2', enrollmentId: 'E1'),
              ]),
          throwsArgumentError);

      expect(atKeys.getKey('apkam:E1:1', CryptographicKeyType.privateAuthentication)!.status,
          KeyPartStatus.active,
          reason: 'the outgoing key must still be active after a rollback');
      expect(atKeys.getKey('apkam:E1:2', CryptographicKeyType.privateAuthentication),
          isNull,
          reason: 'nothing from the failed rotation may survive');
      expect(atKeys.activeEnrollmentId, 'E1');
    });

    test('activeEnrollmentId is null when there is no typed auth material', () {
      // A legacy keyfile: its APKAM keypair is in the flat fields.
      expect(legacyAtKeys(atsign: '@alice'.toAtsign()).activeEnrollmentId,
          isNull);
    });
  });
}
