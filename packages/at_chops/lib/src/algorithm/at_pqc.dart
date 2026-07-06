import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/aes_gcm.dart';
import 'package:at_chops/src/algorithm/encryption/aes_gcm_ffi_algo.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_ffi.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_pure_dart.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_loader.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_ffi.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_pure_dart.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';

/// Auto-resolves FFI vs pure-Dart PQ backends; libcrypto probed once on first access.
abstract final class AtPqc {
  static final DynamicLibrary? _lib = tryLoadLibCrypto();
  static final bool _aesGcmSupported =
      _lib != null && libCryptoSupportsAesGcm(_lib!);

  /// X-Wing hybrid KEM — FFI when available, else [XWingPureDartAlgo].
  static final AtKemAlgorithm xWing =
      (_lib != null && libCryptoSupportsMlKem768(_lib!))
          ? XWingFfiAlgo.fromLib(_lib!)
          : XWingPureDartAlgo.instance;

  /// ML-DSA-65 signing — FFI when available, else pure-Dart.
  ///
  /// Typed as [AtSignatureAlgorithm]: `message` is positional; key material
  /// is passed via required named parameters.
  /// Do not downcast to the concrete type — it is an implementation detail.
  static final AtSignatureAlgorithm mlDsa65 =
      (_lib != null && libCryptoSupportsMlDsa65(_lib!))
          ? MlDsa65FfiAlgo.fromLib(_lib!)
          : MlDsa65PureDartAlgo();

  /// AES-256-GCM authenticated encryption — FFI when available, else pure-Dart.
  ///
  /// AES-256-GCM is the AEAD layer in the PQ-HPKE construction, so it is
  /// treated as a PQ-adjacent primitive and resolved through [AtPqc] like the
  /// other backends.  Because the algorithm requires a key at construction time
  /// this is a factory method rather than a static field.
  ///
  /// Do not downcast to the concrete type — it is an implementation detail.
  static SymmetricEncryptionAlgorithm<Uint8List, Uint8List> aesGcm256(
          AESKey key) =>
      _aesGcmSupported
          ? AesGcm256FfiAlgo.fromLib(_lib!, key)
          : AesGcm256EncryptionAlgo(key);
}
