import 'dart:ffi';

import 'dart:typed_data';

import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/encryption/aes_ctr.dart';
import 'package:at_chops/src/encryption/aes_ctr_ffi_algo.dart';
import 'package:at_chops/src/encryption/aes_ctr_ffi_cipher.dart';
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

  static final bool _aesCtrSupported =
      _lib != null && libCryptoSupportsAesCtr(_lib!);

  /// AES-CTR for a [keyLengthBytes]-byte key (16, 24 or 32) — FFI when
  /// available, else pure-Dart. **Confidentiality only: CTR is
  /// unauthenticated.**
  ///
  /// The key length is fixed here rather than read off the key because it
  /// selects the cipher, and on the FFI path that choice is made before any
  /// key crosses the boundary.
  ///
  /// Both backends PKCS7-pad the plaintext prior to encryption, so they are
  /// wire-interchangeable — an invariant a future edit must not break, since
  /// the two ends of a connection may resolve to different backends.
  ///
  /// The IV must be exactly 16 bytes, and both backends reject any other
  /// length — with [AtEncryptionException] on encrypt and
  /// [AtDecryptionException] on decrypt; the two are siblings, so catching one
  /// does not catch the other. 3.x rejected a short IV only on the FFI path,
  /// which made a caller holding an IV it did not choose — one parsed from a
  /// record, or from an older writer — fail or not depending on whether the
  /// host had libcrypto.
  static SymmetricEncryptionAlgorithm aesCtr(int keyLengthBytes) =>
      _aesCtrSupported
          ? AesCtrFfiAlgo.fromLib(_lib!, keyLengthBytes)
          : AesCtrEncryptionAlgo(keyLengthBytes);

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
          Uint8List key, InitialisationVector iv) =>
      _aesCtrSupported ? AesCtrFfiCipher.fromLib(_lib!, key, iv) : null;
}
