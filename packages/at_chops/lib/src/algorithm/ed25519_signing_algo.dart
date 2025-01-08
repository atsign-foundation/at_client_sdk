import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:better_cryptography/better_cryptography.dart';

/// Data signing and verification for Ed25519 - elliptic curve algorithm
/// Keypair for the algorithm has to generated using [AtChopsUtil.generateEd25519KeyPair()]
class Ed25519SigningAlgo implements AtSigningAlgorithm {
  final _algorithm = Ed25519();
  SimpleKeyPair? _ed25519KeyPair;

  set edd25519KeyPair(SimpleKeyPair value) {
    _ed25519KeyPair = value;
  }

  Ed25519SigningAlgo();

  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (_ed25519KeyPair == null) {
      throw AtSigningException(
          'edd25519 key pair has to be set for signing operation');
    }
    final signature = await _algorithm.sign(data, keyPair: _ed25519KeyPair!);
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey}) async {
    if (publicKey == null) {
      throw AtSigningException(
          'public key has to be passed for signature verification');
    }
    return await _algorithm.verify(
      signedData,
      signature: Signature(signature,
          publicKey:
              SimplePublicKey(publicKey.codeUnits, type: KeyPairType.ed25519)),
    );
  }
}
