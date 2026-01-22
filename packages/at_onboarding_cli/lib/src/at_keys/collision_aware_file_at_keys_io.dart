import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/at_keys/keys_file_writer.dart';
import 'package:at_onboarding_cli/src/util/auth_key_type.dart';
import 'package:chalkdart/chalk.dart';

/// A collision-aware implementation of FileAtKeysIo that integrates with
/// at_onboarding_cli's collision handling system.
///
/// This class provides both:
/// 1. Instance methods (extends WrittenAtKeysIo) for at_auth integration
/// 2. Static utility methods for direct usage
///
/// Both approaches use the same underlying collision-aware file writing logic.
class CollisionAwareFileAtKeysIo extends WrittenAtKeysIo {
  /// Function that takes atSign and returns the file path where keys should be stored
  String Function(String)? filePath;

  /// Optional passphrase for encrypting the keys file
  final String? passPhrase;

  /// Collision handler to use when target file already exists
  final AtKeysFileCollisionHandler collisionHandler;

  CollisionAwareFileAtKeysIo({
    this.filePath,
    this.passPhrase,
    AtKeysFileCollisionHandler? collisionHandler,
  }) : collisionHandler =
            collisionHandler ?? AtKeysFileCollisionHandlers.abortOnCollision {
    // Set default filePath if not provided
    filePath ??=
        (atsign) => getDefaultAtKeysFilePath(getHomeDirectory()!, atsign);
  }

  @override
  Future<AtKeys> read(String atSign) async {
    Map<String, dynamic> decodedAtKeysData = {};
    String file = filePath!(atSign);
    if (!File(file).existsSync()) {
      throw AtException('provided keys file does not exist. '
          'Please check whether the file path $file is valid');
    }
    String atAuthData = await File(file).readAsString();
    decodedAtKeysData = jsonDecode(atAuthData);
    decodedAtKeysData =
        await decodeAtKeys(decodedAtKeysData, passPhrase: passPhrase);
    return decryptAtKeysWithSelfEncKey(
        decodedAtKeysData, PkamAuthMode.keysFile);
  }

  @override
  Future<void> write(String atSign, AtKeys atKeys) async {
    // Encrypt and write using shared helper
    await _writeKeysWithCollisionHandling(
      atKeys: atKeys,
      atSign: atSign,
      targetPath: filePath!(atSign),
      collisionHandler: collisionHandler,
      passPhrase: passPhrase,
      hashingAlgoType: HashingAlgoType.sha512,
    );
  }

  /// Static method for direct usage (e.g., in enroll() flow)
  ///
  /// Returns the final path where the file was written (may be different from
  /// targetPath if collision handler suggested an alternative).
  ///
  /// Parameters:
  /// - [atKeys]: The keys to write
  /// - [atSign]: The atSign these keys belong to
  /// - [targetPath]: The intended file path
  /// - [collisionHandler]: Handler for file collisions (defaults to abort)
  /// - [passPhrase]: Optional passphrase for encryption
  /// - [enrollmentId]: Optional enrollment ID to include in keys file
  /// - [authMode]: Authentication mode (defaults to keysFile)
  /// - [hashingAlgoType]: Hashing algorithm for passphrase encryption
  static Future<String> writeKeys({
    required AtKeys atKeys,
    required String atSign,
    required String targetPath,
    AtKeysFileCollisionHandler? collisionHandler,
    String? passPhrase,
    String? enrollmentId,
    PkamAuthMode authMode = PkamAuthMode.keysFile,
    HashingAlgoType hashingAlgoType = HashingAlgoType.sha512,
  }) async {
    return await _writeKeysWithCollisionHandling(
      atKeys: atKeys,
      atSign: atSign,
      targetPath: targetPath,
      collisionHandler:
          collisionHandler ?? AtKeysFileCollisionHandlers.abortOnCollision,
      passPhrase: passPhrase,
      enrollmentId: enrollmentId,
      authMode: authMode,
      hashingAlgoType: hashingAlgoType,
    );
  }

  /// Shared helper method that handles encryption and collision-aware writing
  ///
  /// This is the core logic used by both instance and static methods.
  static Future<String> _writeKeysWithCollisionHandling({
    required AtKeys atKeys,
    required String atSign,
    required String targetPath,
    required AtKeysFileCollisionHandler collisionHandler,
    String? passPhrase,
    String? enrollmentId,
    PkamAuthMode authMode = PkamAuthMode.keysFile,
    HashingAlgoType hashingAlgoType = HashingAlgoType.sha512,
  }) async {
    final atKeysMap = <String, String>{
      AuthKeyType.aesEncryptedPkamPublicKey: EncryptionUtil.encryptValue(
        atKeys.apkamPublicKey!.toString(),
        atKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.aesEncryptedEncryptionPublicKey: EncryptionUtil.encryptValue(
        atKeys.defaultEncryptionPublicKey!.toString(),
        atKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.aesEncryptedEncryptionPrivateKey: EncryptionUtil.encryptValue(
        atKeys.defaultEncryptionPrivateKey!.toString(),
        atKeys.defaultSelfEncryptionKey!.toString(),
      ),
      AuthKeyType.selfEncryptionKey:
          atKeys.defaultSelfEncryptionKey!.toString(),
      atSign: atKeys.defaultSelfEncryptionKey!.toString(),
      AuthKeyType.apkamSymmetricKey: atKeys.apkamSymmetricKey!.toString(),
    };

    if (enrollmentId != null && enrollmentId.isNotEmpty) {
      atKeysMap['enrollmentId'] = enrollmentId;
    }

    // Add PKAM private key if in keysFile mode
    if (authMode == PkamAuthMode.keysFile && atKeys.apkamPrivateKey != null) {
      atKeysMap[AuthKeyType.aesEncryptedPkamPrivateKey] =
          EncryptionUtil.encryptValue(
        atKeys.apkamPrivateKey!.toString(),
        atKeys.defaultSelfEncryptionKey!.toString(),
      );
    }

    String encodedAtKeysString = jsonEncode(atKeysMap);

    // Apply passphrase encryption if provided
    if (passPhrase != null) {
      AtEncrypted atEncrypted = await AtKeysCrypto.fromHashingAlgorithm(
        hashingAlgoType,
      ).encrypt(encodedAtKeysString, passPhrase);
      encodedAtKeysString = atEncrypted.toString();
    }

    String finalPath = await AtKeysFileWriter.writeKeys(
      encodedAtKeysString,
      targetPath,
      collisionHandler,
    );

    stdout.writeln('\n${chalk.green('[Success]')} Your .atKeys file saved'
        ' at $finalPath\n');

    return finalPath;
  }
}
