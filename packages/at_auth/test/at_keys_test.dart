import 'dart:convert';
import 'dart:io';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/key_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

void main() {
  String filePath = 'test/data/@alice🛠_key.atKeys';
  final atKeysString = File(filePath).readAsStringSync();
  Map<String, dynamic> encryptedAtKeysMap = jsonDecode(atKeysString);
  // A legacy .atKeys file doesn't store the atsign, so the reader supplies it.
  final fixtureAtsign = '@alice🛠'.toAtsign();

  // Factory function to always produce a fresh AtKeys instance
  AtKeys createKeys() => AtKeys(atsign: fixtureAtsign)
    ..apkamPublicKey =
        AtBytes.fromString(encryptedAtKeysMap[KeyIds.apkamPublicKey])
    ..apkamPrivateKey =
        AtBytes.fromString(encryptedAtKeysMap[KeyIds.apkamPrivateKey])
    ..defaultEncryptionPublicKey = AtBytes.fromString(
        encryptedAtKeysMap[KeyIds.defaultEncryptionPublicKey])
    ..defaultEncryptionPrivateKey = AtBytes.fromString(
        encryptedAtKeysMap[KeyIds.defaultEncryptionPrivateKey])
    ..defaultSelfEncryptionKey =
        AtBytes.fromString(encryptedAtKeysMap[KeyIds.defaultSelfEncryptionKey])
    ..apkamSymmetricKey =
        AtBytes.fromString(encryptedAtKeysMap[KeyIds.apkamSymmetricKey])
    ..enrollmentId = encryptedAtKeysMap[AtConstants.enrollmentId]
    // The fixture's non-schema trailer entry lands in metadata.
    ..metadata = {'@alice🛠': encryptedAtKeysMap['@alice🛠']};

  group('AtKeys legacy json transformers', () {
    test('toJson -> keeps every legacy field from the on-disk fixture', () {
      // An upgrade, not a format swap: the typed envelope is added and the
      // flat legacy fields are emitted byte-for-byte as the fixture holds them.
      expect(
        createKeys().toJson(),
        equals({
          ...encryptedAtKeysMap,
          'version': AtKeys.supportedVersion,
          'atsign': fixtureAtsign.toString(),
          // Structural fields are emitted even when null, as the legacy schema
          // fields are.
          'namespaces': null,
          'keys': isEmpty,
        }),
      );
    });

    test('toJson -> legacy fields are nullable', () {
      var map = AtKeys(atsign: fixtureAtsign).toJson();
      map.remove('version');
      map.remove('atsign');
      map.remove('keys');

      expect(map, isNotEmpty);
      for (var entry in map.entries) {
        expect(entry.value, isNull, reason: '${entry.key} should be null');
      }
    });

    test('toJson -> passes legacy metadata through', () {
      AtKeys keys = createKeys();
      keys.metadata = {'@vforreal': 'trailing-metadata'};

      expect(keys.toJson()['@vforreal'], equals('trailing-metadata'));
    });

    test('toJson -> the schema always wins over colliding metadata', () {
      // Metadata is emitted first and filtered through KeyIds.isMetadata, so a
      // key colliding with a structural or key-material field can never be
      // written in its place. A stale metadata copy shadowing the real field is
      // what silently persisted an out-of-date enrollmentId.
      AtKeys keys = createKeys();
      keys.metadata = {
        'atsign': '@vforreal',
        'version': 99,
        'keys': 'garbage',
        AtConstants.enrollmentId: 'stale-enrollment',
        KeyIds.apkamPublicKey: 'stale-key-material',
      };
      var json = keys.toJson();

      expect(json['atsign'], equals(fixtureAtsign.toString()));
      expect(json['version'], equals(AtKeys.supportedVersion));
      expect(json['keys'], isEmpty);
      expect(json[AtConstants.enrollmentId], equals(keys.enrollmentId));
      expect(json[KeyIds.apkamPublicKey],
          equals(encryptedAtKeysMap[KeyIds.apkamPublicKey]));
    });

    test('toJson -> a changed enrollmentId is not shadowed by a stale copy',
        () {
      // The original bug, end to end: read a keyfile, change the enrollmentId,
      // re-encode. The value written must be the new one.
      final keys = AtKeys.fromJson(encryptedAtKeysMap, atsign: fixtureAtsign);
      keys.enrollmentId = 'e-NEW';

      expect(keys.toJson()[AtConstants.enrollmentId], 'e-NEW');
    });

    test('fromJson -> populates legacy metadata', () {
      // Copy the map so we don't pollute the shared encryptedAtKeysMap
      final localMap = Map<String, dynamic>.from(encryptedAtKeysMap);
      localMap['@shabonaganmcsideburns'] = 'trailer';

      var atKeys = AtKeys.fromJson(localMap, atsign: fixtureAtsign);

      expect(atKeys.metadata['@shabonaganmcsideburns'], 'trailer');
    });

    test('fromJson -> never captures a structural field as metadata', () {
      // 'version'/'atsign'/'keys'/'enrollmentId' are owned by the schema. A
      // legacy file carrying one of those names must not have it copied into
      // metadata, or a stale copy would shadow the real field on the next
      // write.
      final localMap = Map<String, dynamic>.from(encryptedAtKeysMap)
        ..['atsign'] = '@shabonaganmcsideburns';

      var atKeys = AtKeys.fromJson(localMap, atsign: fixtureAtsign);

      expect(atKeys.metadata.containsKey('atsign'), isFalse);
      expect(atKeys.metadata.containsKey(AtConstants.enrollmentId), isFalse);
      expect(atKeys.atsign, fixtureAtsign);
      // The real enrollmentId still comes off the document.
      expect(atKeys.enrollmentId, encryptedAtKeysMap[AtConstants.enrollmentId]);
    });

    test('fromJson falls back to legacy for json without a version field', () {
      expect(AtKeys.fromJson(encryptedAtKeysMap, atsign: fixtureAtsign),
          equals(createKeys()));
    });

    test('fromJson throws on an unsupported version', () {
      expect(
        () => AtKeys.fromJson({'version': 2, 'atsign': '@alice', 'keys': []}),
        throwsA(isA<AtKeysUnsupportedVersionException>()),
      );
    });
  });

  group('AtKeys.generate', () {
    test('mints the post-quantum materials and the legacy fields', () async {
      final keys = await AtKeys.generate('@alice'.toAtsign());

      expect(keys.atsign, '@alice'.toAtsign());
      expect(keys.enrollmentId, isNull);
      expect(
        keys.keys.map((m) => (m.keyId, m.keyPartType)).toSet(),
        {
          (KeyIds.apkamPQ, CryptographicKeyType.publicVerification),
          (KeyIds.apkamPQ, CryptographicKeyType.privateSigning),
          (KeyIds.globalXWing, CryptographicKeyType.publicEncryption),
          (KeyIds.globalXWing, CryptographicKeyType.privateDecryption),
        },
      );
      expect(keys.apkamPublicKey, isNotNull);
      expect(keys.apkamPrivateKey, isNotNull);
      expect(keys.defaultEncryptionPublicKey, isNotNull);
      expect(keys.defaultEncryptionPrivateKey, isNotNull);
      expect(keys.defaultSelfEncryptionKey, isNotNull);
      expect(keys.apkamSymmetricKey, isNotNull);
    });

    test('mintLegacy: false leaves every legacy field null', () async {
      final keys =
          await AtKeys.generate('@alice'.toAtsign(), mintLegacy: false);

      expect(keys.keys, hasLength(4));
      expect(keys.apkamPublicKey, isNull);
      expect(keys.apkamPrivateKey, isNull);
      expect(keys.defaultEncryptionPublicKey, isNull);
      expect(keys.defaultEncryptionPrivateKey, isNull);
      expect(keys.defaultSelfEncryptionKey, isNull);
      expect(keys.apkamSymmetricKey, isNull);
    });

    test('carries the enrollmentId and generates fresh material each call',
        () async {
      final first = await AtKeys.generate('@alice'.toAtsign(),
          enrollmentId: 'enroll-1', mintLegacy: false);
      final second = await AtKeys.generate('@alice'.toAtsign(),
          enrollmentId: 'enroll-1', mintLegacy: false);

      expect(first.enrollmentId, 'enroll-1');
      expect(first, isNot(second));
    });

    test('round-trips through toJson', () async {
      final keys = await AtKeys.generate('@alice'.toAtsign());

      expect(AtKeys.fromJson(keys.toJson()), keys);
    });

    test('the enrollmentId survives a typed-document round-trip', () async {
      // enrollmentId is a reserved top-level key rather than legacy payload,
      // so the typed read path has to carry it across itself.
      final keys = await AtKeys.generate('@alice'.toAtsign(),
          enrollmentId: 'enroll-1', mintLegacy: false);

      final reread = AtKeys.fromJson(keys.toJson());

      expect(reread.enrollmentId, 'enroll-1');
      expect(reread.metadata, isEmpty);
      expect(reread, keys);
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
      final first = AtKeys(atsign: '@alice'.toAtsign())
        ..metadata = jsonDecode('{"nested": {"a": 1, "list": [1, 2]}}');
      final same = AtKeys(atsign: '@alice'.toAtsign())
        ..metadata = jsonDecode('{"nested": {"a": 1, "list": [1, 2]}}');
      final different = AtKeys(atsign: '@alice'.toAtsign())
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
      final atKeys = AtKeys(atsign: '@alice'.toAtsign(), keysList: pair);
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
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(), keysList: [symmetricKey('shared-id')]);

      expect(
        atKeys.getKey('shared-id', CryptographicKeyType.privateDecryption),
        isNull,
      );
    });

    test('keysForKeyId returns empty for an unknown keyId', () {
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(), keysList: [symmetricKey('shared-id')]);

      expect(atKeys.keysForKeyId('nope'), isEmpty);
    });

    test('addKey rejects a duplicate keyId', () {
      final atKeys = AtKeys(atsign: '@alice'.toAtsign());
      atKeys.addKey(symmetricKey('dupe'));

      expect(
        () => atKeys.addKey(symmetricKey('dupe', value: 'b3RoZXI=')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addKey allows the same keyPartType across different keyIds', () {
      // An AtKeys belongs to a single enrollment; materials carry no
      // enrollmentId of their own, so the only per-add guard is a duplicate
      // (keyId, keyPartType). Two symmetric keys under different keyIds are
      // fine.
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(), keysList: [symmetricKey('first')]);

      atKeys.addKey(symmetricKey('second', value: 'b3RoZXI='));

      expect(atKeys.keys, hasLength(2));
      expect(atKeys.keys.map((m) => m.keyId).toSet(), {'first', 'second'});
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
        bytes: base64Decode('ZnV0dXJl'),
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
      final atKeys = AtKeys(
          atsign: '@alice'.toAtsign(), keysList: [...rsaKeyPair('pair')]);

      atKeys.retireKey('pair');

      final retired = atKeys.keysForKeyId('pair').toList();
      expect(retired, hasLength(2));
      expect(retired.map((m) => m.status), everyElement(KeyPartStatus.retired));
      expect(
        atKeys.getKey('pair', CryptographicKeyType.publicEncryption)!.bytes,
        rsaKeyPair('pair').first.bytes,
      );
    });

    test('is idempotent for the same status', () {
      final atKeys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('solo')]);

      atKeys.retireKey('solo');
      atKeys.retireKey('solo');

      expect(
        atKeys.keysForKeyId('solo').single.status,
        KeyPartStatus.retired,
      );
    });

    test('moves a retired key forward to dead', () {
      final atKeys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('solo')]);

      atKeys.retireKey('solo');
      atKeys.retireKey('solo', to: KeyPartStatus.dead);

      expect(atKeys.keysForKeyId('solo').single.status, KeyPartStatus.dead);
    });

    test('throws on a backward transition', () {
      final atKeys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('solo')]);
      atKeys.retireKey('solo', to: KeyPartStatus.dead);

      expect(
        () => atKeys.retireKey('solo'),
        throwsA(isA<ArgumentError>()),
      );
      expect(atKeys.keysForKeyId('solo').single.status, KeyPartStatus.dead);
    });

    test('throws for an unknown keyId', () {
      final atKeys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireKey('nope'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects KeyPartStatus.active as a target', () {
      final atKeys =
          AtKeys(atsign: '@alice'.toAtsign(), keysList: [symmetricKey('solo')]);

      expect(
        () => atKeys.retireKey('solo', to: KeyPartStatus.active),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AtKeys promoteKey', () {
    AtKeys keysWith(KeyPartStatus status) => AtKeys(
          atsign: '@alice'.toAtsign(),
          keysList:
              rsaKeyPair('pair').map((m) => m.withStatus(status)).toList(),
        );

    test('promotes every material of a pending group to active', () {
      for (final pending in [
        KeyPartStatus.pendingEnrollment,
        KeyPartStatus.pendingCramDeletion,
      ]) {
        final atKeys = keysWith(pending);

        atKeys.promoteKey('pair');

        expect(atKeys.keysForKeyId('pair').map((m) => m.status),
            everyElement(KeyPartStatus.active),
            reason: '$pending');
      }
    });

    test('refuses to promote a key that is not pending', () {
      // Regression: the guard read `status != pendingEnrollment || status !=
      // pendingCramDeletion`, a tautology — every status satisfied it, so
      // promoteKey could never do anything but throw.
      for (final settled in [
        KeyPartStatus.active,
        KeyPartStatus.retired,
        KeyPartStatus.dead,
      ]) {
        final atKeys = keysWith(settled);

        expect(() => atKeys.promoteKey('pair'), throwsA(isA<ArgumentError>()),
            reason: '$settled');
        expect(atKeys.keysForKeyId('pair').map((m) => m.status),
            everyElement(settled));
      }
    });

    test('throws for an unknown keyId', () {
      final atKeys = keysWith(KeyPartStatus.pendingEnrollment);

      expect(() => atKeys.promoteKey('nope'), throwsA(isA<ArgumentError>()));
    });
  });
}
