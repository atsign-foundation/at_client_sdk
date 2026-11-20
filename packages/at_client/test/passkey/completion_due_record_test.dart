import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/completion_due_record.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/lookup_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';
const _key = 'completion-due.$_eid.a.__e@alice';

void main() {
  late ScriptedAtLookUp remoteLookUp;
  late CompletionDueRecord record;

  CompletionDueRecord recordOver(ScriptedAtLookUp lookUp) =>
      CompletionDueRecord(
          RemoteSecondary(_atSign, AtClientPreference(),
              atLookUp: lookUp,
              lookUps: RecordingLookUps((_) async => null).call),
          atSign: _atSign,
          enrollmentId: _eid);

  setUp(() {
    remoteLookUp = ScriptedAtLookUp((_) async => 'data:1');
    record = recordOver(remoteLookUp);
  });

  test(
      "the record's commands name completion-due.<eid>.a.__e@<atSign> with "
      'the atSign canonical', () async {
    for (final atSign in ['Alice', '@ali.ce']) {
      final lookUp = ScriptedAtLookUp((_) async => 'data:activated');
      final named = CompletionDueRecord(
          RemoteSecondary(_atSign, AtClientPreference(),
              atLookUp: lookUp,
              lookUps: RecordingLookUps((_) async => null).call),
          atSign: atSign,
          enrollmentId: _eid);
      await named.write(CompletionDue.activated);
      await named.read();
      await named.clear();
      expect(
          lookUp.commands.map((c) => c.command),
          [
            'update:$_key activated\n',
            'llookup:$_key\n',
            'delete:$_key\n',
          ],
          reason: 'the atSign $atSign is canonical: its case is folded and '
              'its dots are removed');
    }
  });

  test(
      'a record over a malformed enrollment id is refused before anything is '
      'sent', () {
    for (final enrollmentId in ['a.b', 'E1d2c3']) {
      expect(
          () => CompletionDueRecord(
              RemoteSecondary(_atSign, AtClientPreference(),
                  atLookUp: remoteLookUp,
                  lookUps: RecordingLookUps((_) async => null).call),
              atSign: _atSign,
              enrollmentId: enrollmentId),
          throwsArgumentError,
          reason: enrollmentId);
    }
    expect(remoteLookUp.commands, isEmpty);
  });

  test('write sends update on the authenticated remote', () async {
    await record.write(CompletionDue.activated);
    await record.write(CompletionDue.cramSecretDeleted);
    expect(remoteLookUp.commands, [
      (command: 'update:$_key activated\n', auth: true),
      (command: 'update:$_key cram-deleted\n', auth: true),
    ]);
  });

  test('read sends llookup on the authenticated remote', () async {
    final stored = ScriptedAtLookUp((_) async => 'data:cram-deleted');
    expect(await recordOver(stored).read(), CompletionDue.cramSecretDeleted);
    expect(stored.commands.single, (command: 'llookup:$_key\n', auth: true));
  });

  for (final value in ['activated', 'due', 'cram-deletedx', 'CRAM-DELETED']) {
    test('read counts "$value" as activated', () async {
      final stored = ScriptedAtLookUp((_) async => 'data:$value');
      expect(await recordOver(stored).read(), CompletionDue.activated);
    });
  }

  test('read counts a value with surrounding whitespace as that value',
      () async {
    for (final value in [
      'cram-deleted\n',
      ' cram-deleted ',
      '\tcram-deleted'
    ]) {
      final stored = ScriptedAtLookUp((_) async => 'data:$value');
      expect(await recordOver(stored).read(), CompletionDue.cramSecretDeleted,
          reason: 'the stored value ${jsonEncode(value)} is cram-deleted');
    }
  });

  test('read is null on key not found', () async {
    final missing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0015', 'key not found'));
    expect(await recordOver(missing).read(), isNull);
  });

  test('read is null on data:null', () async {
    final empty = ScriptedAtLookUp((_) async => 'data:null');
    expect(await recordOver(empty).read(), isNull);
  });

  test('read propagates other errors', () async {
    final refused = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0009', 'unauthorized'));
    await expectLater(
        recordOver(refused).read(), throwsA(isA<UnAuthorizedException>()));
  });

  test('read shows an unexpected response quoted and escaped in its error',
      () async {
    final odd = ScriptedAtLookUp((_) async => 'error:AT0011-a\nb"c');
    await expectLater(
        recordOver(odd).read(),
        throwsA(isA<InvalidResponseException>().having(
            (e) => e.message,
            'message',
            r'unexpected llookup response: "error:AT0011-a\u000ab\"c"')));
  });

  test('read throws a typed error on a response without data', () async {
    final odd = ScriptedAtLookUp((_) async => 'error:AT0011-boom');
    await expectLater(
        recordOver(odd).read(), throwsA(isA<InvalidResponseException>()));
  });

  test('clear sends delete on the authenticated remote', () async {
    await record.clear();
    expect(
        remoteLookUp.commands.single, (command: 'delete:$_key\n', auth: true));
  });

  test('clear counts key not found as deleted', () async {
    final missing = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0015', 'key not found'));
    await recordOver(missing).clear();
    expect(missing.commands.single.command, 'delete:$_key\n');
  });

  test('clear propagates other errors', () async {
    final refused = ScriptedAtLookUp(
        (_) async => throw AtLookUpException('AT0009', 'unauthorized'));
    await expectLater(
        recordOver(refused).clear(), throwsA(isA<UnAuthorizedException>()));
  });
}
