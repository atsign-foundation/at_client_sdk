import 'dart:async';
import 'dart:convert';


import 'at_keys.dart' show AtKeys;
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

sealed class AtKeysIo {
  FutureOr<AtKeys> read(String atSign);
}

abstract class WrittenAtKeysIo implements AtKeysIo {
  Future write(String atSign, AtKeys atKeys);
}

abstract class GeneratedAtKeysIo implements AtKeysIo {
  AtKeys generateKeys(String publicKeyId);
}

mixin KeyIOMixin on AtKeysIo {
  final AtSignLogger _logger = AtSignLogger('BaseAtKeysIo');

  AtKeys decryptAtKeysWithSelfEncKey(Map<String, dynamic> jsonData, PkamAuthMode authMode) {
    var securityKeys = AtKeys();
    String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey];
    var atChops = AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
    securityKeys.defaultSelfEncryptionKey = AtBytes.fromString(decryptionKey);
    securityKeys.defaultEncryptionPublicKey = AtBytes.fromString(atChops
        .decryptString(jsonData[auth_constants.defaultEncryptionPublicKey], EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result);
    securityKeys.defaultEncryptionPrivateKey = AtBytes.fromString(atChops
        .decryptString(jsonData[auth_constants.defaultEncryptionPrivateKey], EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result);
    securityKeys.apkamPublicKey = AtBytes.fromString(atChops
        .decryptString(jsonData[auth_constants.apkamPublicKey], EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result);
    // pkam private key will not be saved in keyfile if auth mode is sim/any other secure element.
    // decrypt the private key only when auth mode is keysFile
    if (authMode == PkamAuthMode.keysFile) {
      securityKeys.apkamPrivateKey = AtBytes.fromString(atChops
          .decryptString(jsonData[auth_constants.apkamPrivateKey], EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result);
    }
    securityKeys.apkamSymmetricKey = AtBytes.fromString(jsonData[auth_constants.apkamSymmetricKey]);
    securityKeys.enrollmentId = jsonData[AtConstants.enrollmentId];
    return securityKeys;
  }

  String encryptAtKeysWithSelfEncKey(AtKeys atKeys, PkamAuthMode authMode) {
    Map<String, dynamic> atKeysMap = {};
    if (atKeys.defaultSelfEncryptionKey == null) {
      throw AtException('selfEncryptionKey is required to encrypt the atKeys');
    }
    var atChops = AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(atKeys.defaultSelfEncryptionKey!.toString()));
    atKeysMap[auth_constants.defaultEncryptionPublicKey] = atChops
        .encryptString(atKeys.defaultEncryptionPublicKey.toString(), EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;

    atKeysMap[auth_constants.defaultEncryptionPrivateKey] = atChops
        .encryptString(atKeys.defaultEncryptionPrivateKey.toString(), EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;

    atKeysMap[auth_constants.apkamPublicKey] = atChops
        .encryptString(atKeys.apkamPublicKey.toString(), EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;

    if (authMode == PkamAuthMode.keysFile) {
      atKeysMap[auth_constants.apkamPrivateKey] = atChops
          .encryptString(atKeys.apkamPrivateKey.toString(), EncryptionKeyType.aes256,
              keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
          .result;
    }

    atKeysMap[auth_constants.apkamSymmetricKey] = atKeys.apkamSymmetricKey.toString();
    atKeysMap[auth_constants.defaultSelfEncryptionKey] = atKeys.defaultSelfEncryptionKey.toString();
    atKeysMap[AtConstants.enrollmentId] = atKeys.enrollmentId;
    return jsonEncode(atKeysMap);
  }

  AtKeys generateKeyPairs({String? atSign}) {
    var atKeysFile = AtKeys();
    var logger = AtSignLogger("BaseAtKeysIo");
    // generate user encryption keypair
    logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    //generate selfEncryptionKey
    var selfEncryptionKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    logger.info('Generating your encryption keys and .atKeys file\n');

    //generating pkamKeyPair only if authMode is keysFile
    String? pkamPublicKey;
    if (this is FileAtKeysIo) {
      logger.info('Generating pkam keypair');
      var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
      pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
      atKeysFile.apkamPrivateKey = AtBytes.fromString(apkamRsaKeypair.atPrivateKey.privateKey.toString());
      } 
    // else if (this is SimAtKeysIo) {
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
    atKeysFile.defaultEncryptionPublicKey = AtBytes.fromString(atEncryptionKeyPair.atPublicKey.publicKey.toString());
    atKeysFile.defaultEncryptionPrivateKey = AtBytes.fromString(atEncryptionKeyPair.atPrivateKey.privateKey.toString());
    atKeysFile.defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey.key);
    atKeysFile.apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey.key);

    return atKeysFile;
  }

  Future<Map<String, dynamic>> decodeAtKeys(Map<String, dynamic> decodedAtKeysData, {String? passPhrase}) async {
    // If it contains "iv(InitializationVector)", it means the data is encrypted with a
    // passphrase. Decrypt it.
    if (decodedAtKeysData.containsKey('iv') && passPhrase.isNullOrEmpty) {
      throw AtDecryptionException('Pass Phrase is required for password protected atKeys file');
    }
    if (decodedAtKeysData.containsKey('iv')) {
      _logger.info('Found encrypted atKeys files. Decrypting with the given pass-phrase');
      AtEncrypted atEncrypted = AtEncrypted.fromJson(decodedAtKeysData);

      if (atEncrypted.hashingAlgoType == null) {
        throw AtDecryptionException('Hashing algo type is required for decryption of password protected atKeys file');
      }

      String decryptedAtKeysData =
          await AtKeysCrypto.fromHashingAlgorithm(atEncrypted.hashingAlgoType!).decrypt(atEncrypted, passPhrase!);
      decodedAtKeysData = jsonDecode(decryptedAtKeysData);
    }

    return decodedAtKeysData;
  }
}
