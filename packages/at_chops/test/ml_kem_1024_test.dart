/// ML-KEM-1024 (FIPS 203) against the IETF HPKE working group's published
/// vector for KEM `0x0042`.
///
/// This is the no-hybrid option, and the point of it is that its citation
/// chain contains no draft: FIPS 203 for the KEM itself. The vector below is
/// third-party — the working group's, mirrored by Go's standard library — so
/// conformance here is attested by somebody other than us, unlike the
/// self-generated `pq_seal_v1.json` rows.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(
          File('test/vectors/hpke_wg_0x0042_mlkem1024.json').readAsStringSync())
      as Map;

  const algo = MlKem1024PureDartAlgo.instance;

  test('FIPS 203 Table 3 sizes', () {
    expect(_hex(v['pkRm'] as String),
        hasLength(MlKem1024PureDartAlgo.publicKeyLength));
    expect(_hex(v['enc'] as String),
        hasLength(MlKem1024PureDartAlgo.ciphertextLength));
    expect(_hex(v['shared_secret'] as String),
        hasLength(MlKem1024PureDartAlgo.sharedSecretLength));
    expect(
        _hex(v['skRm'] as String), hasLength(MlKem1024PureDartAlgo.seedLength),
        reason: 'HPKE persists the 64-byte d||z seed, not the expanded key');
  });

  test('the published seed derives the published encapsulation key', () async {
    final kp = await algo.generateKeyPair(_hex(v['skRm'] as String));
    expect(_toHex(kp.publicKey), v['pkRm']);
  });

  test('decapsulation reproduces the published shared secret', () async {
    final ss = await algo.decapsulate(
        (await algo.generateKeyPair(_hex(v['skRm'] as String))).secretKey,
        _hex(v['enc'] as String));
    expect(_toHex(ss), v['shared_secret']);
  });

  test('derandomised encapsulation reproduces the published ciphertext',
      () async {
    // ikmE is 32 bytes here (FIPS 203 `m`) rather than the hybrid's 64, so
    // this also pins which randomness the pure KEM consumes.
    final r = await algo.encapsulate(
        _hex(v['pkRm'] as String), _hex(v['ikmE'] as String));
    expect(_toHex(r.ciphertext), v['enc']);
    expect(_toHex(r.sharedSecret), v['shared_secret']);
  });

  test('a tampered ciphertext decapsulates to a different secret, not an error',
      () async {
    // FIPS 203 rejects implicitly: a corrupted ciphertext yields a well-formed
    // but unrelated shared secret. Anything that raises here would be a
    // decryption oracle.
    final kp = await algo.generateKeyPair();
    final enc = await algo.encapsulate(kp.publicKey);
    final tampered = Uint8List.fromList(enc.ciphertext)..[0] ^= 0x01;
    final ss = await algo.decapsulate(kp.secretKey, tampered);
    expect(ss, hasLength(32));
    expect(ss, isNot(equals(enc.sharedSecret)));
  });
}
