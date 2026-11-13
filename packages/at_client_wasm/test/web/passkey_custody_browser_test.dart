@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/indexeddb_store.dart';
import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/prf_support.dart';
import 'package:at_client_wasm/src/keys/web_passkey_port.dart';
import 'package:at_client_wasm/src/keys/web_prf_environment.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_client_wasm/src/session/web_setup_lock.dart';
import 'package:at_client_wasm/src/session/web_storage_persistence.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import '../session/custody_fakes.dart';

/// Set `-DVIRTUAL_AUTHENTICATOR=true` (`dart test --define`) when the browser
/// runs a CTAP2 virtual authenticator with `hasPrf` and `hasResidentKey`, which
/// only a CDP or Playwright harness can install; `dart test -p chrome` alone
/// cannot, and a real `navigator.credentials.create` then never settles.
const _virtualAuthenticator = bool.fromEnvironment('VIRTUAL_AUTHENTICATOR');

const _atSign = '@alice';
const _cram = 'cram-secret';

/// One browser profile: an IndexedDB database, a lock and a persistence
/// request, over [port]; the atServer is [server].
class _Device {
  _Device(this.dbName, this.server, this.port);

  final String dbName;
  final FakeServer server;
  final PasskeyPort port;
  IndexedDbKeyBytesStore? _store;
  IndexedDbKeyBytesStore get store => _store!;
  late FakeGateway gateway;

  Future<PasskeyCustody> custody() async {
    _store?.close();
    _store = await IndexedDbKeyBytesStore.open(dbName: dbName);
    gateway = FakeGateway(server);
    return PasskeyCustody(
        kek: PasskeyKek(port,
            prfSupport: port is WebPasskeyPort
                ? PrfSupport(WebPrfEnvironment())
                : null),
        pointerReader: server,
        gateway: gateway,
        credentials: store,
        enrollmentIds: store,
        setupLock: WebSetupLock(),
        persistence: WebStoragePersistence());
  }

  /// Clears site data: IndexedDB and web storage. The passkey and the atServer
  /// survive.
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

/// Every record of every object store of database [dbName], by store name then
/// key; the value of a record is its bytes.
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

/// The names of the databases of this origin that [prefix] starts.
Future<List<String>> _databases(String prefix) async {
  final all = (await window.indexedDB.databases().toDart).toDart;
  return [
    for (final info in all)
      if (info.name.startsWith(prefix)) info.name,
  ];
}

/// Asserts that [device] holds, for [session], only the hint: the passkey's
/// credential id and the enrollment id under the atSign, in the one database,
/// with nothing in the key-bytes store and no key material in any record.
Future<void> _expectOnlyHint(_Device device, CustodySession session) async {
  expect(await _databases('custody_'), [device.dbName]);
  final dump = await _dump(device.dbName);
  expect(
      dump.keys,
      unorderedEquals([
        'at_client_wasm_keys',
        'at_client_wasm_credentials',
        'at_client_wasm_enrollments'
      ]));
  expect(dump['at_client_wasm_keys'], isEmpty);
  expect(dump['at_client_wasm_credentials'], {_atSign: session.credentialId});
  expect(dump['at_client_wasm_enrollments'],
      {_atSign: utf8.encode(session.enrollmentId)});

  final stored = [
    for (final records in dump.values)
      for (final bytes in records.values) latin1.decode(bytes),
  ].join('\u0000');
  final secrets = [
    for (final value in session.atKeys.values) '$value',
    base64.encode(session.authSeed),
    base64Url.encode(session.authSeed),
    session.lookupHex,
  ];
  for (final secret in secrets) {
    expect(stored, isNot(contains(secret)));
  }
}

String _dbName() => 'custody_${DateTime.now().microsecondsSinceEpoch}';

void _recoveryTests(String label, PasskeyPort Function() newPort,
    {Object? skip}) {
  group(label, () {
    late _Device device;
    late FakeServer server;

    setUp(() {
      server = FakeServer();
      device = _Device(_dbName(), server, newPort());
    });

    tearDown(() async {
      await device.clearSiteData();
    });

    test(
        'X-K9: enroll, clear site data, recover with the passkey only: same '
        'enrollment, same keys', () async {
      final enrolled =
          await (await device.custody()).onboard(atSign: _atSign, cram: _cram);
      await device.clearSiteData();

      final fresh = await device.custody();
      expect(await device.store.credentialId(_atSign), isNull);
      expect(await device.store.enrollmentId(_atSign), isNull);
      final recovered = await fresh.open(atSign: _atSign);

      expect(recovered.enrollmentId, enrolled.enrollmentId);
      expect(recovered.credentialId, enrolled.credentialId);
      expect(recovered.lookupHex, enrolled.lookupHex);
      expect(recovered.authSeed, enrolled.authSeed);
      expect(recovered.atKeys, enrolled.atKeys);
      expect(device.gateway.activated, isEmpty,
          reason: 'recovery spends no CRAM');
      expect(server.pointerReads, 1);
      expect(await device.store.enrollmentId(_atSign), enrolled.enrollmentId);
    });

    test('X-K19: after onboarding and recovery IndexedDB holds only the hint',
        () async {
      final enrolled =
          await (await device.custody()).onboard(atSign: _atSign, cram: _cram);
      await _expectOnlyHint(device, enrolled);

      await device.clearSiteData();
      final recovered = await (await device.custody()).open(atSign: _atSign);
      await _expectOnlyHint(device, recovered);
    });

    test(
        'onboarding 12: a remembered enrollment reads no pointer; an empty '
        'IndexedDB asserts discoverably, reads the pointer, then PKAMs',
        () async {
      final enrolled =
          await (await device.custody()).onboard(atSign: _atSign, cram: _cram);

      final remembered = await (await device.custody()).open(atSign: _atSign);
      expect(server.pointerReads, 0);
      expect(remembered.enrollmentId, enrolled.enrollmentId);

      await device.clearSiteData();
      final recovered = await (await device.custody()).open(atSign: _atSign);
      expect(server.pointerReads, 1);
      expect(recovered.enrollmentId, enrolled.enrollmentId);
      expect(recovered.atKeys, enrolled.atKeys);
    });

    test(
        'onboarding 11: K-5-prime public keys differ from the published ones: '
        'open throws, closes the session and rewrites no hint', () async {
      await (await device.custody()).onboard(atSign: _atSign, cram: _cram);
      await device.clearSiteData();
      server.publishedTag = 'rotated';

      final fresh = await device.custody();
      await expectLater(fresh.open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));
      expect(device.gateway.lastSession!.closed, isTrue);
      expect(await device.store.credentialId(_atSign), isNull);
      expect(await device.store.enrollmentId(_atSign), isNull);
    });
  }, skip: skip);
}

void main() {
  // Real IndexedDB, navigator.locks and storage; the passkey is a fake with a
  // fixed PRF, so this lane needs no authenticator.
  _recoveryTests(
      'custody on browser storage, fake authenticator', FakeAuthenticator.new);

  // The same flows through the real WebAuthn ceremony.
  _recoveryTests('custody on browser storage, WebPasskeyPort',
      () => WebPasskeyPort(rpId: window.location.hostname, rpName: 'test'),
      skip: _virtualAuthenticator
          ? null
          : 'needs a CDP virtual authenticator with PRF '
              '(-DVIRTUAL_AUTHENTICATOR=true)');
}
