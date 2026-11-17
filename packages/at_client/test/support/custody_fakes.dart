import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show AtKeys, ClosableAtKeysIo, WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/passkey/enrollment_document_store.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show ApkamKeyPair, apkamKeyPairFromSeed, withApkamKey;
import 'package:at_client/src/passkey/enrollment_pointer_store.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';

import 'package:at_commons/atsign.dart';
import 'package:mocktail/mocktail.dart' show Fake;

import 'bytes_passkey_sealer.dart';

/// The base64 of the encryption private key the fake atServer holds.
const fakeEncryptPrivateKey = 'ZW5jLXByaXZhdGU=';

/// The atServer as the custody flows see it: pointers by lookup id, each
/// enrollment's own document, and an ordered log of every write.
class FakeServer implements EnrollmentPointerReader {
  final pointers = <String, String>{};

  /// The namespace each pointer was written in, by lookup id.
  final pointerNamespaces = <String, String>{};
  final documents = <String, String>{};
  final seedByEnrollment = <String, String>{};
  final revoked = <String>{};
  final log = <String>[];

  /// Every step of an onboarding in the order it happened: the server's
  /// writes (as in [log]), the pending record's puts and deletes, the keys the
  /// activation filed, the CRAM being spent and the client opening.
  final timeline = <String>[];
  var pointerReads = 0;
  var documentReads = 0;
  var publishedTag = 'v1';
  var dropPointerWrites = false;

  /// Document puts that throw before one is accepted.
  var documentPutFailures = 0;

  /// Pointer puts that throw before one is accepted.
  var pointerPutFailures = 0;

  /// Runs when a pointer put arrives, before it is accepted.
  void Function()? onPointerPut;

  /// Accepts document puts without storing them.
  var dropDocumentWrites = false;
  var enrollments = 0;

  /// The @keys a session of this server reports.
  Map<String, dynamic> keys = {
    'aesPkamPrivateKey': 'YXBrYW0tcHJpdmF0ZQ==',
    'aesEncryptPrivateKey': 'ZW5jLXByaXZhdGU=',
    'publicTag': 'v1',
  };

  /// Whether the public keys of a document are the published ones.
  late bool Function(Map<String, dynamic> atKeys) publishes =
      (atKeys) => atKeys['publicTag'] == publishedTag;

  @override
  Future<String?> get(String atSign, String lookupHex,
      {required String ns}) async {
    pointerReads++;
    return pointerNamespaces[lookupHex] == ns ? pointers[lookupHex] : null;
  }
}

class FakeSession implements EnrollmentSession {
  FakeSession(this.server, this.enrollmentId);

  final FakeServer server;
  @override
  final String enrollmentId;
  var closed = false;
  var closeCalls = 0;

  /// Makes [close] throw this after marking the session closed.
  Object? closeError;

  @override
  Future<Map<String, dynamic>> atKeys() async => server.keys;

  @override
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys) async =>
      server.publishes(atKeys);

  /// The @keys every [completeActivation] call was given.
  final completed = <Map<String, dynamic>>[];

  /// Makes [completeActivation] throw this.
  Object? completeError;

  @override
  Future<void> completeActivation(Map<String, dynamic> atKeys) async {
    server.timeline.add('complete-activation');
    completed.add(atKeys);
    if (completeError case final e?) throw e;
  }

  @override
  late final EnrollmentDocumentStore documents = _Documents(this);

  @override
  late final EnrollmentPointerStore pointers = _Pointers(this);

  /// The clients [openClient] handed out.
  final clients = <FakeAtClient>[];

  /// Makes [openClient] throw this.
  Object? openClientError;

  /// Makes [openClient] build a client and stop it before it throws
  /// [openClientError], as an opener that fails after starting does.
  var openClientStopsFirst = false;

  /// The keys IO of every [openClient] call, whether it threw or not.
  final keysIos = <WrittenAtKeysIo>[];

  /// Runs as [openClient] starts, as another tab writing between the steps
  /// of an onboarding would.
  void Function()? onOpenClient;

  @override
  Future<AtClient> openClient(WrittenAtKeysIo keysIo) async {
    keysIos.add(keysIo);
    server.timeline.add('open-client');
    onOpenClient?.call();
    if (openClientError case final e?) {
      if (openClientStopsFirst) {
        // The opener tolerates a failing stop; the close that follows is the
        // caller's.
        await FakeAtClient(this, keysIo).stop().catchError((Object _) {});
      }
      throw e;
    }
    final client = FakeAtClient(this, keysIo);
    clients.add(client);
    return client;
  }

  @override
  Future<void> close() async {
    closed = true;
    closeCalls++;
    if (closeError case final e?) throw e;
  }
}

/// The client a [FakeSession] opens: it knows the keys IO it was opened with
/// stops the session, then closes the keys IO when that is flagged
/// `closedByClient`, as a client's stop does.
class FakeAtClient extends Fake implements AtClient {
  FakeAtClient(this.session, this.keysIo);

  final FakeSession session;
  final WrittenAtKeysIo keysIo;

  @override
  String? get enrollmentId => session.enrollmentId;

  @override
  Future<void> stop() async {
    try {
      await session.close();
    } finally {
      if (keysIo case final ClosableAtKeysIo io when io.closedByClient) {
        await io.close();
      }
    }
  }
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
    session.server.timeline.add('put-document:$eid');
    if (session.server.documentPutFailures > 0) {
      session.server.documentPutFailures--;
      throw StateError('document put failed');
    }
    if (!session.server.dropDocumentWrites) {
      session.server.documents[eid] = document;
    }
  }
}

class _Pointers implements EnrollmentPointerStore {
  _Pointers(this.session);

  final FakeSession session;

  @override
  Future<String?> get(String atSign, String lookupHex, {required String ns}) =>
      session.server.get(atSign, lookupHex, ns: ns);

  @override
  Future<void> put(String atSign, String lookupHex, String record,
      {required String ns}) async {
    session.server.log.add('put-pointer:$lookupHex');
    session.server.timeline.add('put-pointer');
    session.server.onPointerPut?.call();
    if (session.server.pointerPutFailures > 0) {
      session.server.pointerPutFailures--;
      throw StateError('pointer put failed');
    }
    if (!session.server.dropPointerWrites) {
      session.server.pointers[lookupHex] = record;
      session.server.pointerNamespaces[lookupHex] = ns;
    }
  }
}

class FakeGateway implements EnrollmentGateway {
  FakeGateway(this.server);

  @override
  final device = 'Test Device';

  final FakeServer server;
  final activated = <({String atSign, Uint8List authSeed, String cram})>[];

  /// Every auth seed buffer handed in, by reference, so a test can see
  /// whether the caller wiped it.
  final seedBuffers = <Uint8List>[];
  FakeSession? lastSession;

  /// How many upcoming [authenticate] calls fail before any session exists.
  var authenticateFailures = 0;

  /// What those failures throw; a [StateError] when null.
  Object? authenticateError;

  /// The enrollment id of every [authenticate] call.
  final authenticated = <String>[];

  /// The close error the next session this gateway hands out will throw.
  Object? closeErrorForNext;

  /// When set, [activate] waits for it before answering.
  Completer<void>? gate;

  /// The open error the next session this gateway hands out will throw.
  Object? openErrorForNext;

  /// Whether that session stops a client it built before throwing.
  var openStopsFirstForNext = false;

  FakeSession _session(String eid) => FakeSession(server, eid)
    ..closeError = closeErrorForNext
    ..openClientError = openErrorForNext
    ..openClientStopsFirst = openStopsFirstForNext;

  @override
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required Uint8List authSeed}) async {
    seedBuffers.add(authSeed);
    authenticated.add(enrollmentId);
    if (authenticateFailures > 0) {
      authenticateFailures--;
      throw authenticateError ?? StateError('authenticate failed');
    }
    if (server.revoked.contains(enrollmentId) ||
        server.seedByEnrollment[enrollmentId] != authSeed.join(',')) {
      throw PkamRefusedException(enrollmentId);
    }
    final session = lastSession = _session(enrollmentId);
    onAuthenticate?.call(session);
    return session;
  }

  /// Runs on each session [authenticate] hands out.
  void Function(FakeSession session)? onAuthenticate;

  /// The exception the last unfinished [activate] threw.
  ActivationUnfinishedException? unfinished;

  /// Makes [activate] spend the CRAM, then fail its PKAM.
  var activationUnfinished = false;

  /// When set, [activate] throws it before anything is filed or spent, as an
  /// atServer that refuses the CRAM secret does.
  Object? activateRefusal;

  /// Runs inside [activate], once the CRAM is spent.
  FutureOr<void> Function()? onActivate;

  /// The keys [activate] files in the keys IO it is given, as a real
  /// activation does before it deletes the CRAM.
  AtKeys keysFor(String atSign, String eid, [ApkamKeyPair? pair]) =>
      withApkamKey(
          AtKeys.legacy(
              encryptionPublicKey: base64Encode(utf8.encode('enc-pub-$eid')),
              encryptionPrivateKey: base64Encode(utf8.encode('enc-priv-$eid')),
              selfEncryptionKey: base64Encode(utf8.encode('self-$eid')))
            ..atsign = Atsign(atSign),
          eid,
          pair ??
              (
                publicKey: base64Encode(utf8.encode('apkam-pub-$eid')),
                privateKey: base64Encode(utf8.encode('apkam-priv-$eid'))
              ));

  /// The keys the last [activate] filed.
  AtKeys? filed;

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required Uint8List authSeed,
      required String cram,
      WrittenAtKeysIo? keysIo}) async {
    seedBuffers.add(authSeed);
    activated.add(
        (atSign: atSign, authSeed: Uint8List.fromList(authSeed), cram: cram));
    await gate?.future;
    final refusal = activateRefusal;
    if (refusal != null) throw refusal;
    final eid = 'eid${++server.enrollments}';
    server.seedByEnrollment[eid] = authSeed.join(',');
    if (keysIo != null) {
      filed = keysFor(atSign, eid, await apkamKeyPairFromSeed(authSeed));
      await keysIo.write(atSign, filed!);
    }
    server.timeline.add('cram-spent');
    await onActivate?.call();
    if (activationUnfinished) {
      throw unfinished = ActivationUnfinishedException(eid,
          atKeys: {...server.keys}..remove('aesPkamPrivateKey'),
          cause: StateError('pkam failed'));
    }
    final session = lastSession = _session(eid);
    onAuthenticate?.call(session);
    return session;
  }
}

/// A passkey authenticator holding several passkeys; [current] answers an
/// assertion that names no credential.
class FakeAuthenticator implements PasskeyPort, UnknownCredentialSignal {
  final prfByCredential = <int, Uint8List>{};

  /// Every PRF buffer handed out, by reference: an authenticator returns
  /// fresh bytes per assertion.
  final issuedPrf = <Uint8List>[];
  Uint8List? current;
  Uint8List? lastAllowCredential;
  var gets = 0;
  var creates = 0;
  final created = <({String atSign, DateTime enrolledAt, String deviceName})>[];

  /// Makes every assertion fail as a cancelled or unmatched ceremony.
  var yieldsNoCredential = false;

  /// The credential ids the platform was told are unknown.
  final signalled = <Uint8List>[];

  @override
  Future<void> signalUnknownCredential(Uint8List credentialId) async {
    signalled.add(credentialId);
    if (signalFails) throw StateError('platform refused');
  }

  /// Makes the signal fail, as a browser without the call does.
  var signalFails = false;

  @override
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName}) async {
    creates++;
    created
        .add((atSign: atSign, enrolledAt: enrolledAt, deviceName: deviceName));
    final n = prfByCredential.length;
    final id = Uint8List.fromList([n + 1]);
    prfByCredential[id[0]] =
        Uint8List.fromList(List.generate(32, (i) => i + n));
    current = id;
    return (credentialId: id, prfEnabled: true);
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    gets++;
    lastAllowCredential = allowCredential;
    if (yieldsNoCredential) throw PasskeyCeremonyException('NotAllowedError');
    if (allowCredential != null &&
        !prfByCredential.containsKey(allowCredential[0])) {
      // As a browser answers a narrowed ceremony whose passkey was deleted.
      throw PasskeyCeremonyException('NotAllowedError');
    }
    final id = allowCredential ?? current!;
    final stored = prfByCredential[id[0]];
    final prf = stored == null ? null : Uint8List.fromList(stored);
    if (prf != null) issuedPrf.add(prf);
    return (credentialId: id, prfFirst: prf);
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

/// Hints held in memory by one object that is both hint ports and writes the
/// pair together, as a combined store does.
class FakeHints extends LegacyHints implements PasskeyHintStore {
  /// The pairs written through [putHint].
  var pairWrites = 0;

  /// Makes [putHint] throw before it stores either id.
  var failPairWrites = false;

  @override
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    if (failWrites || failPairWrites) throw StateError('hint write failed');
    pairWrites++;
    credentials[atSign] = credentialId;
    ids[atSign] = enrollmentId;
  }
}

/// Hints held in memory by a store that is only the two separate ports.
class LegacyHints implements CredentialHintStore, EnrollmentIdStore {
  /// Makes every write fail.
  var failWrites = false;

  final credentials = <String, Uint8List>{};
  final ids = <String, String>{};

  /// How many single ids were written.
  var singleWrites = 0;

  @override
  Future<Uint8List?> credentialId(String atSign) async => credentials[atSign];

  @override
  Future<void> putCredentialId(String atSign, Uint8List id) async {
    if (failWrites) throw StateError('hint write failed');
    singleWrites++;
    credentials[atSign] = id;
  }

  @override
  Future<String?> enrollmentId(String atSign) async => ids[atSign];

  @override
  Future<void> putEnrollmentId(String atSign, String id) async {
    singleWrites++;
    ids[atSign] = id;
  }
}

/// The pending-onboarding records of one device, in memory.
class FakePendingStore implements PendingOnboardingStore {
  FakePendingStore([this.timeline]);

  /// Where each put and delete is noted, in order with the rest of an
  /// onboarding, when given.
  final List<String>? timeline;
  final records = <String, PendingOnboardingRecord>{};

  /// How many records were put.
  var puts = 0;

  /// Makes every put throw.
  var failPuts = false;

  /// Makes every delete throw.
  var failDeletes = false;

  @override
  Future<PendingOnboardingRecord?> get(String atSign) async => records[atSign];

  @override
  Future<void> put(String atSign, PendingOnboardingRecord record) async {
    if (failPuts) throw StateError('pending put failed');
    puts++;
    timeline?.add('put-pending');
    records[atSign] = record;
  }

  @override
  Future<void> delete(String atSign) async {
    if (failDeletes) throw StateError('pending delete failed');
    timeline?.add('delete-pending');
    records.remove(atSign);
  }
}

class FakePersistence implements StoragePersistence {
  FakePersistence([this.timeline]);

  /// Where each request is noted, in order with the rest of an onboarding.
  final List<String>? timeline;
  var requests = 0;
  Object? error;

  @override
  Future<bool> requestPersist() async {
    requests++;
    timeline?.add('request-persist');
    if (error case final e?) throw e;
    return true;
  }
}

/// What a test derives from a PRF output to check the custody flows' records
/// and enrollments: the names, a copy of the auth seed and a vault that opens
/// and seals the way the flow's vault does.
class DerivedKeys {
  DerivedKeys._(this.lookupHex, this.ns, this.authSeed, this.vault);

  static Future<DerivedKeys> derive(Uint8List prf, String atSign) async {
    final derivation =
        await const BytesPasskeyKeyDeriver().derive(PrfSecret(prf), atSign);
    return DerivedKeys._(
        derivation.lookupHex,
        derivation.ns,
        Uint8List.fromList(derivation.authSeed),
        PasskeyVault(derivation, atSign: atSign));
  }

  final String lookupHex;
  final String ns;
  final Uint8List authSeed;
  final PasskeyVault vault;
}
