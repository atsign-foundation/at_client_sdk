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

  test('enrollmentLockKey is atkeys-lock.<eid>.a.__e@<atSign> canonical', () {
    expect(enrollmentLockKey(_eid, 'Alice'), 'atkeys-lock.$_eid.a.__e@alice');
    expect(() => enrollmentLockKey('E1d2c3', _atSign), throwsArgumentError);
  });

  test('tryLock leases the lock record it creates, for the ttl', () async {
    final lease = await storeOver(ScriptedAtLookUp((_) async => 'data:-1'))
        .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10));
    expect('${lease!.key}', 'atkeys-lock.$_eid.a.__e@alice');
    expect(lease.isSpent, isFalse);
    expect(lease.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test('tryLock is null while the lock record exists', () async {
    final held = ScriptedAtLookUp((_) async => throw AtLookUpException(
        'AT0032', 'Immutable records may not be updated'));
    expect(
        await storeOver(held)
            .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
        isNull);
  });

  test('tryLock propagates other errors', () async {
    final failing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0014', 'timed out'));
    await expectLater(
        storeOver(failing)
            .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10)),
        throwsA(isA<AtException>()));
  });

  test('put rejects a document with a newline', () {
    expect(store.put(_atSign, _eid, '{\n}'), throwsArgumentError);
    expect(remoteLookUp.commands, isEmpty);
  });

  group('the completion-due record', () {
    test('completionDueKey is completion-due.<eid>.a.__e@<atSign> canonical',
        () {
      expect(
          completionDueKey(_eid, 'Alice'), 'completion-due.$_eid.a.__e@alice');
      expect(() => completionDueKey('E1d2c3', _atSign), throwsArgumentError);
    });

    test('markCompletionDue sends update on the authenticated remote',
        () async {
      await store.markCompletionDue(_atSign, _eid);
      expect(remoteLookUp.commands.single, (
        command: 'update:completion-due.$_eid.a.__e@alice due\n',
        auth: true
      ));
    });

    test('isCompletionDue sends llookup on the authenticated remote', () async {
      final due = ScriptedAtLookUp((_) async => 'data:due');
      expect(await storeOver(due).isCompletionDue(_atSign, _eid), isTrue);
      expect(due.commands.single,
          (command: 'llookup:completion-due.$_eid.a.__e@alice\n', auth: true));
    });

    test('isCompletionDue is false on key not found', () async {
      final missing = ScriptedAtLookUp(
          (_) async => throw AtLookUpException('AT0015', 'key not found'));
      expect(await storeOver(missing).isCompletionDue(_atSign, _eid), isFalse);
    });

    test('isCompletionDue is false on data:null', () async {
      final empty = ScriptedAtLookUp((_) async => 'data:null');
      expect(await storeOver(empty).isCompletionDue(_atSign, _eid), isFalse);
    });

    test('isCompletionDue propagates other errors', () async {
      final refused = ScriptedAtLookUp(
          (_) async => throw AtLookUpException('AT0009', 'unauthorized'));
      await expectLater(storeOver(refused).isCompletionDue(_atSign, _eid),
          throwsA(isA<UnAuthorizedException>()));
    });

    test('isCompletionDue throws a typed error on a response without data',
        () async {
      final odd = ScriptedAtLookUp((_) async => 'error:AT0011-boom');
      await expectLater(storeOver(odd).isCompletionDue(_atSign, _eid),
          throwsA(isA<InvalidResponseException>()));
    });

    test('clearCompletionDue sends delete on the authenticated remote',
        () async {
      await store.clearCompletionDue(_atSign, _eid);
      expect(remoteLookUp.commands.single,
          (command: 'delete:completion-due.$_eid.a.__e@alice\n', auth: true));
    });

    test('clearCompletionDue counts key not found as deleted', () async {
      final missing = ScriptedAtLookUp(
          (_) async => throw AtLookUpException('AT0015', 'key not found'));
      await storeOver(missing).clearCompletionDue(_atSign, _eid);
      expect(missing.commands.single.command,
          'delete:completion-due.$_eid.a.__e@alice\n');
    });

    test('clearCompletionDue propagates other errors', () async {
      final refused = ScriptedAtLookUp(
          (_) async => throw AtLookUpException('AT0009', 'unauthorized'));
      await expectLater(storeOver(refused).clearCompletionDue(_atSign, _eid),
          throwsA(isA<UnAuthorizedException>()));
    });

    test('a malformed enrollment id is refused before anything is sent',
        () async {
      await expectLater(
          store.markCompletionDue(_atSign, 'a.b'), throwsArgumentError);
      await expectLater(
          store.isCompletionDue(_atSign, 'a.b'), throwsArgumentError);
      await expectLater(
          store.clearCompletionDue(_atSign, 'a.b'), throwsArgumentError);
      expect(remoteLookUp.commands, isEmpty);
    });
  });
}
