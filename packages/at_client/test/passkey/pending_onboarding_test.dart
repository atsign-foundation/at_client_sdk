import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys, AtKeysFileOverwriteException;
import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/at_keys_document.dart';
import 'package:at_commons/at_commons.dart'
    show AtException, UnAuthenticatedException;
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../test_utils/recorded_logs.dart';

const _atSign = '@alice';
const _lockPrefix = 'test:setup';

/// A pending store whose first [get] answers null and later ones answer
/// [later], as a record written by another tab between two reads.
class _LateRecordStore extends FakePendingStore {
  _LateRecordStore(this.later);
  final PendingOnboardingRecord later;
  var reads = 0;
  var deletes = 0;

  @override
  Future<PendingOnboardingRecord?> get(String atSign) async =>
      reads++ == 0 ? null : later;

  @override
  Future<void> delete(String atSign) async {
    deletes++;
  }
}

/// A setup lock that is never granted, as one whose acquisition timed out.
class _TimedOutLock implements SetupLock {
  @override
  Future<T> run<T>(String name, Future<T> Function() body) =>
      Future.error(_LockTimeout(name));
}

class _LockTimeout extends AtException {
  _LockTimeout(String name) : super('$name was not granted');
}

void main() {
  final logs = RecordedLogs();
  setUpAll(logs.installOn);
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late FakePersistence persistence;
  late FakePendingStore pending;
  late FakeSetupLock setupLock;

  PasskeyCustody custody() => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      deriver: const BytesPasskeyKeyDeriver(),
      pointerReader: server,
      gateway: gateway,
      credentials: hints,
      enrollmentIds: hints,
      persistence: persistence,
      pendingStore: pending,
      retryDelay: Duration.zero,
      setupLock: setupLock,
      setupLockPrefix: _lockPrefix);

  Future<DerivedKeys> keysOf(int credential) async => DerivedKeys.derive(
      Uint8List.fromList(List.generate(32, (i) => i + credential)), _atSign);

  /// An onboarding whose process dies once the CRAM is spent.
  Future<void> dieAfterActivation() async {
    gateway.onActivate = () => throw StateError('tab died');
    await expectLater(
        custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
    gateway.onActivate = null;
  }

  Future<Map<String, dynamic>> sealedRecord() async {
    final record = pending.records[_atSign]!;
    return (await keysOf(0))
        .vault
        .open(PasskeyRecordType.pending, record.sealed);
  }

  /// A pending record the first passkey seals for an enrollment the atServer
  /// has never seen, so resuming it is refused PKAM.
  Future<PendingOnboardingRecord> refusedRecord() async {
    final sealed = await (await keysOf(0)).vault.seal(
        PasskeyRecordType.pending, {
      'enrollmentId': 'eid9',
      'atKeys': gateway.keysFor(_atSign, 'eid9').toJson()
    });
    return PendingOnboardingRecord(
        credentialId: Uint8List.fromList([1]),
        enrollmentId: 'eid9',
        encryptionPublicKey: 'other-key',
        sealed: sealed);
  }

  setUp(() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    persistence = FakePersistence(server.timeline);
    pending = FakePendingStore(server.timeline);
    setupLock = FakeSetupLock();
  });

  group('onboard journals the minted keys', () {
    test('the record is durable before the CRAM is spent', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(server.timeline.indexOf('put-pending'),
          lessThan(server.timeline.indexOf('cram-spent')));
    });

    test('persistence is requested before the activation', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(server.timeline.indexOf('request-persist'),
          lessThan(server.timeline.indexOf('put-pending')));
    });

    test('the record holds the enrollment and the minted keys, no APKAM key',
        () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      final sealed = await sealedRecord();
      expect(record.enrollmentId, 'eid1');
      expect(record.credentialId, Uint8List.fromList([1]));
      expect(sealed['enrollmentId'], 'eid1');
      final atKeys = sealed['atKeys'] as Map<String, dynamic>;
      expect(record.encryptionPublicKey, atKeys['aesEncryptPublicKey']);
      final text = jsonEncode(atKeys);
      expect(text, contains(base64Encode(utf8.encode('enc-priv-eid1'))));
      expect(
          text, isNot(contains(base64Encode(utf8.encode('apkam-priv-eid1')))));
    });

    test('the record is opaque outside the vault', () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      expect(record.sealed, isNot(contains('enc-priv')));
      await expectLater(
          (await keysOf(0)).vault.open(PasskeyRecordType.atkeys, record.sealed),
          throwsA(isA<UnsupportedPasskeyRecordException>()));
    });

    test('a record that cannot be sealed stops the activation before the CRAM',
        () async {
      pending.failPuts = true;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(server.timeline, isNot(contains('cram-spent')));
    });

    test('the record is deleted last, after the client opens', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final order = server.timeline;
      final deleted = order.indexOf('delete-pending');
      expect(deleted, greaterThan(order.indexOf('put-document:eid1')));
      expect(deleted, greaterThan(order.indexOf('put-pointer')));
      expect(deleted, greaterThan(order.indexOf('open-client')));
      expect(hints.ids[_atSign], 'eid1');
      expect(pending.records, isEmpty);
    });

    test('a failed document write keeps the record', () async {
      server.documentPutFailures = 99;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(isA<OnboardingIncompleteException>()));
      expect(pending.records, contains(_atSign));
    });

    test('a record another enrollment replaced meanwhile survives the open',
        () async {
      final other = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([2]),
          enrollmentId: 'eid-other',
          sealed: 'sealed-other');
      gateway.onAuthenticate = (session) =>
          session.onOpenClient = () => pending.records[_atSign] = other;
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(pending.records[_atSign], same(other));
    });

    test('abandon keeps the record', () async {
      server.documentPutFailures = 99;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        await e.pending.abandon();
      }
      expect(pending.records, contains(_atSign));
    });
  });

  group('T7 the unfinished activation hands its keys over once', () {
    test('after onboard takes them the exception no longer holds them',
        () async {
      gateway.activationUnfinished = true;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(isA<OnboardingIncompleteException>()));
      expect(gateway.unfinished!.takeAtKeys, throwsStateError);
    });
  });

  group('T4 recovery with no pending record', () {
    test('document, pointer and hints on the atServer: open succeeds',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      pending.records.clear();
      hints.ids.clear();
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(authenticator.creates, 1);
      expect(gateway.activated, hasLength(1));
    });
  });

  group('T5 a failed open keeps the record', () {
    final openError = StateError('open failed');

    // The keys the session reports are the ones the activation journalled, as
    // on a real atServer, so the retry's document is the published one.
    setUp(() => server.keys = {
          ...atKeysDocument(gateway.keysFor(_atSign, 'eid1'), _atSign),
          'publicTag': 'v1'
        });

    Future<void> expectPublishedAndKept() async {
      expect(pending.records, contains(_atSign));
      expect(server.documents, contains('eid1'));
      expect(server.pointers, contains((await keysOf(0)).lookupHex));
      expect(hints.ids[_atSign], 'eid1');
    }

    test('onboard: the retry resumes it with no new passkey and no CRAM',
        () async {
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(openError)));
      await expectPublishedAndKept();

      gateway.openErrorForNext = null;
      final client = await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(client.enrollmentId, 'eid1');
      expect(authenticator.creates, 1);
      expect(gateway.activated.map((a) => a.cram), ['cram']);
      expect(pending.records, isEmpty);
    });

    test('open: the retry resumes it with no new passkey and no CRAM',
        () async {
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(openError)));
      await expectPublishedAndKept();

      gateway.openErrorForNext = null;
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(authenticator.creates, 1);
      expect(gateway.activated, hasLength(1));
      expect(pending.records, isEmpty);
    });

    test('a resumed record whose open fails stays for the next try', () async {
      await dieAfterActivation();
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(same(openError)));
      await expectPublishedAndKept();

      gateway.openErrorForNext = null;
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(pending.records, isEmpty);
    });

    test('a login whose open fails keeps the record it proved obsolete',
        () async {
      server.keys['aesEncryptPublicKey'] = base64Encode(utf8.encode('pub'));
      final first = await custody().onboard(atSign: _atSign, cram: 'cram');
      final stored = await (first as FakeAtClient).keysIo.read(_atSign);
      final record = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([9]),
          enrollmentId: 'eid1',
          encryptionPublicKey: stored.toJson()['aesEncryptPublicKey'] as String,
          sealed: 'junk');
      pending.records[_atSign] = record;
      gateway.openErrorForNext = openError;
      await expectLater(
          custody().open(atSign: _atSign), throwsA(same(openError)));
      expect(pending.records, contains(_atSign));
    });
  });

  group('onboard with a record', () {
    test('resumes without registering and without the CRAM', () async {
      await dieAfterActivation();
      final client = await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(authenticator.creates, 1);
      expect(gateway.activated.map((a) => a.cram), ['cram']);
      expect(authenticator.lastAllowCredential, Uint8List.fromList([1]));
      expect(client.enrollmentId, 'eid1');
      expect(server.documents, contains('eid1'));
      expect(server.pointers, contains((await keysOf(0)).lookupHex));
      expect(hints.ids[_atSign], 'eid1');
      expect(pending.records, isEmpty);
    });

    test('files the keys the record held', () async {
      await dieAfterActivation();
      final sealed = await sealedRecord();
      await custody().onboard(atSign: _atSign, cram: 'cram2');
      final stored = AtKeys.fromJson(await (await keysOf(0))
          .vault
          .open(PasskeyRecordType.atkeys, server.documents['eid1']!));
      final held = AtKeys.fromJson(sealed['atKeys'] as Map<String, dynamic>);
      // The store drops the enrollment's authentication material; the client
      // gets the derived pair filed on every read instead.
      Map<String, dynamic> legacy(AtKeys k) => k.toJson()
        ..remove('enrollments')
        ..remove('version')
        ..remove('atsign')
        ..remove('keys');
      expect(legacy(stored), legacy(held));
    });

    test('finishes the activation before it files anything', () async {
      await dieAfterActivation();
      await custody().onboard(atSign: _atSign, cram: 'cram2');
      final order = server.timeline;
      expect(order, contains('complete-activation'));
      expect(order.indexOf('complete-activation'),
          lessThan(order.indexOf('put-document:eid1')));
    });

    test('a failed activation finish keeps the record for the next try',
        () async {
      await dieAfterActivation();
      gateway.openErrorForNext = null;
      final sessionFails = StateError('publish failed');
      gateway.onAuthenticate = (s) => s.completeError = sessionFails;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(sessionFails));
      expect(pending.records, contains(_atSign));
      expect(server.documents, isEmpty);
      gateway.onAuthenticate = null;
      await custody().onboard(atSign: _atSign, cram: 'cram3');
      expect(pending.records, isEmpty);
      expect(gateway.activated, hasLength(1));
    });

    test('a document that holds everything the record holds is kept as is',
        () async {
      await dieAfterActivation();
      final keys = await keysOf(0);
      final sealed = await sealedRecord();
      final existing = await keys.vault.seal(PasskeyRecordType.atkeys,
          AtKeys.fromJson(sealed['atKeys'] as Map<String, dynamic>).toJson());
      server.documents['eid1'] = existing;
      await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(server.documents['eid1'], existing);
      expect(pending.records, isEmpty);
      expect(server.pointers, contains(keys.lookupHex));
    });

    test('a document that is not these keys is refused and never overwritten',
        () async {
      await dieAfterActivation();
      final keys = await keysOf(0);
      final other = await keys.vault.seal(
          PasskeyRecordType.atkeys, gateway.keysFor(_atSign, 'other').toJson());
      server.documents['eid1'] = other;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(isA<AtKeysFileOverwriteException>()));
      expect(server.documents['eid1'], other);
      expect(server.pointers, isEmpty);
      expect(pending.records, contains(_atSign));
    });

    test('a record its passkey cannot open is a lost passkey, and stays',
        () async {
      await dieAfterActivation();
      authenticator.prfByCredential.remove(1);
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(isA<PasskeyLostException>()));
      expect(pending.records, contains(_atSign));
      expect(authenticator.creates, 1);
      expect(gateway.activated, hasLength(1));
    });

    test('a record the passkey opens to something else stays', () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      pending.records[_atSign] = PendingOnboardingRecord(
          credentialId: record.credentialId,
          enrollmentId: record.enrollmentId,
          encryptionPublicKey: record.encryptionPublicKey,
          sealed: record.sealed
              .replaceRange(record.sealed.length - 4, null, 'AAAA'));
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(isA<PasskeyLostException>()));
      expect(pending.records, contains(_atSign));
    });
  });

  group('a pending record whose enrollment the atServer refuses PKAM', () {
    test('onboard drops it and carries on with the new CRAM', () async {
      await dieAfterActivation();
      server.revoked.add('eid1');
      final client = await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(gateway.activated.map((a) => a.cram), ['cram', 'cram2']);
      expect(authenticator.creates, 2);
      expect(client.enrollmentId, 'eid2');
      expect(pending.records, isEmpty);
    });

    test(
        'onboard drops a record the atServer no longer knows (expired or '
        'invalid) and carries on with the new CRAM', () async {
      await dieAfterActivation();
      pending.records[_atSign] = await refusedRecord();
      final client = await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(gateway.activated.map((a) => a.cram), ['cram', 'cram2']);
      expect(client.enrollmentId, 'eid2');
      expect(pending.records, isEmpty);
    });

    test('open drops it under the lock and continues the login', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      pending.records[_atSign] = await refusedRecord();
      setupLock.names.clear();
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(setupLock.names, contains('$_lockPrefix:$_atSign'));
      expect(pending.records, isEmpty);
    });

    test('open with nothing else to log in with is the lost passkey', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      hints.ids.clear();
      server.pointers.clear();
      pending.records[_atSign] = await refusedRecord();
      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
    });

    test('open keeps a record whose refused enrollment is not the record\'s',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      // Sealed body names eid9, which the atServer has never seen; the
      // record's own enrollment is another.
      final refused = await refusedRecord();
      final record = PendingOnboardingRecord(
          credentialId: refused.credentialId,
          enrollmentId: 'eid-record',
          encryptionPublicKey: refused.encryptionPublicKey,
          sealed: refused.sealed);
      pending.records[_atSign] = record;
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(pending.records[_atSign], same(record));
    });

    test('a resumed handle reports it as a lost passkey', () async {
      gateway.activationUnfinished = true;
      late OnboardingIncompleteException incomplete;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        incomplete = e;
      }
      server.revoked.add('eid1');
      await expectLater(
          incomplete.pending.resume(),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.cause, 'cause', isA<PkamRefusedException>())));
      expect(pending.records, contains(_atSign));
    });
  });

  group('a pending record that fails to resume for another reason', () {
    test('a transport error keeps it on onboard', () async {
      await dieAfterActivation();
      gateway.authenticateFailures = 1;
      final record = pending.records[_atSign]!;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram2'), throwsStateError);
      expect(pending.records[_atSign], same(record));
      expect(gateway.activated, hasLength(1));
    });

    test('a transport error keeps it on open', () async {
      await dieAfterActivation();
      gateway.authenticateFailures = 1;
      final record = pending.records[_atSign]!;
      await expectLater(custody().open(atSign: _atSign), throwsStateError);
      expect(pending.records[_atSign], same(record));
    });

    test('a cancelled prompt keeps it and is a lost passkey with its cause',
        () async {
      await dieAfterActivation();
      authenticator.yieldsNoCredential = true;
      final record = pending.records[_atSign]!;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram2'),
          throwsA(isA<PasskeyLostException>().having(
              (e) => e.cause, 'cause', isA<PasskeyCeremonyException>())));
      expect(pending.records[_atSign], same(record));
      expect(gateway.activated, hasLength(1));
    });
  });

  group('T-ticket1 a server error or throttle during PKAM is no refusal', () {
    // The contract: only an explicit refusal is a PkamRefusedException; any
    // other failed handshake propagates as at_auth's UnAuthenticatedException,
    // which a caller may retry, and nothing is deleted.
    for (final reply in [
      'error:AT0011-Internal server exception',
      'error:AT0028:throttled',
    ]) {
      final failure = UnAuthenticatedException('Failed connecting to $_atSign. '
          '$reply');
      Matcher raw() => throwsA(allOf(
          same(failure),
          isNot(isA<PkamRefusedException>()),
          isNot(isA<PasskeyLostException>())));

      test('"$reply" keeps the record on a resumed onboard', () async {
        await dieAfterActivation();
        gateway
          ..authenticateFailures = 1
          ..authenticateError = failure;
        final record = pending.records[_atSign]!;
        await expectLater(
            custody().onboard(atSign: _atSign, cram: 'cram2'), raw());
        expect(pending.records[_atSign], same(record));
        expect(gateway.activated, hasLength(1));
        gateway.authenticateError = null;
        expect(
            (await custody().onboard(atSign: _atSign, cram: 'cram3'))
                .enrollmentId,
            'eid1');
      });

      test('"$reply" keeps the record on a resumed open', () async {
        await dieAfterActivation();
        gateway
          ..authenticateFailures = 1
          ..authenticateError = failure;
        final record = pending.records[_atSign]!;
        await expectLater(custody().open(atSign: _atSign), raw());
        expect(pending.records[_atSign], same(record));
      });

      test('"$reply" on a login with hints keeps them and is not retried',
          () async {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        gateway
          ..authenticateFailures = 1
          ..authenticateError = failure;
        await expectLater(custody().open(atSign: _atSign), raw());
        expect(hints.ids[_atSign], 'eid1');
        expect(gateway.authenticated, hasLength(1));
      });

      test('"$reply" on a login through the pointer is not a lost passkey',
          () async {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        hints.ids.clear();
        gateway
          ..authenticateFailures = 1
          ..authenticateError = failure;
        await expectLater(custody().open(atSign: _atSign), raw());
        expect(server.pointers, isNotEmpty);
      });
    }
  });

  group('a setup lock that times out', () {
    Matcher timeout() => throwsA(isA<_LockTimeout>());

    PasskeyCustody timedOutCustody() => PasskeyCustody(
        prf: PasskeyPrf(authenticator),
        deriver: const BytesPasskeyKeyDeriver(),
        pointerReader: server,
        gateway: gateway,
        credentials: hints,
        enrollmentIds: hints,
        persistence: persistence,
        pendingStore: pending,
        retryDelay: Duration.zero,
        setupLock: _TimedOutLock(),
        setupLockPrefix: _lockPrefix);

    test('keeps the pending record when onboard waits for the lock', () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      await expectLater(
          timedOutCustody().onboard(atSign: _atSign, cram: 'cram2'), timeout());
      expect(pending.records[_atSign], same(record));
      expect(gateway.activated, hasLength(1));
    });

    test('keeps the pending record when open waits for the lock', () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      await expectLater(timedOutCustody().open(atSign: _atSign), timeout());
      expect(pending.records[_atSign], same(record));
    });

    test('keeps the pending record when a discard waits for the lock',
        () async {
      await dieAfterActivation();
      final record = pending.records[_atSign]!;
      await expectLater(
          timedOutCustody().discardPendingOnboarding(_atSign), timeout());
      expect(pending.records[_atSign], same(record));
    });
  });

  group('discardPendingOnboarding', () {
    test('removes the record without a ceremony or a server call', () async {
      await dieAfterActivation();
      final gets = authenticator.gets;
      final authenticated = gateway.authenticated.length;
      await custody().discardPendingOnboarding('@alice');
      expect(pending.records, isEmpty);
      expect(authenticator.gets, gets);
      expect(gateway.authenticated, hasLength(authenticated));
      expect(setupLock.names.last, '$_lockPrefix:$_atSign');
    });

    test('does nothing when there is no record, or the second time', () async {
      await custody().discardPendingOnboarding(_atSign);
      await dieAfterActivation();
      await custody().discardPendingOnboarding(_atSign);
      await custody().discardPendingOnboarding(_atSign);
      expect(pending.records, isEmpty);
    });

    test('waits for the setup lock', () async {
      await dieAfterActivation();
      final release = Completer<void>();
      final holder =
          setupLock.run('$_lockPrefix:$_atSign', () => release.future);
      var done = false;
      final discarding = custody()
          .discardPendingOnboarding(_atSign)
          .whenComplete(() => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      expect(pending.records, contains(_atSign));
      release.complete();
      await holder;
      await discarding;
      expect(pending.records, isEmpty);
    });

    test('a later onboard runs a fresh ceremony', () async {
      await dieAfterActivation();
      await custody().discardPendingOnboarding(_atSign);
      final client = await custody().onboard(atSign: _atSign, cram: 'cram2');
      expect(authenticator.creates, 2);
      expect(gateway.activated.map((a) => a.cram), ['cram', 'cram2']);
      expect(client.enrollmentId, 'eid2');
    });
  });

  group('an obsolete pending record', () {
    Future<PendingOnboardingRecord> matching() async {
      server.keys['aesEncryptPublicKey'] = base64Encode(utf8.encode('pub'));
      final first = await custody().onboard(atSign: _atSign, cram: 'cram');
      final stored = await (first as FakeAtClient).keysIo.read(_atSign);
      return PendingOnboardingRecord(
          credentialId: Uint8List.fromList([9]),
          enrollmentId: 'eid1',
          encryptionPublicKey: stored.toJson()['aesEncryptPublicKey'] as String,
          sealed: 'junk');
    }

    test('is not deleted by the open that holds no setup lock', () async {
      final record = await matching();
      final store = _LateRecordStore(record);
      pending = store;
      setupLock.names.clear();
      await custody().open(atSign: _atSign);
      expect(setupLock.names, isEmpty);
      expect(store.reads, 1);
      expect(store.deletes, 0);
    });

    test('is deleted by the open that holds it', () async {
      pending.records[_atSign] = await matching();
      await custody().open(atSign: _atSign);
      expect(pending.records, isEmpty);
    });

    test('a failing store is logged with the enrollment id and type only',
        () async {
      pending.records[_atSign] = await matching();
      pending.failDeletes = true;
      logs.records.clear();
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      final lines = logs.at('WARNING').where((m) => m.contains('StateError'));
      expect(lines, hasLength(1));
      expect(lines.single, contains('eid1'));
      expect(lines.single, isNot(contains('pending delete failed')));
    });
  });

  group('open with a record', () {
    test('resumes it under the setup lock', () async {
      await dieAfterActivation();
      setupLock.names.clear();
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(setupLock.names, contains('$_lockPrefix:$_atSign'));
      expect(pending.records, isEmpty);
      expect(gateway.activated, hasLength(1));
    });

    test('a record that cannot be opened does not stop a login that can',
        () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      final keys = await keysOf(0);
      final record = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([9]),
          enrollmentId: 'eidX',
          encryptionPublicKey: 'other-key',
          sealed: 'junk');
      pending.records[_atSign] = record;
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
      expect(server.pointers, contains(keys.lookupHex));
      expect(pending.records[_atSign], same(record));
    });

    test('deletes a record for the keys the login restored', () async {
      server.keys['aesEncryptPublicKey'] = base64Encode(utf8.encode('pub'));
      final first = await custody().onboard(atSign: _atSign, cram: 'cram');
      final stored = await (first as FakeAtClient).keysIo.read(_atSign);
      pending.records[_atSign] = PendingOnboardingRecord(
          credentialId: Uint8List.fromList([9]),
          enrollmentId: 'eid1',
          encryptionPublicKey: stored.toJson()['aesEncryptPublicKey'] as String,
          sealed: 'junk');
      await custody().open(atSign: _atSign);
      expect(pending.records, isEmpty);
    });
  });

  group('a passkey registered for an onboarding that fails', () {
    test('is signalled as unknown when the CRAM is refused', () async {
      gateway.activateRefusal = StateError('cram refused');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expect(authenticator.signalled, [
        Uint8List.fromList([1])
      ]);
      expect(pending.records, isEmpty);
    });

    test('is kept when a pending record holds the activation', () async {
      await dieAfterActivation();
      expect(pending.records, isNotEmpty);
      expect(authenticator.signalled, isEmpty);
    });

    test('is kept when the client fails to open after the keys are written',
        () async {
      gateway.openErrorForNext = StateError('offline');
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(isA<StateError>()));
      expect(authenticator.signalled, isEmpty);
    });

    test('a refused signal does not change the onboarding error', () async {
      gateway.activateRefusal = StateError('cram refused');
      authenticator.signalFails = true;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
    });
  });
}
