// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keys on purpose.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show withApkamKey;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart';
import 'package:test/test.dart';

import '../support/custody_fakes.dart';

const _atSign = '@alice';
const _eid = 'eid-9';

String _b(String s) => base64Encode(utf8.encode(s));

AtKeys _keys({bool withEnrollment = true}) {
  final flat = AtKeys.legacy(
      encryptionPublicKey: _b('enc-pub'),
      encryptionPrivateKey: _b('enc-priv'),
      selfEncryptionKey: _b('self'))
    ..atsign = Atsign(_atSign);
  return withEnrollment
      ? withApkamKey(flat, _eid,
          (publicKey: _b('apkam-pub'), privateKey: _b('apkam-priv')))
      : flat;
}

void main() {
  late DerivedKeys derived;
  late FakePendingStore store;
  late InMemoryAtKeysIo inner;
  final credential = Uint8List.fromList([1, 2, 3]);

  PendingKeysJournal newJournal() => PendingKeysJournal(
      inner: inner,
      atSign: _atSign,
      credentialId: credential,
      vault: derived.vault,
      store: store);

  Future<Map<String, dynamic>> sealed() async => derived.vault
      .open(PasskeyRecordType.pending, store.records[_atSign]!.sealed);

  setUp(() async {
    derived = await DerivedKeys.derive(
        Uint8List.fromList(List.generate(32, (i) => i + 1)), _atSign);
    store = FakePendingStore();
    inner = InMemoryAtKeysIo();
  });

  tearDown(() => derived.vault.close());

  for (final flush in [false, true]) {
    test('${flush ? 'flush' : 'write'} files the keys and seals a copy',
        () async {
      final keys = _keys();
      final journal = newJournal();

      flush
          ? await journal.flush(Atsign(_atSign), keys)
          : await journal.write(_atSign, keys);

      expect(await inner.read(_atSign), keys);
      final record = store.records[_atSign]!;
      expect(record.credentialId, credential);
      expect(record.enrollmentId, _eid);
      expect(record.encryptionPublicKey, _b('enc-pub'));
      expect((await sealed())['enrollmentId'], _eid);
    });
  }

  test('update files the mutated keys and seals them; a refusal seals nothing',
      () async {
    final journal = newJournal();
    await journal.write(_atSign, _keys());
    final before = store.records[_atSign];

    await journal.update(Atsign(_atSign), (keys) => false);
    expect(store.records[_atSign], same(before));

    await journal.update(Atsign(_atSign), (keys) {
      keys.defaultEncryptionPublicKey = AtBytes.fromString(_b('enc-pub-2'));
      return true;
    });
    expect(store.records[_atSign], isNot(same(before)));
    expect(store.records[_atSign]!.encryptionPublicKey, _b('enc-pub-2'));
    expect((await inner.read(_atSign)).defaultEncryptionPublicKey?.toString(),
        _b('enc-pub-2'));
  });

  test('the sealed copy holds no APKAM private key', () async {
    await newJournal().write(_atSign, _keys());

    final document = jsonEncode(await sealed());
    expect(document, isNot(contains(_b('apkam-priv'))));
    expect(document, contains(_b('enc-priv')));
  });

  test('keys naming no enrollment are filed but not sealed', () async {
    final keys = _keys(withEnrollment: false);

    await newJournal().write(_atSign, keys);

    expect(await inner.read(_atSign), keys);
    expect(store.puts, 0);
  });

  test('a record that cannot be kept fails the write', () async {
    store.failPuts = true;

    await expectLater(newJournal().write(_atSign, _keys()), throwsStateError);
  });

  test('reads come from the inner store', () async {
    final keys = _keys();
    await inner.write(_atSign, keys);

    expect(await newJournal().read(_atSign), keys);
    expect(store.puts, 0);
  });
}
