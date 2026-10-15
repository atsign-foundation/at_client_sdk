import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

void main() {
  final prf = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  late Uint8List aliceKek;
  late Uint8List bobKek;
  const atKeys = {
    'aesPkamPrivateKey': 'pkam-private',
    'aesEncryptPrivateKey': 'enc-private',
    'selfEncryptionKey': 'self',
  };

  setUpAll(() async {
    aliceKek = (await RecordKeys.derive(prf, '@alice')).kek;
    bobKek = (await RecordKeys.derive(prf, '@bob')).kek;
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
    final record = await PasskeyRecordCodec.seal(aliceKek, atKeys);
    expect(await PasskeyRecordCodec.open(aliceKek, record), atKeys);
  });

  test('writes exactly v, alg, kdf, iv and ct with a 96-bit iv', () async {
    final json = fields(await PasskeyRecordCodec.seal(aliceKek, atKeys));
    expect(json.keys, unorderedEquals(['v', 'alg', 'kdf', 'iv', 'ct']));
    expect(json['v'], 2);
    expect(json['alg'], 'A256GCM');
    expect(json['kdf'], 'HKDF-SHA256');
    expect(base64Decode(json['iv'] as String), hasLength(12));
  });

  test('draws a fresh iv on every write', () async {
    final first = fields(await PasskeyRecordCodec.seal(aliceKek, atKeys));
    final second = fields(await PasskeyRecordCodec.seal(aliceKek, atKeys));
    expect(first['iv'], isNot(second['iv']));
    expect(first['ct'], isNot(second['ct']));
  });

  test('a tampered ct fails authentication', () async {
    final record = await PasskeyRecordCodec.seal(aliceKek, atKeys);
    final tampered =
        withField(record, 'ct', flipFirstByte(fields(record)['ct'] as String));
    expect(PasskeyRecordCodec.open(aliceKek, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('a tampered iv fails authentication', () async {
    final record = await PasskeyRecordCodec.seal(aliceKek, atKeys);
    final tampered =
        withField(record, 'iv', flipFirstByte(fields(record)['iv'] as String));
    expect(PasskeyRecordCodec.open(aliceKek, tampered),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('ct sealed without the header as AAD fails authentication', () async {
    final record = fields(await PasskeyRecordCodec.seal(aliceKek, atKeys));
    final box = await AesGcm.with256bits().encrypt(
        utf8.encode(jsonEncode(atKeys)),
        secretKey: SecretKey(aliceKek),
        nonce: base64Decode(record['iv'] as String));
    final unbound = jsonEncode({
      ...record,
      'ct': base64Encode([...box.cipherText, ...box.mac.bytes]),
    });
    expect(PasskeyRecordCodec.open(aliceKek, unbound),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  test('another atSign\'s kek cannot open the record', () async {
    final record = await PasskeyRecordCodec.seal(aliceKek, atKeys);
    expect(PasskeyRecordCodec.open(bobKek, record),
        throwsA(isA<PasskeyRecordAuthenticationException>()));
  });

  group('rejects as unsupported', () {
    late String record;
    setUp(() async => record = await PasskeyRecordCodec.seal(aliceKek, atKeys));

    final cases = <String, String Function(String)>{
      'an unknown v': (r) => withField(r, 'v', 3),
      'the v1 envelope version': (r) => withField(r, 'v', 1),
      'an unknown alg': (r) => withField(r, 'alg', 'A128GCM'),
      'an unknown kdf': (r) => withField(r, 'kdf', 'PBKDF2'),
      'an extra field': (r) => withField(r, 'atSign', '@alice'),
      'a missing field': (r) => jsonEncode({...fields(r)}..remove('iv')),
      'a non-base64 ct': (r) => withField(r, 'ct', '!!'),
      'a JSON array': (_) => '[]',
      'a non-JSON value': (_) => 'not json',
      'the null an expired record reads as': (_) => 'null',
    };
    for (final MapEntry(key: name, value: mutate) in cases.entries) {
      test(name, () {
        expect(PasskeyRecordCodec.open(aliceKek, mutate(record)),
            throwsA(isA<UnsupportedPasskeyRecordException>()));
      });
    }
  });

  test('requires a 32-byte kek', () {
    expect(PasskeyRecordCodec.seal(Uint8List(16), atKeys),
        throwsA(isA<ArgumentError>()));
  });
}
