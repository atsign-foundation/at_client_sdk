import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/asn1/rsa_key_codec.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:pointycastle/api.dart'
    show AsymmetricBlockCipher, PrivateKeyParameter, PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

/// RSA asymmetric encryption/decryption.
///
/// Stateless: the public key is passed to [encrypt] and the private key to
/// [decrypt], as raw DER bytes — exactly what `RsaSigningAlgo.generateKeyPair()`
/// returns. If you hold an `AtPublicKey`/`AtPrivateKey` (base64-encoded DER),
/// pass `base64Decode(atPublicKey.publicKey)`.
///
/// The padding is PKCS#1 v1.5, not OAEP: it is what every ciphertext already
/// written by the Atsign Protocol uses.
class RsaEncryptionAlgo implements ASymmetricEncryptionAlgorithm {
  RsaEncryptionAlgo();

  /// Key-size agnostic: the modulus length comes from the key passed per
  /// call, so there is no `rsa2048`/`rsa4096` split here.
  @override
  String get name => EncryptionAlgoType.rsa.name;

  @override
  Uint8List encrypt(Uint8List plainData, Uint8List publicKey) {
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(
          true,
          PublicKeyParameter<RSAPublicKey>(
              RsaKeyCodec.decodePublicKey(publicKey)));
    return _processInBlocks(cipher, plainData);
  }

  @override
  Uint8List decrypt(Uint8List encryptedData, Uint8List privateKey) {
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(
          false,
          PrivateKeyParameter<RSAPrivateKey>(
              RsaKeyCodec.decodePrivateKey(privateKey)));
    return _processInBlocks(cipher, encryptedData);
  }

  /// RSA is a block cipher over a single modulus-wide block, so anything longer
  /// than one block has to be fed through a block at a time.
  static Uint8List _processInBlocks(
      AsymmetricBlockCipher engine, Uint8List input) {
    final blockCount = (input.length / engine.inputBlockSize).ceil();
    final output = Uint8List(blockCount * engine.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;
      outputOffset += engine.processBlock(
          input, inputOffset, chunkSize, output, outputOffset);
      inputOffset += chunkSize;
    }

    return (output.length == outputOffset)
        ? output
        : output.sublist(0, outputOffset);
  }
}
