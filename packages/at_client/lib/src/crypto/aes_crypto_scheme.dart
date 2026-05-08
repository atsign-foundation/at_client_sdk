import 'package:at_chops/at_chops.dart';
import 'package:at_chops/types.dart';
import 'package:at_client/src/crypto/key_lookup.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

import '../client/at_client_spec.dart';
import '../util/encryption_util.dart';

class AESScheme extends CryptoScheme {
  final AtSignLogger _logger = AtSignLogger('AESScheme');
  final AtClient _atClient;
  final KeyLookup _keyLookup;

  /// Do not instantiate directly.
  /// Use [AtChops.schemes.lookup()] instead
  @internal
  AESScheme(this._atClient, {KeyLookup? keyLookup})
      : _keyLookup = keyLookup ?? KeyLookup(_atClient);

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

    AESKey encKey = await _keyLookup.fetchKey(
      keyName: KeyNames.aes256EncKey,
      sharedWith: atKey.sharedWith!,
      sharedBy: atKey.sharedBy!,
      algo: 'aes256',
    ) as AESKey;

    AtEncryptionResult decryptionResultFromAtChops;
    try {
      var encryptionAlgo = AESEncryptionAlgo(AESKey(encKey.key));
      decryptionResultFromAtChops = await _atClient.atChops!.decryptString(
        value,
        EncryptionKeyType.aes256,
        encryptionAlgorithm: encryptionAlgo,
        iv: iV,
      );
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
    AESKey encKey;
    try {
      encKey = await _keyLookup.fetchKey(
        keyName: KeyNames.aes256EncKey,
        sharedWith: atKey.sharedWith!,
        sharedBy: atKey.sharedBy!,
        algo: 'aes256',
      ) as AESKey;
    } on AtException catch (e) {
      _logger.severe(
          'Encryption failed. EncryptionKey: ${KeyNames.aes256EncKey} is null');
      e.stack(
        AtChainedException(
            Intent.fetchCryptoScheme,
            ExceptionScenario.encryptionFailed,
            'Encryption Scheme: AESScheme has not been registred with the atClient'),
      );
      rethrow;
    }

    AtEncryptionResult result;
    try {
      InitialisationVector iV;
      atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();
      iV = AtChopsUtil.generateIVFromBase64String(atKey.metadata.ivNonce!);
      var encryptionAlgo = AESEncryptionAlgo(AESKey(encKey.key));
      result = await _atClient.atChops!.encryptString(
          value, EncryptionKeyType.aes256,
          encryptionAlgorithm: encryptionAlgo, iv: iV);
    } on AtEncryptionException catch (e) {
      _logger.severe(
          'encryption exception during aes key encryption of key: ${atKey.key}. Reason: ${e.toString()}');
      rethrow;
    }
    return result.result;
  }

  @override
  Future<void> register() async {
    await _createAesKey(_atClient.getCurrentAtSign()!.toAtsign());
  }

  Future<void> _createAesKey(Atsign currentAtsign) async {
    _logger.info("Creating new aes key");
    // Generate new symmetric key
    var newSymmetricKeyBase64 =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    InitialisationVector iV = AtChopsUtil.generateRandomIV(16);
    // Encrypt the new symmetric key with our public key
    var atChopsEncryptionResult = await _atClient.atChops!.encryptString(
      newSymmetricKeyBase64,
      EncryptionKeyType.aes256,
      iv: iV,
    );
    var encryptedAESKey = atChopsEncryptionResult.result;

    var updateAESKeyBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = KeyNames.aes256EncKey
        ..sharedBy = currentAtsign
        ..sharedWith = currentAtsign)
      ..value = encryptedAESKey;

    _logger.info("Storing new AES symmetric key to atServer");
    await _atClient.getRemoteSecondary()!.executeVerb(
          updateAESKeyBuilder,
          sync: false,
        );

    _logger.info("Storing new AES symmetric key to local storage");
    await _atClient.getLocalSecondary()!.executeVerb(
          updateAESKeyBuilder,
          sync: false,
        );
  }
}
