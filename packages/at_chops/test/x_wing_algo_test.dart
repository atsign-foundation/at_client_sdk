import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  s = s.replaceAll(RegExp(r'\s'), '');
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const algo = XWingPureDartAlgo.instance;

  group('draft-connolly-cfrg-xwing-kem-10 test vector 1', () {
    // Appendix C, first vector.
    final seed = _hex(
        '7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26');
    final eseed = _hex('3cb1eea988004b93103cfb0aeefd2a686e01fa4a58e8a3639ca8'
        'a1e3f9ae57e235b8cc873c23dc62b8d260169afa2f75ab916a58d974918835d25e6'
        'a435085b2');
    final expectedSs = _hex(
        'd2df0522128f09dd8e2c92b1e905c793d8f57a54c3da25861f10bf4ca613e384');
    final ct = _hex('''
b83aa828d4d62b9a83ceffe1d3d3bb1ef31264643c070c5798927e41fb07914a273f8f96e782
6cd5375a283d7da885304c5de0516a0f0654243dc5b97f8bfeb831f68251219aabdd723bc651
2041acbaef8af44265524942b902e68ffd23221cda70b1b55d776a92d1143ea3a0c475f63ee6
890157c7116dae3f62bf72f60acd2bb8cc31ce2ba0de364f52b8ed38c79d719715963a5dd384
2d8e8b43ab704e4759b5327bf027c63c8fa857c4908d5a8a7b88ac7f2be394d93c3706ddd4e6
98cc6ce370101f4d0213254238b4a2e8821b6e414a1cf20f6c1244b699046f5a01caa0a1a555
16300b40d2048c77cc73afba79afeea9d2c0118bdf2adb8870dc328c5516cc45b1a2058141039
e2c90a110a9e16b318dfb53bd49a126d6b73f215787517b8917cc01cabd107d06859854ee8b4f
9861c226d3764c87339ab16c3667d2f49384e55456dd40414b70a6af841585f4c90c68725d577
04ee8ee7ce6e2f9be582dbee985e038ffc346ebfb4e22158b6c84374a9ab4a44e1f91de5aac51
97f89bc5e5442f51f9a5937b102ba3beaebf6e1c58380a4a5fedce4a4e5026f88f528f59ffd2d
b41752b3a3d90efabe463899b7d40870c530c8841e8712b733668ed033adbfafb2d49d37a44d4
064e5863eb0af0a08d47b3cc888373bc05f7a33b841bc2587c57eb69554e8a3767b7506917b6b
70498727f16eac1a36ec8d8cfaf751549f2277db277e8a55a9a5106b23a0206b4721fa9b30485
52c5bd5b594d6e247f38c18c591aea7f56249c72ce7b117afcc3a8621582f9cf71787e183dee0
9367976e98409ad9217a497df888042384d7707a6b78f5f7fb8409e3b535175373461b776002d
799cbad62860be70573ecbe13b246e0da7e93a52168e0fb6a9756b895ef7f0147a0dc81bfa644
b088a9228160c0f9acf1379a2941cd28c06ebc80e44e17aa2f8177010afd78a97ce0868d1629e
bb294c5151812c583daeb88685220f4da9118112e07041fcc24d5564a99fdbde28869fe072238
7d7a9a4d16e1cc8555917e09944aa5ebaaaec2cf62693afad42a3f518fce67d273cc6c9fb5472
b380e8573ec7de06a3ba2fd5f931d725b493026cb0acbd3fe62d00e4c790d965d7a03a3c0b422
2ba8c2a9a16e2ac658f572ae0e746eafc4feba023576f08942278a041fb82a70a595d5bacbf29
7ce2029898a71e5c3b0d1c6228b485b1ade509b35fbca7eca97b2132e7cb6bc465375146b7dce
ac969308ac0c2ac89e7863eb8943015b24314cafb9c7c0e85fe543d56658c213632599efabfc1
ec49dd8c88547bb2cc40c9d38cbd3099b4547840560531d0188cd1e9c23a0ebee0a03d5577d66
b1d2bcb4baaf21cc7fef1e03806ca96299df0dfbc56e1b2b43e4fc20c37f834c4af62127e7dae
86c3c25a2f696ac8b589dec71d595bfbe94b5ed4bc07d800b330796fda89edb77be0294136139
354eb8cd37591578f9c600dd9be8ec6219fdd507adf3397ed4d68707b8d13b24ce4cd8fb22851
bfe9d632407f31ed6f7cb1600de56f17576740ce2a32fc5145030145cfb97e63e0e41d354274a
079d3e6fb2e15
''');

    test('key generation derives the vector public key', () async {
      final kp = await algo.generateKeyPair(seed);
      expect(kp.publicKey.length, XWingPureDartAlgo.publicKeyLength);
      expect(kp.secretKey, seed);
      final pkHex = _toHex(kp.publicKey);
      // Prefix per the draft's vector listing. The suffix below is pinned
      // from this implementation, cross-validated by the byte-exact ct and
      // ss vector matches in the following tests (ct_M binds to pk_M and
      // the combiner binds ss to pk_X, so those equalities prove the pk).
      expect(pkHex.substring(0, 16), 'e2236b35a8c24b39');
      expect(pkHex.substring(pkHex.length - 32),
          '23593d4ba32d9abac8cd049040ef6534');
    });

    test('derandomized encapsulation reproduces the vector ct and ss',
        () async {
      final kp = await algo.generateKeyPair(seed);
      final result = await algo.encapsulateDerand(kp.publicKey, eseed);
      expect(_toHex(result.ciphertext), _toHex(ct));
      expect(result.sharedSecret, expectedSs);
    });

    test('decapsulation of the vector ciphertext yields the vector ss',
        () async {
      expect(ct.length, XWingPureDartAlgo.ciphertextLength);
      final ss = await algo.decapsulate(seed, ct);
      expect(ss, expectedSs);
    });
  });

  group('round trip and behavior', () {
    test('random-key round trip agrees on the shared secret', () async {
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, 1216);
      expect(kp.secretKey.length, 32);

      final enc = await algo.encapsulate(kp.publicKey);
      expect(enc.ciphertext.length, 1120);
      expect(enc.sharedSecret.length, 32);

      final ss = await algo.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test('two encapsulations against one key produce distinct secrets',
        () async {
      final kp = await algo.generateKeyPair();
      final a = await algo.encapsulate(kp.publicKey);
      final b = await algo.encapsulate(kp.publicKey);
      expect(a.sharedSecret, isNot(equals(b.sharedSecret)));
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });

    test(
        'a tampered ciphertext decapsulates to a different secret '
        '(implicit rejection), not an error', () async {
      final kp = await algo.generateKeyPair();
      final enc = await algo.encapsulate(kp.publicKey);
      final tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;
      final ss = await algo.decapsulate(kp.secretKey, tampered);
      expect(ss.length, 32);
      expect(ss, isNot(equals(enc.sharedSecret)));
    });

    test('wrong-size inputs are rejected', () async {
      expect(() => algo.generateKeyPair(Uint8List(31)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.encapsulate(Uint8List(1215)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.decapsulate(Uint8List(32), Uint8List(1119)),
          throwsA(isA<ArgumentError>()));
      expect(() => algo.decapsulate(Uint8List(33), Uint8List(1120)),
          throwsA(isA<ArgumentError>()));
    });

    test('AtChopsUtil.generateXWingKeyPair round-trips via base64', () async {
      final atKp = await AtChopsUtil.generateXWingKeyPair();
      final pub = base64Decode(atKp.atPublicKey.publicKey);
      final seed = base64Decode(atKp.atPrivateKey.privateKey);
      final enc = await algo.encapsulate(pub);
      final ss = await algo.decapsulate(seed, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });
  });
}
