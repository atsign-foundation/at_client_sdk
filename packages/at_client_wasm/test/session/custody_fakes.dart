import 'dart:async';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/key_bytes_store.dart';
import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/session/enrollment_document_store.dart';
import 'package:at_client_wasm/src/session/enrollment_pointer_store.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_client_wasm/src/session/setup_lock.dart';

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

  /// Document puts that throw before one is accepted.
  var documentPutFailures = 0;

  /// Pointer puts that throw before one is accepted.
  var pointerPutFailures = 0;

  /// Accepts document puts without storing them.
  var dropDocumentWrites = false;
  var enrollments = 0;

  /// The @keys a session of this server reports.
  Map<String, dynamic> keys = {
    'aesPkamPrivateKey': 'apkam-private',
    'aesEncryptPrivateKey': 'enc-private',
    'publicTag': 'v1',
  };

  /// Whether the public keys of a document are the published ones.
  late bool Function(Map<String, dynamic> atKeys) publishes =
      (atKeys) => atKeys['publicTag'] == publishedTag;

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
  Future<Map<String, dynamic>> atKeys() async => server.keys;

  @override
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys) async =>
      server.publishes(atKeys);

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
    if (session.server.documentPutFailures > 0) {
      session.server.documentPutFailures--;
      throw StateError('document put failed');
    }
    if (!session.server.dropDocumentWrites) {
      session.server.documents[eid] = document;
    }
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
    if (session.server.pointerPutFailures > 0) {
      session.server.pointerPutFailures--;
      throw StateError('pointer put failed');
    }
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
  final activated = <({String atSign, Uint8List authSeed, String cram})>[];
  FakeSession? lastSession;

  /// When set, an enroll waits for it before answering.
  Completer<void>? gate;

  @override
  Future<EnrollmentSession> enroll(
      {required String atSign,
      required Uint8List authSeed,
      required String otp}) async {
    enrolled.add((atSign: atSign, authSeed: authSeed, otp: otp));
    await gate?.future;
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

  /// Makes [activate] spend the CRAM, then fail its PKAM.
  var activatePkamFails = false;

  /// Runs inside [activate], once the CRAM is spent.
  FutureOr<void> Function()? onActivate;

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required Uint8List authSeed,
      required String cram}) async {
    activated.add((atSign: atSign, authSeed: authSeed, cram: cram));
    await onActivate?.call();
    final eid = 'eid${++server.enrollments}';
    server.seedByEnrollment[eid] = authSeed.join(',');
    if (activatePkamFails) {
      throw ActivationPkamFailedException(eid,
          atKeys: {...server.keys}..remove('aesPkamPrivateKey'),
          cause: StateError('pkam failed'));
    }
    return lastSession = FakeSession(server, eid);
  }
}

/// A passkey authenticator holding several passkeys; [current] answers an
/// assertion that names no credential.
class FakeAuthenticator implements PasskeyPort {
  final prfByCredential = <int, Uint8List>{};
  Uint8List? current;
  Uint8List? lastAllowCredential;
  var gets = 0;
  var creates = 0;

  /// Makes every assertion fail as a cancelled or unmatched ceremony.
  var yieldsNoCredential = false;

  @override
  Future<Uint8List> create({required String atSign}) async {
    creates++;
    final n = prfByCredential.length;
    final id = Uint8List.fromList([n + 1]);
    prfByCredential[id[0]] =
        Uint8List.fromList(List.generate(32, (i) => i + n));
    return current = id;
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    gets++;
    lastAllowCredential = allowCredential;
    if (yieldsNoCredential) throw PasskeyCeremonyException('NotAllowedError');
    final id = allowCredential ?? current!;
    return (credentialId: id, prfFirst: prfByCredential[id[0]]);
  }
}

/// navigator.locks: one holder per name at a time, in request order.
class FakeSetupLock implements SetupLock {
  final names = <String>[];

  /// The names whose body is running now.
  final held = <String>{};
  final _tails = <String, Future<void>>{};

  @override
  Future<T> run<T>(String name, Future<T> Function() body) {
    names.add(name);
    final previous = _tails[name] ?? Future<void>.value();
    final result = previous.then((_) async {
      held.add(name);
      try {
        return await body();
      } finally {
        held.remove(name);
      }
    });
    _tails[name] = result.then((_) {}, onError: (_) {});
    return result;
  }
}

class FakeHints implements CredentialHintStore, EnrollmentIdStore {
  /// Makes every write fail.
  var failWrites = false;

  final credentials = <String, Uint8List>{};
  final ids = <String, String>{};

  @override
  Future<Uint8List?> credentialId(String atSign) async => credentials[atSign];

  @override
  Future<void> putCredentialId(String atSign, Uint8List id) async {
    if (failWrites) throw StateError('hint write failed');
    credentials[atSign] = id;
  }

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
