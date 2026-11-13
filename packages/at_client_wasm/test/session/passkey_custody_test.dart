import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/key_bytes_store.dart';
import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/keys/passkey_record.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_client_wasm/src/session/enrollment_document_store.dart';
import 'package:at_client_wasm/src/session/enrollment_pointer_store.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:test/test.dart';

const _atSign = '@alice';
const _otp = 'ABC123';

/// The atServer as the custody flows see it: pointers by lookup id, each
/// enrollment's own document, and an ordered log of every write.
class FakeServer implements EnrollmentPointerReader {
  final pointers = <String, String>{};
  final documents = <String, String>{};
  final seedByEnrollment = <String, String>{};
  final revoked = <String>{};
  final log = <String>[];
  var pointerReads = 0;
  var documentReads = 0;
  var publishedTag = 'v1';
  var dropPointerWrites = false;
  var enrollments = 0;

  /// An approver's `enroll:delete`: the enrollment and its key are forgotten.
  void approverDelete(String enrollmentId) {
    revoked.remove(enrollmentId);
    seedByEnrollment.remove(enrollmentId);
  }

  @override
  Future<String?> get(String atSign, String lookupHex) async {
    pointerReads++;
    return pointers[lookupHex];
  }
}

class FakeSession implements EnrollmentSession {
  FakeSession(this.server, this.enrollmentId);

  final FakeServer server;
  @override
  final String enrollmentId;
  var closed = false;

  @override
  Future<Map<String, dynamic>> atKeys() async => {
        'aesPkamPrivateKey': 'apkam-private',
        'aesEncryptPrivateKey': 'enc-private',
        'publicTag': 'v1',
      };

  @override
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys) async =>
      atKeys['publicTag'] == server.publishedTag;

  @override
  late final EnrollmentDocumentStore documents = _Documents(this);

  @override
  late final EnrollmentPointerStore pointers = _Pointers(this);

  @override
  Future<void> revoke(String enrollmentId) async {
    server.log.add('revoke:$enrollmentId');
    server.revoked.add(enrollmentId);
  }

  @override
  Future<void> close() async => closed = true;
}

class _Documents implements EnrollmentDocumentStore {
  _Documents(this.session);

  final FakeSession session;

  void _own(String eid) {
    if (eid != session.enrollmentId) throw StateError('not your document');
  }

  @override
  Future<String?> get(String atSign, String eid) async {
    _own(eid);
    session.server.documentReads++;
    return session.server.documents[eid];
  }

  @override
  Future<void> put(String atSign, String eid, String document) async {
    _own(eid);
    session.server.log.add('put-document:$eid');
    session.server.documents[eid] = document;
  }

  @override
  Future<void> delete(String atSign, String eid) async {
    _own(eid);
    session.server.documents.remove(eid);
  }
}

class _Pointers implements EnrollmentPointerStore {
  _Pointers(this.session);

  final FakeSession session;

  @override
  Future<String?> get(String atSign, String lookupHex) =>
      session.server.get(atSign, lookupHex);

  @override
  Future<void> put(String atSign, String lookupHex, String record) async {
    session.server.log.add('put-pointer:$lookupHex');
    if (!session.server.dropPointerWrites) {
      session.server.pointers[lookupHex] = record;
    }
  }

  @override
  Future<void> delete(String atSign, String lookupHex) async {
    session.server.log.add('delete-pointer:$lookupHex');
    session.server.pointers.remove(lookupHex);
  }
}

/// The atServer's AT0032 refusal of a key that is already enrolled.
class KeyAlreadyEnrolledException implements Exception {}

class FakeGateway implements EnrollmentGateway {
  FakeGateway(this.server);

  final FakeServer server;
  final enrolled = <({String atSign, Uint8List authSeed, String otp})>[];
  FakeSession? lastSession;

  @override
  Future<EnrollmentSession> enroll(
      {required String atSign,
      required Uint8List authSeed,
      required String otp}) async {
    enrolled.add((atSign: atSign, authSeed: authSeed, otp: otp));
    if (server.seedByEnrollment.containsValue(authSeed.join(','))) {
      throw KeyAlreadyEnrolledException();
    }
    final eid = 'eid${++server.enrollments}';
    server.seedByEnrollment[eid] = authSeed.join(',');
    return lastSession = FakeSession(server, eid);
  }

  @override
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required Uint8List authSeed}) async {
    if (server.revoked.contains(enrollmentId) ||
        server.seedByEnrollment[enrollmentId] != authSeed.join(',')) {
      throw PkamRefusedException(enrollmentId);
    }
    return lastSession = FakeSession(server, enrollmentId);
  }
}

/// A passkey authenticator holding several passkeys; [current] answers an
/// assertion that names no credential.
class FakeAuthenticator implements PasskeyPort {
  final prfByCredential = <int, Uint8List>{};
  Uint8List? current;
  var userHandleAtSign = _atSign;
  Uint8List? lastAllowCredential;
  var gets = 0;

  @override
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput}) async {
    final n = prfByCredential.length;
    final id = Uint8List.fromList([n + 1]);
    final prf = Uint8List.fromList(List.generate(32, (i) => i + n));
    prfByCredential[id[0]] = prf;
    current = id;
    return (credentialId: id, prfFirst: prf);
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    gets++;
    lastAllowCredential = allowCredential;
    final id = allowCredential ?? current!;
    return (
      credentialId: id,
      prfFirst: prfByCredential[id[0]],
      userHandle: Uint8List.fromList(userHandleAtSign.codeUnits),
    );
  }
}

class FakeHints implements CredentialHintStore, EnrollmentIdStore {
  final credentials = <String, Uint8List>{};
  final ids = <String, String>{};

  @override
  Future<Uint8List?> credentialId(String atSign) async => credentials[atSign];

  @override
  Future<void> putCredentialId(String atSign, Uint8List id) async =>
      credentials[atSign] = id;

  @override
  Future<String?> enrollmentId(String atSign) async => ids[atSign];

  @override
  Future<void> putEnrollmentId(String atSign, String id) async =>
      ids[atSign] = id;
}

class FakePersistence implements StoragePersistence {
  var requests = 0;
  Object? error;

  @override
  Future<bool> requestPersist() async {
    requests++;
    if (error case final e?) throw e;
    return true;
  }
}

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late FakePersistence persistence;

  PasskeyCustody custody({FakeHints? withHints}) => PasskeyCustody(
      kek: PasskeyKek(authenticator),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      persistence: persistence);

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

  group('open', () {
    setUp(() async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      persistence.requests = 0;
    });

    test('recovers from an empty device with one passkey prompt', () async {
      authenticator.gets = 0;
      final session = await custody(withHints: FakeHints()).open();
      expect(authenticator.gets, 1);
      expect(session.atSign, _atSign);
      expect(session.enrollmentId, 'eid1');
      expect(session.atKeys['aesEncryptPrivateKey'], 'enc-private');
      expect(server.pointerReads, 1);
    });

    test('recovery rewrites the hints and asks for persistence once', () async {
      final fresh = FakeHints();
      await custody(withHints: fresh).open();
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

    test('refuses a passkey that names another atSign than the one asked for',
        () async {
      hints.credentials.clear();
      hints.ids.clear();
      authenticator.userHandleAtSign = '@bob';
      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PasskeyAtSignMismatchException>()));
      expect(server.pointerReads, 0);
    });

    test('a failing persist request does not fail the open', () async {
      persistence.error = StateError('denied');
      expect((await custody().open(atSign: _atSign)).enrollmentId, 'eid1');
    });

    test('recovery without a pointer throws', () async {
      server.pointers.clear();
      expect(custody(withHints: FakeHints()).open(),
          throwsA(isA<NoEnrollmentPointerException>()));
    });

    test('a swapped pointer is refused by PKAM before any document read',
        () async {
      final keys = await keysOf(0);
      server.pointers[keys.lookupHex] = await PasskeyRecordCodec.seal(
          keys.kek, PasskeyRecordType.eid, {'enrollmentId': 'eid9'});
      await expectLater(custody(withHints: FakeHints()).open(),
          throwsA(isA<PkamRefusedException>()));
      expect(server.documentReads, 0);
    });

    test('a revoked enrollment ends in a refusal that needs an approver',
        () async {
      server.revoked.add('eid1');
      final fresh = FakeHints();
      await expectLater(
          custody(withHints: fresh).open(),
          throwsA(isA<PkamRefusedException>()
              .having((e) => e.enrollmentId, 'enrollmentId', 'eid1')
              .having((e) => e.toString(), 'message', contains('approver'))));
      expect(fresh.ids, isEmpty);
    });

    test('a revoked enrollment never reaches enroll or the pointer', () async {
      server.revoked.add('eid1');
      final pointers = {...server.pointers};
      final log = [...server.log];
      await expectLater(custody().open(atSign: _atSign),
          throwsA(isA<PkamRefusedException>()));
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
      await expectLater(custody(withHints: FakeHints()).open(),
          throwsA(isA<PkamRefusedException>()));
    });

    test('an approver deleting the revoked enrollment allows a new one',
        () async {
      server.revoked.add('eid1');
      server.approverDelete('eid1');
      await custody().enroll(atSign: _atSign, otp: _otp, existingPasskey: true);
      final session = await custody(withHints: FakeHints()).open();
      expect(session.enrollmentId, 'eid2');
    });

    test('restored keys that do not match the published ones throw before use',
        () async {
      server.publishedTag = 'v2';
      final fresh = FakeHints();
      await expectLater(custody(withHints: fresh).open(),
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
      final session = await custody(withHints: FakeHints()).open();
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
