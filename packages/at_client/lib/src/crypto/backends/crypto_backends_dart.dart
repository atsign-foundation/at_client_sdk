import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

/// The X-Wing KEM: pure Dart on a platform without `dart:ffi`.
AtKemAlgorithm get xWingKem => XWingPureDartAlgo.instance;

/// AES-256-GCM under [key]; returns `ciphertext || tag`.
Future<Uint8List> aesGcm256Encrypt(AESKey key, Uint8List plaintext,
        {required InitialisationVector iv, required List<int> aad}) =>
    AesGcm256EncryptionAlgo(key).encrypt(plaintext, iv: iv, aad: aad);

/// Opens AES-256-GCM `ciphertext || tag` under [key], throwing
/// `AtDecryptionException` when authentication fails.
Future<Uint8List> aesGcm256Decrypt(AESKey key, Uint8List sealed,
        {required InitialisationVector iv, required List<int> aad}) =>
    AesGcm256EncryptionAlgo(key).decrypt(sealed, iv: iv, aad: aad);
