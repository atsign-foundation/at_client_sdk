import 'dart:convert';
import 'dart:io';
import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_auth/src/keys/legacy/at_keys_legacy.dart';
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

  group('AtKeysSet adapter', () {
    test('fromAtKeysSet maps legacy key purposes to AtKeys fields', () {
      final atKeysSet = WritableAtKeysSet(
        atsign: '@alice'.toAtsign(),
        enrollmentId: 'enrollment',
        keys: [
          _keyPair(
            pairId: 'pkam',
            purpose: KeyPurposes.pkam,
            publicKey: 'pkam-public',
            privateKey: 'pkam-private',
          ),
          _keyPair(
            pairId: 'encryption',
            purpose: KeyPurposes.encryption,
            publicKey: 'encryption-public',
            privateKey: 'encryption-private',
          ),
          _symmetricKey(
            id: 'self-encryption',
            purpose: KeyPurposes.selfEncryption,
            bytes: 'self-encryption-key',
          ),
          _symmetricKey(
            id: 'apkam-symmetric',
            purpose: KeyPurposes.apkamSymmetric,
            bytes: 'apkam-symmetric-key',
          ),
        ],
      );

      final atKeys = AtKeys.fromAtKeysSet(atKeysSet);

      expect(atKeys.apkamPublicKey, _bytes('pkam-public'));
      expect(atKeys.apkamPrivateKey, _bytes('pkam-private'));
      expect(
        atKeys.defaultEncryptionPublicKey,
        _bytes('encryption-public'),
      );
      expect(
        atKeys.defaultEncryptionPrivateKey,
        _bytes('encryption-private'),
      );
      expect(
        atKeys.defaultSelfEncryptionKey,
        _bytes('self-encryption-key'),
      );
      expect(
        atKeys.apkamSymmetricKey,
        _bytes('apkam-symmetric-key'),
      );
      expect(atKeys.enrollmentId, 'enrollment');
    });

    test('fromAtKeysSet leaves missing legacy keys null', () {
      final atKeysSet = WritableAtKeysSet(
        atsign: '@alice'.toAtsign(),
        keys: [
          _keyPair(
            pairId: 'pkam',
            purpose: KeyPurposes.pkam,
            publicKey: 'pkam-public',
            privateKey: 'pkam-private',
          ),
        ],
      );

      final atKeys = AtKeys.fromAtKeysSet(atKeysSet);

      expect(atKeys.apkamPublicKey, _bytes('pkam-public'));
      expect(atKeys.apkamPrivateKey, _bytes('pkam-private'));
      expect(atKeys.defaultEncryptionPublicKey, isNull);
      expect(atKeys.defaultEncryptionPrivateKey, isNull);
      expect(atKeys.defaultSelfEncryptionKey, isNull);
      expect(atKeys.apkamSymmetricKey, isNull);
    });

    test('fromAtKeysSet rejects ambiguous legacy key purposes', () {
      final atKeysSet = WritableAtKeysSet(
        atsign: '@alice'.toAtsign(),
        keys: [
          _keyPair(
            pairId: 'pkam-1',
            purpose: KeyPurposes.pkam,
            publicKey: 'pkam-public-1',
            privateKey: 'pkam-private-1',
          ),
          _keyPair(
            pairId: 'pkam-2',
            purpose: KeyPurposes.pkam,
            publicKey: 'pkam-public-2',
            privateKey: 'pkam-private-2',
          ),
        ],
      );

      expect(
        () => AtKeys.fromAtKeysSet(atKeysSet),
        throwsA(isA<StateError>()),
      );
    });

    test('toAtKeysSet maps AtKeys fields to legacy key purposes', () {
      final atKeys = createKeys();

      final atKeysSet = atKeys.toAtKeysSet(atsign: '@alice'.toAtsign());

      expect(atKeysSet.atsign.toString(), '@alice');
      expect(atKeysSet.enrollmentId, atKeys.enrollmentId);

      final pkamKeyPair = atKeysSet.getKeyPair(KeyPurposes.pkam);
      expect(pkamKeyPair, isNotNull);
      expect(pkamKeyPair!.purpose, KeyPurposes.pkam);
      expect(pkamKeyPair.publicKey, atKeys.apkamPublicKey);
      expect(pkamKeyPair.privateKey, atKeys.apkamPrivateKey);

      final encryptionKeyPair = atKeysSet.getKeyPair(KeyPurposes.encryption);
      expect(encryptionKeyPair, isNotNull);
      expect(encryptionKeyPair!.purpose, KeyPurposes.encryption);
      expect(encryptionKeyPair.publicKey, atKeys.defaultEncryptionPublicKey);
      expect(encryptionKeyPair.privateKey, atKeys.defaultEncryptionPrivateKey);

      final selfEncryptionKey =
          atKeysSet.getSymmetricKey(KeyPurposes.selfEncryption);
      expect(selfEncryptionKey, isNotNull);
      expect(selfEncryptionKey!.purpose, KeyPurposes.selfEncryption);
      expect(selfEncryptionKey.bytes, atKeys.defaultSelfEncryptionKey);

      final apkamSymmetricKey =
          atKeysSet.getSymmetricKey(KeyPurposes.apkamSymmetric);
      expect(apkamSymmetricKey, isNotNull);
      expect(apkamSymmetricKey!.purpose, KeyPurposes.apkamSymmetric);
      expect(apkamSymmetricKey.bytes, atKeys.apkamSymmetricKey);
    });

    test('toAtKeysSet can read atSign from metadata', () {
      final atKeys = createKeys()..metadata['atsign'] = '@alice';

      final atKeysSet = atKeys.toAtKeysSet();

      expect(atKeysSet.atsign.toString(), '@alice');
    });

    test('toAtKeysSet requires an atSign', () {
      expect(
        () => createKeys().toAtKeysSet(),
        throwsArgumentError,
      );
    });

    test('toAtKeysSet rejects partial asymmetric key pairs', () {
      final atKeys = AtKeys()
        ..apkamPublicKey = _bytes('pkam-public')
        ..metadata['atsign'] = '@alice';

      expect(
        () => atKeys.toAtKeysSet(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

AtKeyPair _keyPair({
  required String pairId,
  required String purpose,
  required String publicKey,
  required String privateKey,
  KeyRotationStatus status = KeyRotationStatus.active,
}) {
  return AtKeyPair(
    pairId: pairId,
    purpose: purpose,
    algorithm: 'rsa-2048',
    publicKey: _bytes(publicKey),
    privateKey: _bytes(privateKey),
    rotation: _rotation(status),
  );
}

AtSymmetricKey _symmetricKey({
  required String id,
  required String purpose,
  required String bytes,
  KeyRotationStatus status = KeyRotationStatus.active,
}) {
  return AtSymmetricKey(
    id: id,
    purpose: purpose,
    algorithm: 'aes-256',
    bytes: _bytes(bytes),
    rotation: _rotation(status),
  );
}

AtBytes _bytes(String value) {
  return AtBytes.fromString(base64Encode(utf8.encode(value)));
}

KeyRotation _rotation(KeyRotationStatus status) {
  return KeyRotation(
    status: status,
    createdAt: DateTime.utc(2026),
    retiredAt: DateTime.utc(2027),
  );
}
