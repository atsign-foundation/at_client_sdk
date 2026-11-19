@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys, WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart'
    show
        AtClient,
        AtConnection,
        AtConnectionCause,
        AtConnectionState,
        AtKey,
        ServerMutexLease;
import 'package:at_client/passkey.dart';
import 'package:at_client_wasm/src/keys/indexeddb_store.dart';
import 'package:at_client_wasm/src/keys/web_crypto_passkey.dart';
import 'package:at_client_wasm/src/keys/web_prf_environment.dart';
import 'package:at_client_wasm/src/session/portal_session.dart'
    show PortalSessionOfflineException;
import 'package:at_client_wasm/src/session/web_setup_lock.dart';
import 'package:at_client_wasm/src/session/web_storage_persistence.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

const _atSign = '@alice';
const _cram = 'cram-secret';
const _encPublic = 'ZW5jLXB1YmxpYw==';

/// The atServer as the custody flows see it: pointers, each enrollment's
/// sealed document and the APKAM public key each enrollment authenticates
/// with.
class _Server implements EnrollmentPointerReader {
  final pointers = <String, String>{};
  final pointerNamespaces = <String, String>{};
  final documents = <String, String>{};
  final apkamPublicKeys = <String, String>{};
  final approved = <String>{};
  var pointerReads = 0;
  var enrollments = 0;
  var clientsOffline = false;

  /// The encryption public key published for the atSign, once published.
  String? publishedKey;

  /// Whether the CRAM secret is not yet deleted; an activation needs it.
  var cramLive = true;

  final keys = <String, dynamic>{
    'aesPkamPrivateKey': 'YXBrYW0tcHJpdmF0ZQ==',
    'aesEncryptPrivateKey': 'ZW5jLXByaXZhdGU=',
    'aesEncryptPublicKey': _encPublic,
  };

  @override
  Future<String?> get(String atSign, String lookupHex,
      {required String ns}) async {
    pointerReads++;
    return pointerNamespaces[lookupHex] == ns ? pointers[lookupHex] : null;
  }
}

class _Client implements AtClient {
  _Client(this.session, this.keysIo);

  final _Session session;
  final WrittenAtKeysIo keysIo;

  @override
  final connection = AtConnection(
      atSign: _atSign, attempt: (_) async => AtConnectionState.online());

  @override
  String? get enrollmentId => session.enrollmentId;

  Future<void>? _stopping;

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    await connection.close();
    await session.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements EnrollmentSession {
  _Session(this.server, this.enrollmentId);

  final _Server server;
  @override
  final String enrollmentId;
  var closed = false;

  @override
  Future<Map<String, dynamic>> atKeys() async => server.keys;

  @override
  Future<PublishedEncryptionKey> publishedEncryptionKey(
      Map<String, dynamic> atKeys) async {
    final held = atKeys['aesEncryptPublicKey'];
    if (held is! String) return PublishedEncryptionKey.same;
    return switch (server.publishedKey) {
      null => PublishedEncryptionKey.none,
      final published when published == held => PublishedEncryptionKey.same,
      _ => PublishedEncryptionKey.different,
    };
  }

  @override
  Future<void> revokeOtherEnrollments() async {
    server.approved.removeWhere((eid) => eid != enrollmentId);
  }

  @override
  Future<void> completeActivation(Map<String, dynamic> atKeys) async {
    if (atKeys['aesEncryptPublicKey'] case final String key) {
      server.publishedKey = key;
    }
    server.cramLive = false;
  }

  @override
  late final EnrollmentDocumentStore documents = _Documents(this);

  @override
  late final EnrollmentPointerStore pointers = _Pointers(server);

  @override
  Future<AtClient> openClient(WrittenAtKeysIo keysIo) async {
    final client = _Client(this, keysIo);
    if (server.clientsOffline) {
      // As the session opener does: stop the client, then throw.
      await client.stop();
      throw PortalSessionOfflineException(
          _atSign, AtConnectionState.offline(AtConnectionCause.unreachable));
    }
    return client;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _Documents implements EnrollmentDocumentStore {
  _Documents(this.session);

  final _Session session;

  @override
  Future<String?> get(String atSign, String eid) async =>
      session.server.documents[eid];

  @override
  Future<void> put(String atSign, String eid, String document) async =>
      session.server.documents[eid] = document;

  @override
  Future<ServerMutexLease?> tryLock(String atSign, String eid,
          {required Duration ttl}) async =>
      ServerMutexLease(
          AtKey()..key = 'atkeys-lock.$eid.a', DateTime.now().add(ttl));
}

class _Pointers implements EnrollmentPointerStore {
  _Pointers(this.server);

  final _Server server;

  @override
  Future<String?> get(String atSign, String lookupHex, {required String ns}) =>
      server.get(atSign, lookupHex, ns: ns);

  @override
  Future<void> put(String atSign, String lookupHex, String record,
      {required String ns}) async {
    server.pointers[lookupHex] = record;
    server.pointerNamespaces[lookupHex] = ns;
  }
}

class _Gateway implements EnrollmentGateway {
  _Gateway(this.server);

  @override
  final device = 'Test Device';

  final _Server server;
  var activations = 0;
  _Session? lastSession;

  /// Throws this once the enrollment is approved, as a tab that dies there
  /// would.
  Object? dieAfterActivation;

  /// Every APKAM key pair this gateway received.
  final pairs = <ApkamKeyPair>[];

  @override
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required ApkamKeyPair apkamKeyPair}) async {
    pairs.add(apkamKeyPair);
    if (!server.approved.contains(enrollmentId) ||
        server.apkamPublicKeys[enrollmentId] != apkamKeyPair.publicKey) {
      throw PkamRefusedException(enrollmentId);
    }
    return lastSession = _Session(server, enrollmentId);
  }

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required ApkamKeyPair apkamKeyPair,
      required String cram}) async {
    pairs.add(apkamKeyPair);
    if (!server.cramLive) throw StateError('the CRAM secret is deleted');
    activations++;
    final eid = 'eid${++server.enrollments}';
    server.apkamPublicKeys[eid] = apkamKeyPair.publicKey;
    server.approved.add(eid);
    final died = dieAfterActivation;
    if (died != null) throw died;
    return lastSession = _Session(server, eid);
  }
}

/// Derives as this browser does, and keeps a copy of each auth seed so a test
/// can look for it in the browser's stores.
class _SeedKeepingDeriver implements PasskeyKeyDeriver {
  _SeedKeepingDeriver(this.seeds);

  final List<Uint8List> seeds;

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final derivation = await WebCryptoKeyDeriver().derive(prf, atSign);
    seeds.add(Uint8List.fromList(derivation.authSeed));
    return derivation;
  }
}

/// An authenticator holding one passkey with a fixed PRF output.
class _Authenticator implements PasskeyPort {
  final _id = Uint8List.fromList([7]);
  final prfOutput = Uint8List.fromList(List.generate(32, (i) => i + 3));

  /// The credential each assertion was narrowed to, or null for one that
  /// asked for any passkey.
  final asked = <Uint8List?>[];

  @override
  Future<PasskeyCreation> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) async =>
      (credentialId: _id, prfEnabled: true);

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    asked.add(allowCredential);
    return (credentialId: _id, prfFirst: Uint8List.fromList(prfOutput));
  }
}

/// One browser profile: an IndexedDB database over real IndexedDB, locks and
/// storage, against [server] and one authenticator.
class _Device {
  _Device(this.dbName, this.server);

  final String dbName;
  final _Server server;
  final _authenticator = _Authenticator();
  late IndexedDbHintStore store;

  /// Applied to each gateway this device builds.
  Object? dieAfterActivation;
  late _Gateway gateway;
  final sessions = <PasskeySession>[];

  /// A copy of every auth seed this device derived.
  final seeds = <Uint8List>[];

  Future<PasskeyCustody> custody() async {
    store = await IndexedDbHintStore.open(dbName: dbName);
    gateway = _Gateway(server)..dieAfterActivation = dieAfterActivation;
    return PasskeyCustody(
        prf: PasskeyPrf(_authenticator,
            prfSupport: PrfSupport(WebPrfEnvironment())),
        pointerReader: server,
        gateway: gateway,
        credentials: store,
        enrollmentIds: store,
        setupLock: WebSetupLock(),
        setupLockPrefix: WebSetupLock.namePrefix,
        persistence: WebStoragePersistence(),
        deriver: _SeedKeepingDeriver(seeds));
  }

  Future<AtClient> onboard() async {
    final session =
        await (await custody()).onboard(atSign: _atSign, cram: _cram);
    sessions.add(session);
    return session.client;
  }

  Future<AtClient> open() async {
    final session = await (await custody()).open(atSign: _atSign);
    sessions.add(session);
    return session.client;
  }

  /// Clears site data: IndexedDB and web storage. The passkey and the
  /// atServer survive.
  Future<void> clearSiteData() async {
    store.close();
    final done = Completer<void>();
    final request = window.indexedDB.deleteDatabase(dbName);
    request.onsuccess = (Event _) {
      done.complete();
    }.toJS;
    request.onerror = (Event _) {
      done.completeError(StateError('deleteDatabase failed'));
    }.toJS;
    await done.future;
    window.localStorage.clear();
    window.sessionStorage.clear();
  }

  Future<void> dispose() async {
    for (final session in sessions) {
      await session.stop();
    }
    store.close();
    await clearSiteData();
  }
}

Future<JSAny?> _settled(IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = (Event _) {
    done.complete(request.result);
  }.toJS;
  request.onerror = (Event _) {
    done.completeError(StateError('IndexedDB request failed'));
  }.toJS;
  return done.future;
}

/// Every record of every object store of database [dbName], by store name
/// then key; the value of a record is its bytes.
Future<Map<String, Map<String, Uint8List>>> _dump(String dbName) async {
  final db = await _settled(window.indexedDB.open(dbName)) as IDBDatabase;
  try {
    final dump = <String, Map<String, Uint8List>>{};
    for (var i = 0; i < db.objectStoreNames.length; i++) {
      final name = db.objectStoreNames.item(i)!;
      final store = db.transaction(name.toJS, 'readonly').objectStore(name);
      final keys = (await _settled(store.getAllKeys()) as JSArray<JSAny?>)
          .toDart
          .map((k) => (k! as JSString).toDart)
          .toList();
      final values = (await _settled(store.getAll()) as JSArray<JSAny?>).toDart;
      dump[name] = {
        for (var j = 0; j < keys.length; j++)
          keys[j]: (values[j]! as JSUint8Array).toDart,
      };
    }
    return dump;
  } finally {
    db.close();
  }
}

/// Completes when [tx] commits, and fails when it aborts.
Future<void> _committed(IDBTransaction tx) {
  final done = Completer<void>();
  tx.oncomplete = (Event _) {
    done.complete();
  }.toJS;
  tx.onabort = (Event _) {
    if (!done.isCompleted) done.completeError(StateError('aborted'));
  }.toJS;
  return done.future;
}

/// Creates database [dbName] with the passkey hint stores, a unique index over
/// the credentials store's values, and [holder] holding the credential id the
/// test authenticator registers, so writing that id for another atSign fails
/// with a `ConstraintError`.
Future<void> _seedCredentialHeldBy(String dbName, String holder) async {
  final request = window.indexedDB.open(dbName);
  request.onupgradeneeded = (Event _) {
    final db = request.result as IDBDatabase;
    db.createObjectStore('at_client_wasm_credentials').createIndex(
        'one_atsign_per_credential', ''.toJS, IDBIndexParameters(unique: true));
    db.createObjectStore('at_client_wasm_enrollments');
  }.toJS;
  final db = await _settled(request) as IDBDatabase;
  try {
    final tx = db.transaction('at_client_wasm_credentials'.toJS, 'readwrite');
    tx
        .objectStore('at_client_wasm_credentials')
        .put(Uint8List.fromList([7]).toJS, holder.toJS);
    await _committed(tx);
  } finally {
    db.close();
  }
}

/// Deletes [atSign]'s credential id from database [dbName].
Future<void> _deleteCredential(String dbName, String atSign) async {
  final db = await _settled(window.indexedDB.open(dbName)) as IDBDatabase;
  try {
    final tx = db.transaction('at_client_wasm_credentials'.toJS, 'readwrite');
    tx.objectStore('at_client_wasm_credentials').delete(atSign.toJS);
    await _committed(tx);
  } finally {
    db.close();
  }
}

/// Stores [bytes] as [atSign]'s enrollment id in database [dbName], as they
/// are.
Future<void> _putEnrollmentBytes(
    String dbName, String atSign, List<int> bytes) async {
  final db = await _settled(window.indexedDB.open(dbName)) as IDBDatabase;
  try {
    final tx = db.transaction('at_client_wasm_enrollments'.toJS, 'readwrite');
    tx
        .objectStore('at_client_wasm_enrollments')
        .put(Uint8List.fromList(bytes).toJS, atSign.toJS);
    await _committed(tx);
  } finally {
    db.close();
  }
}

/// Makes this browser's IndexedDB fail every read from object store
/// [storeName] until the test ends, as a read request that errors does;
/// reads of every other object store go through.
void _failReadsOf(String storeName) {
  final prototype =
      (globalContext['IDBObjectStore'] as JSObject)['prototype'] as JSObject;
  final get = prototype['get'] as JSFunction;
  prototype['get'] = ((JSObject store, JSAny? key) {
    if ((store['name'] as JSString).toDart != storeName) {
      return get.callAsFunction(store, key);
    }
    final request = JSObject()
      ..['error'] = DOMException('The read failed.', 'UnknownError');
    Timer.run(() => (request['onerror'] as JSFunction)
        .callAsFunction(request, Event('error')));
    return request;
  }).toJSCaptureThis;
  addTearDown(() => prototype['get'] = get);
}

Future<List<String>> _databases(String prefix) async {
  final all = (await window.indexedDB.databases().toDart).toDart;
  return [
    for (final info in all)
      if (info.name.startsWith(prefix)) info.name,
  ];
}

Future<AtKeys> _keysOf(AtClient client) async =>
    (client as _Client).keysIo.read(_atSign);

/// Every typed material entry of [keys] (the derived pair), in order.
List<Map<String, dynamic>> _pair(Map<String, dynamic> keys) => [
      for (final e in keys['enrollments'] as List)
        for (final k in (e as Map)['keys'] as List)
          for (final m in (k as Map)['material'] as List)
            (m as Map).cast<String, dynamic>()
    ];

/// The createdAt of each typed material entry of [keys]; each must parse.
List<DateTime> _pairStamps(Map<String, dynamic> keys) =>
    [for (final m in _pair(keys)) DateTime.parse(m['createdAt'] as String)];

/// [keys] with only the typed material's createdAt removed: the one field a
/// read stamps afresh.
Map<String, dynamic> _withoutPairStamps(Map<String, dynamic> keys) {
  final copy = jsonDecode(jsonEncode(keys)) as Map<String, dynamic>;
  for (final m in _pair(copy)) {
    m.remove('createdAt');
  }
  return copy;
}

String _dbName() => 'custody_${DateTime.now().microsecondsSinceEpoch}';

void main() {
  late _Device device;
  late _Server server;

  setUp(() {
    window.localStorage.clear();
    window.sessionStorage.clear();
    server = _Server();
    device = _Device(_dbName(), server);
  });

  tearDown(() => device.dispose());

  test(
      'enroll, clear site data, recover with the passkey only: same '
      'enrollment, same keys', () async {
    final enrolled = await device.onboard();
    final enrolledId = enrolled.enrollmentId;
    final enrolledKeys = (await _keysOf(enrolled)).toJson();
    expect(enrolledKeys['aesEncryptPrivateKey'], isNotNull);
    await device.clearSiteData();

    final fresh = await device.custody();
    expect(await device.store.credentialId(_atSign), isNull);
    expect(await device.store.enrollmentId(_atSign), isNull);
    final session = await fresh.open(atSign: _atSign);
    device.sessions.add(session);
    final recovered = session.client;

    expect(recovered.enrollmentId, enrolledId);
    final recoveredKeys = (await _keysOf(recovered)).toJson();
    // Each read files the derived APKAM pair as fresh typed material, so only
    // its createdAt differs between the two reads.
    expect(_withoutPairStamps(recoveredKeys), _withoutPairStamps(enrolledKeys),
        reason: 'recovery restores the keys onboarding made');
    expect(_pairStamps(enrolledKeys), hasLength(2));
    expect(_pairStamps(recoveredKeys), hasLength(2));
    expect((await _keysOf(recovered)).enrollmentToAuthenticateAs(), enrolledId);
    expect(device.gateway.activations, 0, reason: 'recovery spends no CRAM');
    expect(server.pointerReads, 1);
    expect(await device.store.enrollmentId(_atSign), enrolledId);
    expect(await device.store.credentialId(_atSign), [7]);
  });

  test(
      'an onboard whose client open fails offline surfaces that error and '
      'leaves the atSign ready for passkey login', () async {
    server.clientsOffline = true;
    await expectLater(
        device.onboard(), throwsA(isA<PortalSessionOfflineException>()));
    expect(device.gateway.lastSession!.closed, isTrue);
    expect(server.cramLive, isFalse);

    server.clientsOffline = false;
    final onboarded = device.gateway.lastSession!.enrollmentId;
    final loggedIn = await device.open();
    expect(loggedIn.enrollmentId, onboarded);
    expect(server.enrollments, 1, reason: 'login enrolls nothing');
    await _expectOnlyHint(device, onboarded);
  });

  test(
      'A failed IndexedDB write of the passkey hints during onboarding returns '
      'the session, and a login then saves the hints', () async {
    await _seedCredentialHeldBy(device.dbName, '@bob');
    final custody = await device.custody();

    final onboarded = await custody.onboard(atSign: _atSign, cram: _cram);
    device.sessions.add(onboarded);
    device.store.close();

    final enrollmentId = device.gateway.lastSession!.enrollmentId;
    expect(onboarded.client.enrollmentId, enrollmentId,
        reason: 'a passkey session as the new enrollment, and no '
            'IndexedDbException');
    expect(server.cramLive, isFalse,
        reason: 'the hint write comes after the CRAM secret is deleted');
    final dump = await _dump(device.dbName);
    expect(
        dump['at_client_wasm_credentials'],
        {
          '@bob': [7]
        },
        reason: 'the control: IndexedDB refused the write of the hints');
    expect(dump['at_client_wasm_enrollments'], isEmpty,
        reason: 'this browser holds no passkey hints for the atSign');

    await _deleteCredential(device.dbName, '@bob');
    final loggedIn = await device.open();
    expect(loggedIn.enrollmentId, enrollmentId);
    expect(server.enrollments, 1, reason: 'the login enrolls nothing');
    await _expectOnlyHint(device, enrollmentId);
  });

  test(
      'A remembered enrollment id whose stored bytes are not UTF-8 counts as '
      'no hints', () async {
    final enrollmentId = (await device.onboard()).enrollmentId!;
    device.store.close();
    await _putEnrollmentBytes(device.dbName, _atSign, [0x65, 0xff, 0xfe]);
    final custody = await device.custody();
    expect(await device.store.credentialId(_atSign), [7],
        reason: 'the control: this browser remembers the passkey');
    expect(await device.store.enrollmentId(_atSign), isNull,
        reason: 'the store reads bytes that are not UTF-8 as no enrollment '
            'id');
    device._authenticator.asked.clear();
    final pointerReads = server.pointerReads;

    final session = await custody.open(atSign: _atSign);
    device.sessions.add(session);

    expect(device._authenticator.asked, [null],
        reason: 'the login asserts any passkey');
    expect(server.pointerReads, pointerReads + 1,
        reason: "the login reads the passkey's pointer");
    expect(session.client.enrollmentId, enrollmentId,
        reason: 'logged in as the pointed enrollment, with no '
            'IndexedDbException and no FormatException');
    await _expectOnlyHint(device, enrollmentId);
  });

  test(
      'A failed IndexedDB read of the remembered enrollment id counts as no '
      'hints', () async {
    final enrollmentId = (await device.onboard()).enrollmentId!;
    device.store.close();
    final custody = await device.custody();
    expect(await device.store.enrollmentId(_atSign), enrollmentId,
        reason: 'the control: this browser holds the passkey hints');
    _failReadsOf('at_client_wasm_enrollments');
    await expectLater(
        device.store.enrollmentId(_atSign),
        throwsA(isA<IndexedDbException>()
            .having((e) => e.message, 'message', contains('UnknownError'))),
        reason: 'the control: IndexedDB fails the read of the remembered '
            'enrollment id');
    expect(await device.store.credentialId(_atSign), [7],
        reason: 'the control: the credential id is still read');
    device._authenticator.asked.clear();
    final pointerReads = server.pointerReads;

    final session = await custody.open(atSign: _atSign);
    device.sessions.add(session);

    expect(device._authenticator.asked, [null],
        reason: 'the login asserts any passkey');
    expect(server.pointerReads, pointerReads + 1,
        reason: "the login reads the passkey's pointer");
    expect(session.client.enrollmentId, enrollmentId,
        reason: 'logged in as the pointed enrollment, with no '
            'IndexedDbException');
  });

  test(
      'A failed IndexedDB read of the remembered credential id counts as no '
      'hints', () async {
    final enrollmentId = (await device.onboard()).enrollmentId!;
    device.store.close();
    final custody = await device.custody();
    expect(await device.store.credentialId(_atSign), [7],
        reason: 'the control: this browser holds the passkey hints');
    _failReadsOf('at_client_wasm_credentials');
    await expectLater(
        device.store.credentialId(_atSign),
        throwsA(isA<IndexedDbException>()
            .having((e) => e.message, 'message', contains('UnknownError'))),
        reason: 'the control: IndexedDB fails the read of the remembered '
            'credential id');
    expect(await device.store.enrollmentId(_atSign), enrollmentId,
        reason: 'the control: the enrollment id is still read');
    device._authenticator.asked.clear();
    final pointerReads = server.pointerReads;

    final session = await custody.open(atSign: _atSign);
    device.sessions.add(session);

    expect(device._authenticator.asked, [null],
        reason: 'the login asserts any passkey');
    expect(server.pointerReads, pointerReads + 1,
        reason: "the login reads the passkey's pointer");
    expect(session.client.enrollmentId, enrollmentId,
        reason: 'logged in as the pointed enrollment, with no '
            'IndexedDbException');
  });

  test('after onboarding and recovery the browser stores hold only the hint',
      () async {
    final enrolled = await device.onboard();
    final enrolledId = enrolled.enrollmentId!;
    await _expectOnlyHint(device, enrolledId);

    await device.clearSiteData();
    await device.open();
    await _expectOnlyHint(device, enrolledId);
  });

  test(
      'a remembered enrollment reads no pointer; an empty IndexedDB asserts '
      'discoverably, reads the pointer, then authenticates', () async {
    final enrolled = await device.onboard();

    final remembered = await device.open();
    expect(server.pointerReads, 0);
    expect(remembered.enrollmentId, enrolled.enrollmentId);

    await device.clearSiteData();
    final recovered = await device.open();
    expect(server.pointerReads, 1);
    expect(recovered.enrollmentId, enrolled.enrollmentId);
  });

  test(
      'restored public keys that differ from the published ones: open '
      'throws, closes the session and rewrites no hint', () async {
    await device.onboard();
    await device.clearSiteData();
    server.publishedKey = 'rotated';

    final fresh = await device.custody();
    await expectLater(fresh.open(atSign: _atSign),
        throwsA(isA<PublicKeyMismatchException>()));
    expect(device.gateway.lastSession!.closed, isTrue);
    expect(await device.store.credentialId(_atSign), isNull);
    expect(await device.store.enrollmentId(_atSign), isNull);
  });

  group('a tab that dies after the activation', () {
    setUp(() => device.dieAfterActivation = StateError('tab died'));

    /// Kills the tab right after activation, then reloads: a fresh custody
    /// over the same IndexedDB and the same passkey.
    Future<void> dieThenReload() async {
      await expectLater(device.onboard(), throwsA(isA<StateError>()));
      expect(device.gateway.activations, 1);
      expect(server.cramLive, isTrue);
      device.store.close();
      device.dieAfterActivation = null;
    }

    test('The device keeps nothing about an onboarding that did not complete',
        () async {
      await dieThenReload();
      final dump = await _dump(device.dbName);
      expect(
          dump.keys,
          unorderedEquals(
              ['at_client_wasm_credentials', 'at_client_wasm_enrollments']));
      for (final records in dump.values) {
        expect(records, isEmpty);
      }
    });

    test('reload then onboard again with the same CRAM secret completes',
        () async {
      await dieThenReload();
      final client = await device.onboard();
      expect(client.enrollmentId, 'eid2');
      expect(server.cramLive, isFalse);
      expect(server.publishedKey, _encPublic);
      await _expectOnlyHint(device, 'eid2');
    });

    test('reload then log in finds no pointer and is a lost passkey', () async {
      await dieThenReload();
      await expectLater(device.open(), throwsA(isA<PasskeyLostException>()));
      expect(server.enrollments, 1);
    });
  });
}

/// Asserts that [device] holds only the hint: the passkey's credential id and
/// the enrollment id under the atSign, in the one database, with no key
/// material in any record.
Future<void> _expectOnlyHint(_Device device, String enrollmentId) async {
  expect(await _databases('custody_'), [device.dbName]);
  final dump = await _dump(device.dbName);
  expect(
      dump.keys,
      unorderedEquals(
          ['at_client_wasm_credentials', 'at_client_wasm_enrollments']));
  expect(dump['at_client_wasm_credentials'], {
    _atSign: [7]
  });
  expect(
      dump['at_client_wasm_enrollments'], {_atSign: utf8.encode(enrollmentId)});

  final haystack = [
    for (final records in dump.values)
      for (final entry in records.entries) ...[
        entry.key,
        latin1.decode(entry.value),
      ],
    for (final storage in [window.localStorage, window.sessionStorage])
      for (var i = 0; i < storage.length; i++) ...[
        storage.key(i)!,
        storage.getItem(storage.key(i)!)!,
      ],
  ].join('\u0000');
  final secretBytes = [
    device._authenticator.prfOutput,
    ...device.seeds,
    for (final pair in device.gateway.pairs) base64.decode(pair.privateKey),
    for (final value in device.server.keys.values)
      Uint8List.fromList(utf8.encode('$value')),
  ];
  expect(secretBytes, isNotEmpty);
  for (final bytes in secretBytes) {
    final hex =
        [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
    final encodings = {
      latin1.decode(bytes),
      base64.encode(bytes),
      base64Url.encode(bytes),
      base64.encode(bytes).replaceAll('=', ''),
      base64Url.encode(bytes).replaceAll('=', ''),
      hex,
      hex.toUpperCase(),
    };
    for (final encoding in encodings) {
      expect(haystack, isNot(contains(encoding)),
          reason: 'secret found as $encoding');
    }
  }

  final localKeys = [
    for (var i = 0; i < window.localStorage.length; i++)
      window.localStorage.key(i)!,
  ];
  expect(localKeys.toSet().difference({'at_client_wasm:prf-miss-at'}), isEmpty);
  expect(window.sessionStorage.length, 0);
}
