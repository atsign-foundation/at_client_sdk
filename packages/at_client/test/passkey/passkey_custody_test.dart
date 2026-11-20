import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys, AtKeysFileOverwriteException;
import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart'
    show
        AtEnrollmentException,
        AtRootDomain,
        InvalidAtSignException,
        UnAuthenticatedException;
import 'package:at_client/at_client.dart'
    show AtClientPreference, buildAtClient;
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/completion_due_record.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_commons/atsign.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../support/lookup_fakes.dart';
import '../test_utils/recorded_logs.dart';
import '../test_utils/mocks.dart' show MockAtLookupImpl;
import '../test_utils/transport.dart' show defaultAtDirectory;

const _atSign = '@alice';
const _lockPrefix = 'test:setup';
final _enrolledAt = DateTime.utc(2026, 11, 6, 14, 5);

AtLookupMuxable _idleLookUps({
  required String atSign,
  required AtRootDomain rootDomain,
  required AtAuthenticator? authenticator,
  SecondaryAddressFinder? secondaryAddressFinder,
}) {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((_) async => 'data:null');
  return lookUp;
}

/// An authenticator whose report of an unknown credential never settles, as
/// a browser promise that never resolves.
class _UnsettledSignalAuthenticator extends FakeAuthenticator {
  final _settles = Completer<void>();

  @override
  Future<void> signalUnknownCredential(Uint8List credentialId) {
    signalled.add(credentialId);
    return _settles.future;
  }
}

void main() {
  final logs = RecordedLogs();
  setUpAll(logs.installOn);
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late FakePersistence persistence;
  late FakeSetupLock setupLock;
  late List<AtServerAtKeysIo> stores;

  /// That every key store the custody built, from store [from] on, has been
  /// closed, its APKAM private key zeroed.
  void expectStoresClosed({int from = 0}) {
    final built = stores.skip(from);
    expect(built, isNotEmpty);
    expect(built.map((store) => store.holdsPrivateKey), everyElement(isFalse),
        reason: 'a failure closes every key store it built');
  }

  PasskeyCustody custody({LegacyHints? withHints}) => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      deriver: const BytesPasskeyKeyDeriver(),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      persistence: persistence,
      now: () => _enrolledAt,
      retryDelay: Duration.zero,
      setupLock: setupLock,
      setupLockPrefix: _lockPrefix,
      onKeyStore: stores.add);

  Future<DerivedKeys> keysOf(int credential) async {
    final prf = Uint8List.fromList(List.generate(32, (i) => i + credential));
    return DerivedKeys.derive(prf, _atSign);
  }

  /// The steps that complete an activation, from step [from] of the
  /// timeline on: each CRAM secret deletion, revoke request, revoked
  /// enrollment and publish, in the order they happened.
  List<String> completionSteps({int from = 0}) => [
        for (final step in server.timeline.skip(from))
          if (step == 'cram-deleted' ||
              step == 'revoke-others' ||
              step.startsWith('revoke:') ||
              step.startsWith('publish:'))
            step
      ];

  /// [completionSteps] with each write and delete of a completion-due record
  /// in its place.
  List<String> completionAndRecordSteps({int from = 0}) => [
        for (final step in server.timeline.skip(from))
          if (step == 'cram-deleted' ||
              step == 'revoke-others' ||
              step.startsWith('revoke:') ||
              step.startsWith('publish:') ||
              step.startsWith('record-completion-due:') ||
              step.startsWith('clear-completion-due:'))
            step
      ];

  /// The fake key pair another activation tool activates with.
  const otherToolsPair = (publicKey: 'b3RoZXItcHVi', privateKey: 'b3RoZXI=');

  void reset() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    persistence = FakePersistence(server.timeline);
    setupLock = FakeSetupLock();
    stores = [];
  }

  setUp(reset);

  group('a PKAM failure that is not a refusal', () {
    test('AT0011 on a login with hints keeps them and is not retried',
        () async {
      final error =
          UnAuthenticatedException('AT0011-Internal server exception');
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final steps = server.timeline.length;
      gateway
        ..authenticateFailures = 1
        ..authenticateError = error;

      await expectLater(custody().open(atSign: _atSign), throwsA(same(error)));

      expect(gateway.authenticated, ['eid1'],
          reason: 'no retry without the hints');
      expect(hints.ids, {_atSign: 'eid1'});
      expect(completionSteps(from: steps), isEmpty);
    });

    test('AT0011 through the pointer is thrown, not a lost passkey', () async {
      final error =
          UnAuthenticatedException('AT0011-Internal server exception');
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final steps = server.timeline.length;
      final fresh = FakeHints();
      gateway
        ..authenticateFailures = 1
        ..authenticateError = error;

      await expectLater(custody(withHints: fresh).open(atSign: _atSign),
          throwsA(same(error)));

      expect(gateway.authenticated, ['eid1']);
      expect(fresh.ids, isEmpty);
      expect(completionSteps(from: steps), isEmpty);
    });
  });

  group('an atSign not in canonical form', () {
    for (final bad in ['alice', 'left@right', '@left@right', '@@alice']) {
      test('"$bad" is refused by onboard and open before any work', () async {
        final c = custody();
        await expectLater(c.onboard(atSign: bad, cram: 'cram'),
            throwsA(isA<InvalidAtSignException>()));
        await expectLater(
            c.open(atSign: bad), throwsA(isA<InvalidAtSignException>()));
        expect(authenticator.creates + authenticator.gets, 0);
        expect(setupLock.names, isEmpty);
      });
    }
  });

  group('onboard writes', () {
    test('writes the pointer in that namespace, where only open can read it',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final keys = await keysOf(0);
      expect(server.pointerNamespaces[keys.lookupHex], keys.ns);
      expect(await server.get(_atSign, keys.lookupHex, ns: keys.ns), isNotNull);
      expect(await server.get(_atSign, keys.lookupHex, ns: 'atkeysv'), isNull);
    });

    test('writes the document, then the pointer', () async {
      final keys = await keysOf(0);
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(
          server.log, ['put-document:eid1', 'put-pointer:${keys.lookupHex}']);
    });

    test('seals the document without the APKAM private key', () async {
      final keys = await keysOf(0);
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final document = await keys.vault
          .open(PasskeyRecordType.atkeys, server.documents['eid1']!);
      final held = {
        for (final e in document.entries)
          if (e.value != null) e.key
      };
      // Beyond the encryption key and the tag: the versioned header, the
      // atSign and an always-empty `keys` array.
      expect(
          held,
          unorderedEquals([
            'aesEncryptPrivateKey',
            'aesEncryptPublicKey',
            'publicTag',
            'version',
            'atsign',
            'keys'
          ]));
      expect(document['keys'], isEmpty);
      expect(document['atsign'], _atSign);
      expect(document['aesEncryptPrivateKey'], fakeEncryptPrivateKey);
    });

    test('opens the client with the @keys, without the APKAM private key',
        () async {
      final client = (await custody().onboard(atSign: _atSign, cram: 'cram'))
          .client as FakeAtClient;
      final keys = await client.keysIo.read(_atSign);
      expect(keys.toJson()['aesPkamPrivateKey'], isNull);
      expect(keys.atsign, _atSign.toAtsign());
    });

    test('seals the pointer as the enrollment id', () async {
      final keys = await keysOf(0);
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(
          await keys.vault
              .open(PasskeyRecordType.eid, server.pointers[keys.lookupHex]!),
          {'enrollmentId': 'eid1'});
    });

    test('remembers the credential and enrollment id and asks for persistence',
        () async {
      final session = await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(session.client.enrollmentId, 'eid1');
      expect(hints.ids[_atSign], 'eid1');
      expect(hints.credentials[_atSign], Uint8List.fromList([1]));
      // Once before the activation, once when the hints are written.
      expect(persistence.requests, 2);
    });
  });

  group('passkey registration stamp', () {
    void expectStamped() {
      expect(authenticator.created.last, (
        atSign: _atSign,
        enrolledAt: _enrolledAt,
        deviceName: gateway.device
      ));
    }

    test('onboard registers with the gateway device name and the clock',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expectStamped();
    });
  });

  group('a failed onboarding write', () {
    Future<Object> failure() async {
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on Object catch (e) {
        return e;
      }
      fail('onboard completed');
    }

    test('a document put that fails once is retried on the same session',
        () async {
      server.documentPutFailures = 1;
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final keys = await keysOf(0);
      expect(server.log, [
        'put-document:eid1',
        'put-document:eid1',
        'put-pointer:${keys.lookupHex}'
      ]);
      expect(server.documentReads, greaterThanOrEqualTo(1));
      expect(gateway.lastSession!.closed, isFalse);
    });

    test('a document that does not read back never gets a pointer', () async {
      server.dropDocumentWrites = true;
      await failure();
      expect(server.pointers, isEmpty);
    });

    test('a read-back mismatch is attempted once and surfaces', () async {
      server.dropDocumentWrites = true;
      expect(await failure(), isA<AtServerAtKeysWriteException>());
      expect(server.log, ['put-document:eid1']);
    });

    test('an existing different document fails onboarding without a write',
        () async {
      final keys = await keysOf(0);
      final other = AtKeys.legacy(encryptionPrivateKey: 'b3RoZXI=')
        ..atsign = _atSign.toAtsign();
      server.documents['eid1'] =
          await keys.vault.seal(PasskeyRecordType.atkeys, other.toJson());
      expect(await failure(), isA<AtKeysFileOverwriteException>());
      expect(server.log, isNot(contains('put-document:eid1')));
    });

    test('an existing different document is refused on the first attempt',
        () async {
      final keys = await keysOf(0);
      final other = AtKeys.legacy(encryptionPrivateKey: 'b3RoZXI=')
        ..atsign = _atSign.toAtsign();
      server.documents['eid1'] =
          await keys.vault.seal(PasskeyRecordType.atkeys, other.toJson());

      expect(await failure(), isA<AtKeysFileOverwriteException>());

      expect(server.documentReads, 2,
          reason: 'one attempt: the existence check and the comparison');
    });

    test(
        'a document put whose reply is lost counts as written, and the client '
        'is handed a store that reads it from memory', () async {
      server.documentPutRepliesLost = 1;

      final session = await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(server.log.where((e) => e == 'put-document:eid1'), hasLength(1),
          reason: 'the retry finds the document and does not put it again');
      final reads = server.documentReads;
      final client = session.client as FakeAtClient;
      expect((await client.keysIo.read(_atSign)).atsign, _atSign.toAtsign());
      expect(server.documentReads, reads);
      await session.stop();
    });

    test('a document put failing past the bound ends the onboarding', () async {
      server.documentPutFailures = 99;
      expect(await failure(), isA<StateError>());
      expect(server.log, everyElement('put-document:eid1'));
      expect(server.log, hasLength(3));
      expect(gateway.lastSession!.closed, isTrue);
      expectStoresClosed();
      expect(server.cramDeleted, isEmpty);
      expect(hints.ids, isEmpty);
    });

    test('a failed pointer put ends the onboarding before the completion',
        () async {
      server.pointerPutFailures = 1;
      await failure();
      expect(gateway.lastSession!.closed, isTrue);
      expect(gateway.lastSession!.completed, isEmpty);
      expect(server.pointers, isEmpty);
      expect(server.cramDeleted, isEmpty);
    });

    test(
        'a hint write that fails with an Error comes after the CRAM secret is '
        'deleted and fails the onboarding', () async {
      final broken = StateError('the hint store is broken');
      hints
        ..failWrites = true
        ..writeFailure = broken;
      expect(await failure(), same(broken));
      expect(server.cramDeleted, {_atSign});
      expect(gateway.lastSession!.closed, isTrue);
      expectStoresClosed();
      expect(gateway.lastSession!.clients, isEmpty);
      expect(authenticator.signalled, isEmpty,
          reason: 'a failure after the activation is completed reports '
              'nothing to the platform');
    });
  });

  group(
      'Feature: Onboarding writes the @keys before it deletes the CRAM '
      'secret', () {
    test(
        'Onboarding writes the @keys document and pointer before it deletes '
        'the CRAM secret', () async {
      final keys = await keysOf(0);
      await custody().onboard(atSign: _atSign, cram: 'cram');

      final steps = server.timeline;
      expect(steps.indexOf('put-document:eid1'),
          lessThan(steps.indexOf('cram-deleted')));
      expect(steps.indexOf('put-pointer'),
          lessThan(steps.indexOf('cram-deleted')));
      final document = await keys.vault
          .open(PasskeyRecordType.atkeys, server.documents['eid1']!);
      expect(document['aesEncryptPrivateKey'], fakeEncryptPrivateKey);
      await expectLater(
          gateway.activate(
              atSign: _atSign,
              apkamKeyPair: await apkamKeyPairFromSeed(keys.authSeed),
              cram: 'cram'),
          throwsStateError,
          reason: 'the CRAM secret is deleted');
    });

    test('the client opens only after the CRAM secret is deleted', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final steps = server.timeline;
      expect(steps.indexOf('open-client'),
          greaterThan(steps.indexOf('cram-deleted')));
    });

    test(
        'Onboarding deletes the CRAM secret, then revokes the other '
        'enrollments, then publishes its encryption public key', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(
          completionSteps(),
          [
            'cram-deleted',
            'revoke-others',
            'publish:${encryptionPublicKeyOf('eid1')}',
            'cram-deleted',
          ],
          reason: 'the CRAM secret is deleted, then the revoke is sent, then '
              'the key is published with a second delete of the CRAM secret');
      expect(gateway.lastSession!.completed,
          [isEmpty, containsPair('aesEncryptPublicKey', isA<String>())]);
    });

    test(
        'Onboarding records its completion as due before it writes the @keys '
        'document, records the CRAM secret\'s deletion, and deletes that '
        'record last', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');

      final steps = server.timeline;
      final mark = steps.indexOf('record-completion-due:eid1:activated');
      expect(mark, greaterThan(steps.indexOf('activate:eid1')),
          reason: 'the record is written as the new enrollment');
      expect(mark, lessThan(steps.indexOf('put-document:eid1')),
          reason: 'the record is stored before the @keys document');
      expect(mark, lessThan(steps.indexOf('put-pointer')));
      final rewrite =
          steps.indexOf('record-completion-due:eid1:cramSecretDeleted');
      expect(rewrite, greaterThan(steps.indexOf('cram-deleted')),
          reason: 'the record says the CRAM secret is deleted once its delete '
              'answered');
      expect(rewrite, lessThan(steps.indexOf('revoke-others')),
          reason: 'and before the revoke');
      final publish = steps.indexOf('publish:${encryptionPublicKeyOf('eid1')}');
      final clear = steps.indexOf('clear-completion-due:eid1');
      expect(publish, greaterThan(-1));
      expect(clear, greaterThan(steps.lastIndexOf('cram-deleted')),
          reason: 'the record is deleted after the publish and its CRAM '
              'secret delete');
      expect(clear, greaterThan(publish));
      expect(completionAndRecordSteps().last, 'clear-completion-due:eid1',
          reason: 'deleting the record is the completion\'s last step');
      expect(server.completionDue, isEmpty);
    });

    test(
        'An onboarding whose completion-due record cannot be written fails '
        'before it writes anything else', () async {
      final refusal = StateError('the atServer refused the record');
      server.completionDueWriteRefusals[CompletionDue.activated] = refusal;

      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(refusal)));

      expect(server.timeline, contains('record-completion-due:eid1:activated'),
          reason: 'the control: the record\'s write was sent');
      expect(server.log, isEmpty,
          reason: 'no @keys document or pointer is written');
      expect(server.documents, isEmpty);
      expect(server.pointers, isEmpty);
      expect(server.cramDeleted, isEmpty,
          reason: 'the CRAM secret is not deleted');
      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(authenticator.signalled, [authenticator.current],
          reason: 'the new credential is reported to the platform as unknown');
      expect(hints.ids, isEmpty);
    });

    test(
        'An onboarding whose record of the CRAM secret\'s deletion cannot be '
        'written fails, and a login finishes it', () async {
      final refusal = StateError('the atServer refused the rewrite');
      server.completionDueWriteRefusals[CompletionDue.cramSecretDeleted] =
          refusal;

      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(refusal)));

      final steps = server.timeline;
      expect(steps.indexOf('record-completion-due:eid1:cramSecretDeleted'),
          greaterThan(steps.indexOf('cram-deleted')),
          reason: 'the control: the rewrite was sent once the CRAM secret '
              'was deleted');
      expect(server.cramDeleted, {_atSign},
          reason: 'the onboarding fails after the CRAM secret is deleted');
      expect(steps, isNot(contains('revoke-others')),
          reason: 'and before any revoke');
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the record still says only that the '
              'completion is due');
      expect(hints.ids, isEmpty);
      final mark = server.timeline.length;
      final device = FakeHints();

      final session = await custody(withHints: device).open(atSign: _atSign);

      expect(
          completionAndRecordSteps(from: mark),
          [
            'cram-deleted',
            'revoke-others',
            'publish:${encryptionPublicKeyOf('eid1')}',
            'cram-deleted',
            'clear-completion-due:eid1',
          ],
          reason: 'the login finishes the completion');
      expect(server.completionDue, isEmpty);
      expect(session.client.enrollmentId, 'eid1',
          reason: 'it opens the onboarding\'s enrollment');
      expect(device.ids, {_atSign: 'eid1'});
    });

    group(
        'An onboarding interrupted before the CRAM secret is deleted can be '
        'run again with the same secret', () {
      final interruptions = <String, void Function()>{
        'after its enrollment was approved': () =>
            server.documentPutFailures = 99,
        'after its @keys document was written': () =>
            server.pointerPutFailures = 1,
        'after its pointer was written': () => gateway.onAuthenticate =
            (session) => session.completeError = StateError('interrupted'),
      };
      for (final MapEntry(key: point, value: interrupt)
          in interruptions.entries) {
        test(
            'An onboarding interrupted before the CRAM secret is deleted can '
            'be run again with the same secret: $point', () async {
          interrupt();
          await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
              throwsA(anything));
          expect(server.cramDeleted, isEmpty);
          server
            ..documentPutFailures = 0
            ..pointerPutFailures = 0;
          gateway.onAuthenticate = null;

          final session =
              await custody().onboard(atSign: _atSign, cram: 'cram');

          expect(session.client.enrollmentId, 'eid2');
          expect(authenticator.creates, 2, reason: 'a new passkey');
          expect(server.cramDeleted, {_atSign});
          expect(gateway.lastSession!.clients, hasLength(1));
        });
      }
    });

    test('The retry revokes the enrollments interrupted attempts left approved',
        () async {
      server.documentPutFailures = 99;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.approved, {'eid1': _atSign});
      server.documentPutFailures = 0;

      await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(
          completionSteps(),
          containsAllInOrder([
            'cram-deleted',
            'revoke:eid1',
            'publish:${encryptionPublicKeyOf('eid2')}',
          ]),
          reason: 'the earlier enrollment was revoked after the CRAM secret '
              'was deleted and before the new key was published');
      expect(server.approved, {'eid2': _atSign});
    });

    test('A passkey left by an interrupted onboarding is refused as lost',
        () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      final first = authenticator.current;
      gateway.onAuthenticate = null;
      await custody().onboard(atSign: _atSign, cram: 'cram');
      authenticator.current = first;

      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(gateway.authenticated, ['eid1']);
    });

    test(
        'a revoke that fails during onboarding is thrown, reports nothing and '
        'saves no hints, and a login then completes the activation', () async {
      final remains = AtEnrollmentException(
          '1 approved enrollments other than eid1 remain after revoking them');
      gateway.onAuthenticate = (session) => session.revokeError = remains;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(remains)));
      expect(authenticator.signalled, isEmpty,
          reason: 'a failure while completing the activation reports nothing '
              'to the platform');
      expect(hints.credentials, isEmpty);
      expect(hints.ids, isEmpty);
      expect(server.cramDeleted, {_atSign},
          reason: 'the CRAM secret was deleted before the revoke');
      expect(server.publishedKey, isNull);
      expectStoresClosed();
      gateway.onAuthenticate = null;
      final mark = server.timeline.length;

      final session = await custody().open(atSign: _atSign);

      expect(completionSteps(from: mark), [
        'cram-deleted',
        'revoke-others',
        'publish:${encryptionPublicKeyOf('eid1')}',
        'cram-deleted',
      ]);
      expect(session.client.enrollmentId, 'eid1');
      expect(hints.ids, {_atSign: 'eid1'});
    });

    test(
        'A login that finds the completion due deletes the CRAM secret, then '
        'revokes the other enrollments, then publishes the key', () async {
      server.documentPutFailures = 99;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      server.documentPutFailures = 0;
      gateway.onAuthenticate =
          (session) => session.revokeError = StateError('revoke failed');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.approved, {'eid1': _atSign, 'eid2': _atSign},
          reason: 'the control: the failed revoke left the first enrollment');
      expect(server.cramDeleted, {_atSign},
          reason: 'the control: the second onboarding deleted the CRAM secret');
      expect(server.completionDue['eid2'], CompletionDue.cramSecretDeleted,
          reason: 'the control: the second onboarding recorded the CRAM '
              'secret\'s deletion');
      final mark = server.timeline.length;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(
          completionAndRecordSteps(from: mark),
          [
            'cram-deleted',
            'revoke-others',
            'revoke:eid1',
            'publish:${encryptionPublicKeyOf('eid2')}',
            'cram-deleted',
            'clear-completion-due:eid2',
          ],
          reason: 'the login deletes the CRAM secret, then revokes the first '
              'enrollment, then publishes the document\'s key, then deletes '
              'the completion-due record');
      expect(session.client.enrollmentId, 'eid2');
      expect(server.approved, {'eid2': _atSign});
      expect(server.completionDue, isNot(contains('eid2')));
    });

    test(
        'A login that finds the completion done and the document\'s key '
        'published deletes the CRAM secret and revokes nothing', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(server.completionDue, isEmpty,
          reason: 'the control: the onboarding\'s completion is done');
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'),
          reason: 'the control: the onboarding published its key');
      server.approved['eid9'] = _atSign;
      final mark = server.timeline.length;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(completionSteps(from: mark), ['cram-deleted'],
          reason: 'the login deletes the CRAM secret, sends no revoke and '
              'publishes nothing');
      expect(gateway.lastSession!.completed, [isEmpty]);
      expect(server.approved, {'eid1': _atSign, 'eid9': _atSign},
          reason: 'the other enrollment is still approved');
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A login finishes an onboarding over a key another activation tool '
        'published while the CRAM secret was live', () async {
      const otherTools = 'b3RoZXItdG9vbA==';
      server.approved['eid9'] = _atSign;
      server.publishedKey = otherTools;
      gateway.onAuthenticate =
          (session) => session.revokeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.cramDeleted, {_atSign},
          reason: 'the control: the onboarding deleted the CRAM secret');
      expect(server.completionDue, {'eid1': CompletionDue.cramSecretDeleted},
          reason: 'the control: the onboarding recorded that');
      expect(server.publishedKey, otherTools,
          reason: 'the control: the other tool\'s key is still published');
      expect(server.approved, {'eid1': _atSign, 'eid9': _atSign},
          reason: 'the control: the other tool\'s enrollment is approved');
      final mark = server.timeline.length;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(
          completionAndRecordSteps(from: mark),
          [
            'cram-deleted',
            'revoke-others',
            'revoke:eid9',
            'publish:${encryptionPublicKeyOf('eid1')}',
            'cram-deleted',
            'clear-completion-due:eid1',
          ],
          reason: 'the login revokes the other tool\'s enrollment, publishes '
              'the document\'s key, then deletes the completion-due record');
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'),
          reason: 'the document\'s key is published over the other tool\'s');
      expect(server.approved, {'eid1': _atSign});
      expect(server.completionDue, isEmpty);
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A login refuses a key another tool published after its onboarding '
        'stopped before deleting the CRAM secret', () async {
      const otherTools = 'b3RoZXItdG9vbA==';
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the onboarding stopped before its delete of '
              'the CRAM secret answered');
      final other = await gateway.activate(
          atSign: _atSign, apkamKeyPair: otherToolsPair, cram: 'cram');
      await other.completeActivation({'aesEncryptPublicKey': otherTools});
      expect(server.cramDeleted, {_atSign},
          reason: 'the control: the other tool deleted the CRAM secret');
      expect(server.publishedKey, otherTools,
          reason: 'the control: the other tool published its key');
      expect(server.approved, {'eid1': _atSign, 'eid2': _atSign});
      final mark = server.timeline.length;
      final device = FakeHints();

      await expectLater(custody(withHints: device).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(gateway.authenticated.last, 'eid1',
          reason: 'the control: the login authenticated the onboarding\'s '
              'enrollment');
      expect(server.timeline.skip(mark), contains('read-completion-due:eid1'),
          reason: 'the control: the login read the record');
      expect(completionAndRecordSteps(from: mark), isEmpty,
          reason: 'it sends no delete, revoke or publish');
      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(server.publishedKey, otherTools);
      expect(server.approved, {'eid1': _atSign, 'eid2': _atSign},
          reason: 'the other tool\'s enrollment is still approved');
      expect(device.ids, isEmpty);
    });

    test(
        'A login after an onboarding that stopped before deleting the CRAM '
        'secret, with no key published, finishes it', () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      server.approved['eid9'] = _atSign;
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the onboarding stopped before its delete of '
              'the CRAM secret answered');
      expect(server.publishedKey, isNull,
          reason: 'the control: no encryption public key is published');
      final mark = server.timeline.length;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(
          completionAndRecordSteps(from: mark),
          [
            'cram-deleted',
            'revoke-others',
            'revoke:eid9',
            'publish:${encryptionPublicKeyOf('eid1')}',
            'cram-deleted',
            'clear-completion-due:eid1',
          ],
          reason: 'the login deletes the CRAM secret, revokes the other '
              'enrollment, publishes the document\'s key and deletes the '
              'completion-due record');
      expect(server.approved, {'eid1': _atSign});
      expect(server.completionDue, isEmpty);
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A login that finds no key published and the completion done '
        'publishes the document\'s key and revokes nothing', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(server.completionDue, isEmpty,
          reason: 'the control: the onboarding\'s completion is done');
      server.approved['eid9'] = _atSign;
      server.publishedKey = null;
      final mark = server.timeline.length;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(completionAndRecordSteps(from: mark),
          ['publish:${encryptionPublicKeyOf('eid1')}', 'cram-deleted'],
          reason: 'the login publishes the document\'s key and deletes the '
              'CRAM secret, and sends no revoke');
      expect(gateway.lastSession!.completed, [
        {'aesEncryptPublicKey': encryptionPublicKeyOf('eid1')}
      ]);
      expect(server.approved, {'eid1': _atSign, 'eid9': _atSign},
          reason: 'the other enrollment is still approved');
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A completion whose record delete fails saves no passkey hints, and '
        'the next login finishes it', () async {
      final refusal = StateError('the atServer refused the delete');
      server
        ..completionDueClearFailures = 1
        ..completionDueClearError = refusal;

      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(refusal)));

      final steps = server.timeline;
      expect(steps.indexOf('publish:${encryptionPublicKeyOf('eid1')}'),
          lessThan(steps.indexOf('clear-completion-due:eid1')),
          reason: 'the onboarding throws the refusal after the encryption '
              'public key is published');
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
      expect(hints.credentials, isEmpty,
          reason: 'this device saves no passkey hints');
      expect(hints.ids, isEmpty, reason: 'this device saves no passkey hints');
      expect(authenticator.signalled, isEmpty,
          reason: 'a failure while completing the activation reports nothing');
      expect(server.completionDue, {'eid1': CompletionDue.cramSecretDeleted},
          reason: 'the control: the completion is still due');
      final mark = server.timeline.length;
      final device = FakeHints();

      final session = await custody(withHints: device).open(atSign: _atSign);

      expect(
          completionAndRecordSteps(from: mark),
          [
            'cram-deleted',
            'revoke-others',
            'publish:${encryptionPublicKeyOf('eid1')}',
            'cram-deleted',
            'clear-completion-due:eid1',
          ],
          reason: 'the login finishes the completion and deletes the '
              'completion-due record');
      expect(server.completionDue, isEmpty);
      expect(session.client.enrollmentId, 'eid1');
      expect(device.ids, {_atSign: 'eid1'});
    });

    test(
        'A completion-due record the atServer reports as not found counts as '
        'deleted', () async {
      final remote = ScriptedAtLookUp((command) async {
        if (command.startsWith('delete:completion-due.')) {
          throw AtLookUpException('AT0015', 'key not found');
        }
        return 'data:1';
      });
      server.completionDueRecord = CompletionDueRecord(
          RemoteSecondary(_atSign, AtClientPreference(),
              atLookUp: remote,
              lookUps: RecordingLookUps((_) async => null).call),
          atSign: _atSign,
          enrollmentId: 'eid1');

      final session = await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(remote.commands.map((c) => c.command),
          contains('delete:completion-due.eid1.a.__e@alice\n'),
          reason: 'the control: the delete was sent and answered AT0015');
      expect(gateway.lastSession!.clients, hasLength(1),
          reason: 'the onboarding opened its client');
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A login whose read of the completion-due record fails throws and '
        'sends nothing', () async {
      gateway.onAuthenticate = (session) =>
          session.completeErrorAfterDelete = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.publishedKey, isNull,
          reason: 'the control: the onboarding published no key');
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the onboarding\'s completion is due');
      final failure = StateError('the read of the record failed');
      server.completionDueReadError = failure;
      final mark = server.timeline.length;
      final device = FakeHints();

      await expectLater(custody(withHints: device).open(atSign: _atSign),
          throwsA(same(failure)));

      expect(server.timeline.skip(mark), contains('read-completion-due:eid1'),
          reason: 'the control: the login read the record');
      expect(completionAndRecordSteps(from: mark), isEmpty,
          reason: 'it sends no delete, revoke or publish');
      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(device.ids, isEmpty);
    });

    test(
        'A login reads the completion-due record before it looks at the '
        'published key', () async {
      gateway.onAuthenticate = (session) =>
          session.completeErrorAfterDelete = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.publishedKey, isNull,
          reason: 'the control: the onboarding published no key');
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the record says only that the completion is '
              'due, so the login looks up the published key');
      final mark = server.timeline.length;

      await custody(withHints: FakeHints()).open(atSign: _atSign);

      final steps = server.timeline.skip(mark).toList();
      final read = steps.indexOf('read-completion-due:eid1');
      final lookups = [
        for (var i = 0; i < steps.length; i++)
          if (steps[i] == 'lookup-publickey') i
      ];
      expect(read, greaterThan(-1), reason: 'the login reads the record');
      expect(lookups, isNotEmpty,
          reason: 'the control: the login looks up publickey@alice');
      expect(lookups, everyElement(greaterThan(read)),
          reason: 'the login reads the completion-due record before it looks '
              'up publickey@alice');
    });

    test(
        'A login refuses a @keys document whose APKAM public key is not the '
        'passkey\'s, even while the completion is due', () async {
      server.keys = {...server.keys, 'aesPkamPublicKey': 'cm9sbGVkLWJhY2s='};
      gateway.onAuthenticate = (session) =>
          session.completeErrorAfterDelete = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.completionDue, {'eid1': CompletionDue.activated},
          reason: 'the control: the onboarding\'s completion is due');
      final mark = server.timeline.length;
      final device = FakeHints();

      await expectLater(custody(withHints: device).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(gateway.authenticated.last, 'eid1',
          reason: 'the control: the login authenticated the enrollment');
      expect(completionAndRecordSteps(from: mark), isEmpty,
          reason: 'it sends no delete, revoke or publish');
      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(server.completionDue, {'eid1': CompletionDue.activated});
      expect(device.ids, isEmpty);
    });

    test(
        'A login whose revoke keeps failing throws the revoke\'s failure, and '
        'the next login tries again', () async {
      final remains = AtEnrollmentException(
          '1 approved enrollments other than eid1 remain after revoking them');
      gateway.onAuthenticate = (session) => session.revokeError = remains;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(remains)));
      final device = FakeHints();

      for (final login in ['the first login', 'the next login']) {
        final mark = server.timeline.length;
        await expectLater(custody(withHints: device).open(atSign: _atSign),
            throwsA(same(remains)),
            reason: '$login throws the revoke\'s AtEnrollmentException, not '
                'a PasskeyLostException');
        expect(completionSteps(from: mark), ['cram-deleted', 'revoke-others'],
            reason: '$login sends the revoke and publishes nothing');
        expect(gateway.lastSession!.closed, isTrue);
      }
      expect(server.publishedKey, isNull);
      expect(device.credentials, isEmpty, reason: 'no hints are saved');
      expect(device.ids, isEmpty, reason: 'no hints are saved');

      gateway.onAuthenticate = null;
      final session = await custody(withHints: device).open(atSign: _atSign);

      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
      expect(device.ids, {_atSign: 'eid1'});
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'The retry publishes its own encryption public key over an '
        'interrupted attempt\'s', () async {
      const otherTools = 'b3RoZXItdG9vbA==';
      server.publishedKey = otherTools;
      expect(server.cramDeleted, isEmpty,
          reason: 'the control: the CRAM secret is not yet deleted');

      await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
    });

    test(
        'A login after an onboarding interrupted once the CRAM secret is '
        'deleted opens its enrollment', () async {
      gateway.openErrorForNext = StateError('tab closed');
      hints.failPairWrites = true;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.cramDeleted, {_atSign});
      expect(hints.ids, isEmpty, reason: 'the device remembers nothing');
      gateway.openErrorForNext = null;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(session.client.enrollmentId, 'eid1');
      expect(gateway.activated, hasLength(1));
    });

    test(
        'A login after an onboarding that stopped before deleting the CRAM '
        'secret deletes it', () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.cramDeleted, isEmpty,
          reason: 'the control: the onboarding left the CRAM secret');
      gateway.onAuthenticate = null;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(server.cramDeleted, {_atSign},
          reason: 'the login deletes the CRAM secret');
      final steps = server.timeline;
      expect(steps.lastIndexOf('cram-deleted'),
          lessThan(steps.lastIndexOf('open-client')));
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'A login after an onboarding that stopped before publishing its '
        'encryption public key publishes it and deletes the CRAM secret',
        () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.publishedKey, isNull);
      expect(server.cramDeleted, isEmpty);
      gateway.onAuthenticate = null;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(server.publishedKey, encryptionPublicKeyOf('eid1'),
          reason: 'the login publishes the document\'s encryption public key');
      expect(server.cramDeleted, {_atSign},
          reason: 'the login deletes the CRAM secret');
      expect(gateway.lastSession!.completed, [
        isEmpty,
        {'aesEncryptPublicKey': encryptionPublicKeyOf('eid1')}
      ]);
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'a login whose completion fails opens no client and remembers '
        'nothing, and the next login completes it', () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      final fresh = FakeHints();

      await expectLater(
          custody(withHints: fresh).open(atSign: _atSign), throwsStateError,
          reason: 'a login whose completion fails, fails');

      expect(gateway.lastSession!.closed, isTrue);
      expect(gateway.lastSession!.clients, isEmpty);
      expect(fresh.ids, isEmpty);
      expect(server.cramDeleted, isEmpty);
      expectStoresClosed();
      gateway.onAuthenticate = null;

      await custody(withHints: fresh).open(atSign: _atSign);

      expect(server.cramDeleted, {_atSign});
      expect(fresh.ids, {_atSign: 'eid1'});
    });

    test(
        'A login that finds another key published and the completion done '
        'refuses it', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(server.completionDue, isEmpty,
          reason: 'the control: the onboarding\'s completion is done');
      server.approved['eid9'] = _atSign;
      server.publishedKey = 'cm90YXRlZA==';
      final mark = server.timeline.length;

      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(completionAndRecordSteps(from: mark), isEmpty,
          reason: 'it sends no delete, revoke or publish');
      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(server.publishedKey, 'cm90YXRlZA==');
      expect(server.approved, {'eid1': _atSign, 'eid9': _atSign});
    });

    test('A login with saved hints sends no activation completion', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(hints.ids, {_atSign: 'eid1'},
          reason: 'the control: the onboarding saved its hints');
      expect(completionSteps(),
          contains('publish:${encryptionPublicKeyOf('eid1')}'),
          reason: 'the control: the onboarding completed the activation');
      final mark = server.timeline.length;

      final session = await custody().open(atSign: _atSign);

      expect(gateway.authenticated, ['eid1'],
          reason: 'the login authenticated the saved enrollment');
      expect(gateway.lastSession!.completed, isEmpty,
          reason: 'a login with saved hints sends no activation completion');
      expect(completionSteps(from: mark), isEmpty,
          reason: 'a login with saved hints sends no CRAM secret delete, no '
              'revoke and no publish');
      expect(session.client.enrollmentId, 'eid1');
    });

    test(
        'a login with saved hints that finds another encryption public key '
        'published is refused', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      server.publishedKey = 'cm90YXRlZA==';

      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(gateway.authenticated, ['eid1'],
          reason: 'the control: the login used the saved enrollment');
      expect(gateway.lastSession!.closed, isTrue);
      expect(server.publishedKey, 'cm90YXRlZA==');
    });

    test('an interrupted onboarding leaves no hints on the device', () async {
      server.documentPutFailures = 99;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(hints.credentials, isEmpty);
      expect(hints.ids, isEmpty);
    });

    group('a failed onboarding and the platform', () {
      test(
          'A passkey whose onboarding fails before it completes the '
          'activation is reported as unknown', () async {
        for (final fail in <void Function()>[
          () => gateway.activateRefusal = StateError('CRAM refused'),
          () => server.documentPutFailures = 99,
          () => server.pointerPutFailures = 1,
        ]) {
          reset();
          fail();
          await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
              throwsA(anything));
          expect(authenticator.signalled, [authenticator.current],
              reason: 'the registered credential is reported');
        }
      });

      test(
          'A passkey whose onboarding fails while completing the activation '
          'is not reported', () async {
        for (final MapEntry(key: point, value: fail)
            in <String, void Function()>{
          'the CRAM secret is deleted and the reply is lost': () =>
              gateway.onAuthenticate = (session) =>
                  session.completeErrorAfterDelete = StateError('lost'),
          'the CRAM secret delete fails': () => gateway.onAuthenticate =
              (session) => session.completeError = StateError('lost'),
          'the revoke fails': () => gateway.onAuthenticate =
              (session) => session.revokeError = StateError('lost'),
          'the publish fails': () => gateway.onAuthenticate = (session) =>
              session.completeErrorAfterPublish = StateError('lost'),
        }.entries) {
          reset();
          fail();
          await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
              throwsStateError,
              reason: point);
          expect(authenticator.signalled, isEmpty,
              reason: 'nothing is reported when $point');
        }
      });

      test('a failure after the activation is completed is not reported',
          () async {
        gateway.openErrorForNext = StateError('open failed');
        await expectLater(
            custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
        expect(authenticator.signalled, isEmpty);
      });

      test('a refused signal does not change the onboarding error', () async {
        authenticator.signalFails = true;
        final refusal = StateError('CRAM refused');
        gateway.activateRefusal = refusal;
        await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
            throwsA(same(refusal)));
        expect(authenticator.signalled, hasLength(1));
      });

      test(
          'A failed activation is thrown without waiting for the platform to '
          'take the unknown passkey report', () async {
        final unsettled = _UnsettledSignalAuthenticator();
        authenticator = unsettled;
        final refusal = StateError('CRAM refused');
        gateway.activateRefusal = refusal;
        final thrown = await custody()
            .onboard(atSign: _atSign, cram: 'cram')
            .then<Object?>((_) => null, onError: (Object e) => e)
            .timeout(const Duration(seconds: 2),
                onTimeout: () =>
                    fail('onboard waited for the platform report'));
        expect(thrown, same(refusal));
        expect(unsettled.signalled, [unsettled.current],
            reason: 'the new credential is reported once');
        expect(setupLock.held, isEmpty,
            reason: 'the setup lock is released while the report is pending');
      });

      test('a failed registration reports nothing', () async {
        authenticator.createFails = true;
        await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
            throwsA(anything));
        expect(authenticator.signalled, isEmpty);
        expect(gateway.activated, isEmpty);
      });
    });
  });

  group('open', () {
    test('closes the session when remembering the device fails with an Error',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final broken = StateError('the hint store is broken');
      final fresh = FakeHints()
        ..failWrites = true
        ..writeFailure = broken;
      await expectLater(custody(withHints: fresh).open(atSign: _atSign),
          throwsA(same(broken)));
      expect(gateway.lastSession!.closed, isTrue);
      expect(gateway.lastSession!.clients, isEmpty);
    });

    test('opens when remembering the device fails with an Exception', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final fresh = FakeHints()..failWrites = true;
      final session = await custody(withHints: fresh).open(atSign: _atSign);
      expect(session.client.enrollmentId, 'eid1');
      expect(gateway.lastSession!.closed, isFalse);
      expect(fresh.ids, isEmpty);
    });
  });

  group('a client opened from custody', () {
    setUp(() async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
    });

    test('an opened client can still seal and open its document', () async {
      final client =
          (await custody(withHints: FakeHints()).open(atSign: _atSign)).client
              as FakeAtClient;

      final keys = await client.keysIo.read(_atSign);
      keys.fileLegacyMaterial(apkamSymmetricKey: 'YWZ0ZXItb3Blbg==');
      await client.keysIo.flush(_atSign.toAtsign(), keys);
      expect((await client.keysIo.read(_atSign)).enrollmentSymmetricKey,
          isNotNull);
      await client.stop();
    });

    test('an onboarded client can still seal and open its document', () async {
      final client = (await custody().onboard(atSign: '@bob', cram: 'cram'))
          .client as FakeAtClient;

      final keys = await client.keysIo.read('@bob');
      keys.fileLegacyMaterial(apkamSymmetricKey: 'YWZ0ZXItb25ib2FyZA==');
      await client.keysIo.flush('@bob'.toAtsign(), keys);
      expect(
          (await client.keysIo.read('@bob')).enrollmentSymmetricKey, isNotNull);
      await client.stop();
    });

    test('returns a session that closes its key store once its client stops',
        () async {
      final client =
          (await custody(withHints: FakeHints()).open(atSign: _atSign)).client
              as FakeAtClient;

      await client.stop();
      await pumpEventQueue();

      await expectLater(
          Future.sync(() => client.keysIo.read(_atSign)), throwsStateError);
    });

    test('Stopping a client closes no key store', () async {
      final opened =
          (await custody(withHints: FakeHints()).open(atSign: _atSign)).client
              as FakeAtClient;
      final client = await buildAtClient(
          atSign: _atSign,
          namespace: 'wavi',
          preference: AtClientPreference()
            ..namespace = 'wavi'
            ..monitorAutoStart = false,
          secondaryAddressFinder: defaultAtDirectory,
          atKeysIo: opened.keysIo,
          lookUps: _idleLookUps,
          storage: InMemoryAtClientStorage(atSign: _atSign));

      await client.stop();

      expect((await opened.keysIo.read(_atSign)).atsign, _atSign.toAtsign());
    });
  });

  group('setup lock', () {
    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('onboard runs under the per-atSign setup lock', () async {
      await custody().onboard(atSign: '@Alice', cram: 'cram');
      expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
    });

    test('a concurrent setup for the same atSign waits for the first',
        () async {
      gateway.gate = Completer<void>();
      final first = custody().onboard(atSign: _atSign, cram: 'cram');
      await pump();
      final second = custody().onboard(atSign: _atSign, cram: 'cram');
      await pump();
      expect(authenticator.creates, 1);

      gateway.gate!.complete();
      await first;
      await expectLater(second, throwsStateError);
      expect(authenticator.creates, 2);
      expect(authenticator.signalled, hasLength(1));
    });

    test('a setup for another atSign does not wait', () async {
      gateway.gate = Completer<void>();
      final first = custody().onboard(atSign: _atSign, cram: 'cram');
      await pump();
      final second = custody().onboard(atSign: '@bob', cram: 'cram');
      await pump();
      expect(authenticator.creates, 2);

      gateway.gate!.complete();
      await Future.wait([first, second]);
    });

    test('the lock is held until the pointer is written', () async {
      gateway.gate = Completer<void>();
      final first = custody().onboard(atSign: _atSign, cram: 'cram');
      await pump();
      expect(server.log, isEmpty);
      gateway.gate!.complete();
      await first;
      expect(server.log, hasLength(2));
    });

    test('the lock is held at the moment the pointer is written', () async {
      final heldAtWrite = <Set<String>>[];
      server.onPointerPut = () => heldAtWrite.add({...setupLock.held});
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(heldAtWrite, [
        {setupLockName(_lockPrefix, _atSign)}
      ]);
      expect(setupLock.held, isEmpty);
    });
  });

  group('open', () {
    setUp(() async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      persistence.requests = 0;
    });

    test('recovers from an empty device with one passkey prompt', () async {
      authenticator.gets = 0;
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expect(authenticator.gets, 1);
      expect(session.client.enrollmentId, 'eid1');
      final keys = await (session.client as FakeAtClient).keysIo.read(_atSign);
      expect(keys.atsign, _atSign.toAtsign());
      expect(keys.toJson()['aesEncryptPrivateKey'], fakeEncryptPrivateKey);
      expect(server.pointerReads, 1);
    });

    test('recovery rewrites the hints and asks for persistence once', () async {
      final fresh = FakeHints();
      await custody(withHints: fresh).open(atSign: _atSign);
      expect(fresh.ids[_atSign], 'eid1');
      expect(fresh.credentials[_atSign], Uint8List.fromList([1]));
      expect(persistence.requests, 1);
    });

    test('returns without reading the pointer when the device remembers',
        () async {
      final session = await custody().open(atSign: _atSign);
      expect(session.client.enrollmentId, 'eid1');
      expect(server.pointerReads, 0);
      expect(hints.ids[_atSign], 'eid1');
      expect(persistence.requests, 1);
    });

    test('narrows the assertion to the remembered credential', () async {
      authenticator.gets = 0;
      final session = await custody().open(atSign: _atSign);
      expect(session.client.enrollmentId, 'eid1');
      expect(hints.credentials[_atSign], Uint8List.fromList([1]));
      expect(authenticator.lastAllowCredential, Uint8List.fromList([1]));
    });

    group('stale hints', () {
      FakeHints remembering(int credential, String enrollmentId) => FakeHints()
        ..credentials[_atSign] = Uint8List.fromList([credential])
        ..ids[_atSign] = enrollmentId;

      test('a deleted passkey is replaced by any discoverable one', () async {
        final stale = remembering(9, 'eid1');
        authenticator.gets = 0;
        setupLock.names.clear();
        final session = await custody(withHints: stale).open(atSign: _atSign);
        expect(session.client.enrollmentId, 'eid1');
        expect(authenticator.gets, 2);
        expect(authenticator.lastAllowCredential, isNull);
        expect(stale.credentials[_atSign], Uint8List.fromList([1]));
        expect(stale.ids[_atSign], 'eid1');
        expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
      });

      test('a replaced enrollment is found again through the pointer',
          () async {
        server.revoked.add('eid-old');
        final stale = remembering(1, 'eid-old');
        authenticator.gets = 0;
        final session = await custody(withHints: stale).open(atSign: _atSign);
        expect(session.client.enrollmentId, 'eid1');
        expect(authenticator.gets, 2);
        expect(server.pointerReads, 1);
        expect(stale.ids[_atSign], 'eid1');
        expect(stale.credentials[_atSign], Uint8List.fromList([1]));
      });

      test('the retry happens once, then the passkey is lost', () async {
        authenticator.yieldsNoCredential = true;
        authenticator.gets = 0;
        await expectLater(
            custody(withHints: remembering(1, 'eid1')).open(atSign: _atSign),
            throwsA(isA<PasskeyLostException>()));
        expect(authenticator.gets, 2);
      });

      test('a refused PKAM is retried once, then it is lost', () async {
        server.revoked.addAll(['eid-old', 'eid1']);
        authenticator.gets = 0;
        await expectLater(
            custody(withHints: remembering(1, 'eid-old')).open(atSign: _atSign),
            throwsA(isA<PasskeyLostException>()));
        expect(authenticator.gets, 2);
      });

      test(
          'hints saved while the open waits for the setup lock are retried '
          'without them when the atServer refuses their enrollment', () async {
        server.revoked.add('eid-old');
        final saved = FakeHints();
        final release = Completer<void>();
        final other =
            setupLock.run(setupLockName(_lockPrefix, _atSign), () async {
          await release.future;
          saved
            ..credentials[_atSign] = Uint8List.fromList([1])
            ..ids[_atSign] = 'eid-old';
        });
        authenticator.gets = 0;
        setupLock.names.clear();

        final opening = custody(withHints: saved).open(atSign: _atSign);
        while (setupLock.names.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        release.complete();
        await other;
        final session = await opening;

        expect(session.client.enrollmentId, 'eid1');
        expect(authenticator.gets, 2,
            reason: 'one ceremony with the saved hints, one without');
        expect(saved.ids[_atSign], 'eid1');
      });

      test('a credential id alone counts as no hints', () async {
        final half = FakeHints()
          ..credentials[_atSign] = Uint8List.fromList([1]);
        authenticator.gets = 0;
        setupLock.names.clear();
        await custody(withHints: half).open(atSign: _atSign);
        expect(authenticator.gets, 1);
        expect(authenticator.lastAllowCredential, isNull);
        expect(server.pointerReads, 1);
        expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
        expect(half.ids[_atSign], 'eid1');
      });

      test('an enrollment id alone counts as no hints', () async {
        final half = FakeHints()..ids[_atSign] = 'eid1';
        authenticator.gets = 0;
        setupLock.names.clear();
        await custody(withHints: half).open(atSign: _atSign);
        expect(authenticator.gets, 1);
        expect(authenticator.lastAllowCredential, isNull);
        expect(server.pointerReads, 1);
        expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
        expect(half.credentials[_atSign], Uint8List.fromList([1]));
      });
    });

    group('remembering', () {
      test('a combined store receives both ids in one write', () async {
        final combined = FakeHints();
        await custody(withHints: combined).open(atSign: _atSign);
        expect(combined.pairWrites, 1);
        expect(combined.singleWrites, 0);
      });

      test('separate stores receive one write each', () async {
        final separate = LegacyHints();
        await custody(withHints: separate).open(atSign: _atSign);
        expect(separate.singleWrites, 2);
        expect(separate.ids[_atSign], 'eid1');
        expect(separate.credentials[_atSign], Uint8List.fromList([1]));
      });

      test(
          'a failed combined write leaves neither id, and the open asks for '
          'persistence and returns its session', () async {
        final combined = FakeHints()..failPairWrites = true;
        final session =
            await custody(withHints: combined).open(atSign: _atSign);
        expect(session.client.enrollmentId, 'eid1');
        expect(combined.credentials, isEmpty);
        expect(combined.ids, isEmpty);
        expect(persistence.requests, 1,
            reason: 'a dropped hint write still asks for persistence');
      });

      test(
          'separate stores whose first put fails keep neither id, and the '
          'open returns its session', () async {
        final separate = LegacyHints()..failWrites = true;
        final session =
            await custody(withHints: separate).open(atSign: _atSign);
        expect(session.client.enrollmentId, 'eid1');
        expect(separate.credentials, isEmpty);
        expect(separate.ids, isEmpty);
      });

      test(
          'separate stores whose second put fails leave a new credential id '
          'beside the old enrollment id, and the next login replaces both',
          () async {
        server.revoked.add('eid-old');
        final separate = LegacyHints()
          ..credentials[_atSign] = Uint8List.fromList([9])
          ..ids[_atSign] = 'eid-old'
          ..failEnrollmentIdWrites = true;

        final first = await custody(withHints: separate).open(atSign: _atSign);

        expect(first.client.enrollmentId, 'eid1');
        expect(separate.credentials[_atSign], Uint8List.fromList([1]),
            reason: 'the first put landed');
        expect(separate.ids[_atSign], 'eid-old',
            reason: 'the second put did not');
        separate.failEnrollmentIdWrites = false;
        gateway.authenticated.clear();

        final second = await custody(withHints: separate).open(atSign: _atSign);

        expect(gateway.authenticated, ['eid-old', 'eid1'],
            reason: 'PKAM refuses the mixed pair, and the retry without hints '
                'reads the pointer');
        expect(second.client.enrollmentId, 'eid1');
        expect(separate.ids[_atSign], 'eid1');
        expect(separate.credentials[_atSign], Uint8List.fromList([1]));
      });
    });

    test('a failing persist request does not fail the open', () async {
      persistence.error = StateError('denied');
      expect(
          (await custody().open(atSign: _atSign)).client.enrollmentId, 'eid1');
    });

    test('recovery without a pointer is a lost passkey', () async {
      server.pointers.clear();
      await expectLater(
          custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', _atSign)));
    });

    test('an enrollment with no @keys document is typed and opens no client',
        () async {
      server.documents.clear();
      await expectLater(
          custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<MissingAtKeysDocumentException>()
              .having((e) => e.enrollmentId, 'enrollmentId', 'eid1')));
      final session = gateway.lastSession!;
      expect(session.clients, isEmpty);
      expect(session.closed, isTrue);
    });

    test('open reads the document once, the client start included', () async {
      server.documentReads = 0;

      await custody(withHints: FakeHints()).open(atSign: _atSign);
      // What a client does as it starts: read its keys through the store.
      final restored = await gateway.lastSession!.keysIos.last.read(_atSign);

      expect(server.documentReads, 1);
      expect(restored.toJson()['aesEncryptPrivateKey'], fakeEncryptPrivateKey);
    });

    test('a client reading its keys again reads no document', () async {
      await custody(withHints: FakeHints()).open(atSign: _atSign);
      final io = gateway.lastSession!.keysIos.last;
      await io.read(_atSign);
      server.documentReads = 0;

      await io.read(_atSign);

      expect(server.documentReads, 0);
    });

    test('open with hints takes no setup lock', () async {
      final locked = FakeSetupLock();
      setupLock = locked;
      await custody().open(atSign: _atSign);
      expect(locked.names, isEmpty);
    });

    test('open without hints waits for another tab\'s onboarding', () async {
      final locked = FakeSetupLock();
      setupLock = locked;
      final gate = Completer<void>();
      gateway.gate = gate;
      final onboarding = custody().onboard(atSign: '@bob', cram: 'cram');
      await pumpEventQueue();
      expect(locked.held, {'$_lockPrefix:@bob'});

      final getsBefore = authenticator.gets;
      var opened = false;
      final opening = custody(withHints: FakeHints())
          .open(atSign: '@bob')
          .whenComplete(() => opened = true);
      await pumpEventQueue();
      expect(opened, isFalse);
      expect(authenticator.gets, getsBefore);
      expect(server.pointerReads, 0);

      gate.complete();
      final first = await onboarding;
      final second = await opening;

      expect(second.client.enrollmentId, first.client.enrollmentId);
      expect(locked.names, ['$_lockPrefix:@bob', '$_lockPrefix:@bob']);
    });

    test('open without hints uses the hints onboarding wrote meanwhile',
        () async {
      final gate = Completer<void>();
      gateway.gate = gate;
      final onboarding = custody().onboard(atSign: '@bob', cram: 'cram');
      await pumpEventQueue();
      final opening = custody().open(atSign: '@bob');
      await pumpEventQueue();

      gate.complete();
      await onboarding;
      await opening;

      expect(authenticator.lastAllowCredential, isNotNull);
      expect(server.pointerReads, 0);
    });

    test('a ceremony that returns no credential is a lost passkey', () async {
      authenticator.yieldsNoCredential = true;
      await expectLater(
          custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', _atSign)));
      expect(server.pointerReads, 0);
    });

    test('a non-canonical atSign is reported canonical', () async {
      authenticator.yieldsNoCredential = true;
      await expectLater(
          custody(withHints: FakeHints()).open(atSign: '@Alice'),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', _atSign)));
    });

    test('a swapped pointer is refused by PKAM before any document read',
        () async {
      final keys = await keysOf(0);
      server.pointers[keys.lookupHex] = await keys.vault
          .seal(PasskeyRecordType.eid, {'enrollmentId': 'eid9'});
      server.documentReads = 0;
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(server.documentReads, 0);
    });

    test(
        'a remembered enrollment id that is malformed counts as no hints and '
        'is never sent', () async {
      final bad = FakeHints()
        ..credentials[_atSign] = Uint8List.fromList([1])
        ..ids[_atSign] = 'bad id/..';
      authenticator.gets = 0;
      setupLock.names.clear();

      final session = await custody(withHints: bad).open(atSign: _atSign);

      expect(gateway.authenticated, ['eid1'],
          reason: 'only the pointed enrollment is authenticated');
      expect(authenticator.gets, 1);
      expect(authenticator.lastAllowCredential, isNull);
      expect(server.pointerReads, 1);
      expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
      expect(session.client.enrollmentId, 'eid1');
      expect(bad.ids[_atSign], 'eid1');
    });

    test(
        'a failed read of the remembered credential id counts as no hints, '
        'and the enrollment id is not read', () async {
      final device = FakeHints()
        ..credentials[_atSign] = Uint8List.fromList([1])
        ..ids[_atSign] = 'eid1'
        ..credentialIdReadFailure =
            HintStoreException('cannot read the credential id')
        ..enrollmentIdReadFailure =
            HintStoreException('cannot read the enrollment id');
      authenticator.gets = 0;
      logs.records.clear();

      final session = await custody(withHints: device).open(atSign: _atSign);

      expect(authenticator.gets, 1);
      expect(authenticator.lastAllowCredential, isNull,
          reason: 'the login asserts any passkey');
      expect(server.pointerReads, 1,
          reason: "the login reads the passkey's pointer");
      expect(gateway.authenticated, ['eid1'],
          reason: 'only the pointed enrollment is authenticated');
      expect(session.client.enrollmentId, 'eid1');
      final warned = logs
          .at('WARNING')
          .where((m) => m.contains('could not be read'))
          .toList();
      expect(warned, hasLength(1),
          reason: 'only the credential id read warns: the enrollment id, '
              'whose read would also fail, is not read');
      expect(
          warned.single,
          allOf(contains(_atSign), contains('remembered credential id'),
              contains('HintStoreException')));
      expect(warned.single, isNot(contains('cannot read')),
          reason: "the warning carries no exception's message");
    });

    for (final (read, breakRead)
        in <(String, void Function(LegacyHints, Object))>[
      ('credential id', (hints, e) => hints.credentialIdReadFailure = e),
      ('enrollment id', (hints, e) => hints.enrollmentIdReadFailure = e),
    ]) {
      test(
          'an Error reading the remembered $read fails the login before any '
          'prompt and opens nothing', () async {
        final broken = StateError('the hint store is broken');
        final device = FakeHints()
          ..credentials[_atSign] = Uint8List.fromList([1])
          ..ids[_atSign] = 'eid1';
        breakRead(device, broken);
        authenticator
          ..gets = 0
          ..issuedPrf.clear();
        final sessionBefore = gateway.lastSession;

        await expectLater(custody(withHints: device).open(atSign: _atSign),
            throwsA(same(broken)));

        expect(authenticator.gets, 0, reason: 'no passkey prompt');
        expect(authenticator.issuedPrf, isEmpty, reason: 'no PRF output');
        expect(gateway.authenticated, isEmpty, reason: 'no PKAM');
        expect(gateway.lastSession, same(sessionBefore),
            reason: 'no enrollment session');
        expect(setupLock.held, isEmpty);
        expect(device.ids, {_atSign: 'eid1'},
            reason: 'the hints are left as they were');
        expect(device.credentials[_atSign], [1]);
      });
    }

    for (final (read, breakRead) in <(String, void Function(LegacyHints))>[
      (
        'credential id',
        (hints) => hints.credentialIdReadFailure =
            HintStoreException('cannot read the credential id')
      ),
      (
        'enrollment id',
        (hints) => hints.enrollmentIdReadFailure =
            HintStoreException('cannot read the enrollment id')
      ),
    ]) {
      test(
          'a read of the remembered $read that fails before the setup lock '
          'and not under it uses the hints, and warns of nothing', () async {
        breakRead(hints..readFailuresOnce = true);
        authenticator.gets = 0;
        setupLock.names.clear();
        logs.records.clear();

        final session = await custody().open(atSign: _atSign);

        expect(hints.credentialIdReadFailure ?? hints.enrollmentIdReadFailure,
            isNull,
            reason: 'the control: the first read failed');
        expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)],
            reason: 'the failed read sent the open under the setup lock');
        expect(authenticator.gets, 1);
        expect(authenticator.lastAllowCredential, Uint8List.fromList([1]),
            reason: 'the ceremony is narrowed to the remembered credential');
        expect(server.pointerReads, 0, reason: 'no pointer is read');
        expect(gateway.authenticated, ['eid1'],
            reason: 'PKAM is for the remembered enrollment');
        expect(session.client.enrollmentId, 'eid1');
        expect(logs.at('WARNING').where((m) => m.contains('could not be read')),
            isEmpty,
            reason: 'only the read under the setup lock warns, and it read '
                'the hints');
      });
    }

    test('a pointed enrollment id that is malformed is refused before PKAM',
        () async {
      final keys = await keysOf(0);
      server.pointers[keys.lookupHex] = await keys.vault
          .seal(PasskeyRecordType.eid, {'enrollmentId': 'bad id/..'});
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(gateway.authenticated, isEmpty);
    });

    test('a revoked enrollment is a lost passkey whose cause needs an approver',
        () async {
      server.revoked.add('eid1');
      final fresh = FakeHints();
      await expectLater(
          custody(withHints: fresh).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', _atSign)
              .having((e) => e.cause, 'cause', isA<PkamRefusedException>())
              .having((e) => e.cause.toString(), 'cause message',
                  contains('approver'))));
      expect(fresh.ids, isEmpty);
    });

    test('a revoked enrollment never reaches activate or the pointer',
        () async {
      server.revoked.add('eid1');
      final pointers = {...server.pointers};
      final log = [...server.log];
      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(gateway.activated, hasLength(1));
      expect(server.log, log);
      expect(server.pointers, pointers);
      expect(server.enrollments, 1);
    });

    test('restored keys that do not match the published ones throw before use',
        () async {
      server.publishedTag = 'v2';
      final fresh = FakeHints();
      final built = stores.length;
      await expectLater(custody(withHints: fresh).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));
      expect(gateway.lastSession!.closed, isTrue);
      expect(fresh.ids, isEmpty);
      expect(persistence.requests, 0);
      expectStoresClosed(from: built);
    });

    group('a document rolled back in', () {
      Future<void> expectRefused(Map<String, dynamic> rolledBack) async {
        server.keys = {...server.keys, ...rolledBack};
        await custody().onboard(atSign: '@bob', cram: 'cram');
        final fresh = FakeHints();
        await expectLater(custody(withHints: fresh).open(atSign: '@bob'),
            throwsA(isA<PublicKeyMismatchException>()));
        expect(gateway.lastSession!.closed, isTrue);
        expect(fresh.ids, isEmpty);
      }

      test('the flat APKAM public key is refused', () async {
        await expectRefused({'aesPkamPublicKey': 'cm9sbGVkLWJhY2s='});
      });

      test('the encryption public key is refused', () async {
        await custody().onboard(atSign: '@bob', cram: 'cram');
        server.publishedTag = 'v2';
        await expectLater(custody(withHints: FakeHints()).open(atSign: '@bob'),
            throwsA(isA<PublicKeyMismatchException>()));
      });

      test('the enrollment\'s own derived APKAM public key is accepted',
          () async {
        final session =
            await custody(withHints: FakeHints()).open(atSign: _atSign);
        expect(session.client.enrollmentId, 'eid1');
      });
    });
  });

  group('second passkey', () {
    test(
        'a second passkey derives different keys, so it cannot open the '
        'first passkey\'s records', () async {
      final first = await custody().onboard(atSign: _atSign, cram: 'cram');
      server.cramDeleted.remove(_atSign);
      final second = await custody(withHints: FakeHints())
          .onboard(atSign: _atSign, cram: 'cram');
      final firstKeys = await keysOf(0);
      final secondKeys = await keysOf(1);

      expect(authenticator.prfByCredential, hasLength(2));
      expect(second.client.enrollmentId, isNot(first.client.enrollmentId));
      expect(gateway.activated, hasLength(2));
      expect(gateway.activated[1].apkamKeyPair.publicKey,
          isNot(gateway.activated[0].apkamKeyPair.publicKey));
      expect(secondKeys.authSeed, isNot(firstKeys.authSeed));
      expect(secondKeys.lookupHex, isNot(firstKeys.lookupHex));
      expect(server.pointers.keys,
          unorderedEquals([firstKeys.lookupHex, secondKeys.lookupHex]));

      expect(server.pairByEnrollment[first.client.enrollmentId],
          (await apkamKeyPairFromSeed(firstKeys.authSeed)).publicKey,
          reason: "the first enrollment holds the first passkey's pair");
      expect(server.pairByEnrollment[second.client.enrollmentId],
          (await apkamKeyPairFromSeed(secondKeys.authSeed)).publicKey,
          reason: "the second enrollment holds the second passkey's pair");
      expect(server.revoked, contains(first.client.enrollmentId),
          reason: 'the second onboarding revoked the first enrollment, so the '
              'pairs are compared on the second, live one');
      await expectLater(
          gateway.authenticate(
              atSign: _atSign,
              enrollmentId: second.client.enrollmentId!,
              apkamKeyPair: await apkamKeyPairFromSeed(firstKeys.authSeed)),
          throwsA(isA<PkamRefusedException>()));
      expect(
          (await gateway.authenticate(
                  atSign: _atSign,
                  enrollmentId: second.client.enrollmentId!,
                  apkamKeyPair:
                      await apkamKeyPairFromSeed(secondKeys.authSeed)))
              .enrollmentId,
          second.client.enrollmentId);
      await expectLater(
          secondKeys.vault.open(PasskeyRecordType.atkeys,
              server.documents[first.client.enrollmentId]!),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
      await expectLater(
          secondKeys.vault.open(
              PasskeyRecordType.eid, server.pointers[firstKeys.lookupHex]!),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
    });
  });

  group('a failed open', () {
    final openError = StateError('open failed');

    test('onboard rethrows it, keeps the hints and leaves login possible',
        () async {
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(openError)));
      expect(hints.ids[_atSign], 'eid1');
      expect(hints.credentials[_atSign], isNotNull);
      expect(gateway.lastSession!.closed, isTrue);

      gateway.openErrorForNext = null;
      final session = await custody().open(atSign: _atSign);
      expect(session.client.enrollmentId, 'eid1');
    });

    test('onboard closes the session and the store when no client was built',
        () async {
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(openError)));
      final session = gateway.lastSession!;
      expect(session.closeCalls, 1);
      expectStoresClosed();
      await expectLater(
          Future.sync(() => session.keysIos.single.read(_atSign)),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('closed'))));
    });

    test('login rethrows it when closing the session after a stop fails',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      gateway.openErrorForNext = openError;
      gateway.closeErrorForNext = StateError('already closed');
      gateway.openStopsFirstForNext = true;
      await expectLater(
          custody().open(atSign: _atSign), throwsA(same(openError)));
      expect(gateway.lastSession!.closed, isTrue);
    });

    test('a failing close of the session is logged at severe', () async {
      logs.records.clear();
      await custody().onboard(atSign: _atSign, cram: 'cram');
      gateway.openErrorForNext = openError;
      gateway.closeErrorForNext = StateError('already closed');
      gateway.openStopsFirstForNext = true;
      await expectLater(
          custody().open(atSign: _atSign), throwsA(same(openError)));
      final lines = logs.at('SEVERE').where((m) => m.contains('StateError'));
      expect(lines, hasLength(1));
      expect(lines.single, contains('eid1'));
      expect(lines.single, isNot(contains('already closed')));
    });
  });

  group('the client persists its keys', () {
    Future<void> expectPersists(FakeAtClient client) async {
      expect(client.keysIo, isA<AtServerAtKeysIo>());
      final before = server.documents['eid1']!;
      final keys = await client.keysIo.read(_atSign);
      keys.fileLegacyMaterial(apkamSymmetricKey: 'client-symmetric');
      await client.keysIo.flush(_atSign.toAtsign(), keys);
      expect(server.documents['eid1'], isNot(before), reason: 're-sealed');
      final back = await client.keysIo.read(_atSign);
      expect(back.enrollmentSymmetricKey, isNotNull);
      expect(
          back.enrollmentToAuthenticateAs(), keys.enrollmentToAuthenticateAs());
    }

    test('onboard returns a client over an AtServerAtKeysIo', () async {
      final session = await custody().onboard(atSign: _atSign, cram: 'cram');
      await expectPersists(session.client as FakeAtClient);
      await session.stop();
    });

    test('open returns a client over an AtServerAtKeysIo', () async {
      await (await custody().onboard(atSign: _atSign, cram: 'cram')).stop();
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      await expectPersists(session.client as FakeAtClient);
      await session.stop();
    });
  });
}
