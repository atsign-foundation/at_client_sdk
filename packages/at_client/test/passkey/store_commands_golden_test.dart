import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/completion_due_record.dart';
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_pointer_store.dart';
import 'package:at_client/src/passkey/public_lookup.dart';
import 'package:test/test.dart';

import '../support/lookup_fakes.dart';

const _atSign = '@alice';
const _eid = 'e1d2c3';
final _hex = 'ab' * 32;
final _ns = 'cd' * 32;
const _doc = '{"v":2,"typ":"atkeys","iv":"AAEC","ct":"c2Vj"}';
const _record = '{"v":2,"eid":"e1d2c3"}';

void main() {
  late ScriptedAtLookUp remote;

  RemoteSecondary secondary() => RemoteSecondary(_atSign, AtClientPreference(),
      atLookUp: remote, lookUps: RecordingLookUps((_) async => null).call);

  setUp(() => remote = ScriptedAtLookUp((_) async => 'data:1'));

  group('document store commands', () {
    test('get', () async {
      await RemoteEnrollmentDocumentStore(secondary()).get(_atSign, _eid);
      expect(remote.commands.single,
          (command: 'llookup:atkeys.e1d2c3.a.__e@alice\n', auth: true));
    });

    test('put', () async {
      await RemoteEnrollmentDocumentStore(secondary()).put(_atSign, _eid, _doc);
      expect(remote.commands.single, (
        command:
            'update:atkeys.e1d2c3.a.__e@alice {"v":2,"typ":"atkeys","iv":"AAEC","ct":"c2Vj"}\n',
        auth: true
      ));
    });

    test('lock', () async {
      await RemoteEnrollmentDocumentStore(secondary())
          .tryLock(_atSign, _eid, ttl: const Duration(seconds: 10));
      final sent = remote.commands.single;
      expect(sent.auth, isTrue);
      expect(
          sent.command,
          matches(RegExp(
              r'^update:nc:ttl:10000:isEncrypted:false:immutable:true:'
              r'atkeys-lock\.e1d2c3\.a\.__e@alice e1d2c3:[0-9a-f]{32}\n$')));
    });
  });

  group('completion-due record commands', () {
    CompletionDueRecord record() =>
        CompletionDueRecord(secondary(), atSign: _atSign, enrollmentId: _eid);

    test('write activated', () async {
      await record().write(CompletionDue.activated);
      expect(remote.commands.single, (
        command: 'update:completion-due.e1d2c3.a.__e@alice activated\n',
        auth: true
      ));
    });

    test('write cram-deleted', () async {
      await record().write(CompletionDue.cramSecretDeleted);
      expect(remote.commands.single, (
        command: 'update:completion-due.e1d2c3.a.__e@alice cram-deleted\n',
        auth: true
      ));
    });

    test('read', () async {
      await record().read();
      expect(remote.commands.single,
          (command: 'llookup:completion-due.e1d2c3.a.__e@alice\n', auth: true));
    });

    test('clear', () async {
      await record().clear();
      expect(remote.commands.single,
          (command: 'delete:completion-due.e1d2c3.a.__e@alice\n', auth: true));
    });
  });

  group('pointer store commands', () {
    final reader = LookupEnrollmentPointerReader(
        lookUps: RecordingLookUps((_) async => 'data:null').call,
        rootDomain: AtRootDomain.atsignDomain);

    test('put', () async {
      await RemoteEnrollmentPointerStore(reader, secondary())
          .put(_atSign, _hex, _record, ns: _ns);
      expect(remote.commands.single, (
        command:
            'update:public:_${'ab' * 32}.${'cd' * 32}@alice {"v":2,"eid":"e1d2c3"}\n',
        auth: true
      ));
    });
  });

  group('public lookup command', () {
    test('lookup is unauthenticated', () async {
      final lookUps = RecordingLookUps((_) async => 'data:x');
      await publicLookup(
          lookUps: lookUps.call,
          rootDomain: AtRootDomain.atsignDomain,
          atSign: _atSign,
          key: 'k',
          namespace: 'ns');
      expect(lookUps.opened.single.commands.single,
          (command: 'lookup:k.ns@alice\n', auth: false));
    });

    test('an unexpected reply throws InvalidResponseException', () async {
      final lookUps = RecordingLookUps((_) async => 'error:oops');
      await expectLater(
          publicLookup(
              lookUps: lookUps.call,
              rootDomain: AtRootDomain.atsignDomain,
              atSign: _atSign,
              key: 'k'),
          throwsA(isA<InvalidResponseException>()));
    });

    test('a missing reply is told apart from a reply of null', () async {
      Future<String?> lookUpWith(String? reply) => publicLookup(
          lookUps: RecordingLookUps((_) async => reply).call,
          rootDomain: AtRootDomain.atsignDomain,
          atSign: _atSign,
          key: 'k');
      await expectLater(
          lookUpWith(null),
          throwsA(isA<InvalidResponseException>()
              .having((e) => e.message, 'message', 'no lookup response')));
      await expectLater(
          lookUpWith('null'),
          throwsA(isA<InvalidResponseException>().having((e) => e.message,
              'message', 'unexpected lookup response: "null"')));
    });

    test('an unexpected reply is shown quoted and escaped in the message',
        () async {
      final lookUps = RecordingLookUps((_) async => 'error:a\nb"c');
      await expectLater(
          publicLookup(
              lookUps: lookUps.call,
              rootDomain: AtRootDomain.atsignDomain,
              atSign: _atSign,
              key: 'k'),
          throwsA(isA<InvalidResponseException>().having((e) => e.message,
              'message', r'unexpected lookup response: "error:a\u000ab\"c"')));
    });

    test('a long unexpected reply is shortened in the message', () async {
      final lookUps = RecordingLookUps((_) async => 'error:${'x' * 1000}');
      await expectLater(
          publicLookup(
              lookUps: lookUps.call,
              rootDomain: AtRootDomain.atsignDomain,
              atSign: _atSign,
              key: 'k'),
          throwsA(isA<InvalidResponseException>().having(
              (e) => e.message.length, 'message length', lessThan(400))));
    });

    test('the pointer reader sends lookup of the pointer key', () async {
      final lookUps = RecordingLookUps((_) async => 'data:x');
      await LookupEnrollmentPointerReader(
              lookUps: lookUps.call, rootDomain: AtRootDomain.atsignDomain)
          .get(_atSign, _hex, ns: _ns);
      expect(lookUps.opened.single.commands.single,
          (command: 'lookup:_${'ab' * 32}.${'cd' * 32}@alice\n', auth: false));
    });
  });
}
