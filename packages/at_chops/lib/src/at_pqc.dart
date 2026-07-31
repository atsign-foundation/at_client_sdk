import 'dart:ffi';

import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/encryption/aes_gcm.dart';
import 'package:at_chops/src/encryption/aes_gcm_ffi_algo.dart';
import 'package:at_chops/src/encryption/x_wing_ffi.dart';
import 'package:at_chops/src/encryption/x_wing_pure_dart.dart';
import 'package:at_chops/src/ffi/openssl_loader.dart';
import 'package:at_chops/src/signing/ml_dsa_65_ffi.dart';
import 'package:at_chops/src/signing/ml_dsa_65_pure_dart.dart';

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
  /// **AAD note:** [SymmetricEncryptionAlgorithm] does not carry an `aad`
  /// parameter on its interface. If you need AAD (e.g. for PQ-HPKE), use
  /// [AesGcm256EncryptionAlgo] or [AesGcm256FfiAlgo] directly — both expose
  /// `encrypt`/`decrypt` with `{List<int> aad}`. Routing PQ-HPKE through
  /// [AtPqc] is deferred until the interface is widened to carry AAD.
  static final SymmetricEncryptionAlgorithm aesGcm256 = _aesGcmSupported
      ? AesGcm256FfiAlgo.fromLib(_lib!)
      : AesGcm256EncryptionAlgo();
}
