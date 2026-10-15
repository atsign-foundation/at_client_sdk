import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart';
import 'package:web/web.dart' as web;

import '../keys/indexeddb_store.dart';
import '../keys/passkey_kek.dart';
import '../keys/unlock_secret.dart';
import '../keys/web_passkey_port.dart';
import '../session/portal_session.dart';
import '../session/proxy_lookups.dart';
import 'dev_session.dart';

/// Opens the [DevSession] behind `atClientDev.openSession`.
typedef DevSessionOpener = Future<DevSession> Function(
    DevSessionOptions options,
    Future<PassphraseSecret> Function(String atSign) promptPassphrase);

/// The fields of `openSession`'s options object.
class DevSessionOptions {
  final String atSign;
  final String app;
  final String proxyHost;
  final int proxyPort;

  DevSessionOptions({
    required this.atSign,
    required this.app,
    required this.proxyHost,
    required this.proxyPort,
  });

  /// Reads [options]; a missing or wrong-typed field throws an
  /// [ArgumentError] naming it.
  factory DevSessionOptions.fromJs(JSObject options) {
    T field<T extends JSAny>(String name, String type) {
      final value = options.getProperty<JSAny?>(name.toJS);
      if (value == null || !value.typeofEquals(type)) {
        throw ArgumentError.value(value?.dartify(), name, 'must be a $type');
      }
      return value as T;
    }

    return DevSessionOptions(
      atSign: field<JSString>('atSign', 'string').toDart,
      app: field<JSString>('app', 'string').toDart,
      proxyHost: field<JSString>('proxyHost', 'string').toDart,
      proxyPort: field<JSNumber>('proxyPort', 'number').toDartInt,
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

  JSPromise<JSObject> openSession(
          JSObject options, JSFunction promptPassphrase) =>
      _promise(() async {
        final session = await _opener(DevSessionOptions.fromJs(options),
            (atSign) => _prompt(promptPassphrase, atSign));
        return createJSInteropWrapper(DevSessionJs(session));
      });
}

/// Calls the page's `(atSign) => Promise<string>`; a rejection or a
/// non-string result throws.
Future<PassphraseSecret> _prompt(JSFunction prompt, String atSign) async {
  final result =
      await (prompt.callAsFunction(null, atSign.toJS) as JSPromise).toDart;
  if (result == null || !result.typeofEquals('string')) {
    throw ArgumentError.value(
        result?.dartify(), 'promptPassphrase', 'must resolve to a string');
  }
  return PassphraseSecret((result as JSString).toDart);
}

/// Opens a Mode P [DevSession] over the proxy at [DevSessionOptions.proxyHost],
/// with keys in IndexedDB and a passkey for this page's host.
Future<DevSession> defaultOpener(DevSessionOptions options,
    Future<PassphraseSecret> Function(String atSign) promptPassphrase) async {
  final store = await IndexedDbKeyBytesStore.open();
  final client = await portalSession(
    atSign: options.atSign,
    app: options.app,
    prefs: AtClientPreference()
      ..namespace = options.app
      ..monitorAutoStart = false,
    lookUps:
        proxyWebSocketLookUps(host: options.proxyHost, port: options.proxyPort),
    store: store,
    kek: PasskeyKek(WebPasskeyPort(
        rpId: web.window.location.hostname, rpName: 'atSign dev')),
    hintStore: store,
    promptPassphrase: promptPassphrase,
  );
  return AtClientDevSession(client, app: options.app);
}

/// Sets `globalThis.atClientDev`, whose `openSession` uses [opener], by
/// default [defaultOpener].
void installAtClientDev({DevSessionOpener? opener}) {
  globalContext.setProperty(
    'atClientDev'.toJS,
    createJSInteropWrapper(AtClientDevJs(opener ?? defaultOpener)),
  );
}
