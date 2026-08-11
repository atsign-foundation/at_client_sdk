/// Golden pins over the at-rest typed keyfile document.
///
/// Every existing test round-trips the document through the same code that
/// writes it, so a renamed field or a reshaped nesting stays green while
/// orphaning every keyfile already on disk. These pins hold the emitted JSON
/// against a hand-written golden string — the file format IS the contract,
/// and an intended change edits the golden in the same commit, which is the
/// review.
///
/// The writer-consolidation work (one enrollment-key-material writer; the
/// CLI's enroll path routed through FileAtKeysIo) lands on top of exactly
/// this shape.
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  // The keyIds and keyPartTypes below are arbitrary PAYLOAD: these pins hold
  // the document's STRUCTURE — field names, nesting, encoding — and the ids
  // are just strings passing through it. Do not read them as the canonical
  // shapes; those are pinned against their writers in wire_literal_pins_test
  // ('apkam:<enrollmentId>:<generation>' and
  // 'sign:<enrollmentId>:<algorithm>:<generation>'). Changing them here would
  // churn a frozen golden string for no gain.
  group('the typed keyfile document (at rest, frozen)', () {
    test('a fully populated AtKeys emits the golden document byte-for-byte',
        () {
      final atKeys = AtKeys(atsign: '@alice'.toAtsign())
        ..apkamPublicKey = AtBytes.fromString('UEtQVUI=')
        ..apkamPrivateKey = AtBytes.fromString('UEtQUlY=')
        ..defaultEncryptionPublicKey = AtBytes.fromString('RU5DUFVC')
        ..defaultEncryptionPrivateKey = AtBytes.fromString('RU5DUFJW')
        ..defaultSelfEncryptionKey = AtBytes.fromString('U0VMRkVOQw==')
        ..apkamSymmetricKey = AtBytes.fromString('QVBLU1lN')
        ..enrollmentId = 'enroll-1'
        ..metadata['note'] = 'kept'
        ..addKey(AtKeysMaterial(
          keyId: 'apkam:enroll-2',
          enrollmentId: 'enroll-2',
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: KeyAlgorithmType.mlDsa65,
          bytes: AtBytes.fromString('UFJJVg=='),
          createdAt: DateTime.utc(2026, 6, 11),
        ))
        ..addKey(AtKeysMaterial(
          keyId: 'apkam:enroll-2',
          enrollmentId: 'enroll-2',
          keyPartType: CryptographicKeyType.publicVerification,
          keyAlgorithmType: KeyAlgorithmType.mlDsa65,
          bytes: AtBytes.fromString('UFVC'),
          operations: const ['verify'],
          createdAt: DateTime.utc(2026, 6, 11),
        ))
        ..addKey(AtKeysMaterial(
          keyId: 'nskey.buzz.abc123',
          keyPartType: CryptographicKeyType.privateDecapsulation,
          keyAlgorithmType: KeyAlgorithmType.xWing,
          bytes: AtBytes.fromString('U0VFRA=='),
          createdAt: DateTime.utc(2026, 6, 11),
          status: KeyPartStatus.retired,
        ));

      // The golden, spelled out: legacy flat fields first (merged, not
      // nested — upgrading a legacy file is additive), then version/atsign,
      // then the typed materials grouped by keyId. `operations` is omitted
      // when empty; a group's `enrollmentId` is omitted when null.
      expect(
          jsonEncode(atKeys.toJson()),
          '{"aesPkamPublicKey":"UEtQVUI=",'
          '"aesPkamPrivateKey":"UEtQUlY=",'
          '"aesEncryptPublicKey":"RU5DUFVC",'
          '"aesEncryptPrivateKey":"RU5DUFJW",'
          '"selfEncryptionKey":"U0VMRkVOQw==",'
          '"apkamSymmetricKey":"QVBLU1lN",'
          '"enrollmentId":"enroll-1",'
          '"note":"kept",'
          '"version":1,'
          '"atsign":"@alice",'
          '"keys":['
          '{"keyId":"apkam:enroll-2","enrollmentId":"enroll-2","keyParts":['
          '{"keyPartType":"privateSigning","keyAlgorithmType":"mldsa65",'
          '"createdAt":"2026-06-11T00:00:00.000Z","status":"active",'
          '"bytes":"UFJJVg=="},'
          '{"keyPartType":"publicVerification","keyAlgorithmType":"mldsa65",'
          '"operations":["verify"],'
          '"createdAt":"2026-06-11T00:00:00.000Z","status":"active",'
          '"bytes":"UFVC"}]},'
          '{"keyId":"nskey.buzz.abc123","keyParts":['
          '{"keyPartType":"privateDecapsulation","keyAlgorithmType":"xwing",'
          '"createdAt":"2026-06-11T00:00:00.000Z","status":"retired",'
          '"bytes":"U0VFRA=="}]}]}');
    });

    test('the golden document reads back as the same AtKeys', () {
      final golden = AtKeys(atsign: '@alice'.toAtsign())
        ..apkamPublicKey = AtBytes.fromString('UEtQVUI=')
        ..apkamPrivateKey = AtBytes.fromString('UEtQUlY=')
        ..defaultEncryptionPublicKey = AtBytes.fromString('RU5DUFVC')
        ..defaultEncryptionPrivateKey = AtBytes.fromString('RU5DUFJW')
        ..defaultSelfEncryptionKey = AtBytes.fromString('U0VMRkVOQw==')
        ..apkamSymmetricKey = AtBytes.fromString('QVBLU1lN')
        ..enrollmentId = 'enroll-1'
        ..addKey(AtKeysMaterial(
          keyId: 'apkam:enroll-2',
          enrollmentId: 'enroll-2',
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: KeyAlgorithmType.mlDsa65,
          bytes: AtBytes.fromString('UFJJVg=='),
          createdAt: DateTime.utc(2026, 6, 11),
        ));

      final reread =
          AtKeys.fromJson(jsonDecode(jsonEncode(golden.toJson())));
      expect(reread.atsign, golden.atsign);
      expect(reread.apkamPublicKey, golden.apkamPublicKey);
      expect(reread.enrollmentId, golden.enrollmentId);
      final material = reread.getKey(
          'apkam:enroll-2', CryptographicKeyType.privateSigning);
      expect(material, isNotNull);
      expect(material!.keyAlgorithmType, 'mldsa65');
      expect(material.bytes.toString(), 'UFJJVg==');
      expect(material.enrollmentId, 'enroll-2');
    });

    test('absent legacy fields are emitted as null, not dropped', () {
      // A reader distinguishes "field with null" from "no such field"; the
      // legacy shape has always carried the full field set.
      final json = (AtKeys(atsign: '@alice'.toAtsign())
            ..addKey(AtKeysMaterial(
              keyId: 'apkam:enroll-3',
              keyPartType: CryptographicKeyType.privateSigning,
              keyAlgorithmType: KeyAlgorithmType.mlDsa65,
              bytes: AtBytes.fromString('QQ=='),
              createdAt: DateTime.utc(2026, 6, 11),
            )))
          .toJson();
      for (final field in [
        'aesPkamPublicKey',
        'aesPkamPrivateKey',
        'aesEncryptPublicKey',
        'aesEncryptPrivateKey',
        'selfEncryptionKey',
        'apkamSymmetricKey',
        'enrollmentId',
      ]) {
        expect(json.containsKey(field), isTrue,
            reason: '$field must be present (as null) in the flat shape');
        expect(json[field], isNull);
      }
    });

    test('a legacy-only AtKeys emits the flat shape with no typed fields',
        () {
      // The 52.1 boundary from the other side: no atsign and no materials
      // means the legacy format, exactly — a version/atsign/keys tripod
      // appearing here would reformat every legacy keyfile on next write.
      final json = (AtKeys()
            ..apkamPublicKey = AtBytes.fromString('UEtQVUI=')
            ..defaultSelfEncryptionKey = AtBytes.fromString('U0VMRkVOQw=='))
          .toJson();
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('atsign'), isFalse);
      expect(json.containsKey('keys'), isFalse);
    });
  });
}
