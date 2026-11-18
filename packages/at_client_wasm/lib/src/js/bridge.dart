import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart'
    show Atsign, AtKeys, AtRootDomain, AtSignLogger;
import 'package:web/web.dart' as web;

import '../collections/js_collections_adapter.dart';
import '../session/portal_session.dart';
import '../session/session_transport.dart';
import '../session/session_transport_options.dart';
import 'at_error_code.dart';
import 'js_session.dart';

/// What a caller says about the client it wants: the atSign, the client's
/// [namespace] (also the enrollment's app name), the decoded `.atKeys`
/// document [keys] and, when not the production atDirectory, the
/// [rootDomain].
class BridgeOptions {
  const BridgeOptions(
      {required this.atSign,
      required this.namespace,
      required this.keys,
      this.rootDomain});

  final String atSign;
  final String namespace;
  final Map<String, dynamic> keys;
  final AtRootDomain? rootDomain;
}

/// Opens an atSign's session from its keys.
typedef SessionOpener = Future<JsSession> Function(BridgeOptions options);

final _logger = AtSignLogger('AtClientWebBridge');

Future<JsSession> _openSession(BridgeOptions o) async {
  final AtKeys keys;
  try {
    keys = AtKeys.fromJson(o.keys);
  } on Object {
    throw BadKeyException('keys is not a usable .atKeys document');
  }
  final client = await portalSession(
      atSign: o.atSign,
      app: o.namespace,
      keys: keys,
      transport: sessionTransport(SessionTransportOptions(root: o.rootDomain)));
  return AtClientJsSession(client,
      namespace: o.namespace,
      isNavigatorOnline: () => web.window.navigator.onLine,
      warn: _logger.warning);
}

/// The root domain [value] names, `host` or `host:port` (the port defaults to
/// 64; a `proxy:` host is kept). An [ArgumentError] names the parameter,
/// never the value.
AtRootDomain parseRootDomain(String value) {
  try {
    return AtRootDomain.parse(value);
  } on Exception {
    throw _expected('rootDomain', 'host or host:port');
  }
}

/// A rejection reason: a plain object with `code` and `message`, never an
/// `Error`; a collection failure adds `id`, `owner`, `kind` and `failures`
/// where it has them.
JSObject _rejection(Object error) {
  final code = atErrorCode(error);
  final reason = JSObject()..['code'] = code.toJS;
  if (error is JsCollectionsError) {
    reason['message'] = error.message.toJS;
    if (error.id case final id?) reason['id'] = id.toJS;
    if (error.owner case final owner?) reason['owner'] = owner.toJS;
    if (error.kind case final kind?) reason['kind'] = kind.toJS;
    if (error.failures.isNotEmpty) {
      reason['failures'] = _jsValue(error.failures);
    }
  } else {
    // An unmapped error's text may hold anything, so it becomes a fixed
    // message. An [ArgumentError] keeps its text: the bridge words it to
    // name the parameter, never the value.
    reason['message'] = (code == 'internal' && error is! ArgumentError
            ? 'internal error'
            : error.toString())
        .toJS;
  }
  return reason;
}

/// A promise of [body]'s result that rejects with a [_rejection] of whatever
/// [body] throws.
JSPromise<T> _promise<T extends JSAny?>(FutureOr<T> Function() body) =>
    JSPromise<T>((JSFunction resolve, JSFunction reject) {
      Future<T>.sync(body).then((value) => resolve.callAsFunction(null, value),
          onError: (Object error) =>
              reject.callAsFunction(null, _rejection(error)));
    }.toJS);

/// An argument error that names the parameter and the type it expects, never
/// the value received.
ArgumentError _expected(String name, String type) =>
    ArgumentError('$name must be $type');

String? _optionalString(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSString>()) throw _expected(name, 'a string');
  return (value as JSString).toDart;
}

String _string(JSAny? value, String name) =>
    _optionalString(value, name) ?? (throw ArgumentError.notNull(name));

String? _field(JSObject object, String name) =>
    _optionalString(object[name], name);

bool _flag(JSObject object, String name) {
  final value = object[name];
  if (value == null || value.isUndefinedOrNull) return false;
  if (!value.isA<JSBoolean>()) throw _expected(name, 'a boolean');
  return (value as JSBoolean).toDart;
}

JSObject _object(JSAny? value, String name) {
  if (value == null || !value.isA<JSObject>() || value.isA<JSFunction>()) {
    throw _expected(name, 'an object');
  }
  return value as JSObject;
}

/// [value] as an object, or null when it is absent.
JSObject? _optionalObject(JSAny? value, String name) =>
    value == null || value.isUndefinedOrNull ? null : _object(value, name);

JSFunction? _optionalFunction(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSFunction>()) throw _expected(name, 'a function');
  return value as JSFunction;
}

List<String> _strings(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return const [];
  if (!value.isA<JSArray>()) throw _expected(name, 'an array of strings');
  return [
    for (final item in (value as JSArray<JSAny?>).toDart) _string(item, name)
  ];
}

final JSObject _objectClass = globalContext['Object']! as JSObject;

/// The JS value [value] as plain Dart values: strings, bools, numbers
/// (integral ones as `int`), lists and string-keyed maps. Anything else, a
/// function or a bigint say, is refused naming [name].
Object? _fromJs(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (value.isA<JSString>()) return (value as JSString).toDart;
  if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
  if (value.isA<JSNumber>()) {
    final number = (value as JSNumber).toDartDouble;
    if (number.isFinite &&
        number == number.truncateToDouble() &&
        number.abs() <= 9007199254740991) {
      return number.toInt();
    }
    if (!number.isFinite) throw _expected(name, 'finite numbers only');
    return number;
  }
  if (value.isA<JSArray>()) {
    return [
      for (final item in (value as JSArray<JSAny?>).toDart) _fromJs(item, name)
    ];
  }
  if (value.isA<JSObject>() && !value.isA<JSFunction>()) {
    final object = value as JSObject;
    final keys =
        (_objectClass.callMethod('keys'.toJS, object)! as JSArray<JSString>)
            .toDart;
    return <String, dynamic>{
      for (final key in keys) key.toDart: _fromJs(object[key.toDart], name)
    };
  }
  throw _expected(name, 'plain JSON values');
}

/// [value] (Dart values, as [_fromJs] makes them) as JS values. A map
/// becomes an object with no prototype, so a key such as `__proto__` or
/// `toString` is data and never reaches `Object.prototype`.
JSAny? _jsValue(Object? value) => switch (value) {
      null => null,
      String s => s.toJS,
      bool b => b.toJS,
      num n => n.toDouble().toJS,
      Map<Object?, Object?> m => _bareObject(m),
      Iterable<Object?> l => [for (final item in l) _jsValue(item)].toJS,
      _ => throw StateError('not a plain value: ${value.runtimeType}'),
    };

JSObject _bareObject(Map<Object?, Object?> map) {
  final object =
      _objectClass.callMethodVarArgs('create'.toJS, [null])! as JSObject;
  map.forEach((k, v) => object[k! as String] = _jsValue(v));
  return object;
}

/// [map] as a plain object whose values are [_jsValue]s.
JSObject _envelope(Map<String, Object?> map) {
  final object = JSObject();
  map.forEach((k, v) => object[k] = _jsValue(v));
  return object;
}

/// The [JsKey] [value] names. A malformed key is a [BadKeyException] naming
/// the offending field, never the value received.
JsKey _jsKey(JSAny? value) {
  try {
    final object = _object(value, 'key');
    return JsKey(_string(object['key'], 'key'),
        namespace: _field(object, 'namespace'),
        sharedWith: _field(object, 'sharedWith'),
        sharedBy: _field(object, 'sharedBy'),
        isPublic: _flag(object, 'public'),
        isCached: _flag(object, 'cached'),
        noNamespace: _flag(object, 'noNamespace'));
  } on ArgumentError catch (e) {
    throw BadKeyException('$e');
  }
}

/// The JS surface of one open client, as `AtClient` in the TypeScript
/// package wraps it.
@JSExport()
class BridgeSession {
  BridgeSession(this._session);

  final JsSession _session;

  JSPromise<JSBoolean> notify(JSAny? key, JSAny? value) => _promise(() async =>
      (await _session.notify(_jsKey(key), _string(value, 'value'))).toJS);

  /// Calls [callback] with each notification matching [regex] as
  /// `{id, from, key, value, epochMillis, operation}`, and [onError], when
  /// given, with the `{code, message}` of each error on the stream (without
  /// it the error is logged); returns the function that unsubscribes, or,
  /// when it cannot subscribe, the `{code, message}` object the promises
  /// reject with. It does not throw: a Dart `throw` reaches JS wrapped, with
  /// no `code` for the caller to read.
  JSAny subscribe(JSAny? regex, JSFunction callback, [JSAny? onError]) {
    try {
      final report = _optionalFunction(onError, 'onError');
      final unsubscribe = _session.subscribe(
          _string(regex, 'regex'),
          (n) => callback.callAsFunction(
              null,
              _envelope({
                'id': n.id,
                'from': n.from,
                'key': n.key,
                'value': n.value,
                'epochMillis': n.epochMillis,
                'operation': n.operation,
              })), onError: (error) {
        final reason = _rejection(error);
        if (report != null) {
          report.callAsFunction(null, reason);
        } else {
          web.console.warn(
              'at_client_web: a subscription error was dropped (${atErrorCode(error)})'
                  .toJS);
        }
      });
      return unsubscribe.toJS;
    } on Object catch (error) {
      return _rejection(error);
    }
  }

  /// The connection status: `connecting`, `connected`, `waiting:network`,
  /// `waiting:server` or `waiting:auth`.
  JSString status() => _session.status.toJS;

  /// Calls [callback] with each later change of [status]; returns the
  /// function that stops it, or the `{code, message}` object when it cannot.
  JSAny onStatus(JSFunction callback) {
    try {
      final stop =
          _session.onStatus((s) => callback.callAsFunction(null, s.toJS));
      return stop.toJS;
    } on Object catch (error) {
      return _rejection(error);
    }
  }

  /// The collection [name] holding items tagged `opts.type`; `opts` may add
  /// `eventSource` (`data`, `notifs` or `both`) and `expiration`, in
  /// milliseconds (seven days by default).
  JSPromise<JSObject> collection(JSAny? name, JSAny? opts) =>
      _promise(() async {
        final options = _object(opts, 'opts');
        final expiration = options['expiration'];
        final adapter = await _session.collection(_string(name, 'name'),
            type: _string(options['type'], 'type'),
            eventSource: _field(options, 'eventSource'),
            expirationMs: expiration == null || expiration.isUndefinedOrNull
                ? null
                : _wholeNumber(expiration, 'expiration'));
        return createJSInteropWrapper(
            BridgeCollection(adapter, _session.atSign));
      });

  /// A one-time passcode for a new device to enroll with.
  JSPromise<JSString> otp() =>
      _promise(() async => (await _session.otp()).toJS);

  /// The requests awaiting a decision, each `{id, appName, deviceName,
  /// namespaces}` with `namespaces` mapping a namespace to its access.
  JSPromise<JSArray<JSObject>> pendingEnrollments() => _promise(() async => [
        for (final e in await _session.pendingEnrollments())
          _envelope({
            'id': e.id,
            'appName': e.appName,
            'deviceName': e.deviceName,
            'namespaces': e.namespaces,
          })
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

int _wholeNumber(JSAny? value, String name) {
  final n = _fromJs(value, name);
  if (n is! int) throw _expected(name, 'a whole number');
  return n;
}

/// The JS surface of one collection: the adapter's eight operations on JS
/// values. Items are addressed `{id, owner}`, `owner` being this session's
/// atSign when left out.
@JSExport()
class BridgeCollection {
  BridgeCollection(this._adapter, this._self);

  final JsCollectionsAdapter _adapter;
  final String _self;

  JsItemAddress _address(JSAny? value) {
    final object = _object(value, 'address');
    return (
      id: _string(object['id'], 'id'),
      owner: Atsign(_field(object, 'owner') ?? _self),
    );
  }

  Map<String, dynamic> _data(JSAny? value) {
    _object(value, 'data');
    return _fromJs(value, 'data')! as Map<String, dynamic>;
  }

  JSObject _item(JsItem item) => _envelope(item);

  JSObject _listing(JsListing listing) => _envelope({
        'items': [for (final item in listing.items) item],
        'unreadable': [
          for (final u in listing.unreadable)
            {'id': u.id, 'owner': u.owner.toString(), 'code': u.code}
        ],
      });

  /// Creates an item from `data`; `opts` may name its `id` and who it is
  /// `sharedWith`.
  JSPromise<JSObject> create(JSAny? data, [JSAny? opts]) => _promise(() async {
        final options = _optionalObject(opts, 'opts');
        return _item(await _adapter.create(_data(data),
            id: options == null ? null : _field(options, 'id'),
            sharedWith: options == null
                ? const []
                : _strings(options['sharedWith'], 'sharedWith')));
      });

  /// The item at `address`, or null.
  JSPromise<JSAny?> get(JSAny? address) => _promise(() async {
        final item = await _adapter.get(_address(address));
        return item == null ? null : _item(item);
      });

  /// `{items, unreadable}`: every readable item.
  JSPromise<JSObject> list() =>
      _promise(() async => _listing(await _adapter.list()));

  /// `{items, unreadable}`: the items matching every `{path, op, value}` of
  /// `where`.
  JSPromise<JSObject> query(JSAny? where) => _promise(() async {
        if (where == null || !where.isA<JSArray>()) {
          throw _expected('where', 'an array');
        }
        final clauses = [
          for (final raw in (where as JSArray<JSAny?>).toDart)
            (
              path: _string(_object(raw, 'where')['path'], 'path'),
              op: _string((raw! as JSObject)['op'], 'op'),
              value: _fromJs((raw as JSObject)['value'], 'value'),
            )
        ];
        return _listing(await _adapter.query(clauses));
      });

  /// Replaces the data of the item at `address`.
  JSPromise<JSObject> update(JSAny? address, JSAny? data) => _promise(
      () async => _item(await _adapter.update(_address(address), _data(data))));

  /// Adds the atSigns of `atSigns` to the item's recipients.
  JSPromise<JSObject> share(JSAny? address, JSAny? atSigns) =>
      _promise(() async => _item(await _adapter.share(
          _address(address), _strings(atSigns, 'atSigns'))));

  /// Deletes the item at `address`; `opts.cascade` removes its sub-items too.
  JSPromise<JSAny?> remove(JSAny? address, [JSAny? opts]) => _promise(() async {
        final options = _optionalObject(opts, 'opts');
        await _adapter.remove(_address(address),
            cascade: options != null && _flag(options, 'cascade'));
        return null;
      });

  /// Calls `onEvent` with each event of the collection and `onError`, when
  /// given, with the `{code, message}` of each error on the stream; returns
  /// the function that stops watching, or the rejection object when it
  /// cannot start.
  JSAny watch(JSAny? onEvent, [JSAny? onError]) {
    try {
      final deliver = _optionalFunction(onEvent, 'onEvent') ??
          (throw ArgumentError.notNull('onEvent'));
      final report = _optionalFunction(onError, 'onError');
      final cancel = _adapter
          .watch((event) => deliver.callAsFunction(null, _envelope(event)),
              onError: (error) {
        if (report != null) {
          report.callAsFunction(null, _rejection(error));
        } else {
          web.console.warn(
              'at_client_web: a watch error was dropped (${error.code})'.toJS);
        }
      });
      return (() {
        unawaited(cancel());
      }).toJS;
    } on Object catch (error) {
      return _rejection(error);
    }
  }
}

/// The JS surface of the package: what `AtClient.create` calls.
///
/// The opener and the secure-context check are injectable; they default to
/// this browser's.
@JSExport()
class AtClientWebBridge {
  AtClientWebBridge({SessionOpener? open, bool Function()? isSecureContext})
      : _open = open ?? _openSession,
        _isSecureContext = isSecureContext ?? _pageIsSecure;

  final SessionOpener _open;
  final bool Function() _isSecureContext;

  static bool _pageIsSecure() => web.window.isSecureContext;

  /// Opens a session for `{atSign, namespace, keys, rootDomain?}`: `keys` is
  /// the `.atKeys` document, as its JSON text or as an object, and
  /// `rootDomain` is `host` or `host:port`.
  JSPromise<JSObject> create(JSAny? opts) => _promise(() async {
        if (!_isSecureContext()) {
          throw UnsupportedError('a secure context (HTTPS) is required');
        }
        final session = await _open(_options(opts));
        return createJSInteropWrapper(BridgeSession(session));
      });

  BridgeOptions _options(JSAny? opts) {
    final object = _object(opts, 'opts');
    final rootDomain = _field(object, 'rootDomain');
    return BridgeOptions(
        atSign: _string(object['atSign'], 'atSign'),
        namespace: _string(object['namespace'], 'namespace'),
        keys: _keys(object['keys']),
        rootDomain: rootDomain == null ? null : parseRootDomain(rootDomain));
  }

  Map<String, dynamic> _keys(JSAny? value) {
    final Object? document;
    if (value != null && value.isA<JSString>()) {
      try {
        document = jsonDecode((value as JSString).toDart);
      } on FormatException {
        throw BadKeyException('keys is not valid JSON');
      }
    } else {
      document = _fromJs(_object(value, 'keys'), 'keys');
    }
    if (document is! Map<String, dynamic>) {
      throw _expected('keys', 'an .atKeys JSON object or its text');
    }
    return document;
  }
}
