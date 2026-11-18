import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/lookup_fakes.dart';

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
    ('an uppercase letter', 'E1d2c3'),
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

  for (final (name, response) in [
    ('an empty response', null),
    ('a response without a data prefix', 'error:AT0011-boom'),
  ]) {
    test('get throws a typed error on $name', () async {
      final odd = ScriptedAtLookUp((_) async => response);
      await expectLater(storeOver(odd).get(_atSign, _eid),
          throwsA(isA<InvalidResponseException>()));
    });
  }

  test('an unexpected response is not echoed whole into the error', () async {
    final odd = ScriptedAtLookUp((_) async => 'x' * 10000);
    await expectLater(
        storeOver(odd).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>()
            .having((e) => e.message.length, 'message length', lessThan(220))));
  });

  test('put sends update on the authenticated remote', () async {
    await store.put(_atSign, _eid, _document);
    expect(remoteLookUp.commands.single,
        (command: 'update:atkeys.$_eid.a.__e@alice $_document\n', auth: true));
  });

  test('put sends the update with no metadata segment', () async {
    await store.put(_atSign, _eid, _document);
    final command = remoteLookUp.commands.single.command;
    expect(command, startsWith('update:atkeys.'));
    expect(
        command,
        isNot(contains(RegExp(r'(ttl|ttb|ttr|ccd|dataSignature|'
            r'isBinary|isEncrypted|sharedKeyEnc|pubKeyCS|encoding|ivNonce)'))));
    expect(command.substring('update:'.length).split(' ').first,
        'atkeys.$_eid.a.__e@alice');
  });

  test('put rejects a document with a carriage return', () {
    expect(store.put(_atSign, _eid, '{\r}'), throwsArgumentError);
    expect(remoteLookUp.commands, isEmpty);
  });

  test('put rejects a document with a newline', () {
    expect(store.put(_atSign, _eid, '{\n}'), throwsArgumentError);
    expect(remoteLookUp.commands, isEmpty);
  });
}
