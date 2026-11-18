@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show AtKeys, CryptographicMaterialAlgorithm, WrittenAtKeysIo;
import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart'
    show AtClient, AtConnectionCause, AtConnectionState;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/at_keys_document.dart'
    show atKeysDocument;
import 'package:at_commons/at_commons.dart' show InvalidAtSignException;
import 'package:at_commons/atsign.dart' show Atsign;
import 'package:at_client_wasm/src/keys/indexeddb_store.dart';
import 'package:at_client_wasm/src/keys/web_crypto_passkey.dart';
import 'package:at_client_wasm/src/keys/web_prf_environment.dart';
import 'package:at_client_wasm/src/session/portal_session.dart'
    show PortalSessionOfflineException;
import 'package:at_client_wasm/src/session/web_passkey_entry.dart'
    show closingStoreAfter, discardPendingOnboardingIn;
import 'package:at_client_wasm/src/session/web_setup_lock.dart';
import 'package:at_client_wasm/src/session/web_storage_persistence.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

const _atSign = '@alice';
const _cram = 'cram-secret';
const _encPublic = 'ZW5jLXB1YmxpYw==';

/// The atServer as the custody flows see it: pointers, each enrollment's
/// sealed document and the seed each enrollment authenticates with.
class _Server implements EnrollmentPointerReader {
  final pointers = <String, String>{};
  final pointerNamespaces = <String, String>{};
  final documents = <String, String>{};
  final seeds = <String, String>{};
  var pointerReads = 0;
  var enrollments = 0;
  var clientsOffline = false;

  /// The encryption public key published for the atSign, once published.
  String? publishedKey;

  /// Whether the CRAM secret was spent by an activation and is not yet
  /// deleted.
  var cramLive = true;
  var cramSpent = false;

  /// The document the last activation journalled: what a resume reports as
  /// the activated keys, so a retry finds the document its failed attempt
  /// published.
  Map<String, dynamic>? journalled;

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
  String? get enrollmentId => session.enrollmentId;

  @override
  Future<void> stop() => session.close();

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
  Future<Map<String, dynamic>> atKeys() async =>
      server.journalled ?? server.keys;

  @override
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys) async =>
      atKeys['aesEncryptPublicKey'] == server.publishedKey;

  @override
  Future<void> completeActivation(Map<String, dynamic> atKeys) async {
    final published = server.publishedKey;
    if (published == null) {
      server.publishedKey = atKeys['aesEncryptPublicKey'] as String;
    } else if (published != atKeys['aesEncryptPublicKey']) {
      throw PublicKeyMismatchException();
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

  /// Throws this once the CRAM is spent and the keys are filed, as a tab that
  /// dies there would.
  Object? dieAfterActivation;

  /// Every auth seed this gateway received, raw.
  final seeds = <Uint8List>[];

  @override
  Future<EnrollmentSession> authenticate(
      {required String atSign,
      required String enrollmentId,
      required Uint8List authSeed}) async {
    seeds.add(Uint8List.fromList(authSeed));
    if (server.seeds[enrollmentId] != authSeed.join(',')) {
      throw PkamRefusedException(enrollmentId);
    }
    return lastSession = _Session(server, enrollmentId);
  }

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required Uint8List authSeed,
      required String cram,
      WrittenAtKeysIo? keysIo}) async {
    seeds.add(Uint8List.fromList(authSeed));
    activations++;
    server.cramSpent = true;
    final eid = 'eid${++server.enrollments}';
    server.seeds[eid] = authSeed.join(',');
    final minted = _minted(atSign, eid);
    server.journalled = atKeysDocument(minted, atSign);
    await keysIo?.write(atSign, minted);
    final died = dieAfterActivation;
    if (died != null) throw died;
    server.publishedKey = _encPublic;
    server.cramLive = false;
    return lastSession = _Session(server, eid);
  }

  /// The keys an activation mints, with the enrollment's APKAM key filed.
  AtKeys _minted(String atSign, String eid) => AtKeys.legacy(
      encryptionPublicKey: _encPublic,
      encryptionPrivateKey: server.keys['aesEncryptPrivateKey'] as String,
      selfEncryptionKey: 'c2VsZi1rZXk=')
    ..atsign = Atsign(atSign)
    ..fileApkamMaterial(
        enrollmentId: eid,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        publicKey: 'YXBrYW0tcHVibGlj',
        privateKey: server.keys['aesPkamPrivateKey'] as String);
}

/// An authenticator holding one passkey with a fixed PRF output.
class _Authenticator implements PasskeyPort {
  final _id = Uint8List.fromList([7]);
  final prfOutput = Uint8List.fromList(List.generate(32, (i) => i + 3));

  @override
  Future<PasskeyCreation> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) async =>
      (credentialId: _id, prfEnabled: true);

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      (credentialId: _id, prfFirst: Uint8List.fromList(prfOutput));
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
  final clients = <AtClient>[];

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
        pendingStore: store,
        deriver: WebCryptoKeyDeriver());
  }

  Future<AtClient> onboard() async {
    final client =
        await (await custody()).onboard(atSign: _atSign, cram: _cram);
    clients.add(client);
    return client;
  }

  /// Onboards as the browser entry point does: the store closes when the
  /// onboarding ends, however it ends.
  Future<AtClient> onboardThroughEntry() async {
    final custody = await this.custody();
    return closingStoreAfter(
        store, () => custody.onboard(atSign: _atSign, cram: _cram));
  }

  Future<AtClient> open() async {
    final client = await (await custody()).open(atSign: _atSign);
    clients.add(client);
    return client;
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
    for (final client in clients) {
      await client.stop();
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
    final recovered = await fresh.open(atSign: _atSign);
    device.clients.add(recovered);

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
      'an onboard whose client open fails offline surfaces that error, closes '
      'the store and leaves the atSign ready for passkey login', () async {
    server.clientsOffline = true;
    await expectLater(device.onboardThroughEntry(),
        throwsA(isA<PortalSessionOfflineException>()));
    expect(device.gateway.lastSession!.closed, isTrue);
    await expectLater(
        device.store.credentialId(_atSign), throwsA(isA<IndexedDbException>()),
        reason: 'the failed onboard closed its IndexedDB store');

    // The record is deleted only after the client opens, so a failed open
    // keeps it.
    Future<bool> recordKept() async {
      final probe = await IndexedDbHintStore.open(dbName: device.dbName);
      try {
        return await probe.get(_atSign) != null;
      } finally {
        probe.close();
      }
    }

    expect(await recordKept(), isTrue,
        reason: 'a failed open keeps the pending record');

    server.clientsOffline = false;
    final failedEnrollment = device.gateway.lastSession!.enrollmentId;
    final loggedIn = await device.open();
    expect(loggedIn.enrollmentId, failedEnrollment,
        reason: 'login resumes the kept enrollment');
    expect(device.gateway.activations, 0, reason: 'login spends no CRAM');
    expect(await recordKept(), isFalse,
        reason: 'the resumed record is spent once the client opens');
  });

  // Scenario: features/at_client_wasm/indexeddb_errors.feature
  test(
      'A failed IndexedDB request during onboarding is the cause of an '
      'OnboardingIncompleteException', () async {
    const atSign = '@alice🛠';
    final request = window.indexedDB.open(device.dbName, 3);
    request.onupgradeneeded = (Event _) {
      final db = request.result as IDBDatabase;
      db.createObjectStore('at_client_wasm_credentials').createIndex(
          'one_atsign_per_credential',
          ''.toJS,
          IDBIndexParameters(unique: true));
      db.createObjectStore('at_client_wasm_enrollments');
      db.createObjectStore('at_client_wasm_pending');
    }.toJS;
    final raw = await _settled(request) as IDBDatabase;
    addTearDown(() => raw.close());
    final written = Completer<void>();
    final tx = raw.transaction('at_client_wasm_credentials'.toJS, 'readwrite');
    tx.oncomplete = (Event _) {
      written.complete();
    }.toJS;
    tx.onabort = (Event _) {
      if (!written.isCompleted) written.completeError(StateError('put failed'));
    }.toJS;
    tx
        .objectStore('at_client_wasm_credentials')
        .put(Uint8List.fromList(device._authenticator._id).toJS, '@bob'.toJS);
    await written.future;
    raw.close();

    final custody = await device.custody();
    Object? thrown;
    try {
      await closingStoreAfter(
          device.store, () => custody.onboard(atSign: atSign, cram: _cram));
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<OnboardingIncompleteException>(),
        reason: 'the failed hint write after activation leaves the onboarding '
            'to resume');
    final incomplete = thrown as OnboardingIncompleteException;
    addTearDown(incomplete.pending.abandon);
    expect(incomplete.cause, isA<IndexedDbException>(),
        reason: 'its cause is an IndexedDbException');
    final message = (incomplete.cause as IndexedDbException).message;
    expect(message, contains('ConstraintError'),
        reason: "the exception names the browser's error");
    expect(message, isNot(contains(device.gateway.lastSession!.enrollmentId)),
        reason: 'the exception never carries the enrollment id being written');
    expect(message, isNot(contains(atSign)),
        reason: 'the exception never carries the atSign');
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
      expect(server.cramSpent, isTrue);
      device.store.close();
      device.dieAfterActivation = null;
    }

    Future<void> expectResumed(AtClient client) async {
      expect(client.enrollmentId, 'eid1');
      expect(device.gateway.activations, 0, reason: 'resume spends no CRAM');
      expect(server.publishedKey, _encPublic);
      expect(server.cramLive, isFalse, reason: 'resume finishes activation');
      expect(await device.store.credentialId(_atSign), [7]);
      expect(await device.store.enrollmentId(_atSign), 'eid1');
      await _expectOnlyHint(device, 'eid1');
    }

    test('the pending record holds no secret and no new passkey is made',
        () async {
      await dieThenReload();
      final dump = await _dump(device.dbName);
      final record = dump['at_client_wasm_pending']![_atSign]!;
      final text = latin1.decode(record);
      for (final secret in [
        server.keys['aesPkamPrivateKey'] as String,
        base64.encode(device._authenticator.prfOutput),
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(dump['at_client_wasm_credentials'], isEmpty);
    });

    test(
        'discarding the pending onboarding deletes its record and closes the '
        'store; a second discard is a no-op', () async {
      await dieThenReload();
      expect(
          (await _dump(device.dbName))['at_client_wasm_pending'], isNotEmpty);

      device.store = await IndexedDbHintStore.open(dbName: device.dbName);
      final activations = device.gateway.activations;
      await discardPendingOnboardingIn(device.store, _atSign);

      expect((await _dump(device.dbName))['at_client_wasm_pending'], isEmpty);
      expect(device.gateway.activations, activations,
          reason: 'discarding runs no ceremony and no activation');
      await expectLater(device.store.credentialId(_atSign), throwsA(anything),
          reason: 'the discard closed its IndexedDB store');

      device.store = await IndexedDbHintStore.open(dbName: device.dbName);
      await discardPendingOnboardingIn(device.store, _atSign);
      expect((await _dump(device.dbName))['at_client_wasm_pending'], isEmpty);
    });

    test('discarding with no pending record keeps the atSign\'s hints',
        () async {
      device.store = await IndexedDbHintStore.open(dbName: device.dbName);
      await device.store.putHint(_atSign, Uint8List.fromList([1, 2]), 'eid1');
      expect(await device.store.get(_atSign), isNull);

      await discardPendingOnboardingIn(device.store, _atSign);

      final dump = await _dump(device.dbName);
      expect(dump['at_client_wasm_credentials']!.keys, [_atSign]);
      expect(dump['at_client_wasm_enrollments']!.keys, [_atSign]);
    });

    test(
        'discarding deletes the record and the hints that name its enrollment, '
        'and no other atSign\'s hints', () async {
      await dieThenReload();
      device.store = await IndexedDbHintStore.open(dbName: device.dbName);
      final enrollmentId = (await device.store.get(_atSign))!.enrollmentId;
      await device.store
          .putHint(_atSign, Uint8List.fromList([1, 2]), enrollmentId);
      await device.store.putHint('@other', Uint8List.fromList([3, 4]), 'eid2');

      await discardPendingOnboardingIn(device.store, _atSign);

      final dump = await _dump(device.dbName);
      expect(dump['at_client_wasm_pending'], isEmpty);
      expect(dump['at_client_wasm_credentials']!.keys, ['@other']);
      expect(dump['at_client_wasm_enrollments']!.keys, ['@other']);
    });

    test(
        'discarding deletes the record and keeps hints that name another '
        'enrollment', () async {
      await dieThenReload();
      device.store = await IndexedDbHintStore.open(dbName: device.dbName);
      final enrollmentId = (await device.store.get(_atSign))!.enrollmentId;
      final other = '$enrollmentId-other';
      await device.store.putHint(_atSign, Uint8List.fromList([1, 2]), other);

      await discardPendingOnboardingIn(device.store, _atSign);

      final dump = await _dump(device.dbName);
      expect(dump['at_client_wasm_pending'], isEmpty);
      expect(dump['at_client_wasm_credentials']!.keys, [_atSign]);
      expect(dump['at_client_wasm_enrollments']!.keys, [_atSign]);
    });

    test('a discard of an atSign not in canonical form is refused', () async {
      await dieThenReload();
      for (final bad in ['alice', 'left@right']) {
        device.store = await IndexedDbHintStore.open(dbName: device.dbName);
        await expectLater(discardPendingOnboardingIn(device.store, bad),
            throwsA(isA<InvalidAtSignException>()),
            reason: bad);
      }
      expect(
          (await _dump(device.dbName))['at_client_wasm_pending'], isNotEmpty);
    });

    test('reload then open resumes: keys, pointer and hints are written',
        () async {
      await dieThenReload();
      final client = await device.open();
      await expectResumed(client);
      expect(server.pointerReads, 0);
    });

    test('reload then onboard again resumes without the CRAM', () async {
      await dieThenReload();
      final client = await device.onboard();
      await expectResumed(client);
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
      unorderedEquals([
        'at_client_wasm_credentials',
        'at_client_wasm_enrollments',
        'at_client_wasm_pending',
      ]));
  expect(dump['at_client_wasm_pending'], isEmpty,
      reason: 'a finished onboarding leaves no pending record');
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
    ...device.gateway.seeds,
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
