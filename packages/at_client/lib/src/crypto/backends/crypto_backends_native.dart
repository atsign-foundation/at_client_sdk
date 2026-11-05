import 'dart:ffi' show DynamicLibrary;
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:meta/meta.dart' show visibleForTesting;

final DynamicLibrary? _libCrypto = tryLoadLibCrypto();

final bool _opensslAesGcm =
    _libCrypto != null && libCryptoSupportsAesGcm(_libCrypto!);

/// The X-Wing KEM: OpenSSL when the loaded libcrypto supports ML-KEM-768, pure
/// Dart otherwise, as at_chops selects it.
AtKemAlgorithm get xWingKem => AtPqc.xWing;

/// Builds the OpenSSL AES-256-GCM algorithm [aesGcm256Encrypt] and
/// [aesGcm256Decrypt] use when the loaded libcrypto supports it; a test
/// replaces it to see the call.
@visibleForTesting
AesGcm256FfiAlgo Function(DynamicLibrary libCrypto, AESKey key)
    opensslAesGcm256 = AesGcm256FfiAlgo.fromLib;

/// AES-256-GCM under [key]; returns `ciphertext || tag`.
Future<Uint8List> aesGcm256Encrypt(AESKey key, Uint8List plaintext,
        {required InitialisationVector iv, required List<int> aad}) =>
    _opensslAesGcm
        ? opensslAesGcm256(_libCrypto!, key)
            .encrypt(plaintext, iv: iv, aad: aad)
        : AesGcm256EncryptionAlgo(key).encrypt(plaintext, iv: iv, aad: aad);

/// Opens AES-256-GCM `ciphertext || tag` under [key], throwing
/// `AtDecryptionException` when authentication fails.
Future<Uint8List> aesGcm256Decrypt(AESKey key, Uint8List sealed,
        {required InitialisationVector iv, required List<int> aad}) =>
    _opensslAesGcm
        ? opensslAesGcm256(_libCrypto!, key).decrypt(sealed, iv: iv, aad: aad)
        : AesGcm256EncryptionAlgo(key).decrypt(sealed, iv: iv, aad: aad);
