import 'dart:async';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/passkey_record.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:test/test.dart';

import 'custody_fakes.dart';

const _atSign = '@alice';
const _otp = 'ABC123';

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late FakePersistence persistence;
  late FakeSetupLock setupLock;

  PasskeyCustody custody({FakeHints? withHints}) => PasskeyCustody(
      kek: PasskeyKek(authenticator),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      persistence: persistence,
      setupLock: setupLock);

  Future<RecordKeys> keysOf(int credential) async {
    final prf = Uint8List.fromList(List.generate(32, (i) => i + credential));
    return RecordKeys.derive(PrfSecret(prf), _atSign);
  }

  setUp(() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    persistence = FakePersistence();
    setupLock = FakeSetupLock();
  });

  group('enroll', () {
    test('enrolls the derived seed with the otp', () async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      final keys = await keysOf(0);
      expect(gateway.enrolled.single.atSign, _atSign);
      expect(gateway.enrolled.single.otp, _otp);
      expect(gateway.enrolled.single.authSeed, keys.authSeed);
    });

    test('writes the document, then the pointer', () async {
      final keys = await keysOf(0);
      await custody().enroll(atSign: _atSign, otp: _otp);
      expect(
          server.log, ['put-document:eid1', 'put-pointer:${keys.lookupHex}']);
    });

    test('seals the document without the APKAM private key', () async {
      final keys = await keysOf(0);
      await custody().enroll(atSign: _atSign, otp: _otp);
      final document = await PasskeyRecordCodec.open(
          keys.kek, PasskeyRecordType.atkeys, server.documents['eid1']!);
      expect(document.keys,
          unorderedEquals(['aesEncryptPrivateKey', 'publicTag']));
    });

    test('exposes the @keys without the APKAM private key', () async {
      final session = await custody().enroll(atSign: _atSign, otp: _otp);
      expect(session.atKeys, isNot(contains('aesPkamPrivateKey')));
    });

    test('seals the pointer as the enrollment id', () async {
      final keys = await keysOf(0);
      await custody().enroll(atSign: _atSign, otp: _otp);
      expect(
          await PasskeyRecordCodec.open(keys.kek, PasskeyRecordType.eid,
              server.pointers[keys.lookupHex]!),
          {'enrollmentId': 'eid1'});
    });

    test('remembers the credential and enrollment id and asks for persistence',
        () async {
      final session = await custody().enroll(atSign: _atSign, otp: _otp);
      expect(session.enrollmentId, 'eid1');
      expect(hints.ids[_atSign], 'eid1');
      expect(hints.credentials[_atSign], Uint8List.fromList([1]));
      expect(persistence.requests, 1);
    });

    test('with an existing passkey asserts instead of registering', () async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      server.approverDelete('eid1');
      authenticator.gets = 0;
      await custody().enroll(atSign: _atSign, otp: _otp, existingPasskey: true);
      expect(authenticator.gets, 1);
      expect(authenticator.prfByCredential, hasLength(1));
    });
  });

  group('setup lock', () {
    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('enroll runs under the per-atSign setup lock', () async {
      await custody().enroll(atSign: 'Alice', otp: _otp);
      expect(setupLock.names, ['at_client_wasm:setup:@alice']);
    });

    test('a concurrent setup for the same atSign waits for the first',
        () async {
      gateway.gate = Completer<void>();
      final first = custody().enroll(atSign: _atSign, otp: _otp);
      await pump();
      final second = custody().enroll(atSign: _atSign, otp: _otp);
      await pump();
      expect(authenticator.creates, 1);

      gateway.gate!.complete();
      await first;
      await second;
      expect(authenticator.creates, 2);
    });

    test('a setup for another atSign does not wait', () async {
      gateway.gate = Completer<void>();
      final first = custody().enroll(atSign: _atSign, otp: _otp);
      await pump();
      final second = custody().enroll(atSign: '@bob', otp: _otp);
      await pump();
      expect(authenticator.creates, 2);

      gateway.gate!.complete();
      await Future.wait([first, second]);
    });

    test('the lock is held until the pointer is written', () async {
      gateway.gate = Completer<void>();
      final first = custody().enroll(atSign: _atSign, otp: _otp);
      await pump();
      expect(server.log, isEmpty);
      gateway.gate!.complete();
      await first;
      expect(server.log, hasLength(2));
    });
  });

  group('open', () {
    setUp(() async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      persistence.requests = 0;
    });

    test('recovers from an empty device with one passkey prompt', () async {
      authenticator.gets = 0;
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expect(authenticator.gets, 1);
      expect(session.atSign, _atSign);
      expect(session.enrollmentId, 'eid1');
      expect(session.atKeys['aesEncryptPrivateKey'], 'enc-private');
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
      hints.ids.clear();
      authenticator.gets = 0;
      final session = await custody().open(atSign: _atSign);
      expect(session.credentialId, Uint8List.fromList([1]));
      expect(authenticator.lastAllowCredential, Uint8List.fromList([1]));
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
          custody(withHints: FakeHints()).open(atSign: 'Alice'),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', _atSign)));
    });

    test('a swapped pointer is refused by PKAM before any document read',
        () async {
      final keys = await keysOf(0);
      server.pointers[keys.lookupHex] = await PasskeyRecordCodec.seal(
          keys.kek, PasskeyRecordType.eid, {'enrollmentId': 'eid9'});
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(server.documentReads, 0);
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

    test('a revoked enrollment never reaches enroll or the pointer', () async {
      server.revoked.add('eid1');
      final pointers = {...server.pointers};
      final log = [...server.log];
      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expect(gateway.enrolled, hasLength(1));
      expect(server.log, log);
      expect(server.pointers, pointers);
      expect(server.enrollments, 1);
    });

    test('the same key cannot self re-enroll after revocation', () async {
      server.revoked.add('eid1');
      final pointers = {...server.pointers};
      await expectLater(
          custody().enroll(atSign: _atSign, otp: _otp, existingPasskey: true),
          throwsA(isA<KeyAlreadyEnrolledException>()));
      expect(server.pointers, pointers);
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
    });

    test('an approver deleting the revoked enrollment allows a new one',
        () async {
      server.revoked.add('eid1');
      server.approverDelete('eid1');
      await custody().enroll(atSign: _atSign, otp: _otp, existingPasskey: true);
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expect(session.enrollmentId, 'eid2');
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
  });

  group('rotate', () {
    late CustodySession current;
    late RecordKeys oldKeys;

    setUp(() async {
      current = await custody().enroll(atSign: _atSign, otp: _otp);
      oldKeys = await keysOf(0);
    });

    test('enrolls the new passkey, then moves the pointer and revokes',
        () async {
      final rotated = await custody().rotate(current, otp: _otp);
      final newKeys = await keysOf(1);
      expect(rotated.enrollmentId, 'eid2');
      expect(server.pointers.keys, [newKeys.lookupHex]);
      expect(server.log.skip(2), [
        'put-document:eid2',
        'put-pointer:${newKeys.lookupHex}',
        'delete-pointer:${oldKeys.lookupHex}',
        'revoke:eid1',
      ]);
      expect(hints.ids[_atSign], 'eid2');
    });

    test('the rotated session exposes no APKAM private key', () async {
      final rotated = await custody().rotate(current, otp: _otp);
      expect(rotated.atKeys, isNot(contains('aesPkamPrivateKey')));
    });

    test('the rotated document opens under the new passkey', () async {
      await custody().rotate(current, otp: _otp);
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expect(session.enrollmentId, 'eid2');
      expect(session.atKeys['aesEncryptPrivateKey'], 'enc-private');
    });

    test('keeps the old enrollment when the new pointer does not read back',
        () async {
      server.dropPointerWrites = true;
      await expectLater(custody().rotate(current, otp: _otp),
          throwsA(isA<RotationAbortedException>()));
      expect(server.revoked, isEmpty);
      expect(
          server.log, isNot(contains('delete-pointer:${oldKeys.lookupHex}')));
    });
  });
}
