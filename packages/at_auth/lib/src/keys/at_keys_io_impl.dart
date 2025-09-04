import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:at_auth/at_auth.dart';

final AtSignLogger _logger = AtSignLogger('AtKeysIoImpl');

class FileAtKeysIo extends AtKeysIo {
  String? filePath;

  FileAtKeysIo(String this.filePath);

  @override
  FutureOr<AtKeys> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
    if (filePath != null) {
      if (!File(filePath!).existsSync()) {
        throw AtException(
            'provided keys file does not exist. Please check whether the file path ${filePath} is valid');
      }
      String atAuthData = await File(filePath!).readAsString();
      Map<String, dynamic> decodedAtKeysData = jsonDecode(atAuthData);
      decodedAtKeysData = await _decodeAtKeys(decodedAtKeysData, passPhrase: atAuthRequest.passPhrase);
    } else {
      throw AtException('atKeys filePath is required to read from file');
    }
    return _decryptAtKeysWithSelfEncKey(decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future write(String atSign, AtKeys atKeys) {
    // TODO: implement write
    return Future.value();
  }

  @override
  FutureOr<AtKeys> generateKeys(String atSign, {String? publicKeyId}) {
    return _generateKeyPairs(PkamAuthMode.keysFile);
  }
}

class SimAtKeysIo extends AtKeysIo {
  AtKeys? atKeys;
  Map<String, dynamic>? encryptedKeysMap;

  SimAtKeysIo({this.atKeys, this.encryptedKeysMap});

  @override
  FutureOr<AtKeys> read(String atSign) async {
    if (atKeys != null) {
      return atKeys!;
    }
    if (encryptedKeysMap != null) {
      encryptedKeysMap = await _decodeAtKeys(encryptedKeysMap!);
      return _decryptAtKeysWithSelfEncKey(encryptedKeysMap!, PkamAuthMode.sim);
    }

    throw AtAuthenticationException('atAuthKeys or encryptedKeysMap is required to read from keychain');
  }

  @override
  Future write(String atSign, AtKeys atKeys) {
    // TODO: implement write
    return Future.value();
  }

  @override
  FutureOr<AtKeys> generateKeys(String atSign, {String? publicKeyId}) {
    return _generateKeyPairs(PkamAuthMode.keysFile);
  }
}

Future<Map<String, dynamic>> _decodeAtKeys(Map<String, dynamic> decodedAtKeysData, {String? passPhrase}) async {
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

AtKeys _decryptAtKeysWithSelfEncKey(Map<String, dynamic> jsonData, PkamAuthMode authMode) {
  var securityKeys = AtKeys();
  String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey]!;
  var atChops = AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
  securityKeys.defaultEncryptionPublicKey = atChops
      .decryptString(jsonData[auth_constants.defaultEncryptionPublicKey]!, EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;
  securityKeys.defaultEncryptionPrivateKey = atChops
      .decryptString(jsonData[auth_constants.defaultEncryptionPrivateKey]!, EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;
  securityKeys.defaultSelfEncryptionKey = AtBytes.fromString(decryptionKey);
  securityKeys.apkamPublicKey = atChops
      .decryptString(jsonData[auth_constants.apkamPublicKey]!, EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;
  // pkam private key will not be saved in keyfile if auth mode is sim/any other secure element.
  // decrypt the private key only when auth mode is keysFile
  if (authMode == PkamAuthMode.keysFile) {
    securityKeys.apkamPrivateKey = atChops
        .decryptString(jsonData[auth_constants.apkamPrivateKey]!, EncryptionKeyType.aes256,
            keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
        .result;
  }
  securityKeys.apkamSymmetricKey = jsonData[auth_constants.apkamSymmetricKey];
  securityKeys.enrollmentId = jsonData[AtConstants.enrollmentId];
  return securityKeys;
}

AtKeys _generateKeyPairs(PkamAuthMode authMode, {String? publicKeyId}) {
  // generate user encryption keypair
  _logger.info('Generating encryption keypair');
  var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

  //generate selfEncryptionKey
  var selfEncryptionKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
  var apkamSymmetricKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
  var atKeysFile = AtKeys();
  var atChops = AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(selfEncryptionKey.key));
  _logger.info('[Information] Generating your encryption keys and .atKeys file\n');
  //generating pkamKeyPair only if authMode is keysFile
  String? pkamPublicKey;
  if (authMode == PkamAuthMode.keysFile) {
    _logger.info('Generating pkam keypair');
    var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
    pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
    atKeysFile.apkamPrivateKey = AtBytes.fromString(apkamRsaKeypair.atPrivateKey.privateKey.toString());
  } else if (authMode == PkamAuthMode.sim) {
    // get the public key from secure element
    pkamPublicKey = atChops!.readPublicKey(publicKeyId!);
    _logger.info('pkam  public key from sim: ${atKeysFile.apkamPublicKey}');

    // encryption key pair and self encryption symmetric key
    // are not available to injected at_chops. Set it here
    atChops.atChopsKeys.atEncryptionKeyPair = atEncryptionKeyPair;
    atChops.atChopsKeys.selfEncryptionKey = selfEncryptionKey;
    atChops.atChopsKeys.apkamSymmetricKey = apkamSymmetricKey;
  }
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
