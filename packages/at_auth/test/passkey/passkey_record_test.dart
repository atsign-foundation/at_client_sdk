import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';

void main() {
  final prf = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  late RecordSealer aliceSealer;
  late RecordSealer bobSealer;
  const atKeys = {
    'aesPkamPrivateKey': 'pkam-private',
    'aesEncryptPrivateKey': 'enc-private',
    'selfEncryptionKey': 'self',
  };

  setUpAll(() async {
    aliceSealer =
        (await const BytesPasskeyKeyDeriver().derive(prf, '@alice')).sealer;
    bobSealer = (await const BytesPasskeyKeyDeriver().derive(
            PrfSecret(Uint8List.fromList(List.generate(32, (i) => i))), '@bob'))
        .sealer;
  });

  Map<String, Object?> fields(String record) =>
      jsonDecode(record) as Map<String, Object?>;

  String withField(String record, String key, Object? value) =>
      jsonEncode({...fields(record), key: value});

  String flipFirstByte(String b64) {
    final bytes = base64Decode(b64);
    bytes[0] ^= 1;
    return base64Encode(bytes);
  }

  test('round-trips the @keys document', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    expect(
        await PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.atkeys, record),
        atKeys);
  });

  test('a record sealed for @alice does not open as @bob under one sealer',
      () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    await expectLater(
        PasskeyRecordCodec.open(
            aliceSealer, '@bob', PasskeyRecordType.atkeys, record),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a record sealed as one type does not open as another', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    final relabelled = withField(record, 'typ', 'eid');
    await expectLater(
        PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.eid, relabelled),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('writes exactly v, alg, kdf, typ, iv and ct with a 96-bit iv', () async {
    final json = fields(await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys));
    expect(json.keys, unorderedEquals(['v', 'alg', 'kdf', 'typ', 'iv', 'ct']));
    expect(json['typ'], 'atkeys');
    expect(json['v'], 2);
    expect(json['alg'], 'A256GCM');
    expect(json['kdf'], 'HKDF-SHA256');
    expect(base64Decode(json['iv'] as String), hasLength(12));
  });

  test('draws a fresh iv on every write', () async {
    final first = fields(await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys));
    final second = fields(await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys));
    expect(first['iv'], isNot(second['iv']));
    expect(first['ct'], isNot(second['ct']));
  });

  test('a tampered ct fails authentication', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    final tampered =
        withField(record, 'ct', flipFirstByte(fields(record)['ct'] as String));
    expect(
        PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.atkeys, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a tampered iv fails authentication', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    final tampered =
        withField(record, 'iv', flipFirstByte(fields(record)['iv'] as String));
    expect(
        PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.atkeys, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('ct sealed without the header as AAD fails authentication', () async {
    final record = fields(await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys));
    final ct = await aliceSealer.seal(base64Decode(record['iv'] as String),
        utf8.encode(jsonEncode(atKeys)), const []);
    final unbound = jsonEncode({...record, 'ct': base64Encode(ct)});
    expect(
        PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.atkeys, unbound),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('writes the pointer type as eid', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.eid, {'enrollmentId': 'e1'});
    expect(fields(record)['typ'], 'eid');
    expect(
        await PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.eid, record),
        {'enrollmentId': 'e1'});
  });

  test('a record opened as the other type is unsupported', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.eid, {'enrollmentId': 'e1'});
    expect(
        PasskeyRecordCodec.open(
            aliceSealer, '@alice', PasskeyRecordType.atkeys, record),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
  });

  test('a rewritten typ fails authentication', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.eid, {'enrollmentId': 'e1'});
    expect(
        PasskeyRecordCodec.open(aliceSealer, '@alice', PasskeyRecordType.atkeys,
            withField(record, 'typ', 'atkeys')),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('another atSign\'s sealer cannot open the record', () async {
    final record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys);
    expect(
        PasskeyRecordCodec.open(
            bobSealer, '@alice', PasskeyRecordType.atkeys, record),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  group('rejects as unsupported', () {
    late String record;
    setUp(() async => record = await PasskeyRecordCodec.seal(
        aliceSealer, '@alice', PasskeyRecordType.atkeys, atKeys));

    final cases = <String, String Function(String)>{
      'an unknown v': (r) => withField(r, 'v', 3),
      'the v1 envelope version': (r) => withField(r, 'v', 1),
      'an unknown alg': (r) => withField(r, 'alg', 'A128GCM'),
      'an unknown kdf': (r) => withField(r, 'kdf', 'PBKDF2'),
      'an unknown typ': (r) => withField(r, 'typ', 'other'),
      'a missing typ': (r) => jsonEncode({...fields(r)}..remove('typ')),
      'an extra field': (r) => withField(r, 'atSign', '@alice'),
      'a missing field': (r) => jsonEncode({...fields(r)}..remove('iv')),
      'a non-base64 ct': (r) => withField(r, 'ct', '!!'),
      'a JSON array': (_) => '[]',
      'a non-JSON value': (_) => 'not json',
      'the null an expired record reads as': (_) => 'null',
    };
    test('a long non-base64 field is not echoed whole into the message', () {
      final bad = withField(record, 'ct', '!' * 10000);
      expect(
          PasskeyRecordCodec.open(
              aliceSealer, '@alice', PasskeyRecordType.atkeys, bad),
          throwsA(isA<UnsupportedPasskeyRecordException>().having(
              (e) => e.message.length, 'message length', lessThan(220))));
    });

    for (final field in ['iv', 'ct']) {
      test('a non-base64 $field is named, its text not quoted', () {
        final text = '${'A' * 40}!${'B' * 40}';
        expect(
            PasskeyRecordCodec.open(aliceSealer, '@alice',
                PasskeyRecordType.atkeys, withField(record, field, text)),
            throwsA(isA<UnsupportedPasskeyRecordException>()
                .having((e) => e.message, 'message', contains(field))
                .having((e) => e.message, 'message', isNot(contains('AAAA')))
                .having((e) => e.message, 'message', isNot(contains('BBBB')))));
      });
    }

    for (final MapEntry(key: name, value: mutate) in cases.entries) {
      test(name, () {
        expect(
            PasskeyRecordCodec.open(aliceSealer, '@alice',
                PasskeyRecordType.atkeys, mutate(record)),
            throwsA(isA<UnsupportedPasskeyRecordException>()));
      });
    }
  });
}
