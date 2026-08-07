import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/hashing/types.dart';
import 'package:at_chops/src/key/keys.dart';
import 'package:meta/meta.dart';

/// Interface for encrypting and decrypting data. Check [DefaultEncryptionAlgo] for sample implementation.
abstract class AtEncryptionAlgorithm<T, V> {
  /// Encrypts the passed bytes. Bytes are passed as [Uint8List]. Encode String data type to [Uint8List] using [utf8.encode].
  FutureOr<V> encrypt(T plainData);

  /// Decrypts the passed encrypted bytes.
  FutureOr<V> decrypt(T encryptedData);
}

/// Interface for symmetric encryption algorithms. Check [AESEncryptionAlgo] for sample implementation.
abstract class SymmetricEncryptionAlgorithm<T, V>
    extends AtEncryptionAlgorithm<T, V> {
  @override
  FutureOr<V> encrypt(T plainData, {InitialisationVector iv});

  @override
  FutureOr<V> decrypt(T encryptedData, {InitialisationVector iv});
}

/// Interface for asymmetric encryption algorithms. Check [DefaultEncryptionAlgo] for sample implementation.
abstract class ASymmetricEncryptionAlgorithm
    extends AtEncryptionAlgorithm<Uint8List, Uint8List> {
  AtPublicKey? atPublicKey;
  AtPrivateKey? atPrivateKey;

  /// Encrypt [plainData] with [atPublicKey.publicKey]
  @override
  Uint8List encrypt(Uint8List plainData);

  /// Decrypt [encryptedData] with [atPrivateKey.privateKey]
  @override
  Uint8List decrypt(Uint8List encryptedData);
}

/// Interface for data signing. Data is signed using private key from a key pair.
/// Signed data signature is verified with public key of the key pair.
///
/// **Do not implement for new code.** Implement [AtSignatureAlgorithm] instead —
/// it is stateless (key material passed per call) and safe to share as a singleton.
///
/// Removed in v4. Will become `sealed` once all implementers move into this
/// library, closing the hierarchy in favor of [AtSignatureAlgorithm].
@Deprecated(
  'Removed in v4. Use AtSignatureAlgorithm instead.',
)
@sealed
abstract class AtSigningAlgorithm {
  /// Signs the data using private key of asymmetric key pair
  FutureOr<Uint8List> sign(Uint8List data);

  /// Verifies the data signature using public key of asymmetric key pair or the passed [publicKey]
  FutureOr<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey});
}

/// Stateless signing interface — all key material passed per call.
///
/// Safe to share as a singleton.
///
/// Key material is passed via named parameters so that call sites cannot
/// silently transpose same-typed byte arguments (the published 3.3.0 FFI
/// backend took `(secretKey, data)`; a positional reorder would keep
/// compiling while binding arguments to the wrong slots).
abstract interface class AtSignatureAlgorithm {
  /// Generate a fresh signing key pair.
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair();

  /// Signs [message] with [secretKey]; returns the signature bytes.
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey});

  /// Returns `true` if [signature] was produced over [message] with the
  /// private key corresponding to [publicKey].
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey});
}

/// Interface for hashing data. Refer [DefaultHash] for sample implementation.
abstract class AtHashingAlgorithm<K, V> {
  /// Hashes the passed data
  FutureOr<V> hash(K data, {covariant HashParams? hashParams});
}

/// Interface for a Key Encapsulation Mechanism (KEM) such as ML-KEM-768.
///
/// A KEM does not encrypt arbitrary data. It produces a shared secret that
/// both parties can derive — the sender via [encapsulate] against the
/// recipient's public key, the recipient via [decapsulate] using their
/// secret key and the ciphertext sent by the sender.
abstract class AtKemAlgorithm {
  /// Generate a fresh key pair from a secure random source.
  ///
  /// The `secretKey` returned here is what [decapsulate] takes, which is **not
  /// always what a caller should persist**: for X-Wing it is the 32-byte seed,
  /// but for ML-KEM it is the expanded decapsulation key, and for the FFI
  /// backends it is an opaque process-lifetime handle. A caller that has to
  /// keep a key across restarts wants [newSeed] and [keyPairFromSeed], which
  /// mean the same thing on every backend.
  FutureOr<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair();

  /// A fresh seed drawn from a secure random source, of whatever length this
  /// backend's [keyPairFromSeed] takes.
  ///
  /// The length is deliberately not on this interface. It is backend-specific
  /// (32 bytes for X-Wing, 64 for ML-KEM's `d || z`) and a caller has no use
  /// for it: this makes a valid one, and [keyPairFromSeed] rejects an invalid
  /// one. Concrete classes expose their own `seedLength` for the callers that
  /// do name a backend.
  Uint8List newSeed();

  /// Deterministically regenerate the key pair that [seed] produces.
  ///
  /// **This is the pair a stored key should be recovered through.** Persisting
  /// [generateKeyPair]'s `secretKey` is correct only where that key IS its own
  /// seed; nothing round-trips an expanded ML-KEM decapsulation key back to a
  /// public half, and an FFI handle does not outlive the process. Persisting
  /// the seed and re-deriving here is correct for every backend, and it is the
  /// only form in which a caller can hold a key for a KEM it does not name.
  ///
  /// Throws [ArgumentError] if [seed] is not this backend's seed length —
  /// pass [newSeed]'s result and it never is.
  FutureOr<({Uint8List publicKey, Uint8List secretKey})> keyPairFromSeed(
      Uint8List seed);

  /// Encapsulate a fresh shared secret against [publicKey].
  ///
  /// Returns the [ciphertext] to transmit to the holder of the matching
  /// secret key, together with the [sharedSecret] that both parties will
  /// derive.
  FutureOr<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey);

  /// Recover the shared secret from [ciphertext] using [secretKey].
  FutureOr<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext);
}

/// Interface for a Diffie–Hellman key agreement primitive such as X25519.
abstract class AtKeyAgreementAlgorithm {
  /// Compute the shared secret from [privateKey] and [peerPublicKey].
  FutureOr<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey);
}
