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
      expect(json.containsKey('enrollments'), false);
      expect(json.containsKey('atsignKeys'), false);
      expect(json['enrollmentId'], encryptedAtKeysMap['enrollmentId']);

      // The control: the marker DOES appear as soon as there is typed
      // material to mark, or this test would pass against a toJson that never
      // emits a version at all.
      untyped.addKey(symmetricKey('now-typed'));
      final typed = untyped.toJson();
      expect(typed['version'], AtKeys.supportedVersion);
      expect(typed['atsignKeys'], hasLength(1));
    });

    test('a legacy document round-trips field-for-field through a new build',
        () {
      // Read, change nothing, write. Every field must come back with the same
      // value and no field may be added, because a build that rewrites files
      // it only opened makes every upgrade look like a migration.
      //
      // Field-for-field, NOT byte-identical, and the name says so: this
      // compares two Maps, and Dart's Map equality ignores key order. The
      // emitter has one fixed field order, so a legacy file written elsewhere
      // comes back with the same entries in a different sequence. The test
      // said "byte-identically" until 2026-08-18, which is what made an
      // acceptance row claiming byte identity read as already proven.
      final reread =
          AtKeys.fromJson(Map<String, dynamic>.from(encryptedAtKeysMap))
            ..atsign = '@alice🛠'.toAtsign();
      expect(reread.toJson(), equals(encryptedAtKeysMap));
    });

    test('fromJson throws on an unsupported version', () {
      expect(
        () => AtKeys.fromJson({'version': 2, 'atsign': '@alice', 'keys': []}),
        throwsA(isA<AtKeysUnsupportedVersionException>()),
      );
    });

    test('a version 1 document carrying a POPULATED keys array is refused', () {
      // The shape that preceded grouping by enrollment. A populated one is
      // refused rather than read, because `keys` is no longer reserved:
      // parsing it would sweep the whole array into `metadata` as a legacy
      // value, leave the document reading as untyped, and authenticate from
      // the flat block as the LEGACY enrollment while the live enrollment's
      // credentials sat unread beside it.
      expect(
        () => AtKeys.fromJson({
          'version': 1,
          'atsign': '@alice',
          'keys': [
            {'keyId': 'auth:rsa2048:1'}
          ]
        }),
        throwsA(isA<AtKeysValidationException>().having(
            (e) => e.message, 'message', contains('top-level "keys" array'))),
        reason: 'refused by its own message, not by any validation throw: '
            'a test satisfied by an unrelated exception would stay green '
            'through a change that removed this guard',
      );
    });

    test('an EMPTY keys array is accepted, because that is what shipped', () {
      // ⚠️ This arm asserted the opposite until it was measured. The refusal
      // covered the empty array too, on the reasoning that it "matters as
      // much as a populated one" — but the harm named above cannot occur when
      // the array holds nothing: there are no credentials to leave unread,
      // and the flat block IS where such a document's material lives.
      //
      // What settled it: a keyfile was CRAM-onboarded with the published
      // at_auth that introduced `keys`, and it carries `"keys": []` — that
      // version never populated the array, since `addKey` has no caller
      // outside `AtKeys` itself there. Reading that real file here refused
      // it; deleting only the empty array made the same file load with the
      // right atsign and enrollmentId. Refusing the empty shape therefore
      // stranded every keyfile a released build had ever written, to guard
      // an array carrying nothing.
      final keys = AtKeys.fromJson({
        'version': 1,
        'atsign': '@alice',
        'keys': <Object?>[],
        'enrollmentId': 'abc-123',
      });

      expect(keys.atsign, '@alice'.toAtsign());
      expect(keys.enrollmentId, 'abc-123',
          reason: 'the flat block must still be read - accepting the empty '
              'array is worthless if the material beside it is dropped');
      expect(keys.toJson().containsKey('keys'), isFalse,
          reason: 'and the dead field must not be carried into `metadata` '
              'and written back out on the next flush');
    });

    test('and the same document without it parses', () {
      // The control arm. Without it the assertion above is satisfied by a
      // `fromJson` that refuses everything, and the guard it names could be
      // deleted with the test still red for a different reason.
      final keys = AtKeys.fromJson(
          {'version': 1, 'atsign': '@alice', 'enrollments': <Object?>[]});
      expect(keys.atsign, '@alice'.toAtsign());
      expect(keys.keys, isEmpty);
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
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
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

    test(
        'an algorithm this build cannot sign with is refused, not fallen '
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
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
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
          (m) => m.role == CryptographicMaterialRole.publicEncryption);
      final privateMaterial = pair.firstWhere(
          (m) => m.role == CryptographicMaterialRole.privateDecryption);

      expect(
        atKeys.getAtSignKey(
            'shared-pair', CryptographicMaterialRole.publicEncryption),
        same(publicMaterial),
      );
      expect(
        atKeys.getAtSignKey(
            'shared-pair', CryptographicMaterialRole.privateDecryption),
        same(privateMaterial),
      );
    });

    test('getKey returns null when the keyId has no material of that type', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(
        atKeys.getAtSignKey(
            'shared-id', CryptographicMaterialRole.privateDecryption),
        isNull,
      );
    });

    test('keysForKeyId returns empty for an unknown keyId', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(atKeys.atSignKeysForKeyId('nope'), isEmpty);
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

    test('two enrollments may hold the same keyId without colliding', () {
      // This asserted the opposite until the keyfile grouped by enrollment: a
      // keyId used to name one material document-wide, so a second owner for
      // it was a contradiction. Identity is `(enrollment, keyId)` now — the
      // container states the owner once, the id no longer carries it, and
      // both enrollments landing on `pair` is the ordinary case rather than
      // the corrupt one.
      final atKeys = AtKeys(
        keysList: [rsaKeyPair('pair', enrollmentId: 'enroll-1').first],
      );
      final sameIdOtherOwner =
          rsaKeyPair('pair', enrollmentId: 'enroll-2').last;

      atKeys.addKey(sameIdOtherOwner);

      expect(atKeys.keysForKeyId('enroll-1', 'pair'), hasLength(1));
      expect(atKeys.keysForKeyId('enroll-2', 'pair'), hasLength(1));
      expect(
          atKeys
              .getKey('enroll-1', 'pair',
                  CryptographicMaterialRole.publicEncryption)!
              .enrollmentId,
          'enroll-1',
          reason: 'each container answers with its own, not with whichever '
              'was filed first');

      // The control: within ONE enrollment the same (keyId, part) is still a
      // duplicate, so the relaxation is about the owner and nothing else.
      expect(
        () => atKeys.addKey(rsaKeyPair('pair', enrollmentId: 'enroll-1').first),
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

    test('unknown role/algorithm tokens round-trip unmodified',
        () {
      // role and algorithm are open Strings: a reader must
      // hold and re-emit tokens it does not recognise, so a keyfile written
      // by a newer client survives a read-modify-flush by an older one.
      final futuristic = CryptographicMaterial(
        keyId: 'from-the-future',
        role: 'somethingNotInventedYet',
        algorithm: 'slhdsa128s',
        bytes: AtBytes.fromString('ZnV0dXJl'),
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final atKeys = AtKeys(
        atsign: '@alice'.toAtsign(),
        keysList: [futuristic, symmetricKey('familiar')],
      );

      final reparsed = AtKeys.fromJson(atKeys.toJson());
      expect(
        reparsed.getAtSignKey('from-the-future', 'somethingNotInventedYet'),
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
          reread.getAtSignKey(
              'familiar', CryptographicMaterialRole.symmetricEncryption),
          isNotNull);
    });
  });

  group('AtKeys retireKey', () {
    test('marks every material of the group, leaving other fields intact', () {
      final atKeys = AtKeys(keysList: [...rsaKeyPair('pair')]);

      atKeys.retireAtSignKey('pair');

      final retired = atKeys.atSignKeysForKeyId('pair').toList();
      expect(retired, hasLength(2));
      expect(retired.map((m) => m.status), everyElement(CryptographicMaterialStatus.retired));
      expect(
        atKeys
            .getAtSignKey('pair', CryptographicMaterialRole.publicEncryption)!
            .bytes
            .toString(),
        rsaKeyPair('pair').first.bytes.toString(),
      );
    });

    test('is idempotent for the same status', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      atKeys.retireAtSignKey('solo');
      atKeys.retireAtSignKey('solo');

      expect(
        atKeys.atSignKeysForKeyId('solo').single.status,
        CryptographicMaterialStatus.retired,
      );
    });

    test('moves a retired key forward to dead', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      atKeys.retireAtSignKey('solo');
      atKeys.retireAtSignKey('solo', to: CryptographicMaterialStatus.dead);

      expect(
          atKeys.atSignKeysForKeyId('solo').single.status, CryptographicMaterialStatus.dead);
    });

    test('throws on a backward transition', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);
      atKeys.retireAtSignKey('solo', to: CryptographicMaterialStatus.dead);

      expect(
        () => atKeys.retireAtSignKey('solo'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
          atKeys.atSignKeysForKeyId('solo').single.status, CryptographicMaterialStatus.dead);
    });

    test('throws for an unknown keyId', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireAtSignKey('nope'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects CryptographicMaterialStatus.active as a target', () {
      final atKeys = AtKeys(keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireAtSignKey('solo', to: CryptographicMaterialStatus.active),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AtKeys fileApkamMaterial', () {
    test('files both halves under one auth:<algorithm>:<generation> keyId', () {
      final atKeys = AtKeys();

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-9',
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: 'cHVibGljLWhhbGY=',
          privateKey: 'cHJpdmF0ZS1oYWxm');

      // Raw literal: the role:algorithm:generation id is the at-rest shape,
      // and a keyfile written with it has to stay readable by every later
      // build. The enrollment is stated by the container, not the id.
      final filed = atKeys
          .keysForKeyId(
              'enroll-9', 'auth:${CryptographicMaterialAlgorithm.mlDsa65}:1')
          .toList();
      expect(filed, hasLength(2));
      expect(
        atKeys
            .getKey(
                'enroll-9',
                'auth:${CryptographicMaterialAlgorithm.mlDsa65}:1',
                CryptographicMaterialRole.privateAuthentication)!
            .bytes
            .toString(),
        'cHJpdmF0ZS1oYWxm',
      );
      expect(
        atKeys
            .getKey(
                'enroll-9',
                'auth:${CryptographicMaterialAlgorithm.mlDsa65}:1',
                CryptographicMaterialRole.publicAuthentication)!
            .bytes
            .toString(),
        'cHVibGljLWhhbGY=',
      );
      expect(filed.map((m) => m.enrollmentId), everyElement('enroll-9'));
      expect(filed.map((m) => m.algorithm),
          everyElement(CryptographicMaterialAlgorithm.mlDsa65));
      // One mint is one event: both halves carry the same timestamp.
      expect(filed.first.createdAt, filed.last.createdAt);
    });

    test('the filed enrollment resolves its own signing algorithm', () {
      final atKeys = AtKeys();

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-9',
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
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

      final adopted =
          target.keysForKeyId('the-new-enrollment', 'kem:xwing').single;
      expect(adopted.enrollmentId, 'the-new-enrollment');
      expect(adopted.keyId, 'kem:xwing');
      expect(
          adopted.role, CryptographicMaterialRole.symmetricEncryption);
      expect(adopted.algorithm, CryptographicMaterialAlgorithm.aes256);
      expect(adopted.bytes.toString(), 'c2VjcmV0');
      // The builder's own timestamp, not the adoption's.
      expect(adopted.createdAt, built);
      // The source keeps its own tag: adoption copies, it does not move.
      expect(
          source
              .keysForKeyId('the-old-enrollment', 'kem:xwing')
              .single
              .enrollmentId,
          'the-old-enrollment');
    });

    test('carries a non-default status and operations across', () {
      final source = AtKeys(keysList: [
        CryptographicMaterial(
            keyId: 'kem:xwing',
            enrollmentId: 'the-old-enrollment',
            role: CryptographicMaterialRole.privateDecapsulation,
            algorithm: CryptographicMaterialAlgorithm.xWing,
            bytes: AtBytes.fromString('c2VjcmV0'),
            operations: const ['decapsulate'],
            createdAt: DateTime.utc(2026, 3, 4),
            status: CryptographicMaterialStatus.retired),
      ]);
      final target = AtKeys();

      target.adoptMaterials(source.keys, enrollmentId: 'the-new-enrollment');

      final adopted =
          target.keysForKeyId('the-new-enrollment', 'kem:xwing').single;
      expect(adopted.status, CryptographicMaterialStatus.retired);
      expect(adopted.operations, ['decapsulate']);
      expect(adopted.algorithm, CryptographicMaterialAlgorithm.xWing);
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

    test('adopts onto a keyId another enrollment already holds', () {
      // The other half of the identity change, from adoption's side: this
      // refused until the keyfile grouped by enrollment, because the sitting
      // enrollment owned `kem:xwing` for the whole document. It now owns it
      // only within its own container, so the adoption lands beside it.
      final target = AtKeys(keysList: [
        symmetricKey('kem:xwing', enrollmentId: 'the-sitting-enrollment'),
      ]);
      final source = AtKeys(keysList: [
        CryptographicMaterial(
            keyId: 'kem:xwing',
            enrollmentId: 'the-old-enrollment',
            role: CryptographicMaterialRole.privateDecapsulation,
            algorithm: CryptographicMaterialAlgorithm.xWing,
            bytes: AtBytes.fromString('c2VjcmV0'),
            createdAt: DateTime.utc(2026, 3, 4)),
      ]);

      target.adoptMaterials(source.keys, enrollmentId: 'the-new-enrollment');

      expect(
          target.keysForKeyId('the-new-enrollment', 'kem:xwing'), hasLength(1));
      expect(target.keysForKeyId('the-sitting-enrollment', 'kem:xwing'),
          hasLength(1),
          reason: 'the sitting enrollment keeps its own material — an '
              'adoption for somebody else must not overwrite it');
    });
  });

  group('AtKeys authentication material and rotation', () {
    CryptographicMaterial authKey(String keyId,
            {required String enrollmentId,
            String value = 'YXV0aA==',
            CryptographicMaterialStatus status = CryptographicMaterialStatus.active}) =>
        CryptographicMaterial(
            keyId: keyId,
            enrollmentId: enrollmentId,
            role: CryptographicMaterialRole.privateAuthentication,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            bytes: AtBytes.fromString(value),
            createdAt: DateTime.utc(2026, 1, 1),
            status: status);

    test('retiring a key frees its slot for a replacement', () {
      // The whole point of making the invariants status-aware. The control is
      // the second half: WITHOUT retiring, the same add must still throw, or
      // this test would pass against an invariant that checks nothing.
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('auth:rsa2048:1', enrollmentId: 'E1')]);

      expect(() => atKeys.addKey(authKey('auth:rsa2048:2', enrollmentId: 'E1')),
          throwsArgumentError,
          reason: 'two ACTIVE authentication keys for one enrollment must be '
              'refused');

      atKeys.retireKey('E1', 'auth:rsa2048:1');
      atKeys.addKey(authKey('auth:rsa2048:2', enrollmentId: 'E1'));

      expect(
          atKeys
              .getKey('E1', 'auth:rsa2048:1',
                  CryptographicMaterialRole.privateAuthentication)!
              .status,
          CryptographicMaterialStatus.retired);
      expect(atKeys.resolveAuthenticatingEnrollment(), 'E1');
    });

    test('only one enrollment may hold an active authentication key', () {
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('auth:rsa2048:1', enrollmentId: 'E1')]);

      expect(() => atKeys.addKey(authKey('auth:rsa2048:1', enrollmentId: 'E2')),
          throwsArgumentError,
          reason: 'a keyfile has one live enrollment; a second active '
              'authentication key is corruption, not a supported state');

      // Retiring E1's makes room for E2's — which is exactly what a retrofit
      // does, and it must be allowed.
      atKeys.retireKey('E1', 'auth:rsa2048:1');
      atKeys.addKey(authKey('auth:rsa2048:1', enrollmentId: 'E2'));
      expect(atKeys.resolveAuthenticatingEnrollment(), 'E2');
    });

    test('several active SIGNING keys for one enrollment are fine', () {
      // The asymmetry that motivates the split: one authentication key, many
      // signing keys, because signature agility means one per algorithm.
      final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
        CryptographicMaterial(
            keyId: 'sign:mldsa65:1',
            enrollmentId: 'E1',
            role: CryptographicMaterialRole.privateSigning,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            bytes: AtBytes.fromString('YQ=='),
            createdAt: DateTime.utc(2026, 1, 1)),
      ]);

      atKeys.addKey(CryptographicMaterial(
          keyId: 'sign:rsa2048:1',
          enrollmentId: 'E1',
          role: CryptographicMaterialRole.privateSigning,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          bytes: AtBytes.fromString('Yg=='),
          createdAt: DateTime.utc(2026, 1, 1)));

      expect(atKeys.keysForEnrollment('E1').length, 2);

      // The control for the widening: per-algorithm uniqueness still bites.
      // A second ACTIVE mldsa65 signing key for the same enrollment is a
      // duplicate, and permitting it would make "which key signs mldsa65"
      // ambiguous.
      expect(
          () => atKeys.addKey(CryptographicMaterial(
              keyId: 'sign:mldsa65:2',
              enrollmentId: 'E1',
              role: CryptographicMaterialRole.privateSigning,
              algorithm: CryptographicMaterialAlgorithm.mlDsa65,
              bytes: AtBytes.fromString('Yw=='),
              createdAt: DateTime.utc(2026, 1, 1))),
          throwsArgumentError);

      // ...and retiring the first frees that algorithm's slot, which is what
      // a signing-key rotation within one algorithm needs.
      atKeys.retireKey('E1', 'sign:mldsa65:1');
      atKeys.addKey(CryptographicMaterial(
          keyId: 'sign:mldsa65:2',
          enrollmentId: 'E1',
          role: CryptographicMaterialRole.privateSigning,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          bytes: AtBytes.fromString('Yw=='),
          createdAt: DateTime.utc(2026, 1, 1)));
    });

    // Key material is base64 on the way in and on the way out, so a readable
    // label has to be encoded to be filed and encoded again to be asserted
    // against. Declared here rather than inside `signingKeysFor` because the
    // selection it fixtures is read by that accessor, by
    // `withdrawnSigningKeysFor` and by `retireSigningKeys` — three views of one
    // shape, which are only comparable if they are given the same material.
    String b64(String label) => base64Encode(utf8.encode(label));

    CryptographicMaterial part(
            String keyId, String type, String algo, String value,
            {String? enrollmentId, CryptographicMaterialStatus status = CryptographicMaterialStatus.active}) =>
        CryptographicMaterial(
            keyId: keyId,
            enrollmentId: enrollmentId,
            role: type,
            algorithm: algo,
            bytes: AtBytes.fromString(b64(value)),
            createdAt: DateTime.utc(2026, 1, 1),
            status: status);

    /// A complete signing keypair for [enrollmentId], both halves.
    List<CryptographicMaterial> signingPair(String enrollmentId, String algo,
            {int generation = 1,
            String value = 'a',
            CryptographicMaterialStatus status = CryptographicMaterialStatus.active}) =>
        [
          part('sign:$algo:$generation',
              CryptographicMaterialRole.privateSigning, algo, '$value-priv',
              enrollmentId: enrollmentId, status: status),
          part('sign:$algo:$generation',
              CryptographicMaterialRole.publicVerification, algo, '$value-pub',
              enrollmentId: enrollmentId, status: status),
        ];

    /// The atSign-wide PQ signing root as `PqSigningRoot` files it: the same
    /// `privateSigning` role an enrollment's signing key uses, under its own
    /// keyId, with **no** enrollment id — so it lands in the atSign's own
    /// container rather than any enrollment's.
    List<CryptographicMaterial> signingRoot() => [
          part('root:mldsa65:1', CryptographicMaterialRole.privateSigning,
              CryptographicMaterialAlgorithm.mlDsa65, 'root-priv'),
          part('root:mldsa65:1', CryptographicMaterialRole.publicVerification,
              CryptographicMaterialAlgorithm.mlDsa65, 'root-pub'),
        ];

    group('signingKeysFor', () {
      test('returns one entry per algorithm, strongest first', () {
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          // Filed weakest-first, so the order under test is the accessor's
          // rather than the order the keyfile happened to hold them in.
          ...signingPair('E1', CryptographicMaterialAlgorithm.rsa2048,
              value: 'rsa'),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'mldsa'),
        ]);

        expect(atKeys.signingKeysFor('E1').map((k) => k.algorithm).toList(),
            [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048],
            reason: 'a multi-signature writer emits strongest first, and a '
                'single-signature one signs with only that');
        expect(atKeys.signingKeysFor('E1').first.privateKey, b64('mldsa-priv'));
        expect(atKeys.signingKeysFor('E1').first.publicKey, b64('mldsa-pub'));
      });

      test('does not adopt the atSign-wide signing root as an enrollment key',
          () {
        // The root shares the `privateSigning` role, so selecting on the role
        // would hand E1 a key that was never its own — and E1 would sign with
        // a key whose public half is in no _apsk of its own, producing
        // signatures that verify against nothing. Two things exclude it now:
        // it is in the atSign's container, which signingKeysFor never reads,
        // and its id is not a `sign:` one.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingRoot(),
          authKey('auth:rsa2048:1', enrollmentId: 'E1'),
        ]);

        expect(atKeys.signingKeysFor('E1'), isEmpty);

        // ...and still excluded when E1 holds a key of the same algorithm,
        // which is the shape in which the wrong one could win.
        final withOwn = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingRoot(),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'own'),
        ]);
        expect(withOwn.signingKeysFor('E1').single.privateKey, b64('own-priv'));
      });

      test('skips a half pair, a retired pair, and an unreadable algorithm',
          () {
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          // No publicVerification half, so nothing could verify what it signs.
          part('sign:rsa2048:1', CryptographicMaterialRole.privateSigning,
              CryptographicMaterialAlgorithm.rsa2048, 'lonely',
              enrollmentId: 'E1'),
          // Retained to verify what it signed, but no longer signing.
          ...signingPair('E1', CryptographicMaterialAlgorithm.ed25519,
              value: 'old', status: CryptographicMaterialStatus.retired),
          // What a newer client's keyfile looks like from here.
          ...signingPair('E1', 'pq-something-later', value: 'future'),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'live'),
        ]);

        expect(atKeys.signingKeysFor('E1').single.privateKey, b64('live-priv'),
            reason: 'an entry this build cannot read is skipped, not refused: '
                'the rest of the keyfile is still usable');
      });

      test('skips a keyId whose two halves disagree about their algorithm', () {
        // Reachable: the invariants are per (role, algorithm),
        // so nothing compares a keyId's two halves with each other — verified
        // by probe, `addKey` accepts this. Handing the pair out would sign
        // ML-DSA while advertising an RSA public key.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          part('sign:mldsa65:1', CryptographicMaterialRole.privateSigning,
              CryptographicMaterialAlgorithm.mlDsa65, 'mldsa-priv',
              enrollmentId: 'E1'),
          part('sign:mldsa65:1', CryptographicMaterialRole.publicVerification,
              CryptographicMaterialAlgorithm.rsa2048, 'rsa-pub',
              enrollmentId: 'E1'),
        ]);

        expect(atKeys.signingKeysFor('E1'), isEmpty);
      });

      test('does not collect an enrollment whose id it merely prefixes', () {
        // This used to be a real parsing hazard, because the enrollment id sat
        // inside the keyId and `sign:E1:` is a prefix of `sign:E1:sub:`. The
        // id no longer carries the owner, so the separation is now structural
        // — each enrollment has its own container — and this pins that the
        // structural version holds just as the parse-based one did.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1:sub', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'sub'),
        ]);

        expect(atKeys.signingKeysFor('E1'), isEmpty);
        expect(
            atKeys.signingKeysFor('E1:sub').single.privateKey, b64('sub-priv'));
      });
    });

    /// Withdrawing an enrollment's signing key for one algorithm — what a
    /// client does when that algorithm leaves its in-use set.
    ///
    /// The caller names the algorithm, not the keyId: the generation is this
    /// class's grammar, and a caller reconstructing `sign:<algo>:<n>` would be
    /// holding a second copy of it.
    group('retireSigningKeys', () {
      test('retires both halves of the named algorithm and returns its keyId',
          () {
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1', CryptographicMaterialAlgorithm.rsa2048,
              value: 'rsa'),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'mldsa'),
        ]);

        expect(
            atKeys.retireSigningKeys(
                'E1', CryptographicMaterialAlgorithm.rsa2048),
            ['sign:rsa2048:1']);

        expect(atKeys.signingKeysFor('E1').map((k) => k.algorithm).toList(),
            [SigningAlgoType.mldsa65],
            reason: 'the withdrawn key stops being one this enrollment signs '
                'with');
        expect(atKeys.withdrawnSigningKeysFor('E1').single.publicKey,
            b64('rsa-pub'),
            reason: 'and starts being one it advertises as retired — the same '
                'key, which is what keeps what it signed verifiable');
        for (final type in [
          CryptographicMaterialRole.privateSigning,
          CryptographicMaterialRole.publicVerification
        ]) {
          final material = atKeys.getKey('E1', 'sign:rsa2048:1', type);
          expect(material!.status, CryptographicMaterialStatus.retired,
              reason: 'both halves: a keypair half-retired at rest is one the '
                  'next reader can read either way');
          expect(material.bytes.toString(), isNotEmpty,
              reason: 'retired, not removed');
        }
      });

      test('withdraws nothing of another owner', () {
        // Two things share this algorithm and neither is the key being
        // withdrawn: the atSign's own signing root, which lives in the other
        // container, and another enrollment's key of the same keyId, since
        // identity is (enrollment, keyId).
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingRoot(),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'own'),
          ...signingPair('E2', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'other'),
        ]);

        expect(
            atKeys.retireSigningKeys(
                'E1', CryptographicMaterialAlgorithm.mlDsa65),
            ['sign:mldsa65:1']);

        expect(
            atKeys
                .getAtSignKey(
                    'root:mldsa65:1', CryptographicMaterialRole.privateSigning)!
                .status,
            CryptographicMaterialStatus.active);
        expect(atKeys.signingKeysFor('E2').single.privateKey, b64('other-priv'),
            reason: 'identity is (enrollment, keyId): E2 holds the same keyId '
                'and is not touched');
      });

      test('withdraws nothing of this enrollment that merely signs', () {
        // The SHAPE filter rather than the `privateSigning` role, which an
        // enrollment can hold material under for more than one reason. It has
        // to be the enrollment's ONLY material of this algorithm and role —
        // holding it beside a real signing key is a state `addKey` refuses,
        // one active per (enrollment, role, algorithm) — so this is what the
        // hazard actually looks like: an enrollment with no signing key at
        // all, where a role-based selector would withdraw the other thing and
        // report that it had retired a signing key.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          part('root:mldsa65:1', CryptographicMaterialRole.privateSigning,
              CryptographicMaterialAlgorithm.mlDsa65, 'not-a-signing-key',
              enrollmentId: 'E1'),
        ]);

        expect(
            atKeys.retireSigningKeys(
                'E1', CryptographicMaterialAlgorithm.mlDsa65),
            isEmpty);
        expect(
            atKeys
                .getKey('E1', 'root:mldsa65:1',
                    CryptographicMaterialRole.privateSigning)!
                .status,
            CryptographicMaterialStatus.active);
      });

      test('is a no-op when the enrollment holds nothing of that algorithm',
          () {
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'mldsa'),
        ]);

        expect(
            atKeys.retireSigningKeys(
                'E1', CryptographicMaterialAlgorithm.rsa2048),
            isEmpty);
        expect(
            atKeys.retireSigningKeys(
                'E-unknown', CryptographicMaterialAlgorithm.mlDsa65),
            isEmpty,
            reason: 'an enrollment this file does not hold is not an error '
                'here: retireKey throws on an unknown keyId, and turning that '
                'into a throw would make a caller reconciling several '
                'algorithms fail on the one it had nothing to do for');
        expect(atKeys.signingKeysFor('E1'), hasLength(1));
      });

      test('a status this build cannot read is advertised, with its token', () {
        // The keyfile's status vocabulary is open, so a newer build may say
        // something about a signing key that this one has never heard of. This
        // selector read exactly `retired` until 2026-08-22 and SKIPPED such a
        // key — which sounds cautious and is not: the advertisement is
        // rewritten whole on every publish, so an omitted entry withdraws the
        // key, taking with it both what verifies its old envelopes and
        // whatever its owner last said about it. Now that the advertisement's
        // own status is an open token there is nothing left to guess: the
        // keyfile's word travels out unchanged.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1', CryptographicMaterialAlgorithm.rsa2048,
              value: 'rsa',
              status: CryptographicMaterialStatus.of('revoked')),
          ...signingPair('E1', CryptographicMaterialAlgorithm.mlDsa65,
              value: 'mldsa'),
        ]);

        final withdrawn = atKeys.withdrawnSigningKeysFor('E1');
        // Length before fields, so skipping the entry fails saying the key is
        // missing rather than crashing inside `.single` and naming nothing.
        expect(withdrawn, hasLength(1),
            reason: 'the key is still advertised, so what it signed still '
                'verifies for anyone who can read the status - dropping it '
                'from a record that is rewritten whole IS a withdrawal');
        expect(withdrawn.single.publicKey, b64('rsa-pub'));
        expect(withdrawn.single.status, 'revoked',
            reason: 'and it goes out saying what the keyfile says, not what '
                'this build would have guessed');
        expect(atKeys.signingKeysFor('E1').map((k) => k.algorithm).toList(),
            [SigningAlgoType.mldsa65],
            reason: 'it is not active either - the control that stops this '
                'row passing on a selector that simply returns everything');
      });

      test('dead signing material is advertised by nothing', () {
        // The other side of "not active". `dead` was never adopted, so it has
        // nothing to verify and nothing to say - it is the one non-active
        // status that stays out.
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1', CryptographicMaterialAlgorithm.rsa2048,
              value: 'rsa', status: CryptographicMaterialStatus.dead),
        ]);

        expect(atKeys.withdrawnSigningKeysFor('E1'), isEmpty);
      });

      test('leaves an already-retired key where it is', () {
        final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: [
          ...signingPair('E1', CryptographicMaterialAlgorithm.rsa2048,
              value: 'rsa', status: CryptographicMaterialStatus.retired),
        ]);

        expect(
            atKeys.retireSigningKeys(
                'E1', CryptographicMaterialAlgorithm.rsa2048),
            isEmpty,
            reason: 'selected on active material, so a start after the '
                'withdrawal has nothing to do and rewrites nothing');
        expect(atKeys.withdrawnSigningKeysFor('E1'), hasLength(1));
      });
    });

    test('replaceKey retires and files in one call', () {
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('auth:rsa2048:1', enrollmentId: 'E1')]);

      atKeys.replaceKey('E1', 'auth:rsa2048:1',
          [authKey('auth:rsa2048:2', enrollmentId: 'E1', value: 'bmV3')]);

      expect(
          atKeys
              .getKey('E1', 'auth:rsa2048:1',
                  CryptographicMaterialRole.privateAuthentication)!
              .status,
          CryptographicMaterialStatus.retired);
      expect(
          atKeys
              .getKey('E1', 'auth:rsa2048:2',
                  CryptographicMaterialRole.privateAuthentication)!
              .bytes
              .toString(),
          'bmV3');
      expect(atKeys.resolveAuthenticatingEnrollment(), 'E1');
    });

    test('a refused replacement leaves the outgoing key active', () {
      // Rolling back matters more than the happy path: a rotation that
      // retired the old key and then failed to install the new one would
      // leave the enrollment unable to authenticate at all.
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList: [authKey('auth:rsa2048:1', enrollmentId: 'E1')]);

      expect(
          () => atKeys.replaceKey('E1', 'auth:rsa2048:1', [
                authKey('auth:rsa2048:2', enrollmentId: 'E1'),
                // Second one collides with the first: same (keyId, type).
                authKey('auth:rsa2048:2', enrollmentId: 'E1'),
              ]),
          throwsArgumentError);

      expect(
          atKeys
              .getKey('E1', 'auth:rsa2048:1',
                  CryptographicMaterialRole.privateAuthentication)!
              .status,
          CryptographicMaterialStatus.active,
          reason: 'the outgoing key must still be active after a rollback');
      expect(
          atKeys.getKey('E1', 'auth:rsa2048:2',
              CryptographicMaterialRole.privateAuthentication),
          isNull,
          reason: 'nothing from the failed rotation may survive');
      expect(atKeys.resolveAuthenticatingEnrollment(), 'E1');
    });

    test('the authenticating enrollment is null with no typed auth material',
        () {
      // A legacy keyfile: its APKAM keypair is in the flat fields.
      expect(
          legacyAtKeys(atsign: '@alice'.toAtsign())
              .resolveAuthenticatingEnrollment(),
          isNull);
    });
  });
}
