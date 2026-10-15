import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'lookup_fakes.dart';

const _atSign = '@alice';
final _hex = 'ab' * 32;
final _root = AtRootDomain('root.example', 64);
const _record =
    '{"v":2,"alg":"A256GCM","kdf":"HKDF-SHA256","iv":"AAEC","ct":"c2Vj"}';

void main() {
  group('passkeyRecordKey', () {
    test('is _<lookupHex>.atkeysv@<atSign> with the atSign canonical', () {
      expect(passkeyRecordKey('Alice', _hex), '_$_hex.atkeysv@alice');
    });

    for (final (name, hex) in [
      ('uppercase hex', 'AB' * 32),
      ('63 characters', 'a' * 63),
      ('65 characters', 'a' * 65),
      ('a non-hex character', '${'a' * 63}g'),
      ('a dot', '${'a' * 63}.'),
    ]) {
      test('rejects a lookupHex with $name', () {
        expect(() => passkeyRecordKey(_atSign, hex), throwsArgumentError);
      });
    }
  });

  group('LookupPasskeyRecordReader', () {
    PasskeyRecordReader reader(RecordingLookUps lookUps) =>
        LookupPasskeyRecordReader(lookUps: lookUps.call, rootDomain: _root);

    test('get sends an unauthenticated lookup and closes', () async {
      final lookUps = RecordingLookUps((_) async => 'data:$_record');

      expect(await reader(lookUps).get(_atSign, _hex), _record);
      expect(lookUps.roots.single, _root);
      final lookUp = lookUps.opened.single;
      expect(lookUp.authenticator, isNull);
      expect(lookUp.commands.single,
          (command: 'lookup:_$_hex.atkeysv@alice\n', auth: false));
      expect(lookUp.closed, isTrue);
    });

    test('get is null on AT0015', () async {
      final lookUps = RecordingLookUps(
          (_) async => throw AtLookUpException('AT0015', 'key not found'));
      expect(await reader(lookUps).get(_atSign, _hex), isNull);
      expect(lookUps.opened.single.closed, isTrue);
    });

    test('get is null on the data:null an expired record reads as', () async {
      final lookUps = RecordingLookUps((_) async => 'data:null');
      expect(await reader(lookUps).get(_atSign, _hex), isNull);
    });

    test('get propagates other errors and still closes', () async {
      final lookUps = RecordingLookUps(
          (_) async => throw AtLookUpException('AT0014', 'timed out'));
      await expectLater(reader(lookUps).get(_atSign, _hex),
          throwsA(isA<AtLookUpException>()));
      expect(lookUps.opened.single.closed, isTrue);
    });
  });

  group('RemotePasskeyRecordStore', () {
    late ScriptedAtLookUp remoteLookUp;
    late RecordingLookUps readerLookUps;
    late RemotePasskeyRecordStore store;

    setUp(() {
      remoteLookUp = ScriptedAtLookUp((_) async => 'data:1');
      readerLookUps = RecordingLookUps((_) async => 'data:$_record');
      store = RemotePasskeyRecordStore(
          LookupPasskeyRecordReader(
              lookUps: readerLookUps.call, rootDomain: _root),
          RemoteSecondary(_atSign, AtClientPreference(),
              atLookUp: remoteLookUp));
    });

    test('put sends update:ttl in milliseconds on the authenticated remote',
        () async {
      await store.put(_atSign, _hex, _record, ttl: const Duration(days: 90));
      expect(remoteLookUp.commands.single, (
        command: 'update:ttl:7776000000:public:_$_hex.atkeysv@alice $_record\n',
        auth: true
      ));
      expect(readerLookUps.opened, isEmpty);
      expect(remoteLookUp.closed, isFalse);
    });

    test('put rejects a record with a newline', () {
      expect(store.put(_atSign, _hex, '{\n}', ttl: const Duration(days: 1)),
          throwsArgumentError);
      expect(remoteLookUp.commands, isEmpty);
    });

    test('put rejects a non-positive ttl', () {
      expect(store.put(_atSign, _hex, _record, ttl: Duration.zero),
          throwsArgumentError);
    });

    test('delete sends delete:public on the authenticated remote', () async {
      await store.delete(_atSign, _hex);
      expect(remoteLookUp.commands.single,
          (command: 'delete:public:_$_hex.atkeysv@alice\n', auth: true));
    });

    test('get reads through the reader', () async {
      expect(await store.get(_atSign, _hex), _record);
      expect(remoteLookUp.commands, isEmpty);
    });
  });
}
