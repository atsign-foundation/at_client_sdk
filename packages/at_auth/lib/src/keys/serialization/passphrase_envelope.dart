import 'dart:async';
import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Encodes/decodes the passphrase envelope that optionally wraps an atKeys
/// document at rest.
///
/// ## Version 1 — what this writes
///
/// ```json
/// {"v": 1, "content": "<base64 AES ciphertext>", "iv": "<base64, 16 bytes>",
///  "hashingAlgoType": "argon2id", "salt": "<base64, 16 bytes>",
///  "kdfParams": {"memory": 19456, "iterations": 2, "parallelism": 1}}
/// ```
///
/// The AES key is Argon2id over the passphrase and the envelope's own random
/// [saltLength]-byte `salt`.
///
/// ## The legacy form, and why it still decodes
///
/// Envelopes without a `v` field carry no salt, and were written when the
/// derivation used **the passphrase itself** as the Argon2id salt. Derivation
/// was therefore deterministic: two users who picked the same passphrase got
/// the same AES key, and a single precomputation table served all of them.
/// Argon2's memory-hardness still charged an attacker per guess, but the
/// property that makes salting worth doing was absent.
///
/// Those files cannot be rewritten from here — the passphrase is the user's,
/// and nothing on this side can re-derive the document without it. So the
/// legacy derivation is preserved exactly, including its UTF-16 `codeUnits`
/// salt, and dispatch is on the presence of `v`. Reading an old file gets the
/// old derivation; everything written gets the new one.
///
/// Migrating an individual file means re-encoding it, which happens naturally
/// the next time its owner sets a passphrase.
///
/// ## What version 1 does not fix
///
/// The cipher is still unauthenticated AES-256-CTR, so a wrong passphrase does
/// not fail [decode] — it yields arbitrary bytes, and the JSON parse is what
/// rejects them. `kdfParams` exists so the Argon2id cost can be raised again
/// without another forward-incompatible break.
class AtKeysPassphraseEnvelopeCodec {
  const AtKeysPassphraseEnvelopeCodec();

  /// The envelope version this codec writes.
  static const int currentVersion = 1;

  /// Bytes of random salt in a version 1 envelope.
  static const int saltLength = 16;

  bool isEnvelope(Map<String, dynamic> json) {
    return json.containsKey('iv');
  }

  /// Encrypts [plaintext] with a key derived from [passPhrase] and returns
  /// the envelope as a JSON string.
  ///
  /// Set [legacyUnsaltedDerivation] only to produce a file an older client can
  /// still open. It writes the pre-`v` form, whose derivation is deterministic
  /// in the passphrase — see the class doc.
  Future<String> encode(
    String plaintext,
    String passPhrase, {
    HashingAlgoType hashingAlgoType = HashingAlgoType.argon2id,
    HashParams? hashParams,
    bool legacyUnsaltedDerivation = false,
  }) async {
    if (legacyUnsaltedDerivation) {
      final aes = await _encryptorForPassphrase(passPhrase, hashingAlgoType,
          hashParams: hashParams);
      final iv = InitialisationVector.random(16);
      return jsonEncode({
        'content': aes.encrypt(plaintext, iv: iv),
        'iv': base64Encode(iv.ivBytes),
        'hashingAlgoType': hashingAlgoType.name,
      });
    }

    if (hashingAlgoType != HashingAlgoType.argon2id) {
      throw AtException('a version $currentVersion envelope is Argon2id only; '
          '${hashingAlgoType.name} is a single unsalted pass and gives a '
          'passphrase almost no protection, so it can be read for old files '
          'but never written');
    }

    final salt = InitialisationVector.random(saltLength).ivBytes;
    final params = _expectArgonHashParams(hashParams) ??
        ArgonHashParams.owaspMinimum(salt: salt);
    // A caller-supplied params object still gets this envelope's salt: the two
    // have to agree, and the salt is generated here.
    params.salt = salt;

    // The envelope persists the salt and the three costs, and `decode` reads
    // each of them back; `hashLength` is not among them, so decode always
    // derives at whatever ArgonHashParams itself defaults to. Writing a file
    // under a different length would therefore produce one that cannot be
    // opened, reported as an incorrect passphrase rather than as the
    // parameter that actually differed — so refuse it here, where the reason
    // is still known. Persisting it instead would add a field nothing in this
    // tree ever varies, and a stored parameter no caller sets is a format
    // that cannot be exercised.
    final lengthDecodeWillUse = ArgonHashParams().hashLength;
    if (params.hashLength != lengthDecodeWillUse) {
      throw AtException(
          'a version $currentVersion envelope does not persist hashLength, so '
          'it is always read back at $lengthDecodeWillUse bytes; encoding at '
          '${params.hashLength} would write a file that fails to open and '
          'blames the passphrase');
    }

    final aes = await _encryptorForPassphrase(passPhrase, hashingAlgoType,
        hashParams: params);
    final iv = InitialisationVector.random(16);
    return jsonEncode({
      'v': currentVersion,
      'content': aes.encrypt(plaintext, iv: iv),
      'iv': base64Encode(iv.ivBytes),
      'hashingAlgoType': hashingAlgoType.name,
      'salt': base64Encode(salt),
      'kdfParams': {
        'memory': params.memory,
        'iterations': params.iterations,
        'parallelism': params.parallelism,
      },
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

    final HashParams? readParams = _paramsForDecode(json);

    try {
      final aes = await _encryptorForPassphrase(
          passPhrase!, HashingAlgoType.fromString(hashingAlgoName),
          hashParams: readParams);
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

  /// The Argon2id parameters an envelope asks to be decoded with, or null for
  /// the legacy unsalted derivation.
  ///
  /// Dispatch is on `v` rather than on the presence of `salt`, so that an
  /// envelope claiming a version this build has no code for is refused rather
  /// than silently falling back to the weaker derivation and reporting the
  /// result as a wrong passphrase.
  HashParams? _paramsForDecode(Map<String, dynamic> json) {
    final version = json['v'];
    if (version == null) {
      return null;
    }
    if (version != currentVersion) {
      throw AtDecryptionException(
          'this atKeys file declares envelope version $version, which this '
          'build has no code for — refusing rather than guessing at how its '
          'key was derived');
    }

    final salt = json['salt'];
    if (salt is! String || salt.isEmpty) {
      throw AtDecryptionException(
          'a version $currentVersion atKeys envelope must carry a salt');
    }

    final params = ArgonHashParams()..salt = base64Decode(salt);
    final kdfParams = json['kdfParams'];
    if (kdfParams is! Map) {
      throw AtDecryptionException(
          'a version $currentVersion atKeys envelope must carry kdfParams');
    }
    // Read every cost back off the file. The defaults on ArgonHashParams are
    // the legacy ones, so leaving any of these to fall through would derive a
    // different key and surface as an incorrect passphrase.
    for (final name in const ['memory', 'iterations', 'parallelism']) {
      if (kdfParams[name] is! int) {
        throw AtDecryptionException(
            'a version $currentVersion atKeys envelope must carry an integer '
            'kdfParams.$name');
      }
    }
    return params
      ..memory = kdfParams['memory'] as int
      ..iterations = kdfParams['iterations'] as int
      ..parallelism = kdfParams['parallelism'] as int;
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
