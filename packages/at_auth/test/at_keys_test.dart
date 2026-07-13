import 'dart:convert';
import 'dart:io';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/types.dart';
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
    ..metadata = {};

  group('AtKeys legacy json transformers', () {
    test('toLegacyJson -> should return a Map instance', () async {
      //legacy keys? or not? idk...
      encryptedAtKeysMap.remove('@alice🛠');
      expect(createKeys().toLegacyJson(), equals(encryptedAtKeysMap));
    });

    test('fromLegacyJson -> should return AtKeys instance', () async {
      expect(AtKeys.fromLegacyJson(encryptedAtKeysMap), equals(createKeys()));
    });

    test('toLegacyJson -> should be nullable', () async {
      AtKeys nulledKeys = AtKeys();
      var map = nulledKeys.toLegacyJson();
      for (var entry in map.entries) {
        expect(entry.value, isNull);
      }
    });

    test('toLegacyJson -> metadata test', () async {
      AtKeys keys = createKeys();
      keys.metadata = {'atsign': "@vforreal"};
      var json = keys.toLegacyJson();
      var metadata = json['atsign'];
      expect(metadata, equals('@vforreal'));
    });

    test('fromLegacyJson -> metadata', () async {
      // Copy the map so we don't pollute the shared encryptedAtKeysMap
      final localMap = Map<String, dynamic>.from(encryptedAtKeysMap);
      localMap['atsign'] = "@shabonaganmcsideburns";
      var atKeys = AtKeys.fromLegacyJson(localMap);
      expect(atKeys.metadata, isNotEmpty);
    });

    test('fromJson falls back to legacy for json without a version field', () {
      // The pre-v1 contract: fromJson accepts a flat legacy map, exactly as
      // fromLegacyJson would.
      expect(
        AtKeys.fromJson(encryptedAtKeysMap),
        equals(AtKeys.fromLegacyJson(encryptedAtKeysMap)),
      );
    });

    test('fromJson throws on an unsupported version', () {
      expect(
        () => AtKeys.fromJson({'version': 2, 'atSign': '@alice', 'keys': []}),
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

    test('APKAM AtKeys with a null defaultEncryptionPublicKey -> throws', () {
      apkam.defaultEncryptionPublicKey = null;
      expect(() => apkam.toAtChops(), throwsA(isA<AtException>()));
    });

    test('APKAM AtKeys with a null apkamPrivateKey -> throws', () {
      apkam.apkamPrivateKey = null;
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
    test('equality includes atSign and typed key material', () {
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

    test('getMaterial disambiguates materials of the same keyId by type', () {
      final pair = rsaKeyPair('shared-pair');
      final atKeys = AtKeys(keysList: pair);
      final publicMaterial = pair.firstWhere((m) =>
          m.keyPartType == CryptographicKeyType.classicalPublicEncryption);
      final privateMaterial = pair.firstWhere((m) =>
          m.keyPartType == CryptographicKeyType.classicalPrivateDecryption);

      expect(
        atKeys.getMaterial(
            'shared-pair', CryptographicKeyType.classicalPublicEncryption),
        same(publicMaterial),
      );
      expect(
        atKeys.getMaterial(
            'shared-pair', CryptographicKeyType.classicalPrivateDecryption),
        same(privateMaterial),
      );
    });

    test('getMaterial returns null when the keyId has no material of that type',
        () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(
        atKeys.getMaterial(
            'shared-id', CryptographicKeyType.classicalPrivateDecryption),
        isNull,
      );
    });

    test('materialsForKeyId returns empty for an unknown keyId', () {
      final atKeys = AtKeys(keysList: [symmetricKey('shared-id')]);

      expect(atKeys.materialsForKeyId('nope'), isEmpty);
    });

    test('addKey rejects a duplicate keyId', () {
      final atKeys = AtKeys();
      atKeys.addKey(symmetricKey('dupe'));

      expect(
        () => atKeys.addKey(symmetricKey('dupe', value: 'b3RoZXI=')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
