import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys, AtKeysFileOverwriteException;
import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, InvalidAtSignException;
import 'package:at_client/at_client.dart'
    show AtClientPreference, buildAtClient;
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_commons/atsign.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
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
      setupLockPrefix: _lockPrefix);

  Future<DerivedKeys> keysOf(int credential) async {
    final prf = Uint8List.fromList(List.generate(32, (i) => i + credential));
    return DerivedKeys.derive(prf, _atSign);
  }

  void reset() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    persistence = FakePersistence(server.timeline);
    setupLock = FakeSetupLock();
  }

  setUp(reset);

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

    test('a failed remember comes after the CRAM secret is deleted', () async {
      hints.failWrites = true;
      await failure();
      expect(server.cramDeleted, {_atSign});
      expect(gateway.lastSession!.closed, isTrue);
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
        'after its encryption public key was published': () =>
            gateway.onAuthenticate = (session) =>
                session.completeErrorAfterPublish = StateError('interrupted'),
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

      final steps = server.timeline;
      expect(steps, contains('revoke:eid1'));
      expect(steps.indexOf('revoke:eid1'),
          lessThan(steps.indexOf('cram-deleted')));
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

    test('a failed revoke ends the onboarding before the completion', () async {
      gateway.onAuthenticate =
          (session) => session.revokeError = StateError('revoke failed');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(gateway.lastSession!.completed, isEmpty);
      expect(server.cramDeleted, isEmpty);
      expect(authenticator.signalled, hasLength(1));
    });

    test(
        'A login that finishes an onboarding whose revoke failed revokes the '
        'other enrollments before deleting the CRAM secret', () async {
      server.documentPutFailures = 99;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      server.documentPutFailures = 0;
      gateway.onAuthenticate =
          (session) => session.revokeError = StateError('revoke failed');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      gateway.onAuthenticate = null;
      expect(server.approved, {'eid1': _atSign, 'eid2': _atSign});

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(session.client.enrollmentId, 'eid2');
      expect(server.approved, {'eid2': _atSign});
      final steps = server.timeline;
      expect(steps.indexOf('revoke:eid1'),
          inInclusiveRange(0, steps.indexOf('cram-deleted')));
    });

    test(
        'a login that cannot revoke the other enrollments keeps the CRAM '
        'secret', () async {
      gateway.onAuthenticate =
          (session) => session.revokeError = StateError('revoke failed');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);

      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsStateError);

      expect(gateway.lastSession!.completed, isEmpty);
      expect(server.cramDeleted, isEmpty);
    });

    test(
        'The retry publishes its own encryption public key over an '
        'interrupted attempt\'s', () async {
      gateway.onAuthenticate = (session) =>
          session.completeErrorAfterPublish = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
      gateway.onAuthenticate = null;

      await custody().onboard(atSign: _atSign, cram: 'cram');

      expect(server.publishedKey, encryptionPublicKeyOf('eid2'));
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
      gateway.onAuthenticate = (session) =>
          session.completeErrorAfterPublish = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
      expect(server.cramDeleted, isEmpty);
      gateway.onAuthenticate = null;

      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);

      expect(server.cramDeleted, {_atSign},
          reason: 'the login deletes the CRAM secret');
      expect(gateway.lastSession!.completed.single, isEmpty,
          reason: 'the published key is the document\'s, so only the CRAM '
              'secret is deleted');
      expect(server.publishedKey, encryptionPublicKeyOf('eid1'));
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
      expect(gateway.lastSession!.completed.single,
          {'aesEncryptPublicKey': encryptionPublicKeyOf('eid1')});
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
      gateway.onAuthenticate = null;

      await custody(withHints: fresh).open(atSign: _atSign);

      expect(server.cramDeleted, {_atSign});
      expect(fresh.ids, {_atSign: 'eid1'});
    });

    test(
        'a login that finds another encryption public key published is '
        'refused and completes nothing', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      server.publishedKey = 'cm90YXRlZA==';

      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(gateway.lastSession!.completed, isEmpty);
      expect(gateway.lastSession!.closed, isTrue);
      expect(server.publishedKey, 'cm90YXRlZA==');
    });

    test('A login with saved hints sends no activation completion', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(hints.ids, {_atSign: 'eid1'},
          reason: 'the control: the onboarding saved its hints');
      expect(server.timeline.where((step) => step == 'complete-activation'),
          hasLength(1),
          reason: 'the control: the onboarding completed the activation');

      final session = await custody().open(atSign: _atSign);

      expect(gateway.authenticated, ['eid1'],
          reason: 'the login authenticated the saved enrollment');
      expect(gateway.lastSession!.completed, isEmpty,
          reason: 'a login with saved hints sends no activation completion');
      expect(server.timeline.where((step) => step == 'complete-activation'),
          hasLength(1));
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
        for (final fail in <void Function()>[
          () => gateway.onAuthenticate =
              (session) => session.completeError = StateError('lost'),
          () => gateway.onAuthenticate = (session) =>
              session.completeErrorAfterPublish = StateError('lost'),
        ]) {
          reset();
          fail();
          await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
              throwsStateError);
          expect(authenticator.signalled, isEmpty);
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
    test('closes the session when remembering the device fails', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final fresh = FakeHints()..failWrites = true;
      await expectLater(
          custody(withHints: fresh).open(atSign: _atSign), throwsStateError);
      expect(gateway.lastSession!.closed, isTrue);
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

      test('a failed combined write leaves neither id', () async {
        final combined = FakeHints()..failPairWrites = true;
        await expectLater(custody(withHints: combined).open(atSign: _atSign),
            throwsStateError);
        expect(combined.credentials, isEmpty);
        expect(combined.ids, isEmpty);
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

    test('a remembered enrollment id that is malformed is refused before PKAM',
        () async {
      final bad = FakeHints()
        ..credentials[_atSign] = Uint8List.fromList([1])
        ..ids[_atSign] = 'bad id/..';
      await expectLater(custody(withHints: bad).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(gateway.authenticated, isEmpty);
    });

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
      await expectLater(custody(withHints: fresh).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));
      expect(gateway.lastSession!.closed, isTrue);
      expect(fresh.ids, isEmpty);
      expect(persistence.requests, 0);
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

      // NOTE: the second onboarding revoked the first enrollment; it is
      // approved again so that only the keys decide the PKAM below.
      final firstEid = first.client.enrollmentId!;
      server.revoked.remove(firstEid);
      server.approved[firstEid] = _atSign;
      await gateway.authenticate(
          atSign: _atSign,
          enrollmentId: firstEid,
          apkamKeyPair: await apkamKeyPairFromSeed(firstKeys.authSeed));
      await expectLater(
          gateway.authenticate(
              atSign: _atSign,
              enrollmentId: firstEid,
              apkamKeyPair: await apkamKeyPairFromSeed(secondKeys.authSeed)),
          throwsA(isA<PkamRefusedException>()));
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
