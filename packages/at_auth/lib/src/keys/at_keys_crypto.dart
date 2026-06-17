import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

import '../../../../at_chops/lib/src/algorithm/hashing/types.dart';

/// An abstract class that provides cryptographic operations for AtKeys using
/// specific hashing algorithms.
///
/// This class allows for encryption and decryption of AtKeys
/// with a passphrase, using the provided hashing algorithm type.
abstract class AtKeysCrypto {
  /// Returns an instance of [_AtKeysCryptoImpl] based on the
  /// provided [hashingAlgoType].
  ///
  /// The [hashingAlgoType] parameter determines the hashing
  /// algorithm to be used in the cryptographic operations.
  static AtKeysCrypto fromHashingAlgorithm(HashingAlgoType hashingAlgoType) =>
      _AtKeysCryptoImpl(hashingAlgoType);

  /// Encrypts the given [plainAtKeys] using the provided [passPhrase] and
  /// optional [hashParams].
  ///
  /// This method returns an [AtEncrypted] object, which contains the encrypted
  /// AtKeys.
  ///
  /// - [plainAtKeys]: The plain text AtKeys to be encrypted.
  /// - [passPhrase]: The passphrase used for encryption.
  /// - [hashParams]: Optional parameters used for hashing in the
  ///   encryption process.
  ///
  /// Returns a [FutureOr] that resolves to [AtEncrypted] on success.
  FutureOr<AtEncrypted> encrypt(String plainAtKeys, String passPhrase,
      {HashParams? hashParams});

  /// Decrypts the given [atEncrypted] object back to its original
  /// plain text format using the provided [passPhrase] and
  /// optional [hashParams].
  ///
  /// - [atEncrypted]: The encrypted AtKeys object to be decrypted.
  /// - [passPhrase]: The passphrase used for decryption.
  /// - [hashParams]: Optional parameters used for hashing in the
  ///   decryption process.
  ///
  /// Returns a [FutureOr] that resolves to a [String] containing
  /// the decrypted AtKeys on success.
  FutureOr<String> decrypt(AtEncrypted atEncrypted, String passPhrase,
      {HashParams? hashParams});
}

/// The implementation class of [AtKeysCrypto]. The implementation classes is marked private.
/// Use [AtKeysCrypto.fromHashingAlgorithm] to get an instance of [_AtKeysCryptoImpl].
class _AtKeysCryptoImpl implements AtKeysCrypto {
  final HashingAlgoType _hashingAlgoType;

  _AtKeysCryptoImpl(this._hashingAlgoType);

  @override
  Future<AtEncrypted> encrypt(String plainAtKeys, String passPhrase,
      {HashParams? hashParams}) async {
    // 1. Generate hash key based on the hashing algo type:
    String hashKey =
        await _getHashKey(passPhrase, _hashingAlgoType, hashParams: hashParams);

    AESKey aesKey = AESKey(hashKey);
    StringAESEncryptor atEncryptionAlgorithm = StringAESEncryptor(aesKey);

    InitialisationVector iv = InitialisationVector.random(16);
    String encryptedContent =
        atEncryptionAlgorithm.encrypt(plainAtKeys, iv: iv);

    return AtEncrypted()
      ..content = encryptedContent
      ..iv = base64Encode(iv.ivBytes)
      ..hashingAlgoType = _hashingAlgoType;
  }

  @override
  Future<String> decrypt(AtEncrypted atEncrypted, String passPhrase,
      {HashParams? hashParams}) async {
    if (atEncrypted.iv.isNullOrEmpty) {
      throw AtDecryptionException(
          'Initialization vector is required for decryption');
    }
    if (atEncrypted.content.isNullOrEmpty) {
      throw AtDecryptionException('Cannot decrypt empty or null content');
    }

    // 1. Generate hash key based on the hashing algo type:
    String hashKey =
        await _getHashKey(passPhrase, _hashingAlgoType, hashParams: hashParams);
    AESKey aesKey = AESKey(hashKey);
    StringAESEncryptor atEncryptionAlgorithm = StringAESEncryptor(aesKey);

    Uint8List iv = base64Decode(atEncrypted.iv!);
    InitialisationVector initialisationVector = InitialisationVector(iv);

    return atEncryptionAlgorithm.decrypt(atEncrypted.content!,
        iv: initialisationVector);
  }

  /// Generates a hashed key based on the provided [passPhrase] and
  /// [hashingAlgoType], with optional [hashParams] for certain algorithms.
  ///
  /// Returns a [Future] that resolves to a [String] representing the
  /// hashed key.
  Future<String> _getHashKey(String passPhrase, HashingAlgoType hashingAlgoType,
      {HashParams? hashParams}) async {
    return await AtHashingAlgorithmFactory.withHashingAlgorithm(hashingAlgoType)
        .hash(passPhrase, hashParams: hashParams);
  }
}
