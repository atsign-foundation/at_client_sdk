import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Conveys an enrollment's `apkamSymmetricKey` from the enrollee that mints it
/// to the approver that must re-encrypt the atsign's keys under it.
///
/// Signing conveyance are independent axes: ML-DSA (signature) and X-Wing (KEM) are
/// distinct primitives, and one keypair cannot both authenticate and be
/// encapsulated to — which is why an enrollment carries two keypairs, not one.
/// A post-quantum PKAM key therefore says nothing about how the symmetric key
/// travelled.
sealed class ApkamKeyConveyance {
  /// Wraps [symmetricKey] for the holder of [recipientPublicKey], returning the
  /// base64 wire form the enroll verb carries as `encryptedAPKAMSymmetricKey`.
  FutureOr<ConveyedKey> wrap(AtBytes recipientPublicKey);

  /// Reverses [wrap]: unwraps [wrapped] with [recipientPrivateKey], returning
  /// the bytes that went in.
  FutureOr<Uint8List> unwrap(AtBytes wrapped, AtBytes recipientPrivateKey);
}

typedef ConveyedKey = ({Uint8List cipher, Uint8List sharedSecret});

class XWingKeyConveyance implements ApkamKeyConveyance {
  const XWingKeyConveyance();

  @override
  FutureOr<Uint8List> unwrap(
      AtBytes wrapped, AtBytes recipientPrivateKey) async {
    return await XWingPureDartAlgo.instance.decapsulate(
      recipientPrivateKey.bytes,
      wrapped.bytes,
    );
  }

  @override
  FutureOr<ConveyedKey> wrap(AtBytes recipientPublicKey) async {
    final result =
        await XWingPureDartAlgo.instance.encapsulate(recipientPublicKey.bytes);
    return (cipher: result.ciphertext, sharedSecret: result.sharedSecret);
  }
}

class RsaKeyConveyance implements ApkamKeyConveyance {
  const RsaKeyConveyance();
  @override
  FutureOr<Uint8List> unwrap(AtBytes wrapped, AtBytes recipientPrivateKey) {
    return RsaEncryptionAlgo()
        .decrypt(wrapped.bytes, recipientPrivateKey.bytes);
  }

  @override
  FutureOr<ConveyedKey> wrap(AtBytes recipientPublicKey, {Uint8List? secret}) {
    // The constructor argument is a length in BYTES: AES-256 is 32, not 256.
    final sharedSecret = secret ?? AesCtrEncryptionAlgo(32).generateKey();
    final cipher =
        RsaEncryptionAlgo().encrypt(sharedSecret, recipientPublicKey.bytes);
    return (cipher: cipher, sharedSecret: sharedSecret);
  }
}
