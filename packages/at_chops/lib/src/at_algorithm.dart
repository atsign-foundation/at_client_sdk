import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/hashing/types.dart';

/// Interface for symmetric encryption algorithms. Key material is passed per
/// call. Check [AesCtrEncryptionAlgo] for sample implementation.
///
/// Encode String data to [Uint8List] with [utf8.encode] before passing it in.
///
/// [iv] is required: every implementation needs one, none of them return a
/// generated one, and reusing a (key, iv) pair is a security bug — so the
/// caller must own it. For data written before IVs were set, pass
/// [InitialisationVector.legacy].
abstract class SymmetricEncryptionAlgorithm {
  String get name;

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
abstract class ASymmetricEncryptionAlgorithm {
  String get name;

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
abstract class AtSignatureAlgorithm {
  /// Stable identifier for this algorithm — a downstream protocol's wire,
  /// record, or keystore identifier for this signature type (e.g. at_server's
  /// FROM/POL handshake tags its cookie and published-key record with this).
  ///
  /// This *is* [SigningAlgoType.name] — the enum's constants are spelled to
  /// be the identifier, so there is no second vocabulary to translate
  /// between. Implementations return `SigningAlgoType.<value>.name`.
  String get name;

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

/// Interface for hashing data. Refer [Md5HashingAlgo] for sample implementation.
abstract class AtHashingAlgorithm<K, V> {
  String get name;

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
  String get name;

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
abstract class AtKeyAgreementAlgorithm {
  /// Compute the shared secret from [privateKey] and [peerPublicKey].
  FutureOr<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey);
}
