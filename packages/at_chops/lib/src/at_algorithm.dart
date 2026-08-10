import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/hashing/types.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;

/// The umbrella every at_chops algorithm sits under.
///
/// Sealed, so a switch over the algorithm families below is exhaustive without
/// a default arm. Sealing is not transitive, so the families themselves stay
/// freely implementable outside this library — only adding a *seventh* family
/// is closed off, and that is a deliberate breaking change for anyone
/// switching over [AtAlgorithm].
sealed class AtAlgorithm {
  /// Stable identifier for this algorithm — a downstream protocol's wire,
  /// record, or keystore identifier for it (e.g. at_server's FROM/POL
  /// handshake tags its cookie and published-key record with this).
  ///
  /// This *is* the corresponding enum constant's `name` — [SigningAlgoType],
  /// [EncryptionAlgoType], [KemAlgoType], [HashingAlgoType] or
  /// [KeyAgreementAlgoType]. Those constants are spelled to be the identifier,
  /// so there is no second vocabulary to translate between. Implementations
  /// return `<Enum>.<value>.name`.
  String get name;
}

/// Interface for symmetric encryption algorithms. Key material is passed per
/// call. Check [AesCtrEncryptionAlgo] for sample implementation.
///
/// Encode String data to [Uint8List] with [utf8.encode] before passing it in.
///
/// [iv] is required: every implementation needs one, none of them return a
/// generated one, and reusing a (key, iv) pair is a security bug — so the
/// caller must own it. For data written before IVs were set, pass
/// [InitialisationVector.legacy].
abstract class SymmetricEncryptionAlgorithm implements AtAlgorithm {
  /// Generate a fresh key of the length this algorithm requires.
  ///
  /// The length is the implementation's own — AES-256-GCM always returns 32
  /// bytes, AES-CTR returns whatever it was constructed for — so a caller
  /// holding this interface never has to know it.
  Uint8List generateKey();

  /// Encrypt [plainData] with [key] and [iv].
  FutureOr<Uint8List> encrypt(Uint8List plainData, Uint8List key,
      {required InitialisationVector iv});

  /// Decrypt [encryptedData] with [key] and the same [iv] used to encrypt it.
  FutureOr<Uint8List> decrypt(Uint8List encryptedData, Uint8List key,
      {required InitialisationVector iv});
}

/// Interface for asymmetric encryption algorithms. Key material is passed per
/// call. Check [RsaEncryptionAlgo] for sample implementation.
abstract class ASymmetricEncryptionAlgorithm implements AtAlgorithm {
  /// Encrypt [plainData] with [publicKey]
  Uint8List encrypt(Uint8List plainData, Uint8List publicKey);

  /// Decrypt [encryptedData] with [privateKey]
  Uint8List decrypt(Uint8List encryptedData, Uint8List privateKey);
}

/// Stateless signing interface — all key material passed per call.
///
/// Safe to share as a singleton.
///
/// Key material is passed via named parameters so that call sites cannot
/// silently transpose same-typed byte arguments (the published 3.3.0 FFI
/// backend took `(secretKey, data)`; a positional reorder would keep
/// compiling while binding arguments to the wrong slots).
abstract class AtSignatureAlgorithm implements AtAlgorithm {
  /// Generate a fresh signing key pair.
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair();

  /// Signs [message] with [secretKey]; returns the signature bytes.
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey});

  /// Verifies that [signature] was produced over [message] with the private
  /// key corresponding to [publicKey]. Returns normally iff it was.
  ///
  /// Throws [AtSigningVerificationException] if it was not — a wrong key, a
  /// tampered message, a forged signature, or a digest this implementation
  /// cannot use. A failed verification is an error, not a result: returning
  /// `false` invites call sites to ignore it, and one in the SDK did exactly
  /// that. Implementations must not return normally on any outcome other than
  /// a good signature.
  ///
  /// Malformed key or signature *bytes* — a short scalar, an invalid curve
  /// point — are caller errors rather than verification failures, and surface
  /// as whatever the backend raises, typically [ArgumentError] or
  /// [RangeError].
  Future<void> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey});
}

/// Interface for hashing data. Refer [Md5HashingAlgo] for sample implementation.
abstract class AtHashingAlgorithm<K, V> implements AtAlgorithm {
  /// Hashes the passed data
  FutureOr<V> hash(K data, {covariant HashParams? hashParams});
}

/// Interface for a Key Encapsulation Mechanism (KEM) such as ML-KEM-768.
///
/// A KEM does not encrypt arbitrary data. It produces a shared secret that
/// both parties can derive — the sender via [encapsulate] against the
/// recipient's public key, the recipient via [decapsulate] using their
/// secret key and the ciphertext sent by the sender.
abstract class AtKemAlgorithm implements AtAlgorithm {
  /// Generate a fresh key pair from a secure random source.
  ///
  /// Deterministic (seeded) generation is deliberately not part of this
  /// interface: seed length and format are backend-specific (e.g. a 32-byte
  /// X-Wing seed vs a 64-byte ML-KEM `d || z`), so a caller holding an
  /// [AtKemAlgorithm] cannot supply a valid seed without knowing the
  /// concrete backend. Backends that support it take an optional seed on
  /// the concrete class.
  FutureOr<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair();

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
abstract class AtKeyAgreementAlgorithm implements AtAlgorithm {
  /// Compute the shared secret from [privateKey] and [peerPublicKey].
  FutureOr<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey);
}
