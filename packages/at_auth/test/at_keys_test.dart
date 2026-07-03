import 'dart:convert';
import 'dart:io';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/types.dart' as key_types;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:test/test.dart';

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

  group('AtKeys json transformers', () {
    test('toJson -> should return a Map instance', () async {
      //legacy keys? or not? idk...
      encryptedAtKeysMap.remove('@alice🛠');
      expect(createKeys().toJson(), equals(encryptedAtKeysMap));
    });

    test('fromJson -> should return AtKeys instance', () async {
      expect(AtKeys.fromJson(encryptedAtKeysMap), equals(createKeys()));
    });

    test('toJson -> should be nullable', () async {
      AtKeys nulledKeys = AtKeys();
      var map = nulledKeys.toJson();
      for (var entry in map.entries) {
        expect(entry.value, isNull);
      }
    });

    test('toJson -> metadata test', () async {
      AtKeys keys = createKeys();
      keys.metadata = {'atsign': "@vforreal"};
      var json = keys.toJson();
      var metadata = json['atsign'];
      expect(metadata, equals('@vforreal'));
    });

    test('fromJson -> metadata', () async {
      // Copy the map so we don't pollute the shared encryptedAtKeysMap
      final localMap = Map<String, dynamic>.from(encryptedAtKeysMap);
      localMap['atsign'] = "@shabonaganmcsideburns";
      var atKeys = AtKeys.fromJson(localMap);
      expect(atKeys.metadata, isNotEmpty);
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
  });

  group('AtKeys typed key lookup', () {
    test('getKey disambiguates keys with the same id by type', () {
      final publicKey = key_types.AtPublicKey(
        pairId: 'shared-pair',
        algorithm: 'RSA',
        bytes: AtBytes.fromString('cHVibGlj'),
      );
      final privateKey = key_types.AtPrivateKey(
        pairId: 'shared-pair',
        algorithm: 'RSA',
        bytes: AtBytes.fromString('cHJpdmF0ZQ=='),
      );

      final atKeys = AtKeys(keysList: [publicKey, privateKey]);

      expect(
        atKeys.getKey<key_types.AtPublicKey>('shared-pair'),
        same(publicKey),
      );
      expect(
        atKeys.getKey<key_types.AtPrivateKey>('shared-pair'),
        same(privateKey),
      );
    });

    test('getKey returns null when the id exists for another key type', () {
      final atKeys = AtKeys(
        keysList: [
          key_types.AtSymmetricKey(
            id: 'shared-id',
            algorithm: 'AES-256',
            bytes: AtBytes.fromString('c2VjcmV0'),
          ),
        ],
      );

      expect(atKeys.getKey<key_types.AtPrivateKey>('shared-id'), isNull);
    });
  });
}
