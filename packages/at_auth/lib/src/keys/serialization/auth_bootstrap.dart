import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

import '../at_keys.dart';

abstract final class KeyIds {
  // pq id's
  static const String apkamPQ = 'apkam/mldsa65';
  static const String globalXWing = 'atsign/xwing';
  // all legacy
  static const String apkamPublicKey = 'aesPkamPublicKey';
  static const String apkamPrivateKey = 'aesPkamPrivateKey';
  static const String defaultEncryptionPublicKey = 'aesEncryptPublicKey';
  static const String defaultEncryptionPrivateKey = 'aesEncryptPrivateKey';
  static const String defaultSelfEncryptionKey = 'selfEncryptionKey';
  static const String apkamSymmetricKey = 'apkamSymmetricKey';

  static const keySchemaList = [
    apkamPublicKey,
    apkamPrivateKey,
    defaultEncryptionPublicKey,
    defaultEncryptionPrivateKey,
    defaultSelfEncryptionKey,
    apkamSymmetricKey,
  ];
}

class AuthBootstrap {
  static Future<AtKeys> bootstrap(Atsign atsign,
      {String? enrollmentId, bool mintLegacy = true}) async {
    final list = await _generatePqKeys();
    final keys = AtKeys(
      atsign: atsign,
      keysList: list,
      enrollmentId: enrollmentId,
    );
    if (mintLegacy) {
      await _loadLegacyKeys(keys);
    }
    return keys;
  }

  static Future<void> _loadLegacyKeys(AtKeys existing) async {
    var apkamRsaKeypair = RsaKeyPair.generate();
    var atEncryptionKeyPair = RsaKeyPair.generate();
    var selfEncryptionKey = AESKey.generate(256);
    var apkamSymmetricKey = AESKey.generate(256);

    existing.apkamPublicKey =
        AtBytes.fromString(apkamRsaKeypair.atPublicKey.publicKey.toString());
    existing.apkamPrivateKey =
        AtBytes.fromString(apkamRsaKeypair.atPrivateKey.privateKey.toString());
    existing.defaultEncryptionPublicKey = AtBytes.fromString(
        atEncryptionKeyPair.atPublicKey.publicKey.toString());
    existing.defaultEncryptionPrivateKey = AtBytes.fromString(
        atEncryptionKeyPair.atPrivateKey.privateKey.toString());
    existing.defaultSelfEncryptionKey =
        AtBytes.fromString(selfEncryptionKey.key);
    existing.apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key);
  }

  static Future<List<AtKeysMaterial>> _generatePqKeys() async {
    List<AtKeysMaterial> list = [];
    final mldsa = await MlDsa65PureDartAlgo().generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.publicVerification,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: AtBytes(mldsa.publicKey),
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.apkamPQ,
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: AtBytes(mldsa.secretKey),
      createdAt: DateTime.timestamp(),
    ));

    final xwing = await XWingPureDartAlgo.instance.generateKeyPair();
    list.add(AtKeysMaterial(
      keyId: KeyIds.globalXWing,
      keyPartType: CryptographicKeyType.publicEncryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(xwing.publicKey),
      createdAt: DateTime.timestamp(),
    ));
    list.add(AtKeysMaterial(
      keyId: KeyIds.globalXWing,
      keyPartType: CryptographicKeyType.privateDecryption,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(xwing.secretKey),
      createdAt: DateTime.timestamp(),
    ));
    return list;
  }
}
