import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';

class _Store implements PendingOnboardingStore {
  final records = <String, PendingOnboardingRecord>{};

  @override
  Future<PendingOnboardingRecord?> get(String atSign) async => records[atSign];

  @override
  Future<void> put(String atSign, PendingOnboardingRecord record) async =>
      records[atSign] = record;

  @override
  Future<void> delete(String atSign) async => records.remove(atSign);
}

void main() {
  final record = PendingOnboardingRecord(
      credentialId: Uint8List.fromList([1, 2, 3]),
      enrollmentId: 'e1',
      encryptionPublicKey: 'pub',
      sealed: '{"v":2}');

  group('PendingOnboardingRecord', () {
    test('round-trips through JSON', () {
      final back = PendingOnboardingRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
      expect(back.credentialId, [1, 2, 3]);
      expect(back.enrollmentId, 'e1');
      expect(back.encryptionPublicKey, 'pub');
      expect(back.sealed, '{"v":2}');
    });

    test('a record without an encryption public key round-trips', () {
      final bare = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([9]),
          enrollmentId: 'e2',
          sealed: 's');
      final back = PendingOnboardingRecord.fromJson(bare.toJson());
      expect(back.encryptionPublicKey, isNull);
    });

    for (final broken in <Map<String, dynamic>>[
      {},
      {'credentialId': 'AQID', 'enrollmentId': 'e1'},
      {'credentialId': 7, 'enrollmentId': 'e1', 'sealed': 's'},
      {'credentialId': '!!', 'enrollmentId': 'e1', 'sealed': 's'},
      {'credentialId': 'AQID', 'enrollmentId': 'e1', 'sealed': 4},
    ]) {
      test('rejects $broken', () {
        expect(() => PendingOnboardingRecord.fromJson(broken),
            throwsA(isA<UnsupportedPasskeyRecordException>()));
      });
    }

    test('names the atSign and nothing secret in toString', () {
      expect(record.toString(), isNot(contains('pub')));
      expect(record.toString(), isNot(contains('{"v":2}')));
    });
  });

  test('a pending record is sealed under its own type', () async {
    final sealer = (await const BytesPasskeyKeyDeriver().derive(
            PrfSecret(Uint8List.fromList(List.generate(32, (i) => i))),
            '@alice'))
        .sealer;
    final sealed = await PasskeyRecordCodec.seal(
        sealer, '@alice', PasskeyRecordType.pending, {'enrollmentId': 'e1'});
    expect(jsonDecode(sealed)['typ'], 'pending');
    expect(
        await PasskeyRecordCodec.open(
            sealer, '@alice', PasskeyRecordType.pending, sealed),
        {'enrollmentId': 'e1'});
    expect(
        PasskeyRecordCodec.open(
            sealer, '@alice', PasskeyRecordType.atkeys, sealed),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
  });

  test('a store is get, put and delete by atSign', () async {
    final PendingOnboardingStore store = _Store();
    expect(await store.get('@a'), isNull);
    await store.put('@a', record);
    expect(await store.get('@a'), same(record));
    await store.delete('@a');
    expect(await store.get('@a'), isNull);
  });
}
