import 'dart:typed_data';

import 'package:at_chops/src/algorithm/ecc_signing_algo.dart';
import 'package:elliptic/elliptic.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for ecc signing and verification', () {
    test(
        'Test ecc signing and verification using generated private key from ecc',
        () {
      final eccAlgo = EccSigningAlgo();
      var ec = getSecp256r1();
      final eccPrivateKey = ec.generatePrivateKey();
      eccAlgo.privateKey = eccPrivateKey;
      final dataToSign = 'Hello World';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signature = eccAlgo.sign(dataInBytes);
      var verifyResult = eccAlgo.verify(dataInBytes, signature);
      expect(verifyResult, true);
    });
    test('Test ecc verification - passing public key', () {
      final eccAlgo = EccSigningAlgo();
      var ec = getSecp256r1();
      final eccPrivateKey = ec.generatePrivateKey();
      eccAlgo.privateKey = eccPrivateKey;
      final publicKey = eccPrivateKey.publicKey;
      final dataToSign = 'Hello World';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signature = eccAlgo.sign(dataInBytes);
      var verifyResult = eccAlgo.verify(dataInBytes, signature,
          publicKey: publicKey.toString());
      expect(verifyResult, true);
    });
    test('Test invalid ecc verification - passing different public key', () {
      final eccAlgo = EccSigningAlgo();
      var ec = getSecp256r1();
      var ec2 = getSecp256r1();
      final eccPrivateKey = ec.generatePrivateKey();
      eccAlgo.privateKey = eccPrivateKey;
      final publicKey = ec2.generatePrivateKey().publicKey;
      final dataToSign = 'Hello World';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signature = eccAlgo.sign(dataInBytes);
      var verifyResult = eccAlgo.verify(dataInBytes, signature,
          publicKey: publicKey.toString());
      expect(verifyResult, false);
    });
    test('Test ecc signing - private key not set', () {
      final eccAlgo = EccSigningAlgo();
      final dataToSign = 'Hello World';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      expect(
          () => eccAlgo.sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtException &&
              e.toString().contains(
                  'elliptic private key has to be set for signing operation'))));
    });
    test('Test ecc verification - private key and public key not available',
        () {
      final eccAlgo = EccSigningAlgo();
      var ec = getSecp256r1();
      final eccPrivateKey = ec.generatePrivateKey();
      eccAlgo.privateKey = eccPrivateKey;
      final dataToSign = 'Hello World';
      final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);
      final signature = eccAlgo.sign(dataInBytes);
      eccAlgo.privateKey = null;
      expect(
          () => eccAlgo.verify(dataInBytes, signature),
          throwsA(predicate((e) =>
              e is AtException &&
              e.toString().contains(
                  'Cannot verify signature - publicKey not provided or privateKey not available'))));
    });
  });
}
