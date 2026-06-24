import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/atkeys.dart';
import 'package:at_auth/src/keys/io/types.dart';
import 'package:at_auth/src/keys/legacy/at_keys_legacy.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// An implementation of [AtKeysIo] that reads and writes AtKeys to the file system.
/// This implementation uses [FileAtKeysIoStatic] to encode and decode AtKeys.
/// The [FileAtKeysIo] class can be configured with an optional [filePath] and [passPhrase].
///
/// Optional Parameters:
/// If [filePath] is a format function derived from your atSign. Defaults to using %HOME%/.atsign/keys/$atsign_key.t atKeys
/// The [passPhrase] is used for atKeys files that are password protected.
@Deprecated(
  'Use AtKeysSet-based key storage APIs instead. FileAtKeysIo is retained for legacy .atKeys files.',
)
class FileAtKeysIo extends WrittenAtKeysIo {
  String Function(String)? filePath;
  String? passPhrase;
  FileAtKeysIo({this.filePath, this.passPhrase}) {
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  /// Reads AtKeys from the file system.
  /// The [atSign] parameter is used to determine the file path if not provided during instantiation.
  /// The method returns a Future that resolves to an instance of [AtKeys].
  @override
  Future<AtKeysSet> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    String file = filePath!(atSign);
    if (!File(file).existsSync()) {
      throw AtException(
          'provided keys file does not exist. Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    decodedAtKeysData = jsonDecode(atAuthData);
    decodedAtKeysData = await FileAtKeysIoStatic.decodeAtKeys(
      decodedAtKeysData,
      passPhrase: passPhrase,
    );
    AtKeys atKeys = await FileAtKeysIoStatic.decryptAtKeysWithSelfEncKey(
      decodedAtKeysData,
      PkamAuthMode.keysFile,
    );
    return atKeys.toAtKeysSet(atsign: atSign.toAtsign());
  }

  @override
  Future write(String atSign, AtKeys atKeys) async {
    String path = filePath!(atSign);
    if (!Directory(path).parent.existsSync()) {
      await Directory(path).parent.create(recursive: true);
    }
    //don't overwrite the file
    if (File(path).existsSync()) {
      throw AtKeysFileOverwriteException(
          'Tried writing $path, but failed since it already exists');
    }

    String atKeysData = await FileAtKeysIoStatic.encryptAtKeysWithSelfEncKey(
      atKeys,
      PkamAuthMode.keysFile,
      atSign,
    );

    if (passPhrase != null && passPhrase!.isNotEmpty) {
      AtEncrypted atEncrypted =
          await AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id)
              .encrypt(atKeysData, passPhrase!);
      atKeysData = atEncrypted.toString();
    }

    await File(path).writeAsString(atKeysData);
  }

  static const keySchemaList = [
    auth_constants.apkamPublicKey,
    auth_constants.apkamPrivateKey,
    auth_constants.defaultEncryptionPublicKey,
    auth_constants.defaultEncryptionPrivateKey,
    auth_constants.defaultSelfEncryptionKey,
    auth_constants.apkamSymmetricKey,
    auth_constants.apkamEnrollmentId
  ];
}

/// Legacy AtKeys file encoding, decoding, and generation helpers.
///
/// Kept with [FileAtKeysIo] because these helpers operate on the legacy
/// `.atKeys` file format rather than on the generic [AtKeysIo] interface.
///
///  One of the helpers had to remain the WrittenAtKeysIo as they contain a breaking change.
@Deprecated('Only used as a legacy helper.')
abstract final class FileAtKeysIoStatic {
  static final AtSignLogger _logger = AtSignLogger('FileAtKeysIoStatic');

  static FutureOr<AtKeys> decryptAtKeysWithSelfEncKey(
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
    // Pkam private key will not be saved in keyfile if auth mode is sim/secure element.
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

  static AtKeys generateKeyPairs({bool generatePkamKeyPair = true}) {
    var atKeysFile = AtKeys();
    var logger = AtSignLogger('FileAtKeysIoStatic');
    logger.info('Generating encryption keypair');
    var atEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();

    var selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    logger.info('Generating your encryption keys and .atKeys file\n');

    String? pkamPublicKey;
    if (generatePkamKeyPair) {
      logger.info('Generating pkam keypair');
      var apkamRsaKeypair = AtChopsUtil.generateAtPkamKeyPair();
      pkamPublicKey = apkamRsaKeypair.atPublicKey.publicKey.toString();
      atKeysFile.apkamPrivateKey = AtBytes.fromString(
          apkamRsaKeypair.atPrivateKey.privateKey.toString());
    }

    atKeysFile.apkamPublicKey = AtBytes.fromString(pkamPublicKey.toString());
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
    if (decodedAtKeysData.containsKey('iv') && passPhrase.isNullOrEmpty) {
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

      try {
        final decryptedAtKeysData = await AtKeysCrypto.fromHashingAlgorithm(
                atEncrypted.hashingAlgoType!)
            .decrypt(atEncrypted, passPhrase!);
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

// Taken from at_cli_commons, but I can't import it due to circular dependencies
// at_cli_commons depends on at_onboarding_cli....
String getDefaultAtKeysFilePath(String homeDirectory, String atSign) {
  return '$homeDirectory/.atsign/keys/${atSign}_key.atKeys'
      .replaceAll('/', Platform.pathSeparator);
}

String? getHomeDirectory({bool throwIfNull = false}) {
  String? homeDir;
  switch (Platform.operatingSystem) {
    case 'linux':
    case 'macos':
      homeDir = Platform.environment['HOME'];
      break;

    case 'windows':
      homeDir = Platform.environment['USERPROFILE'];
      break;

    case 'android':
      // Probably want internal storage.
      homeDir = '/storage/sdcard0';
      break;

    case 'ios':
    // iOS doesn't really have a home directory.
    case 'fuchsia':
    // I have no idea.
    default:
      homeDir = null;
  }
  if (throwIfNull && homeDir == null) {
    throw ('\nUnable to determine your home directory: please set environment variable\n\n');
  }
  return homeDir;
}
