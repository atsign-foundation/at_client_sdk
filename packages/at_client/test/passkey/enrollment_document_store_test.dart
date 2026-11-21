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

  test('get names an unexpected response by its length in its error', () async {
    final odd = ScriptedAtLookUp((_) async => 'error:AT0011-a\nb"c');
    await expectLater(
        storeOver(odd).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>().having((e) => e.message,
            'message', 'unexpected llookup response of 18 characters')));
  });

  test('get tells a missing reply apart from an empty one', () async {
    await expectLater(
        storeOver(ScriptedAtLookUp((_) async => null)).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>()
            .having((e) => e.message, 'message', 'no llookup response')));
    await expectLater(
        storeOver(ScriptedAtLookUp((_) async => '')).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>().having((e) => e.message,
            'message', 'unexpected llookup response of 0 characters')));
  });

  test('an unexpected response is not echoed whole into the error', () async {
    final odd = ScriptedAtLookUp((_) async => 'x' * 10000);
    await expectLater(
        storeOver(odd).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>()
            .having((e) => e.message.length, 'message length', lessThan(220))));
  });

  test('a reply without a data prefix is not quoted, as it may be the document',
      () async {
    const sealed = '{"v":2,"iv":"SEALEDIVTEXT","ct":"SEALEDCTTEXT"}';
    final odd = ScriptedAtLookUp((_) async => sealed);
    await expectLater(
        storeOver(odd).get(_atSign, _eid),
        throwsA(isA<InvalidResponseException>()
            .having((e) => e.message, 'message',
                contains('${sealed.length} characters'))
            .having((e) => e.message, 'message', isNot(contains('SEALED')))));
  });

  test('put sends update on the authenticated remote', () async {
    await store.put(_atSign, _eid, _document);
    expect(remoteLookUp.commands.single,
        (command: 'update:atkeys.$_eid.a.__e@alice $_document\n', auth: true));
  });

  test('enrollmentLockKey is atkeys-lock.<eid>.a.__e@<atSign> canonical', () {
    expect(enrollmentLockKey(_eid, 'Alice'), 'atkeys-lock.$_eid.a.__e@alice');
    expect(() => enrollmentLockKey('E1d2c3', _atSign), throwsArgumentError);
  });

  test('tryLock leases the lock record it creates, for the ttl', () async {
    // Not the 10s a store uses by default, so a tryLock that ignored its ttl
    // would be seen.
    const ttl = Duration(seconds: 3);
    final lookUp = ScriptedAtLookUp((_) async => 'data:-1');
    final lease = await storeOver(lookUp).tryLock(_atSign, _eid, ttl: ttl);
    expect('${lease!.key}', 'atkeys-lock.$_eid.a.__e@alice');
    expect(lookUp.commands.single.command,
        startsWith('update:nc:ttl:${ttl.inMilliseconds}:'),
        reason: 'the lock record is created for the ttl asked for');
    expect(lease.isSpent, isFalse);
    expect(lease.remaining, lessThanOrEqualTo(ttl),
        reason: 'the lease is no longer than the lock record');
    expect(lease.remaining, greaterThan(ttl - const Duration(seconds: 1)),
        reason: 'the lease is as long as the lock record');
  });

  test('tryLock is null while the lock record exists', () async {
    final held = ScriptedAtLookUp((_) async => throw AtLookUpException(
        'AT0032', 'Immutable records may not be updated'));
    expect(
        await storeOver(held)
            .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
        isNull);
  });

  test('tryLock is null when the atServer replies that the lock exists',
      () async {
    final held = ScriptedAtLookUp(
        (_) async => 'error:AT0032-Immutable records may not be updated');
    expect(
        await storeOver(held)
            .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
        isNull);
  });

  for (final (name, reply, error) in [
    ('an error reply', 'error:AT0015-not found', isA<KeyNotFoundException>()),
    ('an empty reply', '', isA<AtException>()),
  ]) {
    test('tryLock grants no lease on $name', () async {
      await expectLater(
          storeOver(ScriptedAtLookUp((_) async => reply))
              .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
          throwsA(error));
    });
  }

  test('tryLock propagates other errors', () async {
    final failing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0014', 'timed out'));
    await expectLater(
        storeOver(failing)
            .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
        throwsA(isA<AtException>()));
  });

  test(
      'put rejects a document with a newline, naming the field and none of '
      'its text', () async {
    await expectLater(
        store.put(_atSign, _eid, '{"iv":"SEALEDIV",\n"ct":"SEALEDCT"}'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'document')
            .having((e) => e.invalidValue, 'invalidValue', isNull)
            .having((e) => '$e', 'text', isNot(contains('SEALED')))));
    expect(remoteLookUp.commands, isEmpty);
  });

  test('put rejects a document with a carriage return', () async {
    await expectLater(
        store.put(_atSign, _eid, 'abc\rdef'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'document')
            .having((e) => e.invalidValue, 'invalidValue', isNull)
            .having((e) => '$e', 'text', isNot(contains('abc')))));
    expect(remoteLookUp.commands, isEmpty);
  });
}
