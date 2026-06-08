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
}
