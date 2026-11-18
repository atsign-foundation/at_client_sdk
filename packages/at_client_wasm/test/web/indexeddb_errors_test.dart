// Scenarios: features/at_client_wasm/indexeddb_errors.feature. Each test is
// named after its scenario.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_client/at_client.dart' show AtClient, AtRootDomain;
import 'package:at_client/passkey.dart' show PasskeyLostException;
import 'package:at_client_wasm/at_client_wasm_web.dart'
    show IndexedDbException, SessionTransportOptions, passkeyLogin;
import 'package:at_client_wasm/src/keys/indexeddb_store.dart'
    show IndexedDbHintStore;
import 'package:at_commons/at_commons.dart' show AtException;
import 'package:test/test.dart';
import 'package:web/web.dart';

const _atSign = '@alice🛠';

/// The database the passkey entry points open.
const _entryPointDb = 'at_client_wasm';

/// A root no lookup can reach, so no test leaves the browser.
final _transport =
    SessionTransportOptions(root: AtRootDomain('root.example', 6464));

Future<AtClient> _login() => passkeyLogin(
    atSign: _atSign,
    app: 'wavi',
    rpId: 'localhost',
    rpName: 'IndexedDB errors',
    transport: _transport);

Future<T> _settled<T extends JSAny?>(IDBRequest request) {
  final done = Completer<T>();
  request.onsuccess = (Event _) {
    done.complete(request.result as T);
  }.toJS;
  request.onerror = (Event _) {
    done.completeError(StateError('IndexedDB request failed'));
  }.toJS;
  return done.future;
}

/// Opens [name] at [version], running [upgrade] when it upgrades.
Future<IDBDatabase> _rawOpen(String name, int version,
    {void Function(IDBDatabase db)? upgrade}) {
  final request = window.indexedDB.open(name, version);
  request.onupgradeneeded = (Event _) {
    upgrade?.call(request.result as IDBDatabase);
  }.toJS;
  return _settled<IDBDatabase>(request);
}

/// Puts [value] under [key] in [storeName] of [db] and waits for it to commit.
Future<void> _rawPut(
    IDBDatabase db, String storeName, String key, List<int> value) {
  final done = Completer<void>();
  final tx = db.transaction(storeName.toJS, 'readwrite');
  tx.oncomplete = (Event _) {
    done.complete();
  }.toJS;
  tx.objectStore(storeName).put(Uint8List.fromList(value).toJS, key.toJS);
  return done.future;
}

Future<void> _deleteDb(String name) =>
    _settled<JSAny?>(window.indexedDB.deleteDatabase(name));

void main() {
  test(
      'An IndexedDB database that will not open reaches the app as an '
      'IndexedDbException', () async {
    final factory = window.indexedDB as JSObject;
    factory['open'] = ((JSAny? name, JSAny? version) {
      final request = JSObject()
        ..['error'] = DOMException(
            'The user denied permission to access the database.',
            'UnknownError');
      Timer.run(() => (request['onerror'] as JSFunction)
          .callAsFunction(request, Event('error')));
      return request;
    }).toJS;
    addTearDown(() => factory.delete('open'.toJS));

    Object? thrown;
    try {
      await _login();
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<IndexedDbException>(),
        reason: 'the refused open reaches the app as an IndexedDbException');
    expect(thrown, isA<AtException>(),
        reason: 'an app catches the IndexedDbException as an AtException');
    expect((thrown as IndexedDbException).message, contains('UnknownError'),
        reason: "the exception names the browser's error");
  });

  test('A failed IndexedDB request reaches the app as an IndexedDbException',
      () async {
    final name = 'indexeddb_errors_${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() => _deleteDb(name));
    final credentialId = Uint8List.fromList(utf8.encode('credential-held'));
    const enrollmentId = 'enrollment-being-written';
    final raw = await _rawOpen(name, 3, upgrade: (db) {
      db.createObjectStore('at_client_wasm_credentials').createIndex(
          'one_atsign_per_credential',
          ''.toJS,
          IDBIndexParameters(unique: true));
      db.createObjectStore('at_client_wasm_enrollments');
      db.createObjectStore('at_client_wasm_pending');
    });
    await _rawPut(raw, 'at_client_wasm_credentials', '@bob', credentialId);
    raw.close();
    final store = await IndexedDbHintStore.open(dbName: name);
    addTearDown(store.close);

    Object? thrown;
    try {
      await store.putHint(_atSign, credentialId, enrollmentId);
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<IndexedDbException>(),
        reason: 'the failed hint write reaches the caller as an '
            'IndexedDbException');
    final message = (thrown as IndexedDbException).message;
    expect(message, contains('ConstraintError'),
        reason: "the exception names the browser's error");
    expect(message, isNot(contains(enrollmentId)),
        reason: 'the exception never carries the value being written');
    expect(message, isNot(contains(_atSign)),
        reason: 'the exception never carries the atSign');
  });

  test('A passkey database a newer build upgraded opens as it is', () async {
    final credentialId = Uint8List.fromList(utf8.encode('remembered-passkey'));
    final newer = await _rawOpen(_entryPointDb, 4, upgrade: (db) {
      db.createObjectStore('at_client_wasm_credentials');
      db.createObjectStore('at_client_wasm_enrollments');
      db.createObjectStore('at_client_wasm_pending');
    });
    addTearDown(() => _deleteDb(_entryPointDb));
    await _rawPut(newer, 'at_client_wasm_credentials', _atSign, credentialId);
    await _rawPut(newer, 'at_client_wasm_enrollments', _atSign,
        utf8.encode('remembered-enrollment'));
    newer.close();

    final asked = <Uint8List?>[];
    final credentials = window.navigator.credentials as JSObject;
    credentials['get'] = ((CredentialRequestOptions options) {
      final allowed = options.publicKey.allowCredentials.toDart;
      asked.add(
          allowed.isEmpty ? null : (allowed.first.id as JSUint8Array).toDart);
      return (globalContext['Promise'] as JSObject).callMethod<JSPromise>(
          'reject'.toJS,
          DOMException('The operation was not allowed.', 'NotAllowedError'));
    }).toJS;
    addTearDown(() => credentials.delete('get'.toJS));

    Object? thrown;
    try {
      await _login();
    } catch (e) {
      thrown = e;
    }

    expect(asked, isNotEmpty, reason: 'the login asked for a passkey');
    expect(asked.first, credentialId,
        reason: "the device's passkey hints are read from that database");
    expect(thrown, isNot(isA<IndexedDbException>()),
        reason: 'no version error is thrown');
    expect(thrown, isA<PasskeyLostException>(),
        reason: 'the login fails only because no passkey answered');
  });
}
