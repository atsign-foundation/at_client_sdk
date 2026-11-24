import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart'
    show AtClient, AtSignLogger, Atsign, InvalidAtSignException;
import 'package:web/web.dart' as web;

import '../collections/js_collections_adapter.dart';
import '../exceptions.dart';
import '../session/portal_session.dart';
import '../session/session_options.dart';
import '../session/session_transport.dart';
import '../session/session_transport_options.dart';
import '../session/web_passkey_entry.dart';
import 'error_codes.dart';
import '../session/at_client_session.dart';

/// Opens the session of a caller's [SessionOptions].
typedef OpenJsSession = Future<Session> Function(SessionOptions options);

final _logger = AtSignLogger('BridgeEntry');

/// The browser's [OpenJsSession], and the only place a session is opened: a
/// keys session on [portalSession] over [sessionTransport], a passkey session
/// on [passkeyLogin]. The session's `close()` awaits the stop of what was
/// opened: the client's own for keys, the passkey session's, which also
/// closes its vault, for a passkey.
Future<Session> _openSession(SessionOptions options) async {
  final (AtClient client, Future<void> Function() stop) = switch (options) {
    KeysSessionOptions() => await _openKeys(options),
    PasskeySessionOptions() => await _openPasskey(options),
  };
  return sessionOver(client, stop, options);
}

/// The [Session] [options] describes over [client], whose [stop] ends what
/// opened it. A construction that throws awaits [stop] before rethrowing, so
/// an opened client or passkey session is never left running.
Future<Session> sessionOver(AtClient client, Future<void> Function() stop,
    SessionOptions options) async {
  try {
    return AtClientSession(client,
        namespace: options.namespace,
        isNavigatorOnline: () => web.window.navigator.onLine,
        networkChanges: _networkChanges(),
        warn: _logger.warning,
        stop: stop);
  } on Object {
    await stop();
    rethrow;
  }
}

Future<(AtClient, Future<void> Function())> _openKeys(
    KeysSessionOptions options) async {
  final client = await portalSession(
      atSign: options.atSign,
      app: options.namespace,
      keys: options.keys,
      transport:
          sessionTransport(SessionTransportOptions(root: options.rootDomain)));
  return (client, client.stop);
}

Future<(AtClient, Future<void> Function())> _openPasskey(
    PasskeySessionOptions options) async {
  final session = await passkeyLogin(
      atSign: options.atSign,
      app: options.namespace,
      rpId: options.rpId,
      rpName: options.rpName,
      transport: SessionTransportOptions(root: options.rootDomain));
  return (session.client, session.stop);
}

/// An event each time the browser goes online or offline, so a session's
/// `waiting:network` and `waiting:server` follow it.
Stream<void> _networkChanges() {
  late StreamController<void> controller;
  late final JSFunction listener;
  controller = StreamController<void>(
    onListen: () {
      listener = ((web.Event _) => controller.add(null)).toJS;
      web.window.addEventListener('online', listener);
      web.window.addEventListener('offline', listener);
    },
    onCancel: () {
      web.window.removeEventListener('online', listener);
      web.window.removeEventListener('offline', listener);
    },
  );
  return controller.stream;
}

/// A rejection reason: a plain object with `code` and `message`, never an
/// `Error`; a collection failure adds `id`, `owner`, `kind` and `failures`
/// where it has them, and the rejection of a bad address owner adds `id`.
JSObject _toRejection(Object error) {
  final code = errorCodeOf(error);
  final reason = JSObject()..['code'] = code.toJS;
  reason['message'] = atErrorMessage(error).toJS;
  switch (error) {
    case JsCollectionsError():
      if (error.id case final id?) reason['id'] = id.toJS;
      if (error.owner case final owner?) reason['owner'] = owner.toJS;
      if (error.causeType case final kind?) reason['kind'] = kind.toJS;
      if (error.failures.isNotEmpty) {
        reason['failures'] = _toJs(error.failures);
      }
    case InvalidArgumentException(:final id?):
      reason['id'] = id.toJS;
    default:
  }
  return reason;
}

/// A promise of [body]'s result that rejects with a [_toRejection] of whatever
/// [body] throws.
JSPromise<T> _promise<T extends JSAny?>(FutureOr<T> Function() body) =>
    JSPromise<T>((JSFunction resolve, JSFunction reject) {
      Future<T>.sync(body).then((value) => resolve.callAsFunction(null, value),
          onError: (Object error) =>
              reject.callAsFunction(null, _toRejection(error)));
    }.toJS);

/// An argument error that names the parameter and the type it expects, never
/// the value received.
InvalidArgumentException _invalidArgument(String name, String type) =>
    InvalidArgumentException(name, expected: type);

InvalidArgumentException _missingArgument(String name) =>
    InvalidArgumentException.missing(name);

final JSObject _objectClass = globalContext['Object']! as JSObject;
final JSAny _objectPrototype = _objectClass['prototype']!;
final JSObject _arrayClass = globalContext['Array']! as JSObject;

bool _hasOwn(JSObject object, String name) =>
    (_objectClass.callMethod('hasOwn'.toJS, object, name.toJS)! as JSBoolean)
        .toDart;

JSAny? _own(JSObject object, String name) =>
    _hasOwn(object, name) ? object[name] : null;

bool _isArray(JSAny value) =>
    (_arrayClass.callMethod('isArray'.toJS, value)! as JSBoolean).toDart;

bool _isPlainObject(JSObject object) {
  if (_isArray(object)) return false;
  final proto = _objectClass.callMethod('getPrototypeOf'.toJS, object);
  if (proto == null || proto.isUndefinedOrNull) return true;
  return (_objectClass.callMethod('is'.toJS, proto, _objectPrototype)!
          as JSBoolean)
      .toDart;
}

String? _optionalString(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSString>()) throw _invalidArgument(name, 'a string');
  return (value as JSString).toDart;
}

String _string(JSAny? value, String name) =>
    _optionalString(value, name) ?? (throw _missingArgument(name));

String? _field(JSObject object, String name) =>
    _optionalString(_own(object, name), name);

bool _flag(JSObject object, String name) {
  final value = _own(object, name);
  if (value == null || value.isUndefinedOrNull) return false;
  if (!value.isA<JSBoolean>()) throw _invalidArgument(name, 'a boolean');
  return (value as JSBoolean).toDart;
}

JSObject _object(JSAny? value, String name) {
  if (value == null ||
      value.isUndefinedOrNull ||
      !value.isA<JSObject>() ||
      value.isA<JSFunction>() ||
      !_isPlainObject(value as JSObject)) {
    throw _invalidArgument(name, 'an object');
  }
  return value;
}

/// [value] as a plain object, or null when it is absent.
JSObject? _optionalObject(JSAny? value, String name) =>
    value == null || value.isUndefinedOrNull ? null : _object(value, name);

JSFunction? _optionalFunction(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSFunction>()) throw _invalidArgument(name, 'a function');
  return value as JSFunction;
}

JSFunction _function(JSAny? value, String name) =>
    _optionalFunction(value, name) ?? (throw _missingArgument(name));

List<String> _strings(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return const [];
  if (!value.isA<JSArray>()) {
    throw _invalidArgument(name, 'an array of strings');
  }
  return [
    for (final item in (value as JSArray<JSAny?>).toDart) _string(item, name)
  ];
}

/// The deepest nesting [_toDart] accepts and [_toJs] returns. A cyclic
/// page object reaches it instead of recursing until the stack overflows.
const _maxJsDepth = maxItemDataDepth;

/// The JS value [value] as plain Dart values: strings, bools, numbers
/// (integral ones as `int`), lists and string-keyed maps. Anything else —
/// a function, bigint, Date, Map, Set, RegExp, or typed array — is refused
/// naming [name].
Object? _toDart(JSAny? value, String name, [int depth = 0]) {
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
    if (!number.isFinite) throw _invalidArgument(name, 'finite numbers only');
    return number;
  }
  if (value.isA<JSArray>()) {
    if (depth >= _maxJsDepth) {
      throw _invalidArgument(name, 'at most $_maxJsDepth levels deep');
    }
    return [
      for (final item in (value as JSArray<JSAny?>).toDart)
        _toDart(item, name, depth + 1)
    ];
  }
  if (value.isA<JSObject>() && !value.isA<JSFunction>()) {
    final object = value as JSObject;
    if (!_isPlainObject(object)) {
      throw _invalidArgument(name, 'plain JSON values');
    }
    if (depth >= _maxJsDepth) {
      throw _invalidArgument(name, 'at most $_maxJsDepth levels deep');
    }
    final keys =
        (_objectClass.callMethod('keys'.toJS, object)! as JSArray<JSString>)
            .toDart;
    return <String, dynamic>{
      for (final key in keys)
        key.toDart: _toDart(_own(object, key.toDart), name, depth + 1)
    };
  }
  throw _invalidArgument(name, 'plain JSON values');
}

/// [value] (Dart values, as [_toDart] makes them) as JS values. A map
/// becomes an object with no prototype, so a key such as `__proto__` or
/// `toString` is data and never reaches `Object.prototype`. Nesting past
/// [_maxJsDepth] containers, counted as in [_toDart], throws
/// [itemTooDeep] before any recursion goes deeper.
JSAny? _toJs(Object? value, [int depth = 0]) {
  final isContainer = value is Map<Object?, Object?> || value is Iterable;
  if (isContainer && depth >= _maxJsDepth) throw itemTooDeep();
  return switch (value) {
    null => null,
    String s => s.toJS,
    bool b => b.toJS,
    num n => n.toDouble().toJS,
    Map<Object?, Object?> m => _bareObject(m, depth + 1),
    Iterable<Object?> l => [for (final item in l) _toJs(item, depth + 1)].toJS,
    _ => throw StateError('not a plain value: ${value.runtimeType}'),
  };
}

JSObject _bareObject(Map<Object?, Object?> map, int depth) {
  final object =
      _objectClass.callMethodVarArgs('create'.toJS, [null])! as JSObject;
  map.forEach((k, v) => object[k! as String] = _toJs(v, depth));
  return object;
}

/// [map] as a plain object whose values are [_toJs]s.
JSObject _envelope(Map<String, Object?> map) {
  final object = JSObject();
  map.forEach((k, v) => object[k] = _toJs(v));
  return object;
}

void _reportStreamError(JSFunction? report, Object error, String source) {
  if (report != null) {
    report.callAsFunction(null, _toRejection(error));
  } else {
    web.console.warn(
        'at_client_web: a $source error was dropped (${errorCodeOf(error)})'
            .toJS);
  }
}

/// The [NotifyKey] [value] names. A malformed key is a [InvalidKeyException] naming
/// the offending field, never the value received.
NotifyKey _jsKey(JSAny? value) {
  try {
    final object = _object(value, 'key');
    return NotifyKey(_string(_own(object, 'key'), 'key'),
        namespace: _field(object, 'namespace'),
        sharedWith: _field(object, 'sharedWith'),
        sharedBy: _field(object, 'sharedBy'),
        isPublic: _flag(object, 'public'),
        isCached: _flag(object, 'cached'),
        noNamespace: _flag(object, 'noNamespace'));
  } on InvalidArgumentException catch (e) {
    throw InvalidKeyException.field(e);
  }
}

/// The JS surface of one open client, as `AtClient` in the TypeScript
/// package wraps it.
@JSExport()
class BridgeSession {
  BridgeSession(this._session);

  final Session _session;

  JSPromise<JSBoolean> notify(JSAny? key, JSAny? value) => _promise(() async =>
      (await _session.notify(_jsKey(key), _string(value, 'value'))).toJS);

  /// Calls [callback] with each notification matching [regex] as
  /// `{id, from, key, value, epochMillis, operation}`, and [onError], when
  /// given, with the `{code, message}` of each error on the stream (without
  /// it the error is logged); returns the function that unsubscribes, or,
  /// when it cannot subscribe, the `{code, message}` object the promises
  /// reject with. It does not throw: a Dart `throw` reaches JS wrapped, with
  /// no `code` for the caller to read.
  JSAny subscribe([JSAny? regex, JSAny? callback, JSAny? onError]) {
    try {
      final pattern = _string(regex, 'regex');
      final deliver = _function(callback, 'callback');
      final report = _optionalFunction(onError, 'onError');
      final unsubscribe = _session.subscribe(
        pattern,
        (n) {
          deliver.callAsFunction(
              null,
              _envelope({
                'id': n.id,
                'from': n.from,
                'key': n.key,
                'value': n.value,
                'epochMillis': n.epochMillis,
                'operation': n.operation,
              }));
        },
        onError: (error) {
          _reportStreamError(report, error, 'subscription');
        },
      );
      return unsubscribe.toJS;
    } on Object catch (error) {
      return _toRejection(error);
    }
  }

  /// The connection status: `connecting`, `connected`, `waiting:network`,
  /// `waiting:server` or `waiting:auth`.
  JSString status() => _session.status.toJS;

  /// Calls [callback] with each later change of [status]; returns the
  /// function that stops it, or the `{code, message}` object when it cannot.
  JSAny onStatus([JSAny? callback]) {
    try {
      final deliver = _function(callback, 'callback');
      final stop =
          _session.onStatus((s) => deliver.callAsFunction(null, s.toJS));
      return stop.toJS;
    } on Object catch (error) {
      return _toRejection(error);
    }
  }

  /// The collection [name] holding items tagged `opts.type`; `opts` may add
  /// `eventSource` (`data`, `notifs` or `both`) and `expiration`, in
  /// milliseconds (seven days by default).
  JSPromise<JSObject> collection(JSAny? name, JSAny? opts) =>
      _promise(() async {
        final options = _object(opts, 'opts');
        final expiration = _own(options, 'expiration');
        final adapter = await _session.collection(_string(name, 'name'),
            type: _string(_own(options, 'type'), 'type'),
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
  final n = _toDart(value, name);
  if (n is! int) throw _invalidArgument(name, 'a whole number');
  return n;
}

/// The JS surface of one collection: the adapter's eight operations on JS
/// values. Items are addressed `{id, owner}`, `owner` being this session's
/// atSign when left out.
@JSExport()
class BridgeCollection {
  BridgeCollection(this._adapter, this._self);

  final ItemCollection _adapter;
  final String _self;

  JsItemAddress _address(JSAny? value) {
    final object = _object(value, 'address');
    final id = _string(_own(object, 'id'), 'id');
    final rawOwner = _field(object, 'owner');
    try {
      return (id: id, owner: Atsign(rawOwner ?? _self));
    } on InvalidAtSignException {
      throw InvalidArgumentException('owner',
          expected: 'a valid atSign', id: id);
    }
  }

  Map<String, dynamic> _data(JSAny? value) {
    _object(value, 'data');
    return _toDart(value, 'data')! as Map<String, dynamic>;
  }

  /// The item as an object whose `data` is converted from depth 0, so the
  /// cap counts the data's own levels and not the envelope around it.
  JSObject _item(JsItem item) {
    try {
      return _envelope(item);
    } on JsCollectionsError catch (e) {
      if (e.kind == CollectionFailure.tooDeep &&
          (e.id == null || e.owner == null)) {
        throw itemTooDeep(
          id: e.id ?? item['id'] as String?,
          owner: e.owner ?? item['owner']?.toString(),
        );
      }
      rethrow;
    }
  }

  JSObject _listing(JsListing listing) => JSObject()
    ..['items'] = [for (final item in listing.items) _item(item)].toJS
    ..['unreadable'] = _toJs([
      for (final u in listing.unreadable)
        {
          'id': u.id,
          'owner': u.owner.toString(),
          'code': collectionErrorCode(u.kind)
        }
    ]);

  /// Creates an item from `data`; `opts` may name its `id` and who it is
  /// `sharedWith`.
  JSPromise<JSObject> create(JSAny? data, [JSAny? opts]) => _promise(() async {
        final options = _optionalObject(opts, 'opts');
        return _item(await _adapter.create(_data(data),
            id: options == null ? null : _field(options, 'id'),
            sharedWith: options == null
                ? const []
                : _strings(_own(options, 'sharedWith'), 'sharedWith')));
      });

  /// The item at `address`, or null.
  JSPromise<JSAny?> get(JSAny? address) => _promise(() async {
        final item = await _adapter.get(_address(address));
        return item == null ? null : _item(item);
      });

  /// `{items, unreadable}`: every readable item.
  JSPromise<JSObject> list() => _promise(() async {
        return _listing(await _adapter.list());
      });

  /// `{items, unreadable}`: the items matching every `{path, op, value}` of
  /// `where`.
  JSPromise<JSObject> query(JSAny? where) => _promise(() async {
        if (where == null || !where.isA<JSArray>()) {
          throw _invalidArgument('where', 'an array');
        }
        final clauses = [
          for (final raw in (where as JSArray<JSAny?>).toDart)
            () {
              final clause = _object(raw, 'where');
              return (
                path: _string(_own(clause, 'path'), 'path'),
                op: _string(_own(clause, 'op'), 'op'),
                value: _toDart(_own(clause, 'value'), 'value'),
              );
            }()
        ];
        return _listing(await _adapter.query(clauses));
      });

  /// Replaces the data of the item at `address`.
  JSPromise<JSObject> update(JSAny? address, JSAny? data) => _promise(() async {
        return _item(await _adapter.update(_address(address), _data(data)));
      });

  /// Adds the atSigns of `atSigns` to the item's recipients.
  JSPromise<JSObject> share(JSAny? address, JSAny? atSigns) =>
      _promise(() async {
        return _item(await _adapter.share(
            _address(address), _strings(atSigns, 'atSigns')));
      });

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
      final deliver = _function(onEvent, 'onEvent');
      final report = _optionalFunction(onError, 'onError');
      final cancel = _adapter.watch(
        (event) {
          deliver.callAsFunction(null, _envelope(event));
        },
        onError: (error) {
          _reportStreamError(report, error, 'watch');
        },
      );
      return (() {
        unawaited(cancel().catchError((Object _) {
          _logger.warning('Failed to cancel collection watch');
        }));
      }).toJS;
    } on Object catch (error) {
      return _toRejection(error);
    }
  }
}

/// The JS surface of the package: what `AtClient.create` calls.
///
/// The opener and the secure-context check are injectable; they default to
/// this browser's.
@JSExport()
class BridgeEntry {
  BridgeEntry({OpenJsSession? open, bool Function()? isSecureContext})
      : _open = open ?? _openSession,
        _isSecureContext = isSecureContext ?? _pageIsSecure;

  final OpenJsSession _open;
  final bool Function() _isSecureContext;

  static bool _pageIsSecure() => web.window.isSecureContext;

  /// Opens a session for `{atSign, namespace, keys, rootDomain?}`: `keys` is
  /// the `.atKeys` document, as its JSON text or as an object, and
  /// `rootDomain` is `host` or `host:port`.
  JSPromise<JSObject> create(JSAny? opts) => _promise(() async {
        if (!_isSecureContext()) {
          throw UnsupportedOperationException(
              UnsupportedOperation.secureContext);
        }
        final session = await _open(_options(opts));
        return createJSInteropWrapper(BridgeSession(session));
      });

  /// The [SessionOptions] [opts] names. The options validate their own
  /// fields; the bridge words what it says of each.
  SessionOptions _options(JSAny? opts) {
    final object = _object(opts, 'opts');
    final atSign = _string(_own(object, 'atSign'), 'atSign');
    final namespace = _string(_own(object, 'namespace'), 'namespace');
    final rootDomain = _field(object, 'rootDomain');
    final keys = _keys(_own(object, 'keys'));
    try {
      return KeysSessionOptions(
          atSign: atSign,
          namespace: namespace,
          keys: keys,
          rootDomain: rootDomain);
    } on ArgumentError catch (e) {
      throw switch (e.name) {
        'atSign' => _invalidArgument('atSign', 'a valid atSign'),
        'namespace' =>
          _invalidArgument('namespace', 'a non-empty namespace segment'),
        'rootDomain' => _invalidArgument('rootDomain', 'host or host:port'),
        'keys' => InvalidKeyException(KeyRefusal.keysDocument),
        _ => e,
      };
    }
  }

  Map<String, dynamic> _keys(JSAny? value) {
    final Object? document;
    if (value != null && value.isA<JSString>()) {
      try {
        document = jsonDecode((value as JSString).toDart);
      } on FormatException {
        throw InvalidKeyException(KeyRefusal.keysJson);
      }
    } else {
      document = _toDart(_object(value, 'keys'), 'keys');
    }
    if (document is! Map<String, dynamic>) {
      throw _invalidArgument('keys', 'an .atKeys JSON object or its text');
    }
    return document;
  }
}
