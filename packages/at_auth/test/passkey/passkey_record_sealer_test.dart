import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_auth/src/passkey/passkey_record.dart'
    show PasskeyRecordCodec;
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/passkey_fakes.dart';

/// Sealed under the @alice kek (`at_auth/custody/kek/v1|@alice`) derived from
/// PRF output 0..31, iv 0..11, document [_atKeys]. Generated once with an
/// independent HKDF and AES-GCM implementation; changing the wire format or
/// the kek label breaks it.
const _goldenAliceRecord =
    '{"v":2,"alg":"A256GCM","kdf":"HKDF-SHA256","typ":"atkeys",'
    '"iv":"AAECAwQFBgcICQoL","ct":"f3rZoUxXXO/L6zydQWw5shl+FShvyys3jiWO87nV9/Ld76zW/yGNcsCxxQsU13TMQ+vh3FlObhquNMt2lCtEo/UDGN5tDs6/jwEWrGHR81Oog/N0Tip3bFpXpqN3KO8YofwHq1CW3fSD0ESC/1h6Wlaeu+U="}';

const _atKeys = {
  'aesPkamPrivateKey': 'pkam-private',
  'aesEncryptPrivateKey': 'enc-private',
  'selfEncryptionKey': 'self',
};

void main() {
  PrfSecret prf() => PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  late RecordSealer alice;
  late RecordSealer bob;

  setUp(() async {
    alice =
        (await const BytesPasskeyKeyDeriver().derive(prf(), '@alice')).sealer;
    bob = (await const BytesPasskeyKeyDeriver().derive(prf(), '@bob')).sealer;
  });

  Map<String, Object?> fields(String record) =>
      jsonDecode(record) as Map<String, Object?>;

  test('round-trips the @keys document through a RecordSealer', () async {
    final record = await PasskeyRecordCodec.seal(
        alice, '@alice', PasskeyRecordType.atkeys, _atKeys);
    expect(
        await PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, record),
        _atKeys);
  });

  test('a record sealed with the atSign-bound AAD opens (wire format v2)',
      () async {
    expect(
        await PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, _goldenAliceRecord),
        _atKeys);
  });

  test('the codec hands the sealer the atSign-bound AAD and a 96-bit iv',
      () async {
    final spy = SpyRecordSealer(alice);
    final record = await PasskeyRecordCodec.seal(
        spy, '@alice', PasskeyRecordType.atkeys, _atKeys);
    final json = fields(record);
    expect(json.keys, unorderedEquals(['v', 'alg', 'kdf', 'typ', 'iv', 'ct']));
    expect(base64Decode(json['iv'] as String), hasLength(12));
    expect(
        utf8.decode(spy.aads.single),
        '{"alg":"A256GCM","atSign":"@alice","iv":"${json['iv']}",'
        '"kdf":"HKDF-SHA256",'
        '"typ":"atkeys","v":2}');
  });

  test('seal then re-seal with the same iv and aad gives the fixture bytes',
      () async {
    final iv = Uint8List.fromList(List.generate(12, (i) => i));
    final aad = utf8.encode('{"alg":"A256GCM","atSign":"@alice",'
        '"iv":"AAECAwQFBgcICQoL","kdf":"HKDF-SHA256","typ":"atkeys","v":2}');
    final ct = await alice.seal(iv, utf8.encode(jsonEncode(_atKeys)), aad);
    expect(base64Encode(ct), fields(_goldenAliceRecord)['ct']);
  });

  test('a flipped ciphertext byte does not open', () async {
    final record = await PasskeyRecordCodec.seal(
        alice, '@alice', PasskeyRecordType.atkeys, _atKeys);
    final bytes = base64Decode(fields(record)['ct'] as String)..[0] ^= 1;
    final tampered = jsonEncode({...fields(record), 'ct': base64Encode(bytes)});
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a flipped iv byte does not open', () async {
    final record = await PasskeyRecordCodec.seal(
        alice, '@alice', PasskeyRecordType.atkeys, _atKeys);
    final iv = base64Decode(fields(record)['iv'] as String)..[0] ^= 1;
    final tampered = jsonEncode({...fields(record), 'iv': base64Encode(iv)});
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a record whose typ was rewritten does not open as the other type',
      () async {
    final record = await PasskeyRecordCodec.seal(
        alice, '@alice', PasskeyRecordType.eid, _atKeys);
    final retyped = jsonEncode({...fields(record), 'typ': 'atkeys'});
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, retyped),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a record of the other type is refused as unsupported', () async {
    final record = await PasskeyRecordCodec.seal(
        alice, '@alice', PasskeyRecordType.eid, _atKeys);
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, record),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
  });

  test('another passkey sealer does not open it', () async {
    expect(
        PasskeyRecordCodec.open(
            bob, '@alice', PasskeyRecordType.atkeys, _goldenAliceRecord),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a malformed record is unsupported, not an authentication failure', () {
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, '{"v":9}'),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
    expect(
        PasskeyRecordCodec.open(
            alice, '@alice', PasskeyRecordType.atkeys, 'nope'),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
  });
}
