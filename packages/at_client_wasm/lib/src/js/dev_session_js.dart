import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_auth/at_auth.dart' show AtKeys, parseAtKeysFile;
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup_web.dart';
import 'package:web/web.dart' as web;

import '../keys/indexeddb_store.dart';
import '../keys/passkey_kek.dart';
import '../keys/unlock_secret.dart';
import '../keys/web_passkey_port.dart';
import '../session/portal_session.dart';
import '../session/proxy_lookups.dart';
import 'dev_session.dart';

/// Opens the [DevSession] behind `atClientDev.openSession`.
///
/// [uploadAtKeys], when the page offers one, supplies the user's `.atKeys`
/// when this device holds no copy of them.
typedef DevSessionOpener = Future<DevSession> Function(
    DevSessionOptions options,
    Future<PassphraseSecret> Function(String atSign) promptPassphrase,
    [Future<AtKeys> Function(String atSign)? uploadAtKeys]);

/// The fields of `openSession`'s options object.
class DevSessionOptions {
  final String atSign;
  final String app;
  final String proxyHost;
  final int proxyPort;

  /// Whether every atSign's own atServer is reached over its `/ws`, found
  /// through the root's HTTPS lookup, with no proxy. [proxyHost] and
  /// [proxyPort] are then unused.
  final bool direct;

  /// The root server (atDirectory) atSigns are looked up at: by [direct]'s
  /// lookup, and by the key-copy lookup in every mode.
  final AtRootDomain root;

  DevSessionOptions({
    required this.atSign,
    required this.app,
    this.proxyHost = '',
    this.proxyPort = 0,
    this.direct = false,
    this.root = AtRootDomain.atsignDomain,
  });

  /// Reads [options]; a missing or wrong-typed field throws an
  /// [ArgumentError] naming it.
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

    final direct = optional<JSBoolean>('direct', 'boolean')?.toDart ?? false;
    return DevSessionOptions(
      atSign: field<JSString>('atSign', 'string').toDart,
      app: field<JSString>('app', 'string').toDart,
      // Direct mode names no proxy; every other mode needs one.
      proxyHost: direct ? '' : field<JSString>('proxyHost', 'string').toDart,
      proxyPort: direct ? 0 : field<JSNumber>('proxyPort', 'number').toDartInt,
      direct: direct,
      root: switch (optional<JSString>('root', 'string')?.toDart) {
        final root? => _parseRoot(root),
        null => AtRootDomain.atsignDomain,
      },
    );
  }

  static AtRootDomain _parseRoot(String root) {
    try {
      return AtRootDomain.parse(root);
    } on AtException catch (e) {
      throw ArgumentError.value(root, 'root', e.message);
    }
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

  JSPromise<JSAny?> notify(
          String to, String key, String namespace, String value,
          [JSNumber? expiryMs]) =>
      _run(() => _session.notify(to, key, namespace, value,
          expiry: switch (expiryMs) {
            final ms? => Duration(milliseconds: ms.toDartInt),
            null => null,
          }));

  /// Calls [onEvent] with `{from, key, value, epochMillis}` per matching
  /// notification; returns the function that unsubscribes.
  JSFunction onNotification(String regex, JSFunction onEvent) {
    final unsubscribe = _session.onNotification(
        regex,
        (n) => onEvent.callAsFunction(
            null,
            JSObject()
              ..['from'] = n.from.toJS
              ..['key'] = n.key.toJS
              ..['value'] = n.value?.toJS
              ..['epochMillis'] = n.epochMillis.toJS));
    return unsubscribe.toJS;
  }

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

  JSPromise<JSObject> openSession(JSObject options, JSFunction promptPassphrase,
          [JSFunction? uploadAtKeys]) =>
      _promise(() async {
        final session = await _opener(
            DevSessionOptions.fromJs(options),
            (atSign) => _prompt(promptPassphrase, atSign),
            uploadAtKeys == null
                ? null
                : (atSign) => _upload(uploadAtKeys, atSign));
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

/// How a session reaches atServers: [lookUps] makes the connections and
/// [finder] resolves the atSigns they are for.
typedef DevTransport = ({
  AtLookUpFactory lookUps,
  SecondaryAddressFinder finder,
});

/// [DevSessionOptions.direct]: a WebSocket straight to each atSign's own
/// atServer, which the root's HTTPS lookup names. Otherwise every
/// connection goes to the proxy, opening with the `from:` that says which
/// atServer it is for.
DevTransport devTransport(DevSessionOptions options) => options.direct
    ? (
        lookUps: webSocketLookUps(directoryPort: options.root.rootPort),
        finder: HttpsSecondaryAddressFinder(options.root.rootDomain,
            port: options.root.rootPort),
      )
    : (
        lookUps: proxyWebSocketLookUps(
            host: options.proxyHost, port: options.proxyPort),
        finder:
            FixedSecondaryAddressFinder(options.proxyHost, options.proxyPort),
      );

/// Calls the page's `(atSign) => Promise<string>` for the text of the user's
/// `.atKeys` file; a rejection or a non-string result throws.
Future<AtKeys> _upload(JSFunction upload, String atSign) async {
  final result =
      await (upload.callAsFunction(null, atSign.toJS) as JSPromise).toDart;
  if (result == null || !result.typeofEquals('string')) {
    throw ArgumentError.value(
        result?.dartify(), 'uploadAtKeys', 'must resolve to a string');
  }
  return parseAtKeysFile((result as JSString).toDart);
}

/// Opens a Mode P [DevSession] over [devTransport], with keys in IndexedDB
/// and a passkey for this page's host.
Future<DevSession> defaultOpener(DevSessionOptions options,
    Future<PassphraseSecret> Function(String atSign) promptPassphrase,
    [Future<AtKeys> Function(String atSign)? uploadAtKeys]) async {
  final store = await IndexedDbKeyBytesStore.open();
  final transport = devTransport(options);
  final client = await portalSession(
    atSign: options.atSign,
    app: options.app,
    prefs: AtClientPreference()
      ..namespace = options.app
      ..rootDomain = options.root.rootDomain
      ..rootPort = options.root.rootPort
      ..monitorAutoStart = false,
    lookUps: transport.lookUps,
    secondaryAddressFinder: transport.finder,
    store: store,
    kek: PasskeyKek(WebPasskeyPort(
        rpId: web.window.location.hostname, rpName: 'atSign dev')),
    hintStore: store,
    promptPassphrase: promptPassphrase,
    uploadAtKeys: uploadAtKeys,
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
