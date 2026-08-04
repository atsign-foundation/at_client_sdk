import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
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
abstract class AtSignatureAlgorithm {
  /// Const so `extends` subtypes (e.g. a `const`-constructed test double)
  /// can chain a const super call.
  const AtSignatureAlgorithm();

  /// Stable, free-form identifier for this algorithm — a downstream
  /// protocol's wire, record, or keystore identifier for this signature type
  /// (e.g. at_server's FROM/POL handshake tags its cookie and published-key
  /// record with this). Not grammar-constrained: at_chops owns the spelling.
  ///
  /// Implementations that have no reason to diverge should simply return
  /// [signingAlgoType]'s `name` (see [MlDsa65FfiAlgo]). The getter stays
  /// separate from [signingAlgoType] because enum member names are
  /// Dart-identifier-constrained (no hyphens, can't start with a digit) — a
  /// future backend needing a wire spelling the enum can't express can
  /// override this one independently.
  String get name;

  /// The `pkam:`/envelope wire tuple's identifier for this algorithm.
  ///
  /// Typed as [SigningAlgoType] rather than [String] because that verb (and
  /// `at_client`'s signed-envelope `signingAlgo` field) accepts only the
  /// enum's `name` spellings — a free-form string would surface as an
  /// atServer syntax error at authentication time, or fail
  /// `SigningAlgoType.values.byName` on the reading side.
  SigningAlgoType get signingAlgoType;

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
  /// The `pkam:`/envelope wire tuple's `hashingAlgo` identifier for this
  /// algorithm (`envelope['hashingAlgo']` in `at_client`'s signed-envelope
  /// format, `PublicKeyHash.hashingAlgo`) — the same spelling as
  /// [HashingAlgoType.name] for the corresponding enum value (e.g.
  /// `SHA256HashingAlgo().name == HashingAlgoType.sha256.name`), so an
  /// algorithm instance can report the identifier a caller would otherwise
  /// have to track separately.
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
