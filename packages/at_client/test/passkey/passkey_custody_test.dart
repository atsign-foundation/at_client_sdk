import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysFileOverwriteException,
        ClosableAtKeysIo,
        WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, InvalidAtSignException;
import 'package:at_client/src/passkey/at_keys_document.dart';
import 'package:at_client/at_client.dart'
    show AtClient, AtClientPreference, buildAtClient;
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
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

/// The declarations in the class [body] whose name is public and whose
/// header mentions secret material. A member's header runs from its
/// two-space-indented first line to the line ending in `{`, `;` or `=>`.
List<String> _publicSecretMembers(String body) {
  final exposed = RegExp(r'PasskeyVault|_CustodyKeys|authSeed|Uint8List|'
      r'PrfSecret|PasskeyKeyDeriver|CustodySession');
  final name = RegExp(r'^[^(=;{]*?\b(\w+)\s*(?:\(|=>|=|;|\{)');
  final lines = body.split('\n');
  final found = <String>[];
  for (var i = 1; i < lines.length; i++) {
    final first = lines[i];
    if (!RegExp(r'^  [A-Za-z_]').hasMatch(first)) continue;
    final header = StringBuffer(first.trim());
    var end = i;
    while (!RegExp(r'(\{|;|=>)$').hasMatch(lines[end].trimRight()) &&
        end + 1 < lines.length) {
      header.write(' ${lines[++end].trim()}');
    }
    final text = header.toString();
    final declared = name.firstMatch(text)?.group(1);
    if (declared != null &&
        !declared.startsWith('_') &&
        exposed.hasMatch(text)) {
      found.add(text);
    }
  }
  return found;
}

/// Derives like [BytesPasskeyKeyDeriver] and counts the closes of every
/// sealer it hands out, one per vault.
class _CountingDeriver implements PasskeyKeyDeriver {
  final sealerCloses = <int>[];

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final base = await const BytesPasskeyKeyDeriver().derive(prf, atSign);
    final index = sealerCloses.length;
    sealerCloses.add(0);
    return (
      lookupHex: base.lookupHex,
      ns: base.ns,
      authSeed: base.authSeed,
      sealer: _CountingSealer(base.sealer, () => sealerCloses[index]++),
    );
  }
}

class _CountingSealer implements RecordSealer {
  _CountingSealer(this._inner, this._onClose);

  final RecordSealer _inner;
  final void Function() _onClose;

  @override
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad) =>
      _inner.seal(iv, plaintext, aad);

  @override
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad) =>
      _inner.open(iv, ciphertext, aad);

  @override
  void close() {
    _onClose();
    _inner.close();
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
  late FakePendingStore pending;
  late FakeSetupLock setupLock;

  PasskeyCustody custody(
          {LegacyHints? withHints,
          PasskeyKeyDeriver deriver = const BytesPasskeyKeyDeriver()}) =>
      PasskeyCustody(
          prf: PasskeyPrf(authenticator),
          deriver: deriver,
          pointerReader: server,
          gateway: gateway,
          credentials: withHints ?? hints,
          enrollmentIds: withHints ?? hints,
          persistence: persistence,
          pendingStore: pending,
          now: () => _enrolledAt,
          retryDelay: Duration.zero,
          setupLock: setupLock,
          setupLockPrefix: _lockPrefix);

  Future<DerivedKeys> keysOf(int credential) async {
    final prf = Uint8List.fromList(List.generate(32, (i) => i + credential));
    return DerivedKeys.derive(prf, _atSign);
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

  group('an atSign not in canonical form', () {
    for (final bad in ['alice', 'left@right', '@left@right', '@@alice']) {
      test('"$bad" is refused by onboard, open and discard before any work',
          () async {
        final c = custody();
        await expectLater(c.onboard(atSign: bad, cram: 'cram'),
            throwsA(isA<InvalidAtSignException>()));
        await expectLater(
            c.open(atSign: bad), throwsA(isA<InvalidAtSignException>()));
        await expectLater(c.discardPendingOnboarding(bad),
            throwsA(isA<InvalidAtSignException>()));
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
      final client = await custody().onboard(atSign: _atSign, cram: 'cram')
          as FakeAtClient;
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
      final client = await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(client.enrollmentId, 'eid1');
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

  group('onboard retention', () {
    Future<OnboardingIncompleteException> failure() async {
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
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
      final incomplete = await failure();
      expect(server.log, ['put-document:eid1']);
      expect(incomplete.cause, isA<AtServerAtKeysWriteException>());
    });

    test('an existing different document fails onboarding without a write',
        () async {
      final keys = await keysOf(0);
      final other = AtKeys.legacy(encryptionPrivateKey: 'b3RoZXI=')
        ..atsign = _atSign.toAtsign();
      server.documents['eid1'] =
          await keys.vault.seal(PasskeyRecordType.atkeys, other.toJson());
      final incomplete = await failure();
      expect(server.log, isNot(contains('put-document:eid1')));
      expect(incomplete.cause, isA<AtKeysFileOverwriteException>());
    });

    test('a document put failing past the bound throws a resumable handle',
        () async {
      server.documentPutFailures = 99;
      final incomplete = await failure();
      expect(server.log, everyElement('put-document:eid1'));
      expect(server.log, hasLength(3));
      expect(gateway.lastSession!.closed, isFalse);
      expect(incomplete.toString(), isNot(contains(fakeEncryptPrivateKey)));
      expect(hints.ids, isEmpty);
    });

    test('a failed pointer put throws a resumable handle with the session open',
        () async {
      server.pointerPutFailures = 1;
      await failure();
      expect(gateway.lastSession!.closed, isFalse);
      expect(server.pointers, isEmpty);
    });

    test('a failed remember throws a resumable handle', () async {
      hints.failWrites = true;
      await failure();
      expect(gateway.lastSession!.closed, isFalse);
    });

    test('resume writes document, pointer and remembers like a clean onboard',
        () async {
      server.documentPutFailures = 99;
      final incomplete = await failure();
      server.documentPutFailures = 0;
      final resumed = await incomplete.pending.resume();

      final clean = await (() async {
        final other = FakeServer();
        return PasskeyCustody(
                prf: PasskeyPrf(FakeAuthenticator()),
                deriver: const BytesPasskeyKeyDeriver(),
                pointerReader: other,
                gateway: FakeGateway(other),
                credentials: FakeHints(),
                enrollmentIds: FakeHints(),
                pendingStore: FakePendingStore(),
                setupLock: FakeSetupLock(),
                setupLockPrefix: _lockPrefix)
            .onboard(atSign: _atSign, cram: 'cram');
      })();
      Future<Map<String, dynamic>> held(AtClient client) async =>
          atKeysDocument(
              await (client as FakeAtClient).keysIo.read(_atSign), _atSign)
            ..remove('enrollments');
      expect(await held(resumed), await held(clean));
      expect(resumed.enrollmentId, clean.enrollmentId);
      expect(server.pointers, contains((await keysOf(0)).lookupHex));
      expect(hints.ids[_atSign], 'eid1');
      expect(gateway.lastSession!.closed, isFalse);
    });

    test('abandon closes the session the handle owns', () async {
      server.documentPutFailures = 99;
      final incomplete = await failure();
      await incomplete.pending.abandon();
      expect(gateway.lastSession!.closed, isTrue);
    });

    test('an unfinished activation resumes on a new session', () async {
      gateway.activationUnfinished = true;
      final incomplete = await failure();
      expect(incomplete.toString(), isNot(contains(fakeEncryptPrivateKey)));
      final resumed = await incomplete.pending.resume();
      expect(
          (await (resumed as FakeAtClient).keysIo.read(_atSign))
              .toJson()['aesEncryptPrivateKey'],
          fakeEncryptPrivateKey);
      expect(server.pointers, contains((await keysOf(0)).lookupHex));
      expect(server.documents, contains('eid1'));
    });

    test('an unfinished activation keeps the auth seed until its session opens',
        () async {
      gateway.activationUnfinished = true;
      final incomplete = await failure();
      final seed = gateway.seedBuffers.last;
      expect(seed.every((b) => b == 0), isFalse);

      final client = await incomplete.pending.resume() as FakeAtClient;

      expect(seed.every((b) => b == 0), isTrue);
      expect((await client.keysIo.read(_atSign)).atsign, _atSign.toAtsign());
      await client.stop();
    });

    test('abandoning an unfinished activation zeroes the auth seed', () async {
      gateway.activationUnfinished = true;
      final incomplete = await failure();
      final seed = gateway.seedBuffers.last;
      expect(seed.every((b) => b == 0), isFalse);

      await incomplete.pending.abandon();

      expect(seed.every((b) => b == 0), isTrue);
    });

    test('a failed authentication leaves the handle ready to resume again',
        () async {
      gateway.activationUnfinished = true;
      gateway.authenticateFailures = 1;
      final incomplete = await failure();
      await expectLater(incomplete.pending.resume(), throwsStateError);
      expect(server.documents, isEmpty);
      final resumed = await incomplete.pending.resume();
      expect((resumed as FakeAtClient).enrollmentId, 'eid1');
      expect(server.documents, contains('eid1'));
      await expectLater(incomplete.pending.resume(), throwsStateError);
    });
  });

  group('resume', () {
    Future<PendingOnboarding> pending(
        {PasskeyKeyDeriver deriver = const BytesPasskeyKeyDeriver()}) async {
      server.documentPutFailures = 99;
      try {
        await custody(deriver: deriver).onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        server.documentPutFailures = 0;
        return e.pending;
      }
      fail('onboard completed');
    }

    test('runs under the per-atSign setup lock', () async {
      final handle = await pending();
      setupLock.names.clear();
      await handle.resume();
      expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
    });

    test('waits for another holder of the setup lock', () async {
      final handle = await pending();
      final release = Completer<void>();
      final holder = setupLock.run(
          setupLockName(_lockPrefix, _atSign), () => release.future);
      var done = false;
      final resumed = handle.resume().then((s) {
        done = true;
        return s;
      });
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      release.complete();
      await holder;
      await resumed;
      expect(done, isTrue);
    });

    test('onboard takes the lock once, resume inside it does not re-enter',
        () async {
      setupLock.names.clear();
      await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(setupLock.names, hasLength(1));
    });

    test('a successful resume leaves abandon without a session to close',
        () async {
      final handle = await pending();
      final resumed = await handle.resume();
      await handle.abandon();
      expect(gateway.lastSession!.closed, isFalse);
      expect((resumed as FakeAtClient).session, same(gateway.lastSession));
    });

    test('a successful resume on a new session leaves it open after abandon',
        () async {
      gateway.activationUnfinished = true;
      PendingOnboarding handle;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        handle = e.pending;
      }
      await handle.resume();
      await handle.abandon();
      expect(gateway.lastSession!.closed, isFalse);
    });

    test('releaseWith runs after a successful resume', () async {
      final handle = await pending();
      var released = 0;
      handle.releaseWith(() => released++);
      expect(released, 0);
      await handle.resume();
      expect(released, 1);
    });

    test('releaseWith does not run after a failed resume', () async {
      final handle = await pending();
      server.documentPutFailures = 99;
      var released = 0;
      handle.releaseWith(() => released++);
      await expectLater(handle.resume(), throwsStateError);
      expect(released, 0);
    });

    test('abandon after a successful resume leaves the client its keys store',
        () async {
      final handle = await pending();
      final client = await handle.resume() as FakeAtClient;
      final seed = gateway.seedBuffers.last;
      await handle.abandon();
      expect(seed.every((b) => b == 0), isTrue);
      final keys = await client.keysIo.read(_atSign);
      keys.fileLegacyMaterial(apkamSymmetricKey: 'YWZ0ZXItYWJhbmRvbg==');
      await client.keysIo.flush(_atSign.toAtsign(), keys);
      expect((await client.keysIo.read(_atSign)).enrollmentSymmetricKey,
          isNotNull);
      await client.stop();
    });

    test('a second abandon closes the session once', () async {
      final deriver = _CountingDeriver();
      final handle = await pending(deriver: deriver);
      final seed = gateway.seedBuffers.last;
      await handle.abandon();
      await handle.abandon();
      expect(gateway.lastSession!.closeCalls, 1);
      expect(deriver.sealerCloses, [1], reason: 'the vault closed once');
      expect(seed.every((b) => b == 0), isTrue);
    });

    test('abandon waits for a resume that holds the setup lock', () async {
      final handle = await pending();
      final release = Completer<void>();
      final holder = setupLock.run(
          setupLockName(_lockPrefix, _atSign), () => release.future);
      final resumed = handle.resume();
      final abandoned = handle.abandon();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.lastSession!.closeCalls, 0);
      release.complete();
      await holder;
      final client = await resumed as FakeAtClient;
      await abandoned;
      expect(gateway.lastSession!.closed, isFalse);
      expect((await client.keysIo.read(_atSign)).atsign, _atSign.toAtsign());
    });

    test('abandon runs under the per-atSign setup lock', () async {
      final handle = await pending();
      setupLock.names.clear();
      await handle.abandon();
      expect(setupLock.names, [setupLockName(_lockPrefix, _atSign)]);
    });

    test('releaseWith runs once after abandon', () async {
      final handle = await pending();
      var released = 0;
      handle.releaseWith(() => released++);
      await handle.abandon();
      await handle.abandon();
      expect(released, 1);
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

    test('open zeroes the auth seed while the client can still seal and open',
        () async {
      final client = await custody(withHints: FakeHints()).open(atSign: _atSign)
          as FakeAtClient;

      expect(gateway.seedBuffers.last.every((b) => b == 0), isTrue);
      final keys = await client.keysIo.read(_atSign);
      keys.fileLegacyMaterial(apkamSymmetricKey: 'YWZ0ZXItb3Blbg==');
      await client.keysIo.flush(_atSign.toAtsign(), keys);
      expect((await client.keysIo.read(_atSign)).enrollmentSymmetricKey,
          isNotNull);
      await client.stop();
    });

    test(
        'onboard zeroes the auth seed while the client can still seal and open',
        () async {
      final client = await custody().onboard(atSign: _atSign, cram: 'cram')
          as FakeAtClient;

      expect(gateway.seedBuffers.every((s) => s.every((b) => b == 0)), isTrue);
      final keys = await client.keysIo.read(_atSign);
      keys.fileLegacyMaterial(apkamSymmetricKey: 'YWZ0ZXItb25ib2FyZA==');
      await client.keysIo.flush(_atSign.toAtsign(), keys);
      expect((await client.keysIo.read(_atSign)).enrollmentSymmetricKey,
          isNotNull);
      await client.stop();
    });

    test('hands the client a key store it closes when it stops', () async {
      final client = await custody(withHints: FakeHints()).open(atSign: _atSign)
          as FakeAtClient;

      expect(client.keysIo, isA<ClosableAtKeysIo>());
      expect((client.keysIo as ClosableAtKeysIo).closedByClient, isTrue);
    });

    test(
        'stops through the real teardown, closing the vault and keeping the seed zeroed',
        () async {
      final opened = await custody(withHints: FakeHints()).open(atSign: _atSign)
          as FakeAtClient;
      final seed = gateway.seedBuffers.last;
      expect(seed.every((b) => b == 0), isTrue);
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

      await expectLater(
          Future.sync(() => opened.keysIo.read(_atSign)), throwsStateError);
      expect(seed.every((b) => b == 0), isTrue);
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
      await second;
      expect(authenticator.creates, 2);
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
      expect(session.enrollmentId, 'eid1');
      final keys = await (session as FakeAtClient).keysIo.read(_atSign);
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
      expect(session.enrollmentId, 'eid1');
      expect(server.pointerReads, 0);
      expect(hints.ids[_atSign], 'eid1');
      expect(persistence.requests, 1);
    });

    test('narrows the assertion to the remembered credential', () async {
      authenticator.gets = 0;
      final session = await custody().open(atSign: _atSign);
      expect(session.enrollmentId, 'eid1');
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
        expect(session.enrollmentId, 'eid1');
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
        expect(session.enrollmentId, 'eid1');
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
      expect((await custody().open(atSign: _atSign)).enrollmentId, 'eid1');
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
      await custody().onboard(atSign: _atSign, cram: 'cram');
      server.documentReads = 0;

      await custody(withHints: FakeHints()).open(atSign: _atSign);
      // What a client does as it starts: read its keys through the store.
      final restored = await gateway.lastSession!.keysIos.last.read(_atSign);

      expect(server.documentReads, 1);
      expect(restored.toJson()['aesEncryptPrivateKey'], fakeEncryptPrivateKey);
    });

    test('a client reading its keys again reads no document', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
      await custody(withHints: FakeHints()).open(atSign: _atSign);
      final io = gateway.lastSession!.keysIos.last;
      await io.read(_atSign);
      server.documentReads = 0;

      await io.read(_atSign);

      expect(server.documentReads, 0);
    });

    test('open with hints takes no setup lock', () async {
      await custody().onboard(atSign: _atSign, cram: 'cram');
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
      final onboarding = custody().onboard(atSign: _atSign, cram: 'cram');
      await pumpEventQueue();
      expect(locked.held, {'$_lockPrefix:$_atSign'});

      final getsBefore = authenticator.gets;
      var opened = false;
      final opening = custody(withHints: FakeHints())
          .open(atSign: _atSign)
          .whenComplete(() => opened = true);
      await pumpEventQueue();
      expect(opened, isFalse);
      expect(authenticator.gets, getsBefore);
      expect(server.pointerReads, 0);

      gate.complete();
      final first = await onboarding;
      final second = await opening;

      expect(second.enrollmentId, first.enrollmentId);
      expect(locked.names, ['$_lockPrefix:$_atSign', '$_lockPrefix:$_atSign']);
    });

    test('open without hints uses the hints onboarding wrote meanwhile',
        () async {
      final gate = Completer<void>();
      gateway.gate = gate;
      final onboarding = custody().onboard(atSign: _atSign, cram: 'cram');
      await pumpEventQueue();
      final opening = custody().open(atSign: _atSign);
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
        final client =
            await custody(withHints: FakeHints()).open(atSign: _atSign);
        expect(client.enrollmentId, 'eid1');
      });
    });
  });

  group('second passkey', () {
    test(
        'X-K18: a second passkey derives different keys, so it cannot open '
        'the first passkey\'s records', () async {
      final first = await custody().onboard(atSign: _atSign, cram: 'cram');
      final second = await custody(withHints: FakeHints())
          .onboard(atSign: _atSign, cram: 'cram');
      final firstKeys = await keysOf(0);
      final secondKeys = await keysOf(1);

      expect(authenticator.prfByCredential, hasLength(2));
      expect(second.enrollmentId, isNot(first.enrollmentId));
      expect(gateway.activated, hasLength(2));
      expect(
          gateway.activated[1].authSeed, isNot(gateway.activated[0].authSeed));
      expect(secondKeys.authSeed, isNot(firstKeys.authSeed));
      expect(secondKeys.lookupHex, isNot(firstKeys.lookupHex));
      expect(server.pointers.keys,
          unorderedEquals([firstKeys.lookupHex, secondKeys.lookupHex]));

      await expectLater(
          gateway.authenticate(
              atSign: _atSign,
              enrollmentId: first.enrollmentId!,
              authSeed: secondKeys.authSeed),
          throwsA(isA<PkamRefusedException>()));
      await expectLater(
          secondKeys.vault.open(
              PasskeyRecordType.atkeys, server.documents[first.enrollmentId]!),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
      await expectLater(
          secondKeys.vault.open(
              PasskeyRecordType.eid, server.pointers[firstKeys.lookupHex]!),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
    });
  });

  group('a failed open', () {
    final openError = StateError('open failed');

    Future<PendingOnboarding> pending() async {
      server.documentPutFailures = 99;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        server.documentPutFailures = 0;
        return e.pending;
      }
      fail('onboard completed');
    }

    Future<void> expectVaultClosed(WrittenAtKeysIo keysIo) => expectLater(
        keysIo.read(_atSign),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('closed'))));

    test('resume rethrows it and ends the handle once the opener stopped',
        () async {
      final handle = await pending();
      var released = 0;
      handle.releaseWith(() => released++);
      gateway.lastSession!
        ..openClientError = openError
        ..openClientStopsFirst = true;
      await expectLater(handle.resume(), throwsA(same(openError)));
      final session = gateway.lastSession!;
      expect(session.closed, isTrue);
      await expectVaultClosed(session.keysIos.single);
      expect(released, 1);
      await expectLater(
          handle.resume(),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('already resumed'))));
      expect(released, 1);
    });

    test('resume closes the session and vault when no client was built',
        () async {
      final handle = await pending();
      gateway.lastSession!.openClientError = openError;
      await expectLater(handle.resume(), throwsA(same(openError)));
      final session = gateway.lastSession!;
      expect(session.closeCalls, 1);
      await expectVaultClosed(session.keysIos.single);
    });

    test('onboard rethrows it, keeps the hints and leaves login possible',
        () async {
      // The record is kept, so the retry resumes it against the document the
      // failed attempt published: the session reports the journalled keys.
      server.keys = {
        ...atKeysDocument(gateway.keysFor(_atSign, 'eid1'), _atSign),
        'publicTag': 'v1'
      };
      gateway.openErrorForNext = openError;
      await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
          throwsA(same(openError)));
      expect(hints.ids[_atSign], 'eid1');
      expect(hints.credentials[_atSign], isNotNull);
      expect(gateway.lastSession!.closed, isTrue);

      gateway.openErrorForNext = null;
      final client = await custody().open(atSign: _atSign);
      expect(client.enrollmentId, 'eid1');
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

    test('releaseWith on a finished handle runs at once', () async {
      final handle = await pending();
      await handle.abandon();
      var released = 0;
      handle.releaseWith(() => released++);
      expect(released, 1);
    });

    test('a failed publish leaves the handle ready to resume', () async {
      final handle = await pending();
      server.pointerPutFailures = 1;
      await expectLater(handle.resume(), throwsStateError);
      final client = await handle.resume();
      expect(client.enrollmentId, 'eid1');
    });
  });

  group('resume hands over a client', () {
    Future<PendingOnboarding> pending() async {
      server.documentPutFailures = 99;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        server.documentPutFailures = 0;
        return e.pending;
      }
      fail('onboard completed');
    }

    test('resume returns an AtClient', () async {
      final handle = await pending();
      expect(await handle.resume(), isA<AtClient>());
    });

    test('a second resume throws StateError', () async {
      final handle = await pending();
      await handle.resume();
      await expectLater(handle.resume(), throwsStateError);
    });

    test('resume after abandon throws StateError', () async {
      final handle = await pending();
      await handle.abandon();
      await expectLater(handle.resume(), throwsStateError);
    });

    test('releaseWith runs once across resume and abandon', () async {
      final handle = await pending();
      var released = 0;
      handle.releaseWith(() => released++);
      await handle.resume();
      await handle.abandon();
      expect(released, 1);
    });

    test('no public member of PendingOnboarding exposes keys or the vault', () {
      final source =
          File('lib/src/passkey/passkey_custody.dart').readAsStringSync();
      final start = source.indexOf('class PendingOnboarding');
      final end = source.indexOf('\n}\n', start);
      expect(_publicSecretMembers(source.substring(start, end)), isEmpty);
    });

    test('the privacy check flags a public member that exposes a secret', () {
      const exposing = [
        '  Uint8List get credentialId => _credentialId;',
        '  PasskeyVault get vault => _vault;',
        '  final Uint8List authSeed = Uint8List(32);',
        '  Future<void> use(PasskeyVault vault,\n      String x) async {}',
      ];
      for (final member in exposing) {
        expect(_publicSecretMembers('class A {\n$member\n}'), isNotEmpty,
            reason: member);
      }
      expect(
          _publicSecretMembers('class A {\n'
              '  final Uint8List _credentialId;\n'
              '  PasskeyVault? _vault;\n'
              '  Future<void> _use(PasskeyVault vault) async {}\n'
              '  String get atSign => _atSign;\n}'),
          isEmpty);
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
      final client = await custody().onboard(atSign: _atSign, cram: 'cram');
      await expectPersists(client as FakeAtClient);
      await client.stop();
    });

    test('open returns a client over an AtServerAtKeysIo', () async {
      await (await custody().onboard(atSign: _atSign, cram: 'cram')).stop();
      final client =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      await expectPersists(client as FakeAtClient);
      await client.stop();
    });

    test('resume returns a client over an AtServerAtKeysIo', () async {
      server.documentPutFailures = 99;
      late OnboardingIncompleteException incomplete;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
      } on OnboardingIncompleteException catch (e) {
        incomplete = e;
      }
      server.documentPutFailures = 0;
      final client = await incomplete.pending.resume();
      await expectPersists(client as FakeAtClient);
      await client.stop();
    });
  });
}
