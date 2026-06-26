import 'dart:ffi';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_ffi.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_pure_dart.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_loader.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_ffi.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_pure_dart.dart';

/// Auto-resolves FFI vs pure-Dart PQ backends; libcrypto probed once on first access.
abstract final class PqcFfi {
  static final DynamicLibrary? _lib = tryLoadLibCrypto();

  /// X-Wing hybrid KEM — FFI when available, else [XWingPureDartAlgo].
  static final AtKemAlgorithm xWing =
      (_lib != null && libCryptoSupportsMlKem768(_lib!))
          ? XWingFfiAlgo.fromLib(_lib!)
          : XWingPureDartAlgo.instance;

  /// ML-DSA-65 signing — FFI when available, else pure-Dart. Do not downcast.
  static final AtSigningAlgorithm mlDsa65 =
      (_lib != null && libCryptoSupportsMlDsa65(_lib!))
          ? MlDsa65FfiAlgo.fromLib(_lib!)
          : MlDsa65PureDartAlgo();
}
