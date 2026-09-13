import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/encryption/aes.dart';
import 'package:at_chops/src/algorithm/encryption/aes_ctr_ffi_algo.dart';
import 'package:at_chops/src/algorithm/encryption/aes_ctr_ffi_cipher.dart';
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
  /// Because the algorithm requires a key at construction time this is a
  /// factory method rather than a static field.
  ///
  /// **AAD note:** [SymmetricEncryptionAlgorithm] does not carry an `aad`
  /// parameter on its interface. If you need AAD (e.g. for PQ-HPKE), use
  /// [AesGcm256EncryptionAlgo] or [AesGcm256FfiAlgo] directly — both expose
  /// `encrypt`/`decrypt` with `{List<int> aad}`. Routing PQ-HPKE through
  /// [AtPqc] is deferred until the interface is widened to carry AAD.
  static SymmetricEncryptionAlgorithm<Uint8List, Uint8List> aesGcm256(
          AESKey key) =>
      _aesGcmSupported
          ? AesGcm256FfiAlgo.fromLib(_lib!, key)
          : AesGcm256EncryptionAlgo(key);

  static final bool _aesCtrSupported =
      _lib != null && libCryptoSupportsAesCtr(_lib!);

  /// AES-CTR — FFI when available, else pure-Dart. **Confidentiality only:
  /// CTR is unauthenticated.**
  ///
  /// Both backends PKCS7-pad the plaintext prior to encryption, so they are
  /// wire-interchangeable — an invariant a future edit must not break, since
  /// the two ends of a connection may resolve to different backends.
  ///
  /// That interchangeability holds only for a 16-byte IV. Any other IV makes
  /// the choice of backend observable, and in both directions: the pure-Dart
  /// path substitutes 16 zero bytes for a missing IV and right-pads a shorter
  /// one into the counter block, while the FFI path rejects both — with
  /// [AtEncryptionException] on encrypt, [AtDecryptionException] on decrypt;
  /// the two are siblings, so catching one does not catch the other. Callers
  /// that reach this method with an IV they did not choose — one parsed from
  /// a record, or from an older writer — get a failure that depends on
  /// whether the host has libcrypto. Pass exactly 16 bytes.
  static SymmetricEncryptionAlgorithm<Uint8List, Uint8List> aesCtr(
          AESKey key) =>
      _aesCtrSupported
          ? AesCtrFfiAlgo.fromLib(_lib!, key)
          : AESEncryptionAlgo(key);

  /// An incremental AES-CTR cipher over [key] and [iv], or `null` when this
  /// host has no usable libcrypto.
  ///
  /// Unlike [aesCtr] there is no pure-Dart counterpart to fall back to — the
  /// pure-Dart path has no long-lived-context shape — so the caller keeps its
  /// own fallback and this returns `null` rather than choosing one. Callers
  /// own the returned cipher and **must** `dispose()` it; see
  /// [AesCtrFfiCipher] for the contract.
  ///
  /// Raw keystream, no padding: this is *not* wire-compatible with [aesCtr].
  static AesCtrFfiCipher? aesCtrStreamCipher(
          AESKey key, InitialisationVector iv) =>
      _aesCtrSupported ? AesCtrFfiCipher.fromLib(_lib!, key, iv) : null;
}
