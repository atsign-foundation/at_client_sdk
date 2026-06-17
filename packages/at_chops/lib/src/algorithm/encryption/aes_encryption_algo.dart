import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/aes_ctr_factory.dart';
import 'package:at_chops/src/algorithm/padding/pkcs7padding.dart';
import 'package:at_chops/src/algorithm/padding/types.dart';
import 'package:at_commons/at_commons.dart';
import 'package:better_cryptography/better_cryptography.dart';
import 'package:encrypt/encrypt.dart';

/// A class that provides AES encryption and decryption for Uint8List,
/// implementing the [SymmetricEncryptionAlgorithm] interface.
class AESEncryptionAlgo
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  final AESKey _aesKey;
  PaddingAlgorithm? paddingAlgo;
  AESEncryptionAlgo(this._aesKey) {
    paddingAlgo ??= PKCS7Padding(PaddingParams()..blockSize = 16);
  }

  @override
  FutureOr<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv}) async {
    final encryptionAlgo = AesCtrFactory.createEncryptionAlgo(_aesKey);
    var paddedData = paddingAlgo!.addPadding(plainData);
    final secretKey = await encryptionAlgo
        .newSecretKeyFromBytes(base64Decode(_aesKey.toString()));
    var secretBox = await encryptionAlgo.encrypt(paddedData,
        nonce: _getIVFromBytes(iv?.ivBytes)!.bytes, secretKey: secretKey);
    return Uint8List.fromList(secretBox.cipherText);
  }

  @override
  FutureOr<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv}) async {
    final encryptionAlgo = AesCtrFactory.createEncryptionAlgo(_aesKey);
    var secretBox = SecretBox(
      encryptedData,
      nonce: _getIVFromBytes(iv?.ivBytes)!.bytes,
      mac: Mac.empty,
    );
    final secretKey = await encryptionAlgo
        .newSecretKeyFromBytes(base64Decode(_aesKey.toString()));
    var decryptedBytesWithPadding =
        await encryptionAlgo.decrypt(secretBox, secretKey: secretKey);
    var decryptedBytes = paddingAlgo!.removePadding(decryptedBytesWithPadding);
    return Uint8List.fromList(decryptedBytes);
  }

  IV? _getIVFromBytes(Uint8List? ivBytes) {
    if (ivBytes != null) {
      return IV(ivBytes);
    }
    // From the bad old days when we weren't setting IVs
    return IV(Uint8List(16));
  }
}

/// A class that provides AES encryption and decryption for strings,
/// implementing the [SymmetricEncryptionAlgorithm] interface.
///
/// This class uses an [AESKey] to perform encryption and decryption of strings.
/// The key and an [InitialisationVector] (IV) are used for encryption, and the
/// same key must be used for decryption.
class StringAESEncryptor
    implements SymmetricEncryptionAlgorithm<String, String> {
  /// The AES key used for encryption and decryption.
  final AESKey _aesKey;

  /// Constructs an instance of [StringAESEncryptor] with the provided [_aesKey].
  ///
  /// [_aesKey]: The key used for AES encryption and decryption, represented
  /// in Base64 format.
  StringAESEncryptor(this._aesKey);

  /// Decrypts the given [encryptedData] using the provided [iv] (Initialisation Vector).
  ///
  /// The [iv] used for encryption must be the same for decryption. If [iv] is
  /// not provided, an [AtDecryptionException] will be thrown, as the IV is
  /// mandatory for the AES decryption process.
  ///
  /// - [encryptedData]: The Base64-encoded string that represents the encrypted data.
  /// - [iv]: The Initialisation Vector used during decryption. Must be the same
  ///   IV that was used to encrypt the data.
  ///
  /// Returns a [String] that represents the decrypted data.
  ///
  /// Throws an [AtDecryptionException] if the [iv] is missing.

  @override
  String decrypt(String encryptedData, {InitialisationVector? iv}) {
    // The IV used for encryption, the same IV must be used for decryption.
    if (iv == null) {
      throw AtDecryptionException(
          'Initialisation Vector (IV) is required for decryption');
    }
    var aesEncrypter = Encrypter(AES(Key.fromBase64(_aesKey.key)));
    return aesEncrypter.decrypt(Encrypted.fromBase64(encryptedData),
        iv: IV(iv.ivBytes));
  }

  /// Encrypts the given [plainData] using AES encryption and an optional [iv].
  /// The resulting encrypted data will be Base64-encoded.
  ///
  /// - [plainData]: The string that needs to be encrypted.
  /// - [iv]: The Initialisation Vector used for encryption. If not provided,
  ///   AtEncryptionException will be thrown.
  ///
  /// Returns a [String] that contains the encrypted data, encoded in Base64 format.
  ///
  /// Throws an [AtEncryptionException] if the [iv] is missing.
  @override
  String encrypt(String plainData, {InitialisationVector? iv}) {
    if (iv == null) {
      throw AtEncryptionException(
          'Initialisation Vector (IV) is required for encryption');
    }
    var aesEncrypter = Encrypter(AES(Key.fromBase64(_aesKey.key)));
    final encrypted = aesEncrypter.encrypt(plainData, iv: IV(iv.ivBytes));
    return encrypted.base64;
  }
}
