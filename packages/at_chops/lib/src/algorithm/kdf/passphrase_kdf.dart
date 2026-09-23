import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kdf_params.dart';

/// Derives [length] bytes of key material from [secret] and [salt] under
/// [params].
///
/// An implementation throws [ArgumentError] for [params] of another KDF.
abstract interface class PassphraseKdf {
  Future<Uint8List> derive(Uint8List secret, Uint8List salt, KdfParams params,
      {int length = 32});
}

/// Argon2id through `package:cryptography`.
class Argon2idKdf implements PassphraseKdf {
  const Argon2idKdf();

  @override
  Future<Uint8List> derive(Uint8List secret, Uint8List salt, KdfParams params,
          {int length = 32}) =>
      switch (params) {
        Argon2idParams() => _derive(
            Argon2id(
                memory: params.memoryKiB,
                iterations: params.iterations,
                parallelism: params.parallelism,
                hashLength: length),
            secret,
            salt),
        _ => throw ArgumentError.value(params, 'params', 'not Argon2idParams'),
      };
}

/// PBKDF2-HMAC-SHA256 through `package:cryptography`.
class Pbkdf2Sha256Kdf implements PassphraseKdf {
  const Pbkdf2Sha256Kdf();

  @override
  Future<Uint8List> derive(Uint8List secret, Uint8List salt, KdfParams params,
          {int length = 32}) =>
      switch (params) {
        Pbkdf2Sha256Params() => _derive(
            Pbkdf2(
                macAlgorithm: Hmac.sha256(),
                iterations: params.iterations,
                bits: length * 8),
            secret,
            salt),
        _ =>
          throw ArgumentError.value(params, 'params', 'not Pbkdf2Sha256Params'),
      };
}

/// The [PassphraseKdf] that [params] belong to.
PassphraseKdf kdfFor(KdfParams params) => switch (params) {
      Argon2idParams() => const Argon2idKdf(),
      Pbkdf2Sha256Params() => const Pbkdf2Sha256Kdf(),
    };

Future<Uint8List> _derive(
    KdfAlgorithm algorithm, Uint8List secret, Uint8List salt) async {
  final key =
      await algorithm.deriveKey(secretKey: SecretKey(secret), nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}
