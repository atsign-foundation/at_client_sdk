import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/ed25519_signing_algo.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for ed25519 signing and verification', () {
    test('Test data signing and verification using generated keypair',
        () async {
      final ed25519KeyPair = await AtChopsUtil.generateEd25519KeyPair();
      final dataToSign = 'Hello World@123!';
      final signingAlgo = Ed25519SigningAlgo();
      signingAlgo.edd25519KeyPair = ed25519KeyPair;
      final signature =
          await signingAlgo.sign(Uint8List.fromList(dataToSign.codeUnits));
      final publicKeyBytes = (await ed25519KeyPair.extractPublicKey()).bytes;
      print(publicKeyBytes.length);
      final verifyResult = await signingAlgo.verify(
          Uint8List.fromList(dataToSign.codeUnits), signature,
          publicKey: String.fromCharCodes(publicKeyBytes));
      expect(verifyResult, true);
    });
    test('Test data signing and verification - pass incorrect public key',
        () async {
      final ed25519KeyPair = await AtChopsUtil.generateEd25519KeyPair();
      final dataToSign = 'Hello World@123!';
      final signingAlgo = Ed25519SigningAlgo();
      signingAlgo.edd25519KeyPair = ed25519KeyPair;
      final signature =
          await signingAlgo.sign(Uint8List.fromList(dataToSign.codeUnits));
      final publicKeyBytes = (await ed25519KeyPair.extractPublicKey()).bytes;
      print(publicKeyBytes.length);
      const characters =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final random = Random();
      final wrongPublicKey = String.fromCharCodes(
        Iterable.generate(
          32,
          (_) => characters.codeUnitAt(random.nextInt(characters.length)),
        ),
      );
      final verifyResult = await signingAlgo.verify(
          Uint8List.fromList(dataToSign.codeUnits), signature,
          publicKey: wrongPublicKey);
      expect(verifyResult, false);
    });
  });
}
