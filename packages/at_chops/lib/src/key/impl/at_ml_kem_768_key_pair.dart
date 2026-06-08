import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/at_key_pair.dart';

/// ML-KEM-768 (FIPS 203) key pair used for post-quantum key encapsulation.
///
/// Public keys are 1184 raw bytes; secret keys are 2400 raw bytes (pure-Dart
/// format). Both are encoded as base64 strings to fit the existing
/// [AsymmetricKeyPair] String contract. Only pure-Dart-format secret keys are
/// serializable — the OpenSSL FFI backend returns process-lifetime opaque
/// handles, so persisted ML-KEM secret keys must always be used with the
/// pure-Dart algorithm.
class AtMlKem768KeyPair extends AsymmetricKeyPair {
  AtMlKem768KeyPair.create(super.publicKey, super.privateKey)
      : super.create();

  /// Construct from raw [publicKey] and [secretKey] bytes, base64-encoding
  /// them to fit the [AsymmetricKeyPair] String contract.
  ///
  /// For the pure-Dart backend, [publicKey] is 1184 bytes and [secretKey]
  /// is 2400 bytes. For the OpenSSL FFI backend, [secretKey] is an 8-byte
  /// opaque process-lifetime handle — see the class doc.
  AtMlKem768KeyPair.fromBytes(Uint8List publicKey, Uint8List secretKey)
      : super.create(base64Encode(publicKey), base64Encode(secretKey));
}
