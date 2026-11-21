import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart'
    show
        AtEnrollmentException,
        AtEnrollmentPendingException,
        AtKeys,
        AtNoCredentialException,
        AtOpenRefusedException,
        AtRootDomain,
        AtSignLogger,
        Atsign,
        EnrollmentConveyanceException,
        InvalidAtSignException;
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
    final parsed = AtRootDomain.parse(value);
    SessionTransportOptions(root: parsed);
    return parsed;
  } on ArgumentError {
    throw _expected('rootDomain', 'host or host:port');
  } on Exception {
    throw _expected('rootDomain', 'host or host:port');
  }
}

final class _BridgeArgumentError extends ArgumentError {
  _BridgeArgumentError(super.message);
}

final _controlChars =
    RegExp(r'[\x00-\x1f\x7f-\x9f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]');

String _safeMessage(String value) => value.replaceAll(_controlChars, ' ');

String _rejectionMessage(Object error, String code) {
  if (error is _BridgeArgumentError) return error.toString();
  return switch (error) {
    AtOpenRefusedException(:final state) =>
      'the atServer refused the session (${state.cause?.name ?? 'refused'})',
    PortalSessionOfflineException(:final state) =>
      'the session could not reach the atServer (${state.cause?.name ?? 'offline'})',
    AtEnrollmentPendingException() =>
      'onboarding is incomplete: no usable credential',
    EnrollmentConveyanceException(:final keyPackageStatus) =>
      'enrollment approved on server, but key conveyance failed (${keyPackageStatus.name})',
    AtEnrollmentException() =>
      'the enrollment request was denied or is not pending',
    SessionClosedException() => error.toString(),
    UnsupportedKeyMaterialException() =>
      'the keys carry unsupported cryptographic material',
    ManageAccessException() => error.toString(),
    UnsupportedError(:final message) =>
      _safeMessage(message ?? 'unsupported operation'),
    BadKeyException() => error.toString(),
    AtNoCredentialException() => 'keys hold no usable credential',
    InvalidAtSignException() => 'atSign is not valid',
    _ when code == 'closed' => SessionClosedException().toString(),
    _ => 'internal error',
  };
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
    reason['message'] = _rejectionMessage(error, code).toJS;
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
_BridgeArgumentError _expected(String name, String type) =>
    _BridgeArgumentError('$name must be $type');

_BridgeArgumentError _required(String name) =>
    _BridgeArgumentError('$name must not be null');

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
  if (!value.isA<JSString>()) throw _expected(name, 'a string');
  return (value as JSString).toDart;
}

String _string(JSAny? value, String name) =>
    _optionalString(value, name) ?? (throw _required(name));

String? _field(JSObject object, String name) =>
    _optionalString(_own(object, name), name);

bool _flag(JSObject object, String name) {
  final value = _own(object, name);
  if (value == null || value.isUndefinedOrNull) return false;
  if (!value.isA<JSBoolean>()) throw _expected(name, 'a boolean');
  return (value as JSBoolean).toDart;
}

JSObject _object(JSAny? value, String name) {
  if (value == null ||
      value.isUndefinedOrNull ||
      !value.isA<JSObject>() ||
      value.isA<JSFunction>() ||
      !_isPlainObject(value as JSObject)) {
    throw _expected(name, 'an object');
  }
  return value;
}

/// [value] as a plain object, or null when it is absent.
JSObject? _optionalObject(JSAny? value, String name) =>
    value == null || value.isUndefinedOrNull ? null : _object(value, name);

JSFunction? _optionalFunction(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSFunction>()) throw _expected(name, 'a function');
  return value as JSFunction;
}

JSFunction _function(JSAny? value, String name) =>
    _optionalFunction(value, name) ?? (throw _required(name));

List<String> _strings(JSAny? value, String name) {
  if (value == null || value.isUndefinedOrNull) return const [];
  if (!value.isA<JSArray>()) throw _expected(name, 'an array of strings');
  return [
    for (final item in (value as JSArray<JSAny?>).toDart) _string(item, name)
  ];
}

/// The deepest nesting [_fromJs] accepts and [_jsValue] returns. A cyclic
/// page object reaches it instead of recursing until the stack overflows.
const _maxJsDepth = maxItemDataDepth;

/// The JS value [value] as plain Dart values: strings, bools, numbers
/// (integral ones as `int`), lists and string-keyed maps. Anything else —
/// a function, bigint, Date, Map, Set, RegExp, or typed array — is refused
/// naming [name].
Object? _fromJs(JSAny? value, String name, [int depth = 0]) {
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
    if (depth >= _maxJsDepth) {
      throw _expected(name, 'at most $_maxJsDepth levels deep');
    }
    return [
      for (final item in (value as JSArray<JSAny?>).toDart)
        _fromJs(item, name, depth + 1)
    ];
  }
  if (value.isA<JSObject>() && !value.isA<JSFunction>()) {
    final object = value as JSObject;
    if (!_isPlainObject(object)) {
      throw _expected(name, 'plain JSON values');
    }
    if (depth >= _maxJsDepth) {
      throw _expected(name, 'at most $_maxJsDepth levels deep');
    }
    final keys =
        (_objectClass.callMethod('keys'.toJS, object)! as JSArray<JSString>)
            .toDart;
    return <String, dynamic>{
      for (final key in keys)
        key.toDart: _fromJs(_own(object, key.toDart), name, depth + 1)
    };
  }
  throw _expected(name, 'plain JSON values');
}

/// [value] (Dart values, as [_fromJs] makes them) as JS values. A map
/// becomes an object with no prototype, so a key such as `__proto__` or
/// `toString` is data and never reaches `Object.prototype`. Nesting past
/// [_maxJsDepth] containers, counted as in [_fromJs], throws
/// [itemTooDeep] before any recursion goes deeper.
JSAny? _jsValue(Object? value, [int depth = 0]) {
  final isContainer = value is Map<Object?, Object?> || value is Iterable;
  if (isContainer && depth >= _maxJsDepth) throw itemTooDeep();
  return switch (value) {
    null => null,
    String s => s.toJS,
    bool b => b.toJS,
    num n => n.toDouble().toJS,
    Map<Object?, Object?> m => _bareObject(m, depth + 1),
    Iterable<Object?> l =>
      [for (final item in l) _jsValue(item, depth + 1)].toJS,
    _ => throw StateError('not a plain value: ${value.runtimeType}'),
  };
}

JSObject _bareObject(Map<Object?, Object?> map, int depth) {
  final object =
      _objectClass.callMethodVarArgs('create'.toJS, [null])! as JSObject;
  map.forEach((k, v) => object[k! as String] = _jsValue(v, depth));
  return object;
}

/// [map] as a plain object whose values are [_jsValue]s.
JSObject _envelope(Map<String, Object?> map) {
  final object = JSObject();
  map.forEach((k, v) => object[k] = _jsValue(v));
  return object;
}

void _reportStreamError(JSFunction? report, Object error, String source) {
  if (report != null) {
    report.callAsFunction(null, _rejection(error));
  } else {
    web.console.warn(
        'at_client_web: a $source error was dropped (${atErrorCode(error)})'
            .toJS);
  }
}

/// The [JsKey] [value] names. A malformed key is a [BadKeyException] naming
/// the offending field, never the value received.
JsKey _jsKey(JSAny? value) {
  try {
    final object = _object(value, 'key');
    return JsKey(_string(_own(object, 'key'), 'key'),
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
  final _watchCancels = <Future<void> Function()>{};

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
      try {
        RegExp(pattern);
      } on FormatException {
        throw _expected('regex', 'a valid regular expression');
      }
      final deliver = _function(callback, 'callback');
      final report = _optionalFunction(onError, 'onError');
      final unsubscribe = _session.subscribe(
        pattern,
        (n) => deliver.callAsFunction(
            null,
            _envelope({
              'id': n.id,
              'from': n.from,
              'key': n.key,
              'value': n.value,
              'epochMillis': n.epochMillis,
              'operation': n.operation,
            })),
        onError: (error) => _reportStreamError(report, error, 'subscription'),
      );
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
  JSAny onStatus([JSAny? callback]) {
    try {
      final deliver = _function(callback, 'callback');
      final stop =
          _session.onStatus((s) => deliver.callAsFunction(null, s.toJS));
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
        final expiration = _own(options, 'expiration');
        final adapter = await _session.collection(_string(name, 'name'),
            type: _string(_own(options, 'type'), 'type'),
            eventSource: _field(options, 'eventSource'),
            expirationMs: expiration == null || expiration.isUndefinedOrNull
                ? null
                : _wholeNumber(expiration, 'expiration'));
        return createJSInteropWrapper(BridgeCollection(
          adapter,
          _session.atSign,
          isClosed: () => _session.isClosed,
          onWatch: _watchCancels.add,
          onWatchCancel: _watchCancels.remove,
        ));
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
        for (final cancel in [..._watchCancels]) {
          try {
            await cancel();
          } on Object catch (_) {
            _logger.warning('Failed to cancel collection watch on close');
          }
        }
        _watchCancels.clear();
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
  BridgeCollection(
    this._adapter,
    this._self, {
    bool Function()? isClosed,
    void Function(Future<void> Function() cancel)? onWatch,
    void Function(Future<void> Function() cancel)? onWatchCancel,
  })  : _isClosed = isClosed ?? (() => false),
        _onWatch = onWatch,
        _onWatchCancel = onWatchCancel;

  final JsCollection _adapter;
  final String _self;
  final bool Function() _isClosed;
  final void Function(Future<void> Function() cancel)? _onWatch;
  final void Function(Future<void> Function() cancel)? _onWatchCancel;

  void _open() {
    if (_isClosed()) throw SessionClosedException();
  }

  JsItemAddress _address(JSAny? value) {
    final object = _object(value, 'address');
    final id = _string(_own(object, 'id'), 'id');
    final rawOwner = _field(object, 'owner');
    try {
      return (id: id, owner: Atsign(rawOwner ?? _self));
    } on InvalidAtSignException {
      throw JsCollectionsError(
        CollectionErrorCodes.invalidArgument,
        'owner must be a valid atSign',
        id: id.toLowerCase(),
      );
    }
  }

  Map<String, dynamic> _data(JSAny? value) {
    _object(value, 'data');
    return _fromJs(value, 'data')! as Map<String, dynamic>;
  }

  /// The item as an object whose `data` is converted from depth 0, so the
  /// cap counts the data's own levels and not the envelope around it.
  JSObject _item(JsItem item) {
    try {
      return _envelope(item);
    } on JsCollectionsError catch (e) {
      if (e.code == CollectionErrorCodes.tooDeep &&
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
    ..['unreadable'] = _jsValue([
      for (final u in listing.unreadable)
        {'id': u.id, 'owner': u.owner.toString(), 'code': u.code}
    ]);

  /// Creates an item from `data`; `opts` may name its `id` and who it is
  /// `sharedWith`.
  JSPromise<JSObject> create(JSAny? data, [JSAny? opts]) => _promise(() async {
        _open();
        final options = _optionalObject(opts, 'opts');
        return _item(await _adapter.create(_data(data),
            id: options == null ? null : _field(options, 'id'),
            sharedWith: options == null
                ? const []
                : _strings(_own(options, 'sharedWith'), 'sharedWith')));
      });

  /// The item at `address`, or null.
  JSPromise<JSAny?> get(JSAny? address) => _promise(() async {
        _open();
        final item = await _adapter.get(_address(address));
        return item == null ? null : _item(item);
      });

  /// `{items, unreadable}`: every readable item.
  JSPromise<JSObject> list() => _promise(() async {
        _open();
        return _listing(await _adapter.list());
      });

  /// `{items, unreadable}`: the items matching every `{path, op, value}` of
  /// `where`.
  JSPromise<JSObject> query(JSAny? where) => _promise(() async {
        _open();
        if (where == null || !where.isA<JSArray>()) {
          throw _expected('where', 'an array');
        }
        final clauses = [
          for (final raw in (where as JSArray<JSAny?>).toDart)
            () {
              final clause = _object(raw, 'where');
              return (
                path: _string(_own(clause, 'path'), 'path'),
                op: _string(_own(clause, 'op'), 'op'),
                value: _fromJs(_own(clause, 'value'), 'value'),
              );
            }()
        ];
        return _listing(await _adapter.query(clauses));
      });

  /// Replaces the data of the item at `address`.
  JSPromise<JSObject> update(JSAny? address, JSAny? data) => _promise(() async {
        _open();
        return _item(await _adapter.update(_address(address), _data(data)));
      });

  /// Adds the atSigns of `atSigns` to the item's recipients.
  JSPromise<JSObject> share(JSAny? address, JSAny? atSigns) =>
      _promise(() async {
        _open();
        return _item(await _adapter.share(
            _address(address), _strings(atSigns, 'atSigns')));
      });

  /// Deletes the item at `address`; `opts.cascade` removes its sub-items too.
  JSPromise<JSAny?> remove(JSAny? address, [JSAny? opts]) => _promise(() async {
        _open();
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
      _open();
      final deliver = _function(onEvent, 'onEvent');
      final report = _optionalFunction(onError, 'onError');
      late final Future<void> Function() cancel;
      cancel = _adapter.watch(
        (event) {
          if (_isClosed()) return;
          deliver.callAsFunction(null, _envelope(event));
        },
        onError: (error) {
          if (_isClosed()) return;
          _reportStreamError(report, error, 'watch');
        },
      );
      _onWatch?.call(cancel);
      return (() {
        _onWatchCancel?.call(cancel);
        unawaited(cancel().catchError((Object _) {
          _logger.warning('Failed to cancel collection watch');
        }));
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
    final rawAtSign = _string(_own(object, 'atSign'), 'atSign');
    final Atsign atSign;
    try {
      atSign = Atsign(rawAtSign);
    } on InvalidAtSignException {
      throw _expected('atSign', 'a valid atSign');
    }
    final rawNamespace = _string(_own(object, 'namespace'), 'namespace');
    final String namespace;
    try {
      namespace = normalizeSessionNamespace(rawNamespace);
    } on ArgumentError {
      throw _expected('namespace', 'a non-empty namespace segment');
    }
    final rootDomain = _field(object, 'rootDomain');
    return BridgeOptions(
        atSign: atSign,
        namespace: namespace,
        keys: _keys(_own(object, 'keys')),
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
