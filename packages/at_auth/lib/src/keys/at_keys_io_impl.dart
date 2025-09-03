import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:at_auth/at_auth.dart';

final AtSignLogger _logger = AtSignLogger('AtKeysFileIo');

class AtKeysFileIo extends AtKeysIo {
  String? filePath;

  AtKeysFileIo(String this.filePath);

  @override
  FutureOr<AtKeys> read(String atSign) async {
    AtKeys? atKeys;
    AtAuthRequest atAuthRequest = AtAuthRequest(atSign)
      ..atKeysFilePath = filePath;
    if (atAuthRequest.atKeysFilePath != null) {
      atKeys = await _prepareAtKeysFromFilePath(atAuthRequest);
    } else {
      atKeys = atAuthRequest.atAuthKeys;
    }
    if (atKeys == null) {
      throw AtAuthenticationException(
          'keys either were not provided in the AtAuthRequest,'
          ' or could not be read from provided keys file');
    }
    return atKeys;
  }

  @override
  Future write(String atSign, AtKeys atKeys) {
    // TODO: implement write
    return Future.value();
  }
}

class AtKeysKeychainIo extends AtKeysIo {
  late AtKeys atKeys;

  AtKeysKeychainIo(this.atKeys);

  @override
  FutureOr<AtKeys> read(String atSign) {
    return atKeys;
  }

  @override
  Future write(String atSign, AtKeys atKeys) {
    // TODO: implement write
    return Future.value();
  }
}

AtKeys _decryptAtKeys(Map<String, dynamic> jsonData) {
  String decryptionKey = jsonData[auth_constants.defaultSelfEncryptionKey]!;
  var atChops =
      AtChopsImpl(AtChopsKeys()..selfEncryptionKey = AESKey(decryptionKey));
  var defaultEncryptionPublicKey = atChops
      .decryptString(jsonData[auth_constants.defaultEncryptionPublicKey]!,
          EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;
  var defaultEncryptionPrivateKey = atChops
      .decryptString(jsonData[auth_constants.defaultEncryptionPrivateKey]!,
          EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;
  var defaultSelfEncryptionKey = AtBytes.fromString(decryptionKey);
  var apkamPublicKey = atChops
      .decryptString(
          jsonData[auth_constants.apkamPublicKey]!, EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;

  // decrypt the private key since is keysFile
  var apkamPrivateKey = atChops
      .decryptString(
          jsonData[auth_constants.apkamPrivateKey]!, EncryptionKeyType.aes256,
          keyName: 'selfEncryptionKey', iv: AtChopsUtil.generateIVLegacy())
      .result;

  var apkamSymmetricKey = jsonData[auth_constants.apkamSymmetricKey];
  var enrollmentId = jsonData[AtConstants.enrollmentId];

  AtKeys atKeys = AtKeys()
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(defaultEncryptionPublicKey)
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(defaultEncryptionPrivateKey)
    ..defaultSelfEncryptionKey = defaultSelfEncryptionKey
    ..apkamPublicKey = AtBytes.fromString(apkamPublicKey)
    ..apkamPrivateKey = AtBytes.fromString(apkamPrivateKey)
    ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey)
    ..enrollmentId = enrollmentId;

  return atKeys;
}

///method to read and return data from .atKeysFile
///returns map containing encryption keys
Future<AtKeys> _prepareAtKeysFromFilePath(AtAuthRequest atAuthRequest) async {
  if (atAuthRequest.atKeysFilePath == null ||
      atAuthRequest.atKeysFilePath!.isEmpty) {
    throw AtException(
        'atKeys filePath is empty. atKeysFile is required to authenticate');
  }
  if (!File(atAuthRequest.atKeysFilePath!).existsSync()) {
    throw AtException(
        'provided keys file does not exist. Please check whether the file path ${atAuthRequest.atKeysFilePath} is valid');
  }

  String atAuthData = await File(atAuthRequest.atKeysFilePath!).readAsString();
  Map<String, dynamic> decodedAtKeysData = jsonDecode(atAuthData);
  // If it contains "iv(InitializationVector)", it means the data is encrypted with a
  // passphrase. Decrypt it.
  if (decodedAtKeysData.containsKey('iv') &&
      atAuthRequest.passPhrase.isNullOrEmpty) {
    throw AtDecryptionException(
        'Pass Phrase is required for password protected atKeys file');
  }
  if (decodedAtKeysData.containsKey('iv')) {
    _logger.info(
        'Found encrypted atKeys files. Decrypting with the given pass-phrase');
    AtEncrypted atEncrypted = AtEncrypted.fromJson(decodedAtKeysData);

    if (atEncrypted.hashingAlgoType == null) {
      throw AtDecryptionException(
          'Hashing algo type is required for decryption of password protected atKeys file');
    }

    String decryptedAtKeys =
        await AtKeysCrypto.fromHashingAlgorithm(atEncrypted.hashingAlgoType!)
            .decrypt(atEncrypted, atAuthRequest.passPhrase!);
    decodedAtKeysData = jsonDecode(decryptedAtKeys);
  }

  return _decryptAtKeys(decodedAtKeysData);
}
