import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/keys/serialization/codec.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_auth/src/keys/serialization/resolver.dart';
import 'package:at_auth/src/keys/types.dart';

import '../at_keys.dart' show AtKeys;
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart' hide AtKeysCrypto;
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// An interface that defines methods for reading AtKeys.
/// It can be implemented by classes that read AtKeys from different sources,
sealed class AtKeysIo {
  final resolver = const AtKeysDocumentResolver();
  final codec = const AtKeysJsonCodec();
  final passwordCodec = const AtKeysPassphraseEnvelopeCodec();
  FutureOr<AtKeys> read(String atsign);
}

//todo: remove atsign from method signature
/// An interface that defines methods for AtKeys that can be written.
/// It can be implemented by classes that write AtKeys to different sources,
/// such as file system or keychain.
abstract class WrittenAtKeysIo extends AtKeysIo {
  //todo: futureOr & Atsign types
  Future write(String atsign, AtKeys atKeys);
  FutureOr<void> append(Atsign atsign, AtKeysMaterial material);
}

/// An interface that defines methods for AtKeys that can be generated.
/// It can be implemented by classes that generate AtKeys using different methods,
/// such as secure element.
abstract class GeneratedAtKeysIo extends AtKeysIo {
  AtKeys generateKeys(String publicKeyId);
}

/// Static helpers for encoding, decoding, encrypting and decrypting AtKeys.
@Deprecated('Legacy mixin turned into a static helper class')
class AtKeysIoUtil {
  AtKeysIoUtil._();

  static final AtSignLogger _logger = AtSignLogger('BaseAtKeysIo');

  static Future<AtKeys> decryptAtKeysWithSelfEncKey(
      Map<String, dynamic> jsonData, PkamAuthMode authMode) async {
    var securityKeys = AtKeys();
    String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey];
    var atChops =
        AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
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

  static Future<String> encryptAtKeysWithSelfEncKey(
      AtKeys atKeys, PkamAuthMode authMode, String atsign) async {
    Map<String, dynamic> atKeysMap = {};
    if (atKeys.defaultSelfEncryptionKey == null) {
      throw AtException('selfEncryptionKey is required to encrypt the atKeys');
    }
    var atChops = AtChopsImpl(AtChopsKeys()
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

  static AtKeys generateKeyPairs({
    PkamAuthMode authMode = PkamAuthMode.keysFile,
  }) {
    var atKeysFile = AtKeys();
    // generate user encryption keypair
    _logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    //generate selfEncryptionKey
    var selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    _logger.info('Generating your encryption keys and .atKeys file\n');

    //generating pkamKeyPair only if authMode is keysFile
    String? pkamPublicKey;
    if (authMode == PkamAuthMode.keysFile) {
      _logger.info('Generating pkam keypair');
      var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
      pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
      atKeysFile.apkamPrivateKey = AtBytes.fromString(
          apkamRsaKeypair.atPrivateKey.privateKey.toString());
    }
    // else if (this is GeneratedAtKeysIo) {
    //   // get the public key from secure element
    //   if (atSign == null) {
    //     throw AtAuthenticationException('atSign is required to read pkam public key from sim/secure element');
    //   }
    //   String? publicKeyId = (this as SimAtKeysIo).publicKeyMap[atSign];
    //   if (publicKeyId == null) {
    //     throw AtAuthenticationException('publicKeyId is required in SimAtKeysIo.publicKeyMap to read pkam public key from sim/secure element');
    //   }
    //   pkamPublicKey = atChops.readPublicKey(publicKeyId);
    //   logger.info('pkam  public key from sim: $pkamPublicKey');

    //   // encryption key pair and self encryption symmetric key
    //   // are not available to injected at_chops. Set it here
    //   atChops.atChopsKeys.atEncryptionKeyPair = atEncryptionKeyPair;
    //   atChops.atChopsKeys.selfEncryptionKey = selfEncryptionKey;
    //   atChops.atChopsKeys.apkamSymmetricKey = apkamSymmetricKey;
    // }
    atKeysFile.apkamPublicKey = AtBytes.fromString(pkamPublicKey.toString());
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
    // If it contains "iv(InitializationVector)", it means the data is encrypted with a
    // passphrase. Decrypt it.
    if (decodedAtKeysData.containsKey('iv') && passPhrase.isNullOrEmpty) {
      throw AtDecryptionException(
          'Pass Phrase is required for password protected atKeys file');
    }
    if (decodedAtKeysData.containsKey('iv')) {
      _logger.info(
          'Found encrypted atKeys files. Decrypting with the given pass-phrase');
      PassphraseEnvelope envelope =
          PassphraseEnvelope.fromJson(decodedAtKeysData);

      if (envelope.hashingAlgoType == null) {
        throw AtDecryptionException(
            'Hashing algo type is required for decryption of password protected atKeys file');
      }

      try {
        final decryptedAtKeysData =
            await AtKeysCrypto.fromHashingAlgorithm(envelope.hashingAlgoType!)
                .decrypt(envelope, passPhrase!);
        // jsonDecode must stay inside the try: the cipher is unauthenticated,
        // so an incorrect passphrase does not fail decrypt() -- it yields
        // arbitrary bytes. Whether those bytes parse as a JSON object is
        // effectively random per file (the IV varies per write), so a wrong
        // passphrase otherwise escapes as an uncaught FormatException (invalid
        // JSON) or a cast error (valid non-object JSON) instead of the
        // documented AtDecryptionException.
        decodedAtKeysData =
            jsonDecode(decryptedAtKeysData) as Map<String, dynamic>;
      } catch (e) {
        throw AtDecryptionException(
            'Failed to decrypt atKeys file - passphrase may be incorrect: $e');
      }
    }

    return decodedAtKeysData;
  }
}
