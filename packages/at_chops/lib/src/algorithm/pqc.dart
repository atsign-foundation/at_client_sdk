import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_ffi.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_pure_dart.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_loader.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_ffi.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_pure_dart.dart';

// ── Adapter layer ─────────────────────────────────────────────────────────────
//
// [AtSignatureAlgorithm] mandates canonical param order (message first, then key
// material). Two constraints prevent the ML-DSA-65 algo classes from implementing
// it directly without breaking existing call sites:
//
//   1. MlDsa65PureDartAlgo.signBytes / verifyBytes are *static*. Dart static
//      methods cannot satisfy an interface, so a wrapper instance is needed.
//
//   2. MlDsa65FfiAlgo.signBytes(secretKey, message) / verifyBytes(publicKey,
//      message, signature) use non-canonical param order for backward compat.
//      Reordering them is a silent break (both params are Uint8List).
//
// MlDsa65PureDartSigner and MlDsa65FfiSigner absorb both mismatches so every
// AtSignatureAlgorithm caller sees uniform canonical order regardless of backend.
//
// Callers should always use [PqcFfi.mlDsa65] (typed [AtSignatureAlgorithm]) rather
// than constructing these adapters directly — the concrete type is an impl detail.

/// [AtSignatureAlgorithm] adapter over [MlDsa65PureDartAlgo]'s static methods.
final class MlDsa65PureDartSigner implements AtSignatureAlgorithm {
  const MlDsa65PureDartSigner();

  @override
  Future<Uint8List> signBytes(Uint8List message, Uint8List secretKey) =>
      MlDsa65PureDartAlgo.signBytes(message, secretKey);

  @override
  Future<bool> verifyBytes(
          Uint8List message, Uint8List signature, Uint8List publicKey) =>
      MlDsa65PureDartAlgo.verifyBytes(message, signature, publicKey);
}

/// [AtSignatureAlgorithm] adapter over [MlDsa65FfiAlgo] that presents canonical
/// `(message, secretKey)` / `(message, signature, publicKey)` param order.
///
/// [MlDsa65FfiAlgo.signBytes] and [MlDsa65FfiAlgo.verifyBytes] use non-canonical
/// order for backward compatibility; this adapter maps to canonical order internally.
final class MlDsa65FfiSigner implements AtSignatureAlgorithm {
  final MlDsa65FfiAlgo _algo;

  const MlDsa65FfiSigner(this._algo);

  @override
  Future<Uint8List> signBytes(Uint8List message, Uint8List secretKey) =>
      _algo.signBytes(secretKey, message); // map canonical→FFI order

  @override
  Future<bool> verifyBytes(
          Uint8List message, Uint8List signature, Uint8List publicKey) =>
      _algo.verifyBytes(publicKey, message, signature); // map canonical→FFI order
}

// ── PqcFfi resolver ───────────────────────────────────────────────────────────

/// Auto-resolves FFI vs pure-Dart PQ backends; libcrypto probed once on first access.
abstract final class PqcFfi {
  static final DynamicLibrary? _lib = tryLoadLibCrypto();

  /// X-Wing hybrid KEM — FFI when available, else [XWingPureDartAlgo].
  static final AtKemAlgorithm xWing =
      (_lib != null && libCryptoSupportsMlKem768(_lib!))
          ? XWingFfiAlgo.fromLib(_lib!)
          : XWingPureDartAlgo.instance;

  /// ML-DSA-65 signing — FFI when available, else pure-Dart.
  ///
  /// Typed as [AtSignatureAlgorithm]: pass `message` first, then key material.
  /// Do not downcast to the concrete type — it is an implementation detail.
  static final AtSignatureAlgorithm mlDsa65 =
      (_lib != null && libCryptoSupportsMlDsa65(_lib!))
              ? MlDsa65FfiSigner(MlDsa65FfiAlgo.fromLib(_lib!))
          : const MlDsa65PureDartSigner();
}
