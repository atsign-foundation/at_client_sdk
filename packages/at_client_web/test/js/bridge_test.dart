@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client/at_client.dart'
    show
        AtConnectionCause,
        AtConnectionState,
        AtEnrollmentException,
        AtNoCredentialException,
        AtOpenRefusedException,
        Atsign,
        StoppedException;
import 'package:at_client_web/src/collections/js_collections_adapter.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/at_error_code.dart';
import 'package:at_client_web/src/js/bridge.dart';
import 'package:at_client_web/src/js/js_session.dart';
import 'package:test/test.dart';

/// A [JsCollection] that records each call and answers what it is
/// told to.
class _FakeAdapter implements JsCollection {
  final calls = <String>[];
  Object? failure;
  var missing = false;
  JsItem item = {
    'id': 'i1',
    'owner': '@alice',
    'type': 'note',
    'data': <String, Object?>{'n': 1},
    'sharedWith': <String>[],
    'createdAt': 1,
    'expiresAt': 2,
    'availableAt': null,
  };
  JsListing listing = (items: const [], unreadable: const []);
  void Function(JsEvent)? onEvent;
  void Function(CollectionException)? onError;
  Object? last;
  var cancelled = 0;

  Future<T> _run<T>(String call, T Function() result, [Object? args]) async {
    calls.add(call);
    last = args;
    if (failure case final error?) throw error;
    return result();
  }

  @override
  Future<JsItem> create(Map<String, dynamic> data,
          {String? id, List<String> sharedWith = const []}) =>
      _run('create', () => item, (data, id, sharedWith));

  @override
  Future<JsItem?> get(JsItemAddress address) => _run('get',
      () => missing ? null : item, (address.id, address.owner.toString()));

  @override
  Future<JsListing> list() => _run('list', () => listing);

  @override
  Future<JsListing> query(List<JsWhereClause> clauses) => _run('query',
      () => listing, [for (final c in clauses) (c.path, c.op, c.value)]);

  @override
  Future<JsItem> update(JsItemAddress address, Map<String, dynamic> data) =>
      _run('update', () => item, (address.id, address.owner.toString(), data));

  @override
  Future<JsItem> share(JsItemAddress address, List<String> atSigns) => _run(
      'share', () => item, (address.id, address.owner.toString(), atSigns));

  @override
  Future<void> remove(JsItemAddress address, {bool cascade = false}) =>
      _run('remove', () {}, (address.id, address.owner.toString(), cascade));

  @override
  Future<void> Function() watch(void Function(JsEvent event) onEvent,
      {required void Function(CollectionException error) onError}) {
    if (failure case final error?) throw error;
    this.onEvent = onEvent;
    this.onError = onError;
    return () async => cancelled++;
  }
}

/// A [JsSession] that records each call.
class _FakeSession implements JsSession {
  final calls = <String>[];
  final keysSeen = <JsKey>[];
  final values = <Object>[];
  final listeners = <void Function(JsNotification)>[];
  var closed = false;
  var unsubscribed = 0;
  var delivered = true;
  Object? failure;
  String? subscribedRegex;
  void Function(Object)? errorSink;
  String passcode = 'Z9Y8X7';
  List<JsEnrollment> pending = [];
  final decided = <String>[];
  final adapter = _FakeAdapter();
  final collectionArgs = <Object?>[];
  var statusNow = 'connecting';
  final statusListeners = <void Function(String)>[];

  @override
  String get atSign => '@alice';

  @override
  bool get isClosed => closed;

  void _call(String name, [JsKey? key]) {
    if (closed) throw SessionClosedException();
    calls.add(name);
    if (key != null) keysSeen.add(key);
    if (failure case final error?) throw error;
  }

  @override
  Future<bool> notify(JsKey key, String value) async {
    _call('notify', key);
    values.add(value);
    return delivered;
  }

  @override
  void Function() subscribe(String regex, void Function(JsNotification) onEvent,
      {required void Function(Object error) onError}) {
    _call('subscribe');
    subscribedRegex = regex;
    errorSink = onError;
    listeners.add(onEvent);
    return () {
      unsubscribed++;
      listeners.remove(onEvent);
    };
  }

  @override
  String get status => statusNow;

  @override
  void Function() onStatus(void Function(String) onChange) {
    _call('onStatus');
    statusListeners.add(onChange);
    return () => statusListeners.remove(onChange);
  }

  @override
  Future<JsCollection> collection(String name,
      {required String type, String? eventSource, int? expirationMs}) async {
    _call('collection');
    collectionArgs.add((name, type, eventSource, expirationMs));
    return adapter;
  }

  @override
  Future<String> otp() async {
    _call('otp');
    return passcode;
  }

  @override
  Future<List<JsEnrollment>> pendingEnrollments() async {
    _call('pendingEnrollments');
    return pending;
  }

  @override
  Future<void> approve(String id) async {
    _call('approve');
    decided.add('approve $id');
  }

  @override
  Future<void> deny(String id) async {
    _call('deny');
    decided.add('deny $id');
  }

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
  }
}

/// What a promise settled with: a value or a rejection.
sealed class _Settled {}

class _Resolved extends _Settled {
  _Resolved(this.value);
  final JSAny? value;
}

class _Rejected extends _Settled {
  _Rejected(this.reason);
  final JSAny? reason;

  String get code => (reason! as JSObject)['code'].dartify()! as String;
  String get message => (reason! as JSObject)['message'].dartify()! as String;
  Object? field(String name) => (reason! as JSObject)[name].dartify();
}

Future<_Settled> _settle(JSAny? promise) {
  final done = Completer<_Settled>();
  (promise! as JSObject).callMethod(
      'then'.toJS,
      ((JSAny? v) => done.complete(_Resolved(v))).toJS,
      ((JSAny? r) => done.complete(_Rejected(r))).toJS);
  return done.future;
}

Future<JSAny?> _resolved(JSAny? promise) async {
  final settled = await _settle(promise);
  if (settled is _Rejected) {
    fail('rejected with ${settled.code}: ${settled.message}');
  }
  return (settled as _Resolved).value;
}

Future<_Rejected> _rejected(JSAny? promise) async {
  final settled = await _settle(promise);
  if (settled is _Resolved) fail('resolved with ${settled.value}');
  return settled as _Rejected;
}

/// Data with [levels] nested containers, the data object itself being the
/// first. Built in a loop, never by literal nesting.
Map<String, Object?> _nested(int levels) {
  Object? inner = 'leaf';
  for (var i = 0; i < levels; i++) {
    inner = <String, Object?>{'k': inner};
  }
  return inner! as Map<String, Object?>;
}

JSObject _obj(Map<String, Object?> map) => map.jsify()! as JSObject;

JSAny? _call(JSObject target, String name, [List<JSAny?> args = const []]) =>
    args.isEmpty
        ? target.callMethod(name.toJS)
        : target.callMethodVarArgs(name.toJS, args);

/// A JS object built by `JSON.parse`, so it can carry a `__proto__` key.
JSObject _json(String text) =>
    (globalContext['JSON']! as JSObject).callMethod('parse'.toJS, text.toJS)!
        as JSObject;

final JSObject _reflectClass = globalContext['Reflect']! as JSObject;

JSAny _jsConstruct(String ctor, [List<JSAny?> args = const []]) => _reflectClass
    .callMethod('construct'.toJS, globalContext[ctor]!, args.toJS)!;

void main() {
  late _FakeSession session;
  late List<BridgeOptions> opened;
  late bool secure;
  late Object? openFailure;
  late JSObject api;

  setUp(() {
    session = _FakeSession();
    opened = [];
    secure = true;
    openFailure = null;
    api = createJSInteropWrapper(AtClientWebBridge(
        open: (o) async {
          opened.add(o);
          if (openFailure case final error?) throw error;
          return session;
        },
        isSecureContext: () => secure));
  });

  const keysJson = '{"@alice":{"k":"v"}}';
  Map<String, Object?> opts([Map<String, Object?> more = const {}]) => {
        'atSign': '@alice',
        'namespace': 'tally',
        'keys': keysJson,
        ...more,
      };

  Future<JSObject> create([Map<String, Object?>? o]) async =>
      (await _resolved(_call(api, 'create', [_obj(o ?? opts())])))! as JSObject;

  group('the bridge has no passkey entry points', () {
    test('only create is exposed', () {
      for (final name in ['onboard', 'enroll', 'prfSupported']) {
        expect(api.has(name), isFalse, reason: name);
      }
      expect(api.has('create'), isTrue);
    });
  });

  group('create', () {
    test('opens with the options and returns a session', () async {
      final result = await create();

      final o = opened.single;
      expect((o.atSign, o.namespace, o.rootDomain), ('@alice', 'tally', null));
      expect(o.keys, {
        '@alice': {'k': 'v'}
      });
      for (final method in [
        'notify',
        'subscribe',
        'status',
        'onStatus',
        'collection',
        'close'
      ]) {
        expect(result.has(method), isTrue, reason: method);
      }
    });

    test('keys may be an object as well as the document text', () async {
      await create(opts({
        'keys': {
          '@alice': {'k': 'v'}
        }
      }));

      expect(opened.single.keys, {
        '@alice': {'k': 'v'}
      });
    });

    test('rootDomain host:port and host pass through', () async {
      await create(opts({'rootDomain': 'root.example.org:9002'}));
      await create(opts({'rootDomain': 'root.example.org'}));
      await create(opts({'rootDomain': 'proxy:p.example.org:9003'}));

      final roots = [
        for (final o in opened)
          (o.rootDomain!.rootDomain, o.rootDomain!.rootPort)
      ];
      expect(roots, [
        ('root.example.org', 9002),
        ('root.example.org', 64),
        ('proxy:p.example.org', 9003)
      ]);
    });

    test(
        'an unusable rootDomain rejects with invalid_argument naming rootDomain',
        () async {
      for (final bad in [
        '',
        'sentinel.example.org:0',
        'sentinel.example.org:65536',
        'a:b:c:d-sentinel-9',
        'evil.com/path?sentinel=1:443',
        'bad host sentinel',
      ]) {
        final r = await _rejected(_call(api, 'create', [
          _obj(opts({'rootDomain': bad}))
        ]));

        expect(r.code, 'invalid_argument');
        expect(r.message, contains('rootDomain'));
        expect(r.message, isNot(contains('sentinel')));
      }
      expect(opened, isEmpty);
    });

    test('a caller mistake at create opens no connection', () async {
      for (final bad in <Map<String, Object?>>[
        opts({'atSign': 'not an atsign'}),
        opts({'namespace': 5}),
        opts({'rootDomain': 'a:b:c'}),
        opts({'keys': 5}),
      ]) {
        final r = await _rejected(_call(api, 'create', [_obj(bad)]));
        expect(r.code, 'invalid_argument');
      }
      expect(opened, isEmpty);
    });

    test('invalid or empty atSign rejects naming atSign', () async {
      for (final bad in ['', '   ', '@a@b-sentinel', '@alice sentinel']) {
        final r = await _rejected(_call(api, 'create', [
          _obj(opts({'atSign': bad}))
        ]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('atSign'));
        expect(r.message, isNot(contains('sentinel')));
      }
      expect(opened, isEmpty);
    });

    test('invalid or empty namespace rejects naming namespace', () async {
      for (final bad in ['', '   ', 'a.b-sentinel', 'a b sentinel']) {
        final r = await _rejected(_call(api, 'create', [
          _obj(opts({'namespace': bad}))
        ]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('namespace'));
        expect(r.message, isNot(contains('sentinel')));
      }
      expect(opened, isEmpty);
    });

    test('credential-less keys reject with bad_key', () async {
      openFailure = AtNoCredentialException('@alice');

      final r = await _rejected(_call(api, 'create', [_obj(opts())]));

      expect(r.code, 'bad_key');
    });

    test('keys that are not JSON reject with bad_key', () async {
      final r = await _rejected(_call(api, 'create', [
        _obj(opts({'keys': 'not json sentinel-9'}))
      ]));

      expect(r.code, 'bad_key');
      expect(r.message, isNot(contains('sentinel')));
    });

    test(
        'create with missing or mistyped options rejects with invalid_argument naming the option',
        () async {
      for (final (name, drop) in [
        ('atSign', 'atSign'),
        ('namespace', 'namespace'),
        ('keys', 'keys')
      ]) {
        final o = opts()..remove(drop);
        final r = await _rejected(_call(api, 'create', [_obj(o)]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains(name));
      }
      for (final name in ['atSign', 'namespace', 'rootDomain', 'keys']) {
        for (final bad in <Object?>[5, true, <Object?>[]]) {
          final r = await _rejected(_call(api, 'create', [
            _obj(opts({name: bad}))
          ]));
          expect(r.code, 'invalid_argument', reason: name);
          expect(r.message, contains(name));
        }
      }
      for (final bad in [null, 'x'.toJS, <JSAny?>[].toJS, (() {}).toJS]) {
        final r = await _rejected(_call(api, 'create', [bad]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('opts'));
      }
      expect(opened, isEmpty);
    });

    test('create rejects with unsupported outside a secure context', () async {
      secure = false;

      expect((await _rejected(_call(api, 'create', [_obj(opts())]))).code,
          'unsupported');
      expect(opened, isEmpty);
    });

    test('rejects with the code of a typed exception', () async {
      openFailure = AtEnrollmentException('denied');

      final r = await _rejected(_call(api, 'create', [_obj(opts())]));

      expect(r.code, 'enrollment_denied');
    });

    test('a rejection is a plain object with only code and message', () async {
      openFailure = AtEnrollmentException('denied');

      final r = await _rejected(_call(api, 'create', [_obj(opts())]));

      final reason = r.reason! as JSObject;
      expect(
          (globalContext['Object']! as JSObject)
              .callMethod('keys'.toJS, reason)
              .dartify(),
          unorderedEquals(['code', 'message']));
    });

    test('an unmapped exception rejects internal with a fixed message',
        () async {
      openFailure = StateError('sentinel-secret-5');

      final r = await _rejected(_call(api, 'create', [_obj(opts())]));

      expect(r.code, 'internal');
      expect(r.message, 'internal error');
      expect(r.message, isNot(contains('sentinel')));
    });

    test(
        'external ArgumentError, AtOpenRefusedException, and PortalSessionOfflineException do not leak internal details',
        () async {
      openFailure =
          ArgumentError.value('sentinel-secret-arg', 'root', 'bad root');
      var r = await _rejected(_call(api, 'create', [_obj(opts())]));
      expect(r.code, 'internal');
      expect(r.message, 'internal error');
      expect(r.message, isNot(contains('sentinel')));

      openFailure = AtOpenRefusedException(
          '@alice',
          AtConnectionState.refused(AtConnectionCause.revoked,
              error: StateError('sentinel-server-detail')));
      r = await _rejected(_call(api, 'create', [_obj(opts())]));
      expect(r.code, 'pkam_refused');
      expect(r.message, isNot(contains('sentinel')));

      openFailure = PortalSessionOfflineException(
          '@alice',
          AtConnectionState.offline(AtConnectionCause.unreachable,
              error: StateError('sentinel-socket-detail')));
      r = await _rejected(_call(api, 'create', [_obj(opts())]));
      expect(r.code, 'offline');
      expect(r.message, isNot(contains('sentinel')));
    });
  });

  group('argument errors', () {
    const sentinel = 'sentinel-value-7f3a';
    JSObject wrapped() => _obj({
          'inner': sentinel,
          'list': [sentinel]
        })
          ..['toString'] = (() => sentinel.toJS).toJS;

    Future<void> expectNamed(JSAny? promise, String parameter,
        {String code = 'invalid_argument'}) async {
      final r = await _rejected(promise);
      expect(r.code, code);
      expect(r.message, contains(parameter));
      expect(r.message, isNot(contains(sentinel)));
    }

    test('options name the parameter without its value', () async {
      await expectNamed(_call(api, 'create', [wrapped()]), 'atSign');
      await expectNamed(_call(api, 'create', [sentinel.toJS]), 'opts');
      await expectNamed(
          _call(api, 'create', [
            _obj(opts({'atSign': wrapped()}))
          ]),
          'atSign');
      await expectNamed(
          _call(api, 'create', [
            _obj(opts({'keys': 5}))
          ]),
          'keys');
    });

    test('session calls name the parameter without its value', () async {
      final s = await create();
      await expectNamed(
          _call(s, 'notify', [
            _obj({'key': wrapped()}),
            'v'.toJS
          ]),
          'key',
          code: 'bad_key');
      await expectNamed(_call(s, 'notify', [sentinel.toJS, 'v'.toJS]), 'key',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'notify', [
            _obj({'key': 'k', 'namespace': wrapped()}),
            'v'.toJS
          ]),
          'namespace',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'notify', [
            _obj({'key': 'k', 'public': sentinel}),
            'v'.toJS
          ]),
          'public',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'notify', [
            _obj({'key': 'k'}),
            wrapped()
          ]),
          'value');
      await expectNamed(_call(s, 'approve', [wrapped()]), 'id');
      await expectNamed(_call(s, 'collection', ['c'.toJS, wrapped()]), 'type');
      await expectNamed(
          _call(s, 'collection', [
            'c'.toJS,
            _obj({'type': 't', 'expiration': sentinel})
          ]),
          'expiration');
    });
  });

  group('session', () {
    late JSObject s;

    setUp(() async => s = await create());

    test('notify maps the key fields', () async {
      final key = _obj({
        'key': 'note',
        'namespace': 'other',
        'sharedWith': '@bob',
        'sharedBy': '@carol'
      });

      await _resolved(_call(s, 'notify', [key, 'hello'.toJS]));
      await _resolved(_call(s, 'notify', [
        _obj({'key': 'plain'}),
        'v'.toJS
      ]));

      expect(session.values, ['hello', 'v']);
      final first = session.keysSeen.first;
      expect((first.key, first.namespace, first.sharedWith, first.sharedBy),
          ('note', 'other', '@bob', '@carol'));
      final second = session.keysSeen.last;
      expect((second.namespace, second.sharedWith, second.sharedBy),
          (null, null, null));
    });

    test('notify maps the public, cached and noNamespace flags', () async {
      await _resolved(_call(s, 'notify', [
        _obj({'key': 'k', 'public': true, 'cached': true, 'noNamespace': true}),
        'v'.toJS
      ]));
      await _resolved(_call(s, 'notify', [
        _obj({'key': 'k', 'public': false}),
        'v'.toJS
      ]));

      final flagged = session.keysSeen.first;
      expect((flagged.isPublic, flagged.isCached, flagged.noNamespace),
          (true, true, true));
      final plain = session.keysSeen.last;
      expect((plain.isPublic, plain.isCached, plain.noNamespace),
          (false, false, false));
    });

    test('notify rejects a value that is not a string', () async {
      final r = await _rejected(_call(s, 'notify', [
        _obj({'key': 'k'}),
        5.toJS
      ]));

      expect(r.code, 'invalid_argument');
      expect(session.calls, isNot(contains('notify')));
    });

    test('notify resolves true when delivered and false when not', () async {
      final key = _obj({'key': 'rpc', 'sharedWith': '@alice'});

      expect(
          (await _resolved(_call(s, 'notify', [key, 'ping'.toJS]))).dartify(),
          isTrue);
      session.delivered = false;
      expect(
          (await _resolved(_call(s, 'notify', [key, 'ping'.toJS]))).dartify(),
          isFalse);
      expect(session.values, ['ping', 'ping']);
    });

    test('a failing call rejects with the code of its exception', () async {
      session.failure = BadKeyException('notify needs sharedWith');

      final r = await _rejected(_call(s, 'notify', [
        _obj({'key': 'rpc'}),
        'x'.toJS
      ]));

      expect(r.code, 'bad_key');
    });

    test('a mapped exception keeps its message', () async {
      session.failure = BadKeyException('notify needs sharedWith');

      final r = await _rejected(_call(s, 'notify', [
        _obj({'key': 'rpc'}),
        'x'.toJS
      ]));

      expect(r.code, 'bad_key');
      expect(r.message, contains('notify needs sharedWith'));
    });

    test('subscribe delivers events and returns an unsubscribe function',
        () async {
      final seen = <Object?>[];
      final unsubscribe = _call(s, 'subscribe', [
        r'rpc\.req'.toJS,
        ((JSAny? event) => seen.add(event.dartify())).toJS
      ])! as JSFunction;

      expect(session.subscribedRegex, r'rpc\.req');
      session.listeners.single((
        id: 'n1',
        from: '@alice',
        key: 'rpc.req.1.tally',
        value: 'ping',
        epochMillis: 42,
        operation: 'delete'
      ));
      expect(seen, [
        {
          'id': 'n1',
          'from': '@alice',
          'key': 'rpc.req.1.tally',
          'value': 'ping',
          'epochMillis': 42,
          'operation': 'delete'
        }
      ]);

      unsubscribe.callAsFunction();

      expect(session.unsubscribed, 1);
      expect(session.listeners, isEmpty);
    });

    test(
        'bridge subscribe drops notifications and errors after session is closed',
        () async {
      final seen = <Object?>[];
      final errors = <Object?>[];
      _call(s, 'subscribe', [
        '.*'.toJS,
        ((JSAny? event) => seen.add(event.dartify())).toJS,
        ((JSAny? err) => errors.add(err.dartify())).toJS,
      ]);

      await _resolved(_call(s, 'close'));
      session.listeners.single((
        id: 'n2',
        from: '@bob',
        key: 'k.tally@bob',
        value: 'late',
        epochMillis: 99,
        operation: 'update',
      ));
      session.errorSink!(StateError('late'));

      expect(seen, isEmpty);
      expect(errors, isEmpty);
    });

    group('subscribe failures', () {
      // The `{code, message}` a failed subscribe answers with, in place of
      // the unsubscribe function.
      JSObject failed(JSAny? regex) {
        final result = _call(s, 'subscribe', [regex, (() {}).toJS]);
        expect(result.isA<JSFunction>(), isFalse);
        return result! as JSObject;
      }

      test('after close it answers {code: closed, message}', () async {
        await _resolved(_call(s, 'close'));

        final e = failed('x'.toJS);

        expect(e['code'].dartify(), 'closed');
        expect(e['message'].dartify(), isA<String>());
      });

      test('a bad argument answers {code: invalid_argument, message} naming it',
          () {
        final e = failed(5.toJS);

        expect(e['code'].dartify(), 'invalid_argument');
        expect(e['message'].dartify() as String, contains('regex'));
      });

      test('subscribe with invalid regex rejects naming regex', () {
        final e = failed('['.toJS);

        expect(e['code'].dartify(), 'invalid_argument');
        expect(e['message'].dartify() as String, contains('regex'));
      });

      test(
          'subscribe with non-function callback returns {code: invalid_argument} without throwing',
          () {
        for (final bad in [null, 5.toJS, _obj({})]) {
          final r = _call(s, 'subscribe', ['x'.toJS, bad])! as JSObject;
          expect(r['code'].dartify(), 'invalid_argument');
          expect(r['message'].dartify() as String, contains('callback'));
        }
      });
    });

    test('close stops the session and later calls reject with closed',
        () async {
      await _resolved(_call(s, 'close'));

      expect(session.closed, isTrue);
      final r = await _rejected(_call(s, 'notify', [
        _obj({'key': 'k'}),
        'v'.toJS
      ]));
      expect(r.code, 'closed');
      for (final (method, args) in [
        (
          'notify',
          <JSAny?>[
            _obj({'key': 'k'}),
            'v'.toJS
          ]
        ),
        (
          'collection',
          <JSAny?>[
            'c'.toJS,
            _obj({'type': 't'})
          ]
        ),
        ('otp', <JSAny?>[]),
        ('pendingEnrollments', <JSAny?>[]),
        ('approve', <JSAny?>['e1'.toJS]),
        ('deny', <JSAny?>['e1'.toJS]),
      ]) {
        expect((await _rejected(_call(s, method, args))).code, 'closed',
            reason: method);
      }
    });

    group('subscribe errors', () {
      test('subscribe errors go to onError as {code, message}', () async {
        final seen = <Object?>[];
        _call(s, 'subscribe', [
          'x'.toJS,
          (() {}).toJS,
          ((JSAny? e) => seen.add(e.dartify())).toJS
        ]);

        session.errorSink!(StateError('sentinel-secret-5'));

        expect(seen, [
          {'code': 'internal', 'message': 'internal error'}
        ]);
      });

      test('subscribe with no onError does not throw', () {
        _call(s, 'subscribe', ['x'.toJS, (() {}).toJS]);

        expect(() => session.errorSink!(StateError('x')), returnsNormally);
      });

      test('a non-function onError answers a rejection object', () {
        final r = _call(s, 'subscribe', ['x'.toJS, (() {}).toJS, 5.toJS])!
            as JSObject;

        expect(r['message'].dartify() as String, contains('onError'));
      });
    });

    group('status', () {
      test('status() reads the latest value', () {
        expect(_call(s, 'status').dartify(), 'connecting');
        session.statusNow = 'waiting:network';
        expect(_call(s, 'status').dartify(), 'waiting:network');
      });

      test('onStatus delivers changes and returns an off function', () {
        final seen = <Object?>[];
        final off =
            _call(s, 'onStatus', [((JSAny? v) => seen.add(v.dartify())).toJS])!
                as JSFunction;

        session.statusListeners.single('connected');
        session.statusListeners.single('waiting:auth');
        off.callAsFunction();

        expect(seen, ['connected', 'waiting:auth']);
        expect(session.statusListeners, isEmpty);
      });

      test('onStatus after close answers {code: closed}', () async {
        await _resolved(_call(s, 'close'));

        final r = _call(s, 'onStatus', [(() {}).toJS])! as JSObject;

        expect(r['code'].dartify(), 'closed');
      });

      test(
          'onStatus with non-function callback returns {code: invalid_argument} without throwing',
          () {
        for (final bad in [null, 5.toJS, _obj({})]) {
          final r = _call(s, 'onStatus', [bad])! as JSObject;
          expect(r['code'].dartify(), 'invalid_argument');
          expect(r['message'].dartify() as String, contains('callback'));
        }
      });
    });

    group('collection', () {
      late JSObject c;
      late _FakeAdapter adapter;

      setUp(() async {
        adapter = session.adapter;
        c = (await _resolved(_call(s, 'collection', [
          'tasks'.toJS,
          _obj({'type': 'task', 'eventSource': 'both', 'expiration': 5000})
        ])))! as JSObject;
      });

      test('collection passes name, type, eventSource and expiration', () {
        expect(session.collectionArgs.single, ('tasks', 'task', 'both', 5000));
        for (final op in [
          'create',
          'get',
          'list',
          'query',
          'update',
          'share',
          'remove',
          'watch'
        ]) {
          expect(c.has(op), isTrue, reason: op);
        }
      });

      test('collection eventSource and expiration are optional', () async {
        await _resolved(_call(s, 'collection', [
          'c'.toJS,
          _obj({'type': 't'})
        ]));

        expect(session.collectionArgs.last, ('c', 't', null, null));
      });

      test('collection create maps data, id and sharedWith', () async {
        final item = (await _resolved(_call(c, 'create', [
          _obj({
            'title': 'a',
            'n': 2,
            'tags': ['x']
          }),
          _obj({
            'id': 'i9',
            'sharedWith': ['@bob']
          })
        ])))! as JSObject;

        final (data, id, shared) =
            adapter.last! as (Map<String, dynamic>, String?, List<String>);
        expect(data, {
          'title': 'a',
          'n': 2,
          'tags': ['x']
        });
        expect(id, 'i9');
        expect(shared, ['@bob']);
        expect(item['id'].dartify(), 'i1');
        expect(item['availableAt'].dartify(), isNull);
        expect((item['data']! as JSObject)['n'].dartify(), 1);
      });

      test('collection item data is a null-prototype object (T6.3)', () async {
        adapter.item = {
          ...adapter.item,
          'data': <String, Object?>{
            '__proto__': 'p',
            'toString': 'ts',
            'inner': {'__proto__': 1},
            'list': [
              {'__proto__': 1}
            ]
          }
        };

        final item = (await _resolved(_call(c, 'get', [
          _obj({'id': 'i1'})
        ])))! as JSObject;

        final data = item['data']! as JSObject;
        final object = globalContext['Object']! as JSObject;
        expect(object.callMethod('getPrototypeOf'.toJS, data), isNull);
        expect(object.callMethod('keys'.toJS, data).dartify(),
            unorderedEquals(['__proto__', 'toString', 'inner', 'list']));
        expect(
            object.callMethod(
                'getPrototypeOf'.toJS, data['inner']! as JSObject),
            isNull);
        final element = (data['list']! as JSArray).toDart.single! as JSObject;
        expect(object.callMethod('getPrototypeOf'.toJS, element), isNull);
        expect(object.callMethod('getPrototypeOf'.toJS, item), isNotNull);
      });

      test('a data key named __proto__ arrives as data, not a prototype',
          () async {
        await _resolved(_call(
            c, 'create', [_json('{"__proto__": {"polluted": true}, "a": 1}')]));

        final (data, _, _) =
            adapter.last! as (Map<String, dynamic>, Object?, Object?);
        expect(data.keys, containsAll(['__proto__', 'a']));
      });

      test('collection get defaults the owner to the session and resolves null',
          () async {
        await _resolved(_call(c, 'get', [
          _obj({'id': 'i1'})
        ]));
        expect(adapter.last, ('i1', '@alice'));
        await _resolved(_call(c, 'get', [
          _obj({'id': 'i1', 'owner': 'bob'})
        ]));
        expect(adapter.last, ('i1', '@bob'));
        adapter.missing = true;
        expect(
            await _resolved(_call(c, 'get', [
              _obj({'id': 'gone'})
            ])),
            isNull);
      });

      test('collection list and query return {items, unreadable}', () async {
        adapter.listing = (
          items: [adapter.item],
          unreadable: [
            (
              id: 'u1',
              owner: Atsign('@bob'),
              kind: CollectionFailure.unreadable
            )
          ]
        );

        final listed = (await _resolved(_call(c, 'list')))! as JSObject;
        final queried = (await _resolved(_call(c, 'query', [
          [
            {'path': 'a.b', 'op': '>=', 'value': 3},
            {'path': 'c', 'op': 'isNull'}
          ].jsify()
        ])))! as JSObject;

        expect((listed['items']! as JSArray).length, 1);
        expect((listed['unreadable'].dartify() as List).single, {
          'id': 'u1',
          'owner': '@bob',
          'code': collectionErrorCode(CollectionFailure.unreadable)
        });
        expect((queried['items']! as JSArray).length, 1);
        expect((queried['unreadable'].dartify() as List).single,
            containsPair('id', 'u1'));
        expect(adapter.last, [('a.b', '>=', 3), ('c', 'isNull', null)]);
      });

      test(
          'collection item data nested deeper than 64 levels rejects with COLLECTION_ITEM_TOO_DEEP',
          () async {
        adapter.item = {...adapter.item, 'data': _nested(65)};

        final r = await _rejected(_call(c, 'get', [
          _obj({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
        expect(r.message, isNot(contains('internal')));
      });

      test('tooDeep from collection item preserves id and owner', () async {
        adapter.item = {...adapter.item, 'data': _nested(65)};

        final r = await _rejected(_call(c, 'get', [
          _obj({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
        expect(r.field('id'), 'i1');
        expect(r.field('owner'), '@alice');
      });

      test('collection item data nested exactly 64 levels deep resolves',
          () async {
        adapter.item = {...adapter.item, 'data': _nested(64)};
        adapter.listing = (items: [adapter.item], unreadable: const []);

        final got = (await _resolved(_call(c, 'get', [
          _obj({'id': 'i1'})
        ])))! as JSObject;
        final listed = (await _resolved(_call(c, 'list')))! as JSObject;

        var levels = 0;
        JSAny? at = got['data'];
        while (at.isA<JSObject>()) {
          levels++;
          at = (at! as JSObject)['k'];
        }
        expect(levels, 64);
        expect((listed['items']! as JSArray).length, 1);
      });

      test(
          'collection item data nested 100000 levels deep rejects without overflowing the stack',
          () async {
        adapter.item = {...adapter.item, 'data': _nested(100000)};

        final r = await _rejected(_call(c, 'get', [
          _obj({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
      });

      test('collection update, share and remove map their arguments', () async {
        await _resolved(_call(c, 'update', [
          _obj({'id': 'i1'}),
          _obj({'a': 1})
        ]));
        final (id, owner, data) =
            adapter.last! as (String, String, Map<String, dynamic>);
        expect((id, owner), ('i1', '@alice'));
        expect(data, {'a': 1});
        await _resolved(_call(c, 'share', [
          _obj({'id': 'i1', 'owner': '@alice'}),
          ['@bob', '@carol'].jsify()
        ]));
        expect(adapter.last.toString(), '(i1, @alice, [@bob, @carol])');
        final removed = await _resolved(_call(c, 'remove', [
          _obj({'id': 'i1'}),
          _obj({'cascade': true})
        ]));
        expect(adapter.last, ('i1', '@alice', true));
        expect(removed, isNull);
        await _resolved(_call(c, 'remove', [
          _obj({'id': 'i1'})
        ]));
        expect(adapter.last, ('i1', '@alice', false));
      });

      test('a collection failure rejects with its code and fields (T6.4)',
          () async {
        adapter.failure = CollectionException(
            CollectionFailure.partialFailure, 'some writes failed',
            id: 'i1',
            owner: '@alice',
            causeType: 'AtKeyException',
            failures: [
              {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
            ]);

        final r = await _rejected(_call(c, 'share', [
          _obj({'id': 'i1'}),
          ['@bob'].jsify()
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.partialFailure));
        expect(r.message, 'some writes failed');
        expect((r.field('id'), r.field('owner'), r.field('kind')),
            ('i1', '@alice', 'AtKeyException'));
        expect(r.field('failures'), [
          {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
        ]);
      });

      test(
          'a collection rejection keeps code, message, id, owner, kind and failures',
          () async {
        final cases = <(CollectionException, String, String, Object?)>[
          (
            CollectionException(CollectionFailure.notFound, 'item not found',
                id: 'i1', owner: '@alice', causeType: 'StateError'),
            'item not found',
            'StateError',
            null
          ),
          (
            CollectionException(
                CollectionFailure.notOwner, 'i1 belongs to @bob, not @alice',
                id: 'i1', owner: '@bob'),
            'i1 belongs to @bob, not @alice',
            '',
            null
          ),
          (
            CollectionException(CollectionFailure.failed, 'operation failed',
                id: 'i1', owner: '@alice', causeType: 'StateError'),
            'operation failed',
            'StateError',
            null
          ),
          (
            CollectionException(
                CollectionFailure.partialFailure, 'some writes failed',
                id: 'i1',
                owner: '@alice',
                causeType: 'CollectionOpException',
                failures: [
                  {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
                ]),
            'some writes failed',
            'CollectionOpException',
            [
              {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
            ]
          ),
        ];
        for (final (failure, message, kind, failures) in cases) {
          adapter.failure = failure;
          final r = await _rejected(_call(c, 'list'));
          expect(r.code, collectionErrorCode(failure.kind));
          expect(r.message, message);
          expect(r.field('id'), failure.id);
          expect(r.field('owner'), failure.owner);
          expect(r.field('kind'), kind.isEmpty ? isNull : kind);
          expect(r.field('failures'), failures);
        }
      });

      test(
          'list and query report each unreadable record with the same code as before',
          () async {
        adapter.listing = (
          items: const [],
          unreadable: [
            (
              id: 'u1',
              owner: Atsign('@bob'),
              kind: CollectionFailure.unreadable
            ),
            (id: 'u2', owner: Atsign('@bob'), kind: CollectionFailure.tooDeep),
          ]
        );
        for (final result in [
          await _resolved(_call(c, 'list')),
          await _resolved(_call(c, 'query', [
            [
              {'path': 'a', 'op': 'isNull'}
            ].jsify()
          ])),
        ]) {
          expect(((result! as JSObject)['unreadable'].dartify() as List), [
            {
              'id': 'u1',
              'owner': '@bob',
              'code': collectionErrorCode(CollectionFailure.unreadable)
            },
            {
              'id': 'u2',
              'owner': '@bob',
              'code': collectionErrorCode(CollectionFailure.tooDeep)
            },
          ]);
        }
      });

      test('every collection code reaches JS unchanged', () async {
        for (final kind in [
          CollectionFailure.notFound,
          CollectionFailure.alreadyExists,
          CollectionFailure.wrongType,
          CollectionFailure.hasSubItems,
          CollectionFailure.invalidArgument,
          CollectionFailure.failed,
          CollectionFailure.tooDeep,
        ]) {
          adapter.failure = CollectionException(kind, 'm');
          expect((await _rejected(_call(c, 'list'))).code,
              collectionErrorCode(kind));
        }
      });

      test('collection bad arguments reject naming the parameter', () async {
        for (final (promise, name) in [
          (_call(c, 'get', ['i1'.toJS]), 'address'),
          (_call(c, 'create', [5.toJS]), 'data'),
          (_call(c, 'query', [5.toJS]), 'where'),
          (
            _call(c, 'share', [
              _obj({'id': 'i'}),
              'x'.toJS
            ]),
            'atSigns'
          ),
        ]) {
          final r = await _rejected(promise);
          expect(r.code, 'invalid_argument');
          expect(r.message, contains(name));
        }
      });

      test('collection data that is an array or too deep rejects naming data',
          () async {
        JSObject nested(int levels) {
          var o = _obj({});
          for (var i = 0; i < levels; i++) {
            o = _obj({'n': o});
          }
          return o;
        }

        final cyclic = _obj({});
        cyclic['self'] = cyclic;
        for (final (promise, message) in [
          (
            _call(c, 'create', [
              <JSAny?>[1.toJS].toJS
            ]),
            'an object'
          ),
          (
            _call(c, 'update', [
              _obj({'id': 'i1'}),
              <JSAny?>[1.toJS].toJS
            ]),
            'an object'
          ),
          (_call(c, 'create', [nested(100)]), 'levels deep'),
          (_call(c, 'create', [cyclic]), 'levels deep'),
        ]) {
          final r = await _rejected(promise);
          expect(r.code, 'invalid_argument');
          expect(r.message, contains('data'));
          expect(r.message, contains(message));
        }
      });

      test(
          'collection watch delivers events, including unknown, and unsubscribes (T6.5, T6.8)',
          () async {
        final events = <Object?>[];
        final errors = <Object?>[];
        final off = _call(c, 'watch', [
          ((JSAny? e) => events.add(e.dartify())).toJS,
          ((JSAny? e) => errors.add(e.dartify())).toJS
        ])! as JSFunction;

        adapter.onEvent!({'type': 'updated', 'id': 'i1', 'owner': '@alice'});
        adapter.onEvent!({'type': 'unknown', 'id': 'i2', 'owner': '@bob'});
        adapter.onError!(CollectionException(CollectionFailure.failed, 'boom'));
        off.callAsFunction();

        expect(events, [
          {'type': 'updated', 'id': 'i1', 'owner': '@alice'},
          {'type': 'unknown', 'id': 'i2', 'owner': '@bob'}
        ]);
        expect(errors, [
          {
            'code': collectionErrorCode(CollectionFailure.failed),
            'message': 'boom'
          }
        ]);
        expect(adapter.cancelled, 1);
      });

      test('collection watch needs a function and never throws', () {
        final r = _call(c, 'watch', [5.toJS])! as JSObject;

        expect(r['code'].dartify(), 'invalid_argument');
        expect(r['message'].dartify() as String, contains('onEvent'));
      });

      test(
          'collection operations and watch reject with closed after session close',
          () async {
        await _resolved(_call(s, 'close'));

        for (final (method, args) in [
          (
            'create',
            <JSAny?>[
              _obj({'a': 1})
            ]
          ),
          (
            'get',
            <JSAny?>[
              _obj({'id': 'i1'})
            ]
          ),
          ('list', <JSAny?>[]),
          ('query', <JSAny?>[<JSAny?>[].toJS]),
          (
            'update',
            <JSAny?>[
              _obj({'id': 'i1'}),
              _obj({'a': 2})
            ]
          ),
          (
            'share',
            <JSAny?>[
              _obj({'id': 'i1'}),
              ['bob'].jsify()
            ]
          ),
          (
            'remove',
            <JSAny?>[
              _obj({'id': 'i1'})
            ]
          ),
        ]) {
          expect((await _rejected(_call(c, method, args))).code, 'closed',
              reason: method);
        }

        final watchRes = _call(c, 'watch', [((JSAny? _) {}).toJS])! as JSObject;
        expect(watchRes['code'].dartify(), 'closed');
      });

      test('invalid address owner rejects with invalid_argument naming owner',
          () async {
        for (final (method, args) in [
          (
            'get',
            <JSAny?>[
              _obj({'id': 'i1', 'owner': '@a@b-sentinel'})
            ]
          ),
          (
            'update',
            <JSAny?>[
              _obj({'id': 'i1', 'owner': '@a@b-sentinel'}),
              _obj({'a': 1})
            ]
          ),
          (
            'share',
            <JSAny?>[
              _obj({'id': 'i1', 'owner': '@a@b-sentinel'}),
              ['@bob'].jsify()
            ]
          ),
          (
            'remove',
            <JSAny?>[
              _obj({'id': 'i1', 'owner': '@a@b-sentinel'})
            ]
          ),
        ]) {
          final r = await _rejected(_call(c, method, args));
          expect(r.code, 'invalid_argument', reason: method);
          expect(r.message, contains('owner'));
          expect(r.message, isNot(contains('sentinel')));
          expect(r.field('id'), 'i1');
        }
      });

      test(
          'non-plain JS objects in collection arguments reject naming the parameter',
          () async {
        final nonPlain = <JSAny>[
          _jsConstruct('Date'),
          _jsConstruct('Uint8Array', [
            [1, 2].jsify()
          ]),
          _jsConstruct('Map'),
          _jsConstruct('Set'),
          _jsConstruct('RegExp', ['a'.toJS]),
          _jsConstruct('ArrayBuffer', [4.toJS]),
        ];
        for (final bad in nonPlain) {
          final optRes = await _rejected(_call(c, 'create', [
            _obj({'a': 1}),
            bad
          ]));
          expect(optRes.code, 'invalid_argument');
          expect(optRes.message, contains('opts'));

          final dataRes = await _rejected(_call(c, 'create', [
            _obj({'nested': bad})
          ]));
          expect(dataRes.code, 'invalid_argument');
          expect(dataRes.message, contains('data'));
        }
        final arrOpts = await _rejected(_call(c, 'create', [
          _obj({'a': 1}),
          <JSAny?>[].toJS
        ]));
        expect(arrOpts.code, 'invalid_argument');
        expect(arrOpts.message, contains('opts'));
      });

      test(
          'prototype-polluted Object.prototype fields are ignored across bridge calls',
          () async {
        final proto =
            (globalContext['Object']! as JSObject)['prototype']! as JSObject;
        final polluted = <String, JSAny?>{
          'rootDomain': 'evil.example:443'.toJS,
          'sharedWith': ['eve'].jsify(),
          'sharedBy': '@eve'.toJS,
          'public': true.toJS,
          'cached': true.toJS,
          'noNamespace': true.toJS,
          'owner': '@eve'.toJS,
          'cascade': true.toJS,
          'eventSource': 'data'.toJS,
          'expiration': 999.toJS,
          'id': 'polluted-id'.toJS,
        };
        for (final entry in polluted.entries) {
          proto[entry.key] = entry.value;
        }
        try {
          await create();
          expect(opened.last.rootDomain, isNull);

          await _resolved(_call(s, 'notify', [
            _obj({'key': 'k'}),
            'v'.toJS
          ]));
          final sentKey = session.keysSeen.last;
          expect((
            sentKey.sharedWith,
            sentKey.sharedBy,
            sentKey.isPublic,
            sentKey.isCached,
            sentKey.noNamespace
          ), (
            null,
            null,
            false,
            false,
            false
          ));

          await _resolved(_call(s, 'collection', [
            'clean'.toJS,
            _obj({'type': 't'})
          ]));
          expect(session.collectionArgs.last, ('clean', 't', null, null));

          await _resolved(_call(c, 'create', [
            _obj({'a': 1}),
            _obj({})
          ]));
          final (_, createdId, createdShared) =
              adapter.last! as (Map<String, dynamic>, String?, List<String>);
          expect(createdId, isNull);
          expect(createdShared, isEmpty);

          await _resolved(_call(c, 'get', [
            _obj({'id': 'i1'})
          ]));
          expect(adapter.last, ('i1', '@alice'));

          await _resolved(_call(c, 'remove', [
            _obj({'id': 'i1'}),
            _obj({})
          ]));
          expect(adapter.last, ('i1', '@alice', false));
        } finally {
          for (final key in polluted.keys) {
            _reflectClass.callMethod('deleteProperty'.toJS, proto, key.toJS);
          }
        }
      });
    });

    group('pairing', () {
      test('otp resolves the passcode', () async {
        expect((await _resolved(_call(s, 'otp'))).dartify(), 'Z9Y8X7');
        expect(session.calls, ['otp']);
      });

      test('pendingEnrollments resolves one plain object per request',
          () async {
        session.pending = [
          (
            id: 'e1',
            appName: 'tally',
            deviceName: 'Phone',
            namespaces: {'tally': 'rw', 'wavi': 'r'}
          )
        ];

        final result = await _resolved(_call(s, 'pendingEnrollments'));

        expect(result.dartify(), [
          {
            'id': 'e1',
            'appName': 'tally',
            'deviceName': 'Phone',
            'namespaces': {'tally': 'rw', 'wavi': 'r'}
          }
        ]);
      });

      test('pendingEnrollments with none pending resolves an empty array',
          () async {
        expect((await _resolved(_call(s, 'pendingEnrollments'))).dartify(),
            isEmpty);
      });

      test('approve and deny pass the id and resolve undefined', () async {
        final approved = await _resolved(_call(s, 'approve', ['e1'.toJS]));
        final denied = await _resolved(_call(s, 'deny', ['e2'.toJS]));

        expect(session.decided, ['approve e1', 'deny e2']);
        expect(approved, isNull);
        expect(denied, isNull);
      });

      test('approve takes the id alone, whatever else is passed', () async {
        await _resolved(_call(s, 'approve', [
          'e1'.toJS,
          _obj({
            'namespaces': {'*': 'rw'}
          })
        ]));

        expect(session.decided, ['approve e1']);
      });

      test('approve and deny reject a non-string id', () async {
        for (final method in ['approve', 'deny']) {
          expect((await _rejected(_call(s, method, [_obj({})]))).code,
              'invalid_argument');
          expect((await _rejected(_call(s, method, [5.toJS]))).code,
              'invalid_argument');
        }
        expect(session.decided, isEmpty);
      });

      test('each call rejects with unsupported without __manage', () async {
        session.failure = ManageAccessException();

        for (final (method, args) in [
          ('otp', <JSAny?>[]),
          ('pendingEnrollments', <JSAny?>[]),
          ('approve', <JSAny?>['e1'.toJS]),
          ('deny', <JSAny?>['e1'.toJS]),
        ]) {
          expect((await _rejected(_call(s, method, args))).code, 'unsupported',
              reason: method);
        }
      });

      test('an unknown id rejects with enrollment_denied', () async {
        session.failure = AtEnrollmentException('no enrollment e9');

        expect((await _rejected(_call(s, 'approve', ['e9'.toJS]))).code,
            'enrollment_denied');
      });
    });
  });
}
