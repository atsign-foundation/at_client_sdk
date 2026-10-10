import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// The X-Wing KEM: pure Dart on a platform without `dart:ffi`.
AtKemAlgorithm get xWingKem => XWingPureDartAlgo.instance;

/// Which AES-256-GCM implementation [aesGcm256Encrypt] and [aesGcm256Decrypt]
/// use: `dart` here.
@visibleForTesting
String get aesGcm256Backend => 'dart';

/// AES-256-GCM under [key]; returns `ciphertext || tag`.
Future<Uint8List> aesGcm256Encrypt(AESKey key, Uint8List plaintext,
        {required InitialisationVector iv, required List<int> aad}) =>
    AesGcm256EncryptionAlgo(key).encrypt(plaintext, iv: iv, aad: aad);

/// Opens AES-256-GCM `ciphertext || tag` under [key], throwing
/// `AtDecryptionException` when authentication fails.
Future<Uint8List> aesGcm256Decrypt(AESKey key, Uint8List sealed,
        {required InitialisationVector iv, required List<int> aad}) =>
    AesGcm256EncryptionAlgo(key).decrypt(sealed, iv: iv, aad: aad);
