import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/crypto/util.dart';
import 'package:at_client/src/crypto/key_lookup.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:encrypt/encrypt.dart';
import 'package:meta/meta.dart';

import '../client/at_client_spec.dart';
import '../util/encryption_util.dart';

class RSAScheme extends CryptoScheme {
  final AtSignLogger _logger = AtSignLogger('RSAScheme');
  final AtClient _atClient;
  final KeyLookup _keyLookup;

  /// Do not instantiate directly.
  /// Use [AtChops.schemes.lookup()] instead
  @internal
  RSAScheme(this._atClient, {KeyLookup? keyLookup})
      : _keyLookup = keyLookup ?? KeyLookup(_atClient); // mocking

  /// Returns the decrypted value for the given encrypted value.
  ///
  /// Throws [IllegalArgumentException] if encrypted value is null.
  ///
  /// Throws [KeyNotFoundException] if encryption keys are not found.
  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic value) async {
    // setup IV
    InitialisationVector? iV;
    if (atKey.metadata.ivNonce != null) {
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
    } else {
      iV = AtChopsUtil.generateIVLegacy();
    }
    AESKey? sharedKey;
    //decryption
    try {
      if (atKey.metadata.sharedKeyEnc != null) {
        sharedKey = AESKey(atKey.metadata.sharedKeyEnc!);
      }
      sharedKey ??= await _keyLookup.fetchKey(
        keyName: AtConstants.atEncryptionSharedKey,
        sharedWith: atKey.sharedWith!,
        sharedBy: atKey.sharedBy!,
        algo: EncryptionKeyType.rsa4096.name,
      ) as AESKey;
    } catch (_) {
      _logger.severe('Decryption failed. SharedKey is null');
      throw SharedKeyNotFoundException('Empty or null SharedKey is found',
          intent: Intent.fetchEncryptionSharedKey,
          exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
    }
    await CryptoUtil.validatePublicKey(atKey, _atClient);
    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(AESKey(sharedKey.key));
      decryptionResultFromAtChops = await _atClient.atChops!.decryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
      _logger.finer(
          'decryptionResultFromAtChops: ${decryptionResultFromAtChops.result}');
    } on AtDecryptionException catch (e) {
      _logger.severe(
          'decryption exception during of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return decryptionResultFromAtChops.result;
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, value) async {
    AESKey sharedKey;
    try {
      sharedKey = await _keyLookup.fetchKey(
        keyName: AtConstants.atEncryptionSharedKey,
        sharedWith: atKey.sharedWith!,
        sharedBy: atKey.sharedBy!,
        algo: EncryptionKeyType.rsa2048.name,
      ) as AESKey;
    } catch (_) {
      _logger.severe('Decryption failed. SharedKey is null');
      final key = await _createSharedKey(
        atKey.sharedBy!.toAtsign(),
        atKey.sharedWith!.toAtsign(),
      );
      sharedKey = AESKey(key);
    }

    AtEncryptionResult result;
    try {
      InitialisationVector iV;
      atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      var encryptionAlgo = AESEncryptionAlgo(AESKey(sharedKey.key));
      result = await _atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during shared key encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return result.result;
  }

  @override
  Future<void> register() async {
    //ensure public and private encryption keys exist (they do)
  }

  Future<String> _createSharedKey(Atsign sharedBy, Atsign sharedWith) async {
    _logger
        .info("Creating new shared symmetric key as $sharedBy for $sharedWith");
    // Generate new symmetric key
    var newSymmetricKeyBase64 =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // Encrypt the new symmetric key with our public key
    var atChopsEncryptionResult = await _atClient.atChops!
        .encryptString(newSymmetricKeyBase64, EncryptionKeyType.rsa2048);
    var encryptedSharedKeyMyCopy = atChopsEncryptionResult.result;
    _logger.info(
        'encryptedSharedKeyMyCopy from atChops: $encryptedSharedKeyMyCopy');

    // Store my copy for future use
    // First, store to atServer
    // try {
    _logger.info("Storing new shared symmetric key to atServer");
    await _storeMyEncryptedSharedKey(
      sharedWith,
      sharedBy,
      encryptedSharedKeyMyCopy,
      _atClient.getRemoteSecondary()!,
    );

    // Now store to local
    _logger.info("Storing new shared symmetric key to local storage");
    await _storeMyEncryptedSharedKey(
      sharedWith,
      sharedBy,
      encryptedSharedKeyMyCopy,
      _atClient.getLocalSecondary()!,
    );

    // Return the unencrypted symmetric key
    return newSymmetricKeyBase64;
  }

  /// Stores the encryptedSharedKey for future use.
  Future<void> _storeMyEncryptedSharedKey(
    Atsign sharedWith,
    Atsign sharedBy,
    String encryptedSharedKey,
    Secondary secondary,
  ) async {
    var updateSharedKeyForCurrentAtSignBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key =
            '${AtConstants.atEncryptionSharedKey}.${sharedWith.replaceAll('@', '')}'
        ..sharedBy = sharedBy)
      ..value = encryptedSharedKey;
    await secondary.executeVerb(updateSharedKeyForCurrentAtSignBuilder,
        sync: false);
  }
}
