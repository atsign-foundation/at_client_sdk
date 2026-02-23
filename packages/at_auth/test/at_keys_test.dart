import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:test/test.dart';

void main() {
  String filePath = 'test/data/@alice🛠_key.atKeys';
  final atKeysString = File(filePath).readAsStringSync();
  Map<String, dynamic> encryptedAtKeysMap = jsonDecode(atKeysString);
  AtKeys keys = AtKeys()
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
    test('toJson -> should return a Map<String,dynamic> instance', () async {
      expect(encryptedAtKeysMap, equals(keys.toJson()));
    });

    test('fromJson -> should return AtKeys instance', () async {
      expect(keys, AtKeys.fromJson(encryptedAtKeysMap));
    });

    test('toJson -> should be nullable', () async {
      AtKeys nulledKeys = AtKeys();
      var map = nulledKeys.toJson();
      for (var entry in map.entries) {
        expect(entry.value, isNull);
      }
    });

    test('toJson -> metadata test', () async {
      keys.metadata = {
        'atsign': "@vforreal",
      };
      var json = keys.toJson();
      var metadata = json['atsign'];
      expect(metadata, equals('@vforreal'));
    });

    test('fromJson -> metadata', () async {
      encryptedAtKeysMap['atsign'] = "@shabonaganmcsideburns";
      var atKeys = AtKeys.fromJson(encryptedAtKeysMap);
      expect(atKeys.metadata, isNotEmpty);
    });
  });

  group('AtKeys AtChops transformers', () {
    test('MPKAM AtKeys to AtChopsImpl', () {
      AtChops chops = keys.toAtChops();
      expect(chops, isA<AtChopsImpl>());
    });

    test('APKAM AtKeys to AtChopsImpl', () {
      AtChops chops = keys.toAtChops();
      expect(chops, isA<AtChopsImpl>());
    });

    test('MPKAM AtKeys to AtChopsImpl -> throws', () {
      keys.apkamPrivateKey = null;
      keys.defaultEncryptionPrivateKey = null;
      expect(() => keys.toAtChops(), throwsA(isA<AtException>()));
    });

    test('APKAM AtKeys to AtChopsImpl -> throws', () {
      keys.apkamPublicKey = null;
      keys.defaultEncryptionPrivateKey = null;
      keys.apkamSymmetricKey = null;
      expect(() => keys.toAtChops(), throwsA(isA<AtException>()));
    });
  });
}
