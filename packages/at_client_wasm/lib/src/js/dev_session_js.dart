import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart';
import 'package:web/web.dart' as web;

import '../keys/indexeddb_store.dart';
import '../keys/passkey_kek.dart';
import '../keys/web_passkey_port.dart';
import '../session/portal_session.dart';
import '../session/proxy_lookups.dart';
import 'dev_session.dart';

/// Opens the [DevSession] behind `atClientDev.openSession`.
typedef DevSessionOpener = Future<DevSession> Function(
    DevSessionOptions options);

/// The fields of `openSession`'s options object.
class DevSessionOptions {
  final String atSign;
  final String app;
  final String proxyHost;
  final int proxyPort;

  /// The text of the `.atKeys` file the page picked, or null when it picked
  /// none.
  final String? atKeys;

  DevSessionOptions({
    required this.atSign,
    required this.app,
    required this.proxyHost,
    required this.proxyPort,
    this.atKeys,
  });

  /// Reads [options]; a missing required field, or a wrong-typed field,
  /// throws an [ArgumentError] naming it.
  factory DevSessionOptions.fromJs(JSObject options) {
    T? optional<T extends JSAny>(String name, String type) {
      final value = options.getProperty<JSAny?>(name.toJS);
      if (value == null) return null;
      if (!value.typeofEquals(type)) {
        throw ArgumentError.value(value.dartify(), name, 'must be a $type');
      }
      return value as T;
    }

    T field<T extends JSAny>(String name, String type) =>
        optional<T>(name, type) ??
        (throw ArgumentError.value(null, name, 'must be a $type'));

    return DevSessionOptions(
      atSign: field<JSString>('atSign', 'string').toDart,
      app: field<JSString>('app', 'string').toDart,
      proxyHost: field<JSString>('proxyHost', 'string').toDart,
      proxyPort: field<JSNumber>('proxyPort', 'number').toDartInt,
      atKeys: optional<JSString>('atKeys', 'string')?.toDart,
    );
  }
}

/// Runs [body] as a JS promise; a Dart error rejects it with a JS `Error`.
JSPromise<T> _promise<T extends JSAny?>(Future<T> Function() body) =>
    JSPromise<T>((JSFunction resolve, JSFunction reject) {
      Future.sync(body).then(
        (value) => resolve.callAsFunction(null, value),
        onError: (Object e) => reject.callAsFunction(null, _jsError(e)),
      );
    }.toJS);

/// [_promise] for a [body] with no result: resolves with `null`.
JSPromise<JSAny?> _run(Future<void> Function() body) => _promise(() async {
      await body();
      return null;
    });

/// The JS `Error` a promise rejects with for the Dart error [e]: message
/// `<type>: <message>`, and `code` set to the AT error code when [e]'s type
/// has one.
JSObject _jsError(Object e) {
  final type = '${e.runtimeType}';
  final message = switch (e) {
    AtException(:final message) || StateError(:final message) => message,
    _ => '$e',
  };
  final error = (globalContext['Error'] as JSFunction)
      .callAsConstructor<JSObject>('$type: $message'.toJS);
  if (error_codes[type] case final String code) {
    error['code'] = code.toJS;
  }
  return error;
}

@JSExport()
class DevSessionJs {
  final DevSession _session;
  bool _closed = false;

  DevSessionJs(this._session);

  JSPromise<JSAny?> put(String key, String value) =>
      _run(() => _session.put(key, value));

  JSPromise<JSString?> get(String key) =>
      _promise(() async => (await _session.get(key))?.toJS);

  JSPromise<JSAny?> delete(String key) => _run(() => _session.delete(key));

  JSPromise<JSAny?> close() => _run(() async {
        if (_closed) return;
        _closed = true;
        await _session.close();
      });
}

@JSExport()
class AtClientDevJs {
  final DevSessionOpener _opener;

  AtClientDevJs(this._opener);

  JSPromise<JSObject> openSession(JSObject options) => _promise(() async {
        final session = await _opener(DevSessionOptions.fromJs(options));
        return createJSInteropWrapper(DevSessionJs(session));
      });
}

/// Opens a Mode P [DevSession] over the proxy at [DevSessionOptions.proxyHost],
/// with keys in IndexedDB under a passkey for this page's host. A first visit
/// imports [DevSessionOptions.atKeys] and seals it under a new passkey.
Future<DevSession> defaultOpener(DevSessionOptions options) async {
  final store = await IndexedDbKeyBytesStore.open();
  final client = await portalSession(
    atSign: options.atSign,
    app: options.app,
    prefs: AtClientPreference()
      ..namespace = options.app
      ..monitorAutoStart = false,
    lookUps:
        proxyWebSocketLookUps(host: options.proxyHost, port: options.proxyPort),
    secondaryAddressFinder:
        FixedSecondaryAddressFinder(options.proxyHost, options.proxyPort),
    store: store,
    kek: PasskeyKek(WebPasskeyPort(
        rpId: web.window.location.hostname, rpName: 'atSign dev')),
    hintStore: store,
    importAtKeys: (atSign) => _importAtKeys(atSign, options.atKeys),
  );
  return AtClientDevSession(client, app: options.app);
}

/// Decodes [atKeysText], the `.atKeys` file picked for [atSign].
///
/// Throws [ArgumentError] when no file was picked, and [UnsupportedError]
/// otherwise: the file's self-encrypted fields have no decoder without
/// `dart:io` yet.
Future<AtKeys> _importAtKeys(String atSign, String? atKeysText) async {
  if (atKeysText == null) {
    throw ArgumentError.value(
        null, 'atKeys', 'pick the .atKeys file for $atSign');
  }
  throw UnsupportedError(
      'decoding a .atKeys file in the browser is not available yet');
}

/// Sets `globalThis.atClientDev`, whose `openSession` uses [opener], by
/// default [defaultOpener].
void installAtClientDev({DevSessionOpener? opener}) {
  globalContext.setProperty(
    'atClientDev'.toJS,
    createJSInteropWrapper(AtClientDevJs(opener ?? defaultOpener)),
  );
}
