import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart' show InvalidAtSignException;
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';

/// Sealed under the @alice kek (`at_auth/custody/kek/v1|@alice`) derived from
/// the PRF output 0..31, with iv 0..11; generated once with an independent
/// HKDF and AES-GCM implementation.
const _aliceRecord =
    '{"v":2,"alg":"A256GCM","kdf":"HKDF-SHA256","typ":"atkeys",'
    '"iv":"AAECAwQFBgcICQoL","ct":"f3rZoUxXXO/L6zydQWw5shl+FShvyys3jiWO87nV9/Ld76zW/yGNcsCxxQsU13TMQ+vh3FlObhquNMt2lCtEo/UDGN5tDs6/jwEWrGHR81Oog/N0Tip3bFpXpqN3KO8YofwHq34Me7Kx9IvF79PXcqMYs1M="}';

/// `{"selfEncryptionKey":"self"}` sealed with iv 0..11 and the AAD `aad` under
/// the @bob kek (`at_auth/custody/kek/v1|@bob`) derived from the PRF output
/// 0..31 (key 8fb7e99d947dfcc3177666ae510ec31f911e06ec2b04706391c14133ed402bf3).
const _bobSealed =
    'OuBPH3jARbJUY1QXfqI7/iOyZJaxBd03BlkkrMVVS2EpGWIa2hSQ90BIclc=';

void main() {
  const deriver = BytesPasskeyKeyDeriver();
  PrfSecret prf([int shift = 0]) =>
      PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + shift)));
  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  test('the label constants share one versioned scheme', () {
    expect(recordIdLabel, 'at_auth/custody/record-id/v1');
    expect(recordNsLabel, 'at_auth/custody/ns/v1');
    expect(recordSealLabel, 'at_auth/custody/kek/v1');
    expect(recordAuthSeedLabel, 'at_auth/custody/auth-seed/v1');
  });

  test('lookupHex and ns match the golden vectors for @alice and @bob',
      () async {
    final alice = await deriver.derive(prf(), '@alice');
    final bob = await deriver.derive(prf(), '@bob');
    expect(alice.lookupHex,
        '562dd8ceae1d04851c10847fea609250dc0c74d92af520a4ab96565bfea6c4b6');
    expect(alice.ns,
        '10781e72da94f814194f90c4c40d75d7b0b029d06253d40a610b0ad977b2d620');
    expect(bob.lookupHex,
        'ac8dabc6a3f6c618517f650bf7de7f34d1f8bc604c100768d9e3418aaa56b5fb');
    expect(bob.ns,
        '50e50b134d591ebbf53d1ebe9d8cbde9654259659520783786cc298dea3f7e07');
  });

  test('the auth seed matches the golden vector for @alice', () async {
    final alice = await deriver.derive(prf(), '@alice');
    expect(hex(alice.authSeed),
        'b0e85850ef5407a914408bc6ccdc6a32baeb6446127275414199179a2cf79fc6');
  });

  test('the sealer holds the key the kek label derives', () async {
    final alice = await deriver.derive(prf(), '@alice');
    final record = jsonDecode(_aliceRecord) as Map<String, dynamic>;
    final iv = base64Decode(record['iv'] as String);
    final aad = utf8.encode(jsonEncode({
      'alg': 'A256GCM',
      'iv': record['iv'],
      'kdf': 'HKDF-SHA256',
      'typ': 'atkeys',
      'v': 2
    }));
    final plaintext =
        await alice.sealer.open(iv, base64Decode(record['ct'] as String), aad);
    expect(jsonDecode(utf8.decode(plaintext))['selfEncryptionKey'], 'self');
  });

  test('the sealer for @bob does not open an @alice record', () async {
    final bob = await deriver.derive(prf(), '@bob');
    expect(
        PasskeyRecordCodec.open(
            bob.sealer, '@bob', PasskeyRecordType.atkeys, _aliceRecord),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('ns and lookupHex are 64 lowercase hex and differ', () async {
    final d = await deriver.derive(prf(), '@alice');
    expect(d.ns, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(d.lookupHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(d.ns, isNot(d.lookupHex));
    expect(hex(d.authSeed), isNot(d.lookupHex));
    expect(d.authSeed, hasLength(32));
  });

  test('every spelling of the atSign derives the same values', () async {
    final canonical = await deriver.derive(prf(), '@alice');
    for (final variant in ['@Alice', 'alice', 'ALICE', '@ali.ce']) {
      final d = await deriver.derive(prf(), variant);
      expect(d.lookupHex, canonical.lookupHex, reason: variant);
      expect(d.ns, canonical.ns, reason: variant);
      expect(d.authSeed, canonical.authSeed, reason: variant);
    }
  });

  test('values differ across atSigns and across passkeys', () async {
    final alice = await deriver.derive(prf(), '@alice');
    expect((await deriver.derive(prf(), '@alicf')).ns, isNot(alice.ns));
    expect((await deriver.derive(prf(1), '@alice')).ns, isNot(alice.ns));
  });

  test('lookupHex and the auth seed are unrelated across atSigns', () async {
    final alice = await deriver.derive(prf(), '@alice');
    final bob = await deriver.derive(prf(), '@bob');
    expect(bob.lookupHex, isNot(alice.lookupHex));
    expect(bob.authSeed, isNot(alice.authSeed));
  });

  test('the sealer for @bob opens a record sealed under the @bob key only',
      () async {
    final alice = await deriver.derive(prf(), '@alice');
    final bob = await deriver.derive(prf(), '@bob');
    final iv = Uint8List.fromList(List.generate(12, (i) => i));
    final aad = utf8.encode('aad');
    final plaintext = await bob.sealer.open(iv, base64Decode(_bobSealed), aad);
    expect(utf8.decode(plaintext), '{"selfEncryptionKey":"self"}');
    await expectLater(alice.sealer.open(iv, base64Decode(_bobSealed), aad),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('rejects an invalid atSign', () {
    expect(deriver.derive(prf(), '@al ice'),
        throwsA(isA<InvalidAtSignException>()));
  });

  test('zeroes the PRF bytes before returning', () async {
    final secret = prf();
    await deriver.derive(secret, '@alice');
    expect(secret.output, everyElement(0));
  });
}
