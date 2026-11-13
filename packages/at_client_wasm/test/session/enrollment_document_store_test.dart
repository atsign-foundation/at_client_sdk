import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client_wasm/src/session/enrollment_document_store.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'lookup_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';
const _document =
    '{"v":2,"alg":"A256GCM","kdf":"HKDF-SHA256","typ":"atkeys","iv":"AAEC","ct":"c2Vj"}';

void main() {
  late ScriptedAtLookUp remoteLookUp;
  late RemoteEnrollmentDocumentStore store;

  RemoteEnrollmentDocumentStore storeOver(ScriptedAtLookUp lookUp) =>
      RemoteEnrollmentDocumentStore(RemoteSecondary(
          _atSign, AtClientPreference(),
          atLookUp: lookUp, lookUps: RecordingLookUps((_) async => null).call));

  setUp(() {
    remoteLookUp = ScriptedAtLookUp((_) async => 'data:$_document');
    store = storeOver(remoteLookUp);
  });

  test('enrollmentDocumentKey is atkeys.<eid>.a.__e@<atSign> canonical', () {
    expect(enrollmentDocumentKey(_eid, 'Alice'), 'atkeys.$_eid.a.__e@alice');
  });

  for (final (name, eid) in [
    ('an empty id', ''),
    ('a dot', 'a.b'),
    ('a space', 'a b'),
    ('an at sign', '@a'),
  ]) {
    test('enrollmentDocumentKey rejects an enrollmentId with $name', () {
      expect(() => enrollmentDocumentKey(eid, _atSign), throwsArgumentError);
    });
  }

  test('get sends llookup on the authenticated remote', () async {
    expect(await store.get(_atSign, _eid), _document);
    expect(remoteLookUp.commands.single,
        (command: 'llookup:atkeys.$_eid.a.__e@alice\n', auth: true));
  });

  test('get is null on key not found', () async {
    final missing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0015', 'key not found'));
    expect(await storeOver(missing).get(_atSign, _eid), isNull);
  });

  test('get is null on data:null', () async {
    final empty = ScriptedAtLookUp((_) async => 'data:null');
    expect(await storeOver(empty).get(_atSign, _eid), isNull);
  });

  test('get propagates other errors', () {
    final failing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0014', 'timed out'));
    expect(storeOver(failing).get(_atSign, _eid), throwsA(isA<AtException>()));
  });

  test('put sends update on the authenticated remote', () async {
    await store.put(_atSign, _eid, _document);
    expect(remoteLookUp.commands.single,
        (command: 'update:atkeys.$_eid.a.__e@alice $_document\n', auth: true));
  });

  test('put rejects a document with a newline', () {
    expect(store.put(_atSign, _eid, '{\n}'), throwsArgumentError);
    expect(remoteLookUp.commands, isEmpty);
  });

  test('delete sends delete on the authenticated remote', () async {
    await store.delete(_atSign, _eid);
    expect(remoteLookUp.commands.single,
        (command: 'delete:atkeys.$_eid.a.__e@alice\n', auth: true));
  });
}
