@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client_web/src/session/web_storage_persistence.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  final storage = window.navigator.storage as JSObject;
  late JSArray<JSString> calls;

  /// Replaces navigator.storage.persist with one that notes each call and
  /// resolves to [granted].
  void stubPersist(bool granted) {
    final make = globalContext.callMethod<JSFunction>(
        'Function'.toJS,
        'calls'.toJS,
        'granted'.toJS,
        'return function() { calls.push("persist");'
                ' return Promise.resolve(granted); };'
            .toJS);
    storage['persist'] = make.callAsFunction(null, calls, granted.toJS);
  }

  setUp(() => calls = JSArray<JSString>());
  tearDown(() => storage.delete('persist'.toJS));

  test('requestPersist answers true when the browser grants persistence',
      () async {
    stubPersist(true);
    expect(await WebStoragePersistence().requestPersist(), isTrue);
    expect(calls.toDart, hasLength(1));
  });

  test('requestPersist answers false when the browser refuses persistence',
      () async {
    stubPersist(false);
    expect(await WebStoragePersistence().requestPersist(), isFalse);
    expect(calls.toDart, hasLength(1));
  });

  test('requestPersist answers whether the browser granted persistence',
      () async {
    expect(await WebStoragePersistence().requestPersist(), isA<bool>());
  });
}
