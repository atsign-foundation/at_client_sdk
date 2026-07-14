import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Encodes/decodes the passphrase envelope that optionally wraps an atKeys
/// document at rest:
///
/// ```json
/// {"content": "<base64 AES ciphertext>", "iv": "<base64, 16 bytes>",
///  "hashingAlgoType": "argon2id"}
/// ```
///
/// The AES key is derived by hashing the passphrase with `hashingAlgoType`.
/// A JSON object is recognized as an envelope by the presence of its `iv`
/// field ([isEnvelope]).
class AtKeysPassphraseEnvelopeCodec {
  const AtKeysPassphraseEnvelopeCodec();

  bool isEnvelope(Map<String, dynamic> json) {
    return json.containsKey('iv');
  }

  /// Encrypts [plaintext] with a key derived from [passPhrase] and returns
  /// the envelope as a JSON string.
  Future<String> encode(
    String plaintext,
    String passPhrase, {
    HashingAlgoType hashingAlgoType = HashingAlgoType.argon2id,
    HashParams? hashParams,
  }) async {
    final aes = await _encryptorForPassphrase(passPhrase, hashingAlgoType,
        hashParams: hashParams);
    final iv = InitialisationVector.random(16);
    return jsonEncode({
      'content': aes.encrypt(plaintext, iv: iv),
      'iv': base64Encode(iv.ivBytes),
      'hashingAlgoType': hashingAlgoType.name,
    });
  }

  /// Decrypts a passphrase envelope back to the JSON object it wraps.
  /// Returns [json] unchanged when it is not an envelope.
  Future<Map<String, dynamic>> decode(
    Map<String, dynamic> json, {
    String? passPhrase,
  }) async {
    if (!isEnvelope(json)) {
      return json;
    }
    if (passPhrase.isNullOrEmpty) {
      throw AtDecryptionException(
          'Pass Phrase is required for password protected atKeys file');
    }

    final hashingAlgoName = json['hashingAlgoType'];
    if (hashingAlgoName is! String || hashingAlgoName.isEmpty) {
      throw AtDecryptionException(
          'Hashing algo type is required for decryption of password protected atKeys file');
    }
    final iv = json['iv'];
    if (iv is! String || iv.isEmpty) {
      throw AtDecryptionException(
          'Initialization vector is required for decryption');
    }
    final content = json['content'];
    if (content is! String || content.isEmpty) {
      throw AtDecryptionException('Cannot decrypt empty or null content');
    }

    try {
      final aes = await _encryptorForPassphrase(
          passPhrase!, HashingAlgoType.fromString(hashingAlgoName));
      final plaintext =
          aes.decrypt(content, iv: InitialisationVector(base64Decode(iv)));
      // jsonDecode must stay inside the try: the cipher is unauthenticated,
      // so an incorrect passphrase does not fail decrypt() -- it yields
      // arbitrary bytes. Whether those bytes parse as a JSON object is
      // effectively random per file (the IV varies per write), so a wrong
      // passphrase otherwise escapes as an uncaught FormatException (invalid
      // JSON) or a cast error (valid non-object JSON) instead of the
      // documented AtDecryptionException.
      final decodedJson = jsonDecode(plaintext);
      if (decodedJson is! Map<String, dynamic>) {
        throw AtKeysParseException(
            'Expected decrypted atKeys file to contain a JSON object');
      }
      return decodedJson;
    } catch (e) {
      throw AtDecryptionException(
          'Failed to decrypt atKeys file - passphrase may be incorrect: $e');
    }
  }

  /// Derives the AES key by hashing [passPhrase] with [hashingAlgoType].
  Future<StringAESEncryptor> _encryptorForPassphrase(
    String passPhrase,
    HashingAlgoType hashingAlgoType, {
    HashParams? hashParams,
  }) async {
    final hashKey = switch (hashingAlgoType) {
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
    return StringAESEncryptor(AESKey(hashKey));
  }

  ArgonHashParams? _expectArgonHashParams(HashParams? hashParams) {
    if (hashParams == null || hashParams is ArgonHashParams) {
      return hashParams as ArgonHashParams?;
    }
    throw AtException('Argon2id hashing requires ArgonHashParams');
  }
}
