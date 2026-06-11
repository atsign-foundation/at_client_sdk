import 'dart:async';
import 'dart:convert';

import 'at_keys.dart' show AtKeys;
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/keys/at_keys_passphrase_envelope.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// Legacy mixin that provides common functionality for encoding and decoding AtKeys.
class LegacyKeyIOUtil {
  static final AtKeysPassphraseEnvelopeCodec _passphraseEnvelopeCodec =
      AtKeysPassphraseEnvelopeCodec();

  static FutureOr<AtKeys> decryptAtKeysWithSelfEncKey(
      Map<String, dynamic> jsonData, PkamAuthMode authMode) async {
    var securityKeys = AtKeys();
    String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey];
    var atChops = AtChopsImpl(
        LegacyAtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
    securityKeys.defaultSelfEncryptionKey = AtBytes.fromString(decryptionKey);
    securityKeys.defaultEncryptionPublicKey = AtBytes.fromString(
        (await atChops.decryptString(
                jsonData[auth_constants.defaultEncryptionPublicKey],
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result);
    securityKeys.defaultEncryptionPrivateKey = AtBytes.fromString(
        (await atChops.decryptString(
                jsonData[auth_constants.defaultEncryptionPrivateKey],
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result);
    securityKeys
        .apkamPublicKey = AtBytes.fromString((await atChops.decryptString(
            jsonData[auth_constants.apkamPublicKey], EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
        .result);
    // pkam private key will not be saved in keyfile if auth mode is sim/any other secure element.
    // decrypt the private key only when auth mode is keysFile
    if (authMode == PkamAuthMode.keysFile) {
      securityKeys.apkamPrivateKey = AtBytes.fromString(
          (await atChops.decryptString(jsonData[auth_constants.apkamPrivateKey],
                  EncryptionKeyType.aes256,
                  keyName: 'selfEncryptionKey',
                  iv: AtChopsUtil.generateIVLegacy()))
              .result);
    }
    securityKeys.apkamSymmetricKey =
        AtBytes.fromString(jsonData[auth_constants.apkamSymmetricKey] ?? '');
    securityKeys.enrollmentId = jsonData[AtConstants.enrollmentId];
    return securityKeys;
  }

  static FutureOr<String> encryptAtKeysWithSelfEncKey(
      AtKeys atKeys, PkamAuthMode authMode, String atsign) async {
    Map<String, dynamic> atKeysMap = {};
    if (atKeys.defaultSelfEncryptionKey == null) {
      throw AtException('selfEncryptionKey is required to encrypt the atKeys');
    }
    var atChops = AtChopsImpl(LegacyAtChopsKeys()
      ..selfEncryptionKey =
          AESKey(atKeys.defaultSelfEncryptionKey!.toString()));
    atKeysMap[auth_constants.defaultEncryptionPublicKey] =
        (await atChops.encryptString(
                atKeys.defaultEncryptionPublicKey.toString(),
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result;

    atKeysMap[auth_constants.defaultEncryptionPrivateKey] =
        (await atChops.encryptString(
                atKeys.defaultEncryptionPrivateKey.toString(),
                EncryptionKeyType.aes256,
                keyName: 'selfEncryptionKey',
                iv: AtChopsUtil.generateIVLegacy()))
            .result;

    atKeysMap[auth_constants.apkamPublicKey] = (await atChops.encryptString(
            atKeys.apkamPublicKey.toString(), EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
        .result;

    if (authMode == PkamAuthMode.keysFile) {
      atKeysMap[auth_constants.apkamPrivateKey] = (await atChops.encryptString(
              atKeys.apkamPrivateKey.toString(), EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy()))
          .result;
    }

    atKeysMap[auth_constants.apkamSymmetricKey] =
        atKeys.apkamSymmetricKey.toString();
    atKeysMap[auth_constants.defaultSelfEncryptionKey] =
        atKeys.defaultSelfEncryptionKey.toString();
    atKeysMap[AtConstants.enrollmentId] = atKeys.enrollmentId;
    atKeysMap[atsign] = atKeys.defaultSelfEncryptionKey.toString();
    return jsonEncode(atKeysMap);
  }

  static AtKeys generateKeyPairs({String? atSign}) {
    var atKeysFile = AtKeys();
    var logger = AtSignLogger("BaseAtKeysIo");
    // generate user encryption keypair
    logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    //generate selfEncryptionKey
    var selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    logger.info('Generating your encryption keys and .atKeys file\n');

    //Standard order of an atKeys file is ->
    // pkam keypair -> encryption keypair -> selfEncryption key -> enrollmentId --> apkam symmetric key -->
    // @sign: selfEncryptionKey[self encryption key again]
    // note: "->" stands for "followed by"
    atKeysFile.defaultEncryptionPublicKey = AtBytes.fromString(
        atEncryptionKeyPair.atPublicKey.publicKey.toString());
    atKeysFile.defaultEncryptionPrivateKey = AtBytes.fromString(
        atEncryptionKeyPair.atPrivateKey.privateKey.toString());
    atKeysFile.defaultSelfEncryptionKey =
        AtBytes.fromString(selfEncryptionKey.key);
    atKeysFile.apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key);

    return atKeysFile;
  }

  static Future<Map<String, dynamic>> decodeAtKeys(
      Map<String, dynamic> decodedAtKeysData,
      {String? passPhrase}) async {
    return _passphraseEnvelopeCodec.decode(
      decodedAtKeysData,
      passPhrase: passPhrase,
    );
  }
}
