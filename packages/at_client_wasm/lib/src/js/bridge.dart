import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../session/web_passkey_entry.dart' as entry;
import 'at_error_code.dart';
import 'js_session.dart';

/// What a caller says about the client it wants: the atSign, the client's
/// [namespace], the enrollment's [app] (the namespace when not given) and the
/// relying party ([rpId] defaulting to the page's hostname, and [rpName]).
class BridgeOptions {
  const BridgeOptions(
      {required this.atSign,
      required this.namespace,
      required this.app,
      required this.rpId,
      required this.rpName});

  final String atSign;
  final String namespace;
  final String app;
  final String rpId;
  final String rpName;
}

/// Opens an atSign's session with its passkey.
typedef LoginOpener = Future<JsSession> Function(BridgeOptions options);

/// Onboards a fresh atSign with [cram], naming the enrollment's device
/// [deviceName] when given.
typedef OnboardOpener = Future<JsSession> Function(
    BridgeOptions options, String cram, String? deviceName);

/// Enrolls this browser as device [deviceName] of app [appName] with an
/// approver-issued [otp].
typedef EnrollOpener = Future<JsSession> Function(
    BridgeOptions options, String appName, String deviceName, String otp);

Future<JsSession> _openLogin(BridgeOptions o) async => AtClientJsSession(
    await entry.passkeyLogin(
        atSign: o.atSign, app: o.app, rpId: o.rpId, rpName: o.rpName),
    namespace: o.namespace);

Future<JsSession> _openOnboard(
        BridgeOptions o, String cram, String? deviceName) async =>
    AtClientJsSession(
        await entry.onboardNewAtSign(
            atSign: o.atSign,
            cram: cram,
            app: o.app,
            rpId: o.rpId,
            rpName: o.rpName,
            device: deviceName),
        namespace: o.namespace);

Future<JsSession> _openEnroll(
        BridgeOptions o, String appName, String deviceName, String otp) async =>
    AtClientJsSession(
        await entry.passkeyEnroll(
            atSign: o.atSign,
            otp: otp,
            app: appName,
            device: deviceName,
            rpId: o.rpId,
            rpName: o.rpName),
        namespace: o.namespace);

/// A rejection reason: a plain `{code, message}` object, never an `Error`.
extension type _Rejection._(JSObject _) implements JSObject {
  external factory _Rejection({String code, String message});
}

/// A promise of [body]'s result that rejects with a [_Rejection] carrying
/// [atErrorCode] of whatever [body] throws.
JSPromise<T> _promise<T extends JSAny?>(FutureOr<T> Function() body) =>
    JSPromise<T>((JSFunction resolve, JSFunction reject) {
      Future<T>.sync(body).then((value) => resolve.callAsFunction(null, value),
          onError: (Object error) => reject.callAsFunction(null,
              _Rejection(code: atErrorCode(error), message: error.toString())));
    }.toJS);

String? _optionalString(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSString>()) {
    throw ArgumentError.value(value.dartify(), name, 'must be a string');
  }
  return (value as JSString).toDart;
}

String _string(JSAny? value, String name) =>
    _optionalString(value, name) ?? (throw ArgumentError.notNull(name));

String? _field(JSObject object, String name) =>
    _optionalString(object[name], name);

JsKey _jsKey(JSAny? value) {
  if (value == null || !value.isA<JSObject>()) {
    throw ArgumentError.value(value.dartify(), 'key', 'must be an object');
  }
  final object = value as JSObject;
  return JsKey(_string(object['key'], 'key'),
      namespace: _field(object, 'namespace'),
      sharedWith: _field(object, 'sharedWith'),
      sharedBy: _field(object, 'sharedBy'));
}

/// The text or bytes a caller stores.
Object _storable(JSAny? value) {
  if (value != null && value.isA<JSString>()) return (value as JSString).toDart;
  if (value != null && value.isA<JSUint8Array>()) {
    return Uint8List.fromList((value as JSUint8Array).toDart);
  }
  throw ArgumentError.value(
      value.dartify(), 'value', 'must be a string or Uint8Array');
}

JSAny? _readable(Object? value) => switch (value) {
      null => null,
      String() => value.toJS,
      Uint8List() => value.toJS,
      _ => '$value'.toJS,
    };

/// The JS surface of one open client, as `AtClient` in the TypeScript
/// package wraps it.
@JSExport()
class BridgeSession {
  BridgeSession(this._session);

  final JsSession _session;

  JSPromise<JSAny?> put(JSAny? key, JSAny? value) => _promise(() async {
        await _session.put(_jsKey(key), _storable(value));
        return null;
      });

  JSPromise<JSAny?> get(JSAny? key) =>
      _promise(() async => _readable(await _session.get(_jsKey(key))));

  JSPromise<JSAny?> delete(JSAny? key) => _promise(() async {
        await _session.delete(_jsKey(key));
        return null;
      });

  JSPromise<JSArray<JSString>> keys([JSAny? regex]) => _promise(() async => [
        for (final key in await _session.keys(_optionalString(regex, 'regex')))
          key.toJS
      ].toJS);

  JSPromise<JSBoolean> notify(JSAny? key, JSAny? value) => _promise(() async =>
      (await _session.notify(_jsKey(key), _string(value, 'value'))).toJS);

  /// Calls [callback] with each notification matching [regex] as
  /// `{id, from, key, value, epochMillis}`; returns the function that
  /// unsubscribes.
  JSFunction subscribe(JSAny? regex, JSFunction callback) {
    final unsubscribe = _session.subscribe(
        _string(regex, 'regex'),
        (n) => callback.callAsFunction(
            null,
            {
              'id': n.id,
              'from': n.from,
              'key': n.key,
              'value': n.value,
              'epochMillis': n.epochMillis,
            }.jsify()));
    return unsubscribe.toJS;
  }

  /// A one-time passcode for a new device to enroll with.
  JSPromise<JSString> otp() =>
      _promise(() async => (await _session.otp()).toJS);

  /// The requests awaiting a decision, each `{id, appName, deviceName,
  /// namespaces}` with `namespaces` mapping a namespace to its access.
  JSPromise<JSArray<JSObject>> pendingEnrollments() => _promise(() async => [
        for (final e in await _session.pendingEnrollments())
          {
            'id': e.id,
            'appName': e.appName,
            'deviceName': e.deviceName,
            'namespaces': e.namespaces,
          }.jsify()! as JSObject
      ].toJS);

  /// Approves the request [id] for exactly what it asked for.
  JSPromise<JSAny?> approve(JSAny? id) => _promise(() async {
        await _session.approve(_string(id, 'id'));
        return null;
      });

  JSPromise<JSAny?> deny(JSAny? id) => _promise(() async {
        await _session.deny(_string(id, 'id'));
        return null;
      });

  JSPromise<JSAny?> close() => _promise(() async {
        await _session.close();
        return null;
      });
}

/// The JS surface of the package: what each static of `AtClient` calls.
///
/// The openers, the PRF probe, the secure-context check and the hostname are
/// injectable; they default to this browser's.
@JSExport()
class AtClientWebBridge {
  AtClientWebBridge(
      {LoginOpener? login,
      OnboardOpener? onboard,
      EnrollOpener? enroll,
      Future<bool> Function()? prfSupported,
      bool Function()? isSecureContext,
      String Function()? hostname})
      : _login = login ?? _openLogin,
        _onboard = onboard ?? _openOnboard,
        _enroll = enroll ?? _openEnroll,
        _prfSupported = prfSupported ?? entry.prfSupported,
        _isSecureContext = isSecureContext ?? _pageIsSecure,
        _hostname = hostname ?? _pageHostname;

  final LoginOpener _login;
  final OnboardOpener _onboard;
  final EnrollOpener _enroll;
  final Future<bool> Function() _prfSupported;
  final bool Function() _isSecureContext;
  final String Function() _hostname;

  static bool _pageIsSecure() => web.window.isSecureContext;

  static String _pageHostname() => web.window.location.hostname;

  /// Whether this browser can evaluate passkey PRF.
  JSPromise<JSBoolean> prfSupported() =>
      _promise(() async => (await _prfSupported()).toJS);

  /// Opens a session with the atSign's passkey.
  JSPromise<JSObject> create(JSAny? opts) =>
      _promise(() => _session(opts, (o) => _login(o)));

  /// Onboards a fresh atSign with its CRAM secret.
  JSPromise<JSObject> onboard(JSAny? opts, JSAny? cram, [JSAny? deviceName]) =>
      _promise(() => _session(
          opts,
          (o) => _onboard(o, _string(cram, 'cram'),
              _optionalString(deviceName, 'deviceName'))));

  /// Enrolls this browser with an approver-issued one-time code.
  JSPromise<JSObject> enroll(
          JSAny? opts, JSAny? appName, JSAny? deviceName, JSAny? otp) =>
      _promise(() => _session(
          opts,
          (o) => _enroll(o, _string(appName, 'appName'),
              _string(deviceName, 'deviceName'), _string(otp, 'otp'))));

  /// [open]ed on the parsed [opts] and wrapped for JS, refused outside a
  /// secure context.
  Future<JSObject> _session(JSAny? opts,
      Future<JsSession> Function(BridgeOptions options) open) async {
    if (!_isSecureContext()) {
      throw UnsupportedError('passkeys need a secure context (HTTPS)');
    }
    final session = await open(_options(opts));
    return createJSInteropWrapper(BridgeSession(session));
  }

  BridgeOptions _options(JSAny? opts) {
    if (opts == null || !opts.isA<JSObject>()) {
      throw ArgumentError.value(opts.dartify(), 'opts', 'must be an object');
    }
    final object = opts as JSObject;
    final namespace = _string(object['namespace'], 'namespace');
    final rpId = _field(object, 'rpId') ?? _hostname();
    return BridgeOptions(
        atSign: _string(object['atSign'], 'atSign'),
        namespace: namespace,
        app: _field(object, 'app') ?? namespace,
        rpId: rpId,
        rpName: _string(object['rpName'], 'rpName'));
  }
}
