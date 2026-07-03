import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_chops/at_chops.dart' hide AtEncrypted, AtKeysCrypto;
import 'package:at_chops/types.dart';
import 'package:at_commons/at_commons.dart';

class AtKeysPassphraseEnvelopeCodec {
  final AtDecryptionException Function(String) _decryptionException;

  const AtKeysPassphraseEnvelopeCodec({
    AtDecryptionException Function(String)? decryptionException,
  }) : _decryptionException =
            decryptionException ?? _defaultDecryptionException;

  static AtDecryptionException _defaultDecryptionException(String message) {
    return AtDecryptionException(message);
  }

  bool isEnvelope(Map<String, dynamic> json) {
    return json.containsKey('iv');
  }

  Future<Map<String, dynamic>> decode(
    Map<String, dynamic> json, {
    String? passPhrase,
  }) async {
    if (!isEnvelope(json)) {
      return json;
    }
    if (passPhrase.isNullOrEmpty) {
      throw _decryptionException(
          'Pass Phrase is required for password protected atKeys file');
    }

    final envelope = PassphraseEnvelope.fromJson(json);
    if (envelope.hashingAlgoType == null) {
      throw _decryptionException(
          'Hashing algo type is required for decryption of password protected atKeys file');
    }

    final String decryptedAtKeysData;
    try {
      decryptedAtKeysData = await AtKeysCrypto.fromHashingAlgorithm(
        envelope.hashingAlgoType!,
      ).decrypt(envelope, passPhrase!);
    } catch (e) {
      throw _decryptionException(
          'Failed to decrypt atKeys file - passphrase may be incorrect: $e');
    }

    final decodedJson = jsonDecode(decryptedAtKeysData);
    if (decodedJson is! Map<String, dynamic>) {
      throw AtKeysParseException(
          'Expected decrypted atKeys file to contain a JSON object');
    }
    return decodedJson;
  }
}

/// A class that represents encrypted atKeys, along with metadata such as
/// initialization vector (IV) and the hashing algorithm used.
///
/// This class is used to serialize and deserialize encrypted data for
/// transmission or storage. It provides methods to convert the object
/// to JSON format and parse it back from JSON.
class PassphraseEnvelope {
  /// The encrypted content, typically represented as a Base64 string.
  String? content;

  /// The initialization vector (IV) used during encryption, which adds randomness
  /// to the encryption process and ensures the same content results in different
  /// ciphertexts.
  String? iv;

  /// The type of hashing algorithm used for encryption, represented by an
  /// enum of type [HashingAlgoType].
  HashingAlgoType? hashingAlgoType;

  /// Converts this [PassphraseEnvelope] instance into a JSON-compatible map.
  ///
  /// The returned map includes the encrypted content, IV, and the name of the
  /// hashing algorithm used. The [hashingAlgoType] is converted to its string name.
  ///
  /// Returns a [Map] representing the encrypted data.
  Map<String, String?> toJson() {
    return {
      'content': content,
      'iv': iv,
      'hashingAlgoType': hashingAlgoType?.name
    };
  }

  /// Creates an [PassphraseEnvelope] instance from a JSON-compatible map.
  ///
  /// This method takes a [Map] as input and assigns the corresponding values
  /// to the [content], [iv], and [hashingAlgoType] fields. If the hashing
  /// algorithm is provided as a string, it is converted back to its enum type
  /// using [HashingAlgoType.fromString].
  ///
  /// Returns an [PassphraseEnvelope] object populated with data from the map.
  static PassphraseEnvelope fromJson(Map<String, dynamic> map) {
    PassphraseEnvelope atEncrypted = PassphraseEnvelope()
      ..content = map['content']
      ..iv = map['iv'];

    if (map['hashingAlgoType'] != null && map['hashingAlgoType']!.isNotEmpty) {
      atEncrypted.hashingAlgoType =
          HashingAlgoType.fromString(map['hashingAlgoType']!);
    }
    return atEncrypted;
  }

  /// Returns the string representation of this [PassphraseEnvelope] instance.
  ///
  /// This method converts the object into its JSON string form by calling
  /// [toJson] and encoding the resulting map using [jsonEncode].
  ///
  /// Returns the JSON string representation of the object.
  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

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
  /// This method returns an [PassphraseEnvelope] object, which contains the encrypted
  /// AtKeys.
  ///
  /// - [plainAtKeys]: The plain text AtKeys to be encrypted.
  /// - [passPhrase]: The passphrase used for encryption.
  /// - [hashParams]: Optional parameters used for hashing in the
  ///   encryption process.
  ///
  /// Returns a [FutureOr] that resolves to [PassphraseEnvelope] on success.
  FutureOr<PassphraseEnvelope> encrypt(String plainAtKeys, String passPhrase,
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
  FutureOr<String> decrypt(PassphraseEnvelope atEncrypted, String passPhrase,
      {HashParams? hashParams});
}

/// The implementation class of [AtKeysCrypto]. The implementation classes is marked private.
/// Use [AtKeysCrypto.fromHashingAlgorithm] to get an instance of [_AtKeysCryptoImpl].
class _AtKeysCryptoImpl implements AtKeysCrypto {
  final HashingAlgoType _hashingAlgoType;

  _AtKeysCryptoImpl(this._hashingAlgoType);

  @override
  Future<PassphraseEnvelope> encrypt(String plainAtKeys, String passPhrase,
      {HashParams? hashParams}) async {
    // 1. Generate hash key based on the hashing algo type:
    String hashKey =
        await _getHashKey(passPhrase, _hashingAlgoType, hashParams: hashParams);

    AESKey aesKey = AESKey(hashKey);
    StringAESEncryptor atEncryptionAlgorithm = StringAESEncryptor(aesKey);

    InitialisationVector iv = InitialisationVector.random(16);
    String encryptedContent =
        atEncryptionAlgorithm.encrypt(plainAtKeys, iv: iv);

    return PassphraseEnvelope()
      ..content = encryptedContent
      ..iv = base64Encode(iv.ivBytes)
      ..hashingAlgoType = _hashingAlgoType;
  }

  @override
  Future<String> decrypt(PassphraseEnvelope atEncrypted, String passPhrase,
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
    return switch (hashingAlgoType) {
      HashingAlgoType.argon2id => await Argon2idHashingAlgo().hash(
          passPhrase,
          hashParams: _expectArgonHashParams(hashParams),
        ),
      HashingAlgoType.sha512 => SHA512HashingAlgo().hash(
          utf8.encode(passPhrase),
          hashParams: hashParams,
        ),
      HashingAlgoType.sha256 => SHA256HashingAlgo().hash(
          utf8.encode(passPhrase),
          hashParams: hashParams,
        ),
      HashingAlgoType.md5 => Md5HashingAlgo().hash(
          utf8.encode(passPhrase),
          hashParams: hashParams,
        ),
    };
  }

  ArgonHashParams? _expectArgonHashParams(HashParams? hashParams) {
    if (hashParams == null || hashParams is ArgonHashParams) {
      return hashParams as ArgonHashParams?;
    }
    throw AtException('Argon2id hashing requires ArgonHashParams');
  }
}
