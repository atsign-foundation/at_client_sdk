@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_client/at_client.dart'
    show
        AtClient,
        AtConnection,
        AtConnectionCause,
        AtConnectionState,
        AtEnrollmentException,
        AtNoCredentialException,
        AtOpenRefusedException,
        Atsign;
import 'package:at_client_web/src/collections/js_collections_adapter.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:at_client_web/src/js/bridge.dart';
import 'package:at_client_web/src/keys/indexeddb_store.dart';
import 'package:at_client_web/src/log_text.dart' show singleLine;
import 'package:at_client_web/src/session/at_client_session.dart';
import 'package:at_client_web/src/session/session_options.dart';
import 'package:at_client_web/src/session/web_passkey_entry.dart'
    show openEntryHintStore;
import 'package:at_lookup/at_lookup_web.dart' show HttpsSecondaryAddressFinder;
import 'package:at_utils/at_utils.dart' show AtSignLogger, LoggingHandler;
import 'package:test/fake.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'bridge_test_helpers.dart';

/// A [ItemCollection] that records each call and answers what it is
/// told to.
class _FakeAdapter implements ItemCollection {
  _FakeAdapter(this._isClosed);

  /// Like `SessionBoundCollection`, which owns the closed-state check: every
  /// operation and watch throws once the session is closed. The bridge adds no
  /// check of its own.
  final bool Function() _isClosed;
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
  void Function(JsCollectionsError)? onError;
  Object? last;
  Object? cancelFailure;
  var cancelled = 0;

  Future<T> _run<T>(String call, T Function() result, [Object? args]) async {
    if (_isClosed()) throw SessionClosedException();
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
      {required void Function(JsCollectionsError error) onError}) {
    if (_isClosed()) throw SessionClosedException();
    if (failure case final error?) throw error;
    this.onEvent = onEvent;
    this.onError = onError;
    return () async {
      if (cancelFailure case final error?) throw error;
      cancelled++;
    };
  }
}

/// Collects the lines the bridge's logger writes, as the other tests do. The
/// logger is built once and keeps the handler it was built with, so the list
/// is cleared rather than the handler replaced between tests.
class _Collect implements LoggingHandler {
  final List<String> lines = [];

  @override
  void call(record) =>
      lines.add('${record.level.name}|${record.loggerName}|${record.message}');
}

/// A [Session] that records each call.
class _FakeSession implements Session {
  final calls = <String>[];
  final keysSeen = <String>[];
  final values = <Object>[];
  final listeners = <void Function(ReceivedNotification)>[];
  var closed = false;
  var unsubscribed = 0;
  var delivered = true;
  Object? failure;
  String? subscribedRegex;
  void Function(Object)? errorSink;
  String passcode = 'Z9Y8X7';
  List<JsEnrollment> pending = [];
  final decided = <String>[];
  late final adapter = _FakeAdapter(() => closed);
  final collectionArgs = <Object?>[];
  var statusNow = 'connecting';
  final statusListeners = <void Function(String)>[];

  @override
  String get atSign => '@alice';

  @override
  bool get isClosed => closed;

  void _call(String name, [String? key]) {
    if (closed) throw SessionClosedException();
    calls.add(name);
    if (key != null) keysSeen.add(key);
    if (failure case final error?) throw error;
  }

  @override
  Future<bool> notify(String key, String value) async {
    _call('notify', key);
    values.add(value);
    return delivered;
  }

  @override
  void Function() subscribe(
      String regex, void Function(ReceivedNotification) onEvent,
      {required void Function(Object error) onError}) {
    _call('subscribe');
    subscribedRegex = regex;
    // Like AtClientSession, deliver nothing once the session is closed.
    void deliver(ReceivedNotification n) {
      if (!closed) onEvent(n);
    }

    errorSink = (error) {
      if (!closed) onError(error);
    };
    listeners.add(deliver);
    return () {
      unsubscribed++;
      listeners.remove(deliver);
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
  Future<ItemCollection> collection(String name,
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

/// Data with [levels] nested containers, the data object itself being the
/// first. Built in a loop, never by literal nesting.
Map<String, Object?> _nested(int levels) {
  Object? inner = 'leaf';
  for (var i = 0; i < levels; i++) {
    inner = <String, Object?>{'k': inner};
  }
  return inner! as Map<String, Object?>;
}

/// A JS object built by `JSON.parse`, so it can carry a `__proto__` key.
JSObject _json(String text) =>
    (globalContext['JSON']! as JSObject).callMethod('parse'.toJS, text.toJS)!
        as JSObject;

final JSObject _reflectClass = globalContext['Reflect']! as JSObject;

/// The own property names of [object], as `Object.getOwnPropertyNames` gives
/// them: the exact JS surface a wrapped object exposes.
List<String> _ownNames(JSObject object) {
  final names = (globalContext['Object']! as JSObject)
      .callMethod('getOwnPropertyNames'.toJS, object)! as JSArray<JSString>;
  return [for (final name in names.toDart) name.toDart];
}

JSAny _jsConstruct(String ctor, [List<JSAny?> args = const []]) => _reflectClass
    .callMethod('construct'.toJS, globalContext[ctor]!, args.toJS)!;

/// A client whose session cannot be built: reading its connection throws,
/// as an invalid session namespace does.
class _ThrowingConnectionClient extends Fake implements AtClient {
  _ThrowingConnectionClient(this.failure);

  final Object failure;

  @override
  AtConnection get connection => throw failure;
}

/// A hint store whose first read fails before any passkey ceremony, so the
/// browser's own login runs in a test, and that records its close.
class _RefusingHintStore extends Fake implements IndexedDbHintStore {
  final failure = StateError('the hint store read failed');

  var closes = 0;

  @override
  Future<Uint8List?> credentialId(String atSign) async => throw failure;

  @override
  void close() => closes++;
}

void main() {
  // The bridge's logger is built on first use and keeps the handler it was
  // built with, so the collector is installed before any test touches it.
  final logs = _Collect();
  final previousHandler = AtSignLogger.defaultLoggingHandler;
  AtSignLogger.defaultLoggingHandler = logs;
  tearDownAll(() => AtSignLogger.defaultLoggingHandler = previousHandler);
  setUp(logs.lines.clear);

  late _FakeSession session;
  late List<SessionOptions> opened;
  late bool secure;
  late Object? openFailure;
  late JSObject api;

  setUp(() {
    session = _FakeSession();
    opened = [];
    secure = true;
    openFailure = null;
    api = createJSInteropWrapper(BridgeEntry(
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
      (await resolved(invoke(api, 'create', [jsObject(o ?? opts())])))!
          as JSObject;

  group('the bridge has no passkey entry points', () {
    test('only create is exposed', () {
      expect(_ownNames(api), ['create']);
    });
  });

  group('create', () {
    test('opens with the options and returns a session', () async {
      final result = await create();

      final o = opened.single;
      expect((o.atSign, o.namespace, o.rootDomain), ('@alice', 'tally', null));
      expect((o as KeysSessionOptions).keys.toJson()['@alice'], {'k': 'v'});
      expect(
          _ownNames(result),
          unorderedEquals([
            'notify',
            'subscribe',
            'status',
            'onStatus',
            'collection',
            'otp',
            'pendingEnrollments',
            'approve',
            'deny',
            'close',
          ]));
    });

    test('create resolves only once the session is open', () async {
      final opener = Completer<Session>();
      final bridge = createJSInteropWrapper(
          BridgeEntry(open: (_) => opener.future, isSecureContext: () => true));

      final pending = settle(invoke(bridge, 'create', [jsObject(opts())]));
      var settled = false;
      unawaited(pending.then((_) {
        settled = true;
      }));
      await pumpEventQueue();
      expect(settled, isFalse,
          reason: "create's promise is still pending while the opener runs");

      opener.complete(session);
      final outcome = await pending;
      expect(outcome, isA<Resolved>(),
          reason: 'create resolves with the session');
      expect(
          _ownNames((outcome as Resolved).value! as JSObject),
          unorderedEquals([
            'notify',
            'subscribe',
            'status',
            'onStatus',
            'collection',
            'otp',
            'pendingEnrollments',
            'approve',
            'deny',
            'close',
          ]));
    });

    test('keys may be an object as well as the document text', () async {
      await create(opts({
        'keys': {
          '@alice': {'k': 'v'}
        }
      }));

      expect((opened.single as KeysSessionOptions).keys.toJson()['@alice'],
          {'k': 'v'});
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
        final r = await rejected(invoke(api, 'create', [
          jsObject(opts({'rootDomain': bad}))
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
        final r = await rejected(invoke(api, 'create', [jsObject(bad)]));
        expect(r.code, 'invalid_argument');
      }
      expect(opened, isEmpty);
    });

    test('invalid or empty atSign rejects naming atSign', () async {
      for (final bad in ['', '   ', '@a@b-sentinel', '@alice sentinel']) {
        final r = await rejected(invoke(api, 'create', [
          jsObject(opts({'atSign': bad}))
        ]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('atSign'));
        expect(r.message, isNot(contains('sentinel')));
      }
      expect(opened, isEmpty);
    });

    test('invalid or empty namespace rejects naming namespace', () async {
      for (final bad in ['', '   ', 'a.b-sentinel', 'a b sentinel']) {
        final r = await rejected(invoke(api, 'create', [
          jsObject(opts({'namespace': bad}))
        ]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('namespace'));
        expect(r.message, isNot(contains('sentinel')));
      }
      expect(opened, isEmpty);
    });

    test('credential-less keys reject with bad_key', () async {
      openFailure = AtNoCredentialException('@alice');

      final r = await rejected(invoke(api, 'create', [jsObject(opts())]));

      expect(r.code, 'bad_key');
    });

    test(
        'create with several bad inputs reports the type checks and key decoding before the options',
        () async {
      const notJson = 'not json sentinel-9';
      for (final bad in <Map<String, Object?>>[
        opts({'atSign': 'not an atsign', 'keys': notJson}),
        opts({'rootDomain': 'a:b:c', 'keys': notJson}),
        opts({
          'atSign': 'not an atsign',
          'rootDomain': 'a:b:c',
          'keys': notJson
        }),
      ]) {
        final r = await rejected(invoke(api, 'create', [jsObject(bad)]));
        expect(r.code, 'bad_key', reason: '$bad');
        expect(r.message, isNot(contains('sentinel')));
      }
      final r = await rejected(invoke(api, 'create', [
        jsObject(opts({'namespace': 5, 'keys': notJson}))
      ]));
      expect(r.code, 'invalid_argument');
      expect(r.message, contains('namespace'));
      expect(opened, isEmpty);
    });

    test('keys that are not JSON reject with bad_key', () async {
      final r = await rejected(invoke(api, 'create', [
        jsObject(opts({'keys': 'not json sentinel-9'}))
      ]));

      expect(r.code, 'bad_key');
      expect(r.message, isNot(contains('sentinel')));
    });

    test('an atKeys document the options refuse rejects with bad_key',
        () async {
      final r = await rejected(invoke(api, 'create', [
        jsObject(opts({
          'keys': {'version': 999}
        }))
      ]));

      expect(r.code, 'bad_key');
      expect(r.message, 'keys is not a usable .atKeys document');
      expect(opened, isEmpty);
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
        final r = await rejected(invoke(api, 'create', [jsObject(o)]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains(name));
      }
      for (final name in ['atSign', 'namespace', 'rootDomain', 'keys']) {
        for (final bad in <Object?>[5, true, <Object?>[]]) {
          final r = await rejected(invoke(api, 'create', [
            jsObject(opts({name: bad}))
          ]));
          expect(r.code, 'invalid_argument', reason: name);
          expect(r.message, contains(name));
        }
      }
      for (final bad in [null, 'x'.toJS, <JSAny?>[].toJS, (() {}).toJS]) {
        final r = await rejected(invoke(api, 'create', [bad]));
        expect(r.code, 'invalid_argument');
        expect(r.message, contains('opts'));
      }
      expect(opened, isEmpty);
    });

    test('create rejects with unsupported outside a secure context', () async {
      secure = false;

      final r = await rejected(invoke(api, 'create', [jsObject(opts())]));
      expect(r.code, 'unsupported');
      expect(r.message, 'a secure context (HTTPS) is required');
      expect(opened, isEmpty);
    });

    test('rejects with the code of a typed exception', () async {
      openFailure = AtEnrollmentException('denied');

      final r = await rejected(invoke(api, 'create', [jsObject(opts())]));

      expect(r.code, 'enrollment_denied');
    });

    test('a rejection is a plain object with only code and message', () async {
      openFailure = AtEnrollmentException('denied');

      final r = await rejected(invoke(api, 'create', [jsObject(opts())]));

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

      final r = await rejected(invoke(api, 'create', [jsObject(opts())]));

      expect(r.code, 'internal');
      expect(r.message, 'internal error');
      expect(r.message, isNot(contains('sentinel')));
    });

    test(
        'external ArgumentError, AtOpenRefusedException, and PortalSessionOfflineException do not leak internal details',
        () async {
      openFailure =
          ArgumentError.value('sentinel-secret-arg', 'root', 'bad root');
      var r = await rejected(invoke(api, 'create', [jsObject(opts())]));
      expect(r.code, 'internal');
      expect(r.message, 'internal error');
      expect(r.message, isNot(contains('sentinel')));

      openFailure = AtOpenRefusedException(
          '@alice',
          AtConnectionState.refused(AtConnectionCause.revoked,
              error: StateError('sentinel-server-detail')));
      r = await rejected(invoke(api, 'create', [jsObject(opts())]));
      expect(r.code, 'pkam_refused');
      expect(r.message, isNot(contains('sentinel')));

      openFailure = PortalSessionOfflineException(
          '@alice',
          AtConnectionState.offline(AtConnectionCause.unreachable,
              error: StateError('sentinel-socket-detail')));
      r = await rejected(invoke(api, 'create', [jsObject(opts())]));
      expect(r.code, 'offline');
      expect(r.message, isNot(contains('sentinel')));
    });

    group('passkey sign-in', () {
      Map<String, Object?> passkeyOpts(
              [Map<String, Object?> more = const {}]) =>
          {
            'atSign': '@alice',
            'namespace': 'tally',
            'passkey': true,
            'rpId': 'example.org',
            'rpName': 'Tally',
            ...more,
          };

      test('opens a passkey session from the passkey options', () async {
        await create(passkeyOpts({'rootDomain': 'root.example.org:9002'}));

        final o = opened.single;
        expect(o, isA<PasskeySessionOptions>());
        final passkey = o as PasskeySessionOptions;
        expect(
            (passkey.atSign, passkey.namespace, passkey.rpId, passkey.rpName),
            ('@alice', 'tally', 'example.org', 'Tally'));
        expect((passkey.rootDomain!.rootDomain, passkey.rootDomain!.rootPort),
            ('root.example.org', 9002));
      });

      test('passkey sign-in needs no keys document', () async {
        await create(passkeyOpts());

        expect(opened.single, isA<PasskeySessionOptions>());
      });

      test('create with the passkey options opens a passkey session', () async {
        final passkey = GatedPasskeySession(PasskeyClient())
          ..stopGate = Completer<void>();
        final login = RecordingPasskeyLogin(passkey);
        final bridge = createJSInteropWrapper(BridgeEntry(
            open: (o) => openJsSession(o, passkeyOpen: login.call),
            isSecureContext: () => true));

        final result =
            await resolved(invoke(bridge, 'create', [jsObject(passkeyOpts())]))
                as JSObject;

        final passkeyOptions = login.seen.single;
        expect((
          passkeyOptions.atSign,
          passkeyOptions.namespace,
          passkeyOptions.rpId,
          passkeyOptions.rpName
        ), (
          '@alice',
          'tally',
          'example.org',
          'Tally'
        ), reason: 'create opens through the passkey login');
        expect(login.transports.single.root.rootDomain, 'root.atsign.org');

        var closed = false;
        final closing =
            resolved(invoke(result, 'close')).then((_) => closed = true);
        await pumpEventQueue();
        expect(closed, isFalse,
            reason: "close awaits the passkey session's stop");
        expect(passkey.stops, 1);
        passkey.stopGate!.complete();
        await closing;
        expect(closed, isTrue);
      });

      test(
          "create with the passkey options opens through the browser's passkey login",
          () async {
        final store = _RefusingHintStore();
        var openedStores = 0;
        final defaultOpen = openEntryHintStore;
        openEntryHintStore = () async {
          openedStores++;
          return store;
        };
        addTearDown(() => openEntryHintStore = defaultOpen);

        await expectLater(
            openJsSession(PasskeySessionOptions(
                atSign: 'alice',
                namespace: 'wavi',
                rpId: 'localhost',
                rpName: 'test')),
            throwsA(same(store.failure)));

        expect(openedStores, 1, reason: 'the browser login opened its store');
        expect(store.closes, 1, reason: 'the browser login closed its store');
      });

      test(
          'missing or mistyped passkey fields reject with invalid_argument '
          'naming the option', () async {
        for (final name in ['atSign', 'namespace', 'rpId', 'rpName']) {
          final o = passkeyOpts()..remove(name);
          final r = await rejected(invoke(api, 'create', [jsObject(o)]));
          expect(r.code, 'invalid_argument');
          expect(r.message, contains(name));
        }
        for (final name in ['atSign', 'namespace', 'rpId', 'rpName']) {
          for (final bad in <Object?>[5, true, <Object?>[]]) {
            final r = await rejected(invoke(api, 'create', [
              jsObject(passkeyOpts({name: bad}))
            ]));
            expect(r.code, 'invalid_argument', reason: name);
            expect(r.message, contains(name));
          }
          final empty = await rejected(invoke(api, 'create', [
            jsObject(passkeyOpts({name: '   '}))
          ]));
          expect(empty.code, 'invalid_argument', reason: name);
          expect(empty.message, contains(name));
        }
        for (final bad in <Object?>[5, 'yes', <Object?>[]]) {
          final r = await rejected(invoke(api, 'create', [
            jsObject(passkeyOpts({'passkey': bad}))
          ]));
          expect(r.code, 'invalid_argument');
          expect(r.message, contains('passkey'));
        }
        expect(opened, isEmpty);
      });

      test(
          'create passes appName and appVersion to the keys and passkey '
          'options', () async {
        await create(opts({'appName': 'Tally', 'appVersion': '1.2.3'}));
        final keys = opened.last;
        expect((keys.appName, keys.appVersion), ('Tally', '1.2.3'));

        await create(passkeyOpts({'appName': 'Tally', 'appVersion': '1.2.3'}));
        final passkey = opened.last;
        expect(passkey, isA<PasskeySessionOptions>());
        expect((passkey.appName, passkey.appVersion), ('Tally', '1.2.3'));
      });

      test(
          'a non-string appName or appVersion rejects invalid_argument '
          'naming the option', () async {
        for (final name in ['appName', 'appVersion']) {
          for (final form in [opts, passkeyOpts]) {
            for (final bad in <Object?>[5, true, <Object?>[]]) {
              final r = await rejected(invoke(api, 'create', [
                jsObject(form({name: bad}))
              ]));
              expect(r.code, 'invalid_argument', reason: name);
              expect(r.message, contains(name));
            }
          }
        }
        expect(opened, isEmpty);
      });
    });
  });

  group('argument errors', () {
    const sentinel = 'sentinel-value-7f3a';
    JSObject wrapped() => jsObject({
          'inner': sentinel,
          'list': [sentinel]
        })
          ..['toString'] = (() => sentinel.toJS).toJS;

    Future<void> expectNamed(JSAny? promise, String parameter,
        {String code = 'invalid_argument'}) async {
      final r = await rejected(promise);
      expect(r.code, code);
      expect(r.message, contains(parameter));
      expect(r.message, isNot(contains(sentinel)));
    }

    test('options name the parameter without its value', () async {
      await expectNamed(invoke(api, 'create', [wrapped()]), 'atSign');
      await expectNamed(invoke(api, 'create', [sentinel.toJS]), 'opts');
      await expectNamed(
          invoke(api, 'create', [
            jsObject(opts({'atSign': wrapped()}))
          ]),
          'atSign');
      await expectNamed(
          invoke(api, 'create', [
            jsObject(opts({'keys': 5}))
          ]),
          'keys');
    });

    test('session calls name the parameter without its value', () async {
      final s = await create();
      await expectNamed(invoke(s, 'notify', [wrapped(), 'v'.toJS]), 'key',
          code: 'bad_key');
      await expectNamed(
          invoke(s, 'notify', ['@bob:k.wavi@alice'.toJS, wrapped()]), 'value');
      await expectNamed(invoke(s, 'approve', [wrapped()]), 'id');
      await expectNamed(invoke(s, 'collection', ['c'.toJS, wrapped()]), 'type');
      await expectNamed(
          invoke(s, 'collection', [
            'c'.toJS,
            jsObject({'type': 't', 'expiration': sentinel})
          ]),
          'expiration');
    });
  });

  group('session', () {
    late JSObject s;

    setUp(() async => s = await create());

    test('notify passes the key text whole', () async {
      await resolved(
          invoke(s, 'notify', ['@bob:note.other@carol'.toJS, 'hello'.toJS]));
      await resolved(invoke(s, 'notify', ['@bob:plain@alice'.toJS, 'v'.toJS]));

      expect(session.values, ['hello', 'v']);
      expect(session.keysSeen, ['@bob:note.other@carol', '@bob:plain@alice']);
    });

    test('bridge notify takes key text and refuses a non-string key', () async {
      for (final bad in <JSAny?>[
        jsObject({'key': 'k'}),
        5.toJS,
        <JSAny?>[].toJS,
      ]) {
        final r = await rejected(invoke(s, 'notify', [bad, 'v'.toJS]));
        expect(r.code, 'bad_key');
        expect(r.message, contains('key'));
      }
      expect(session.keysSeen, isEmpty);
    });

    test('notify rejects a value that is not a string', () async {
      final r = await rejected(
          invoke(s, 'notify', ['@bob:k.wavi@alice'.toJS, 5.toJS]));

      expect(r.code, 'invalid_argument');
      expect(session.calls, isNot(contains('notify')));
    });

    test('notify resolves true when delivered and false when not', () async {
      final key = '@alice:k.wavi@alice'.toJS;

      expect(
          (await resolved(invoke(s, 'notify', [key, 'ping'.toJS]))).dartify(),
          isTrue);
      session.delivered = false;
      expect(
          (await resolved(invoke(s, 'notify', [key, 'ping'.toJS]))).dartify(),
          isFalse);
      expect(session.values, ['ping', 'ping']);
    });

    test('a failing call rejects with the code of its exception', () async {
      session.failure = InvalidKeyException(KeyRefusal.sharedWithMissing);

      final r = await rejected(
          invoke(s, 'notify', ['@bob:rpc.wavi@alice'.toJS, 'x'.toJS]));

      expect(r.code, 'bad_key');
    });

    test('a mapped exception keeps its message', () async {
      session.failure = InvalidKeyException(KeyRefusal.sharedWithMissing);

      final r = await rejected(
          invoke(s, 'notify', ['@bob:rpc.wavi@alice'.toJS, 'x'.toJS]));

      expect(r.code, 'bad_key');
      expect(r.message, contains('notify needs sharedWith'));
    });

    test('a notify failure rejects notify_failed by its kind, never its text',
        () async {
      // The session turns an at_client send failure into a typed
      // NotifyFailedException; the bridge never sees the raw AtClientException.
      session.failure = NotifyFailedException(NotifyFailure.sendFailed);

      final r = await rejected(
          invoke(s, 'notify', ['@bob:rpc.wavi@alice'.toJS, 'x'.toJS]));

      expect(r.code, 'notify_failed');
      expect(r.message, 'sending the notification failed');
    });

    test('subscribe delivers events and returns an unsubscribe function',
        () async {
      final seen = <Object?>[];
      final unsubscribe = invoke(s, 'subscribe', [
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

    test('a peer-chosen notification id and key are bounded in the envelope',
        () async {
      final seen = <Object?>[];
      invoke(s, 'subscribe', [
        '.*'.toJS,
        ((JSAny? event) => seen.add(event.dartify())).toJS,
      ]);
      final direction = String.fromCharCode(0x202e);
      final hostile = '${'n' * 600}\n$direction';

      session.listeners.single((
        id: hostile,
        from: '@alice',
        key: hostile,
        value: 'ping',
        epochMillis: 42,
        operation: 'update',
      ));

      final event = seen.single! as Map;
      for (final field in ['id', 'key']) {
        final text = event[field]! as String;
        expect(text, isNot(contains('\n')), reason: '$field holds no newline');
        expect(text, isNot(contains(direction)),
            reason: '$field holds no direction character');
        expect(singleLine(text), text, reason: '$field is one line');
        expect(text.length, lessThanOrEqualTo(maxErrorMessageLength),
            reason: '$field takes the rejection bound');
      }
      expect(event['value'], 'ping');
      expect(event['from'], '@alice');
      expect(event['epochMillis'], 42);
      expect(event['operation'], 'update');
    });

    test(
        'bridge subscribe drops notifications and errors after session is closed',
        () async {
      final seen = <Object?>[];
      final errors = <Object?>[];
      invoke(s, 'subscribe', [
        '.*'.toJS,
        ((JSAny? event) => seen.add(event.dartify())).toJS,
        ((JSAny? err) => errors.add(err.dartify())).toJS,
      ]);

      await resolved(invoke(s, 'close'));
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
        final result = invoke(s, 'subscribe', [regex, (() {}).toJS]);
        expect(result.isA<JSFunction>(), isFalse);
        return result! as JSObject;
      }

      test('after close it answers {code: closed, message}', () async {
        await resolved(invoke(s, 'close'));

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

      test('the bridge hands the regex text to the session uncompiled', () {
        invoke(s, 'subscribe', ['['.toJS, (() {}).toJS]);

        expect(session.subscribedRegex, '[');
      });

      test('subscribe with invalid regex rejects naming regex', () {
        session.failure = InvalidArgumentException('regex');
        final e = failed('['.toJS);

        expect(e['code'].dartify(), 'invalid_argument');
        expect(e['message'].dartify() as String, contains('regex'));
      });

      test(
          'subscribe with non-function callback returns {code: invalid_argument} without throwing',
          () {
        for (final bad in [null, 5.toJS, jsObject({})]) {
          final r = invoke(s, 'subscribe', ['x'.toJS, bad])! as JSObject;
          expect(r['code'].dartify(), 'invalid_argument');
          expect(r['message'].dartify() as String, contains('callback'));
        }
      });
    });

    test('close stops the session and later calls reject with closed',
        () async {
      await resolved(invoke(s, 'close'));

      expect(session.closed, isTrue);
      final r = await rejected(
          invoke(s, 'notify', ['@bob:k.wavi@alice'.toJS, 'v'.toJS]));
      expect(r.code, 'closed');
      for (final (method, args) in [
        ('notify', <JSAny?>['@bob:k.wavi@alice'.toJS, 'v'.toJS]),
        (
          'collection',
          <JSAny?>[
            'c'.toJS,
            jsObject({'type': 't'})
          ]
        ),
        ('otp', <JSAny?>[]),
        ('pendingEnrollments', <JSAny?>[]),
        ('approve', <JSAny?>['e1'.toJS]),
        ('deny', <JSAny?>['e1'.toJS]),
      ]) {
        expect((await rejected(invoke(s, method, args))).code, 'closed',
            reason: method);
      }
    });

    group('subscribe errors', () {
      test('subscribe errors go to onError as {code, message}', () async {
        final seen = <Object?>[];
        invoke(s, 'subscribe', [
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
        invoke(s, 'subscribe', ['x'.toJS, (() {}).toJS]);

        expect(() => session.errorSink!(StateError('x')), returnsNormally);
      });

      test('a non-function onError answers a rejection object', () {
        final r = invoke(s, 'subscribe', ['x'.toJS, (() {}).toJS, 5.toJS])!
            as JSObject;

        expect(r['message'].dartify() as String, contains('onError'));
      });
    });

    group('status', () {
      test('status() reads the latest value', () {
        expect(invoke(s, 'status').dartify(), 'connecting');
        session.statusNow = 'waiting:network';
        expect(invoke(s, 'status').dartify(), 'waiting:network');
      });

      test('onStatus delivers changes and returns an off function', () {
        final seen = <Object?>[];
        final off =
            invoke(s, 'onStatus', [((JSAny? v) => seen.add(v.dartify())).toJS])!
                as JSFunction;

        session.statusListeners.single('connected');
        session.statusListeners.single('waiting:auth');
        off.callAsFunction();

        expect(seen, ['connected', 'waiting:auth']);
        expect(session.statusListeners, isEmpty);
      });

      test('onStatus after close answers {code: closed}', () async {
        await resolved(invoke(s, 'close'));

        final r = invoke(s, 'onStatus', [(() {}).toJS])! as JSObject;

        expect(r['code'].dartify(), 'closed');
      });

      test(
          'onStatus with non-function callback returns {code: invalid_argument} without throwing',
          () {
        for (final bad in [null, 5.toJS, jsObject({})]) {
          final r = invoke(s, 'onStatus', [bad])! as JSObject;
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
        c = (await resolved(invoke(s, 'collection', [
          'tasks'.toJS,
          jsObject({'type': 'task', 'eventSource': 'both', 'expiration': 5000})
        ])))! as JSObject;
      });

      test('collection passes name, type, eventSource and expiration', () {
        expect(session.collectionArgs.single, ('tasks', 'task', 'both', 5000));
        expect(
            _ownNames(c),
            unorderedEquals([
              'create',
              'get',
              'list',
              'query',
              'update',
              'share',
              'remove',
              'watch',
            ]));
      });

      test('collection eventSource and expiration are optional', () async {
        await resolved(invoke(s, 'collection', [
          'c'.toJS,
          jsObject({'type': 't'})
        ]));

        expect(session.collectionArgs.last, ('c', 't', null, null));
      });

      test(
          'a non-finite expiration rejects with invalid_argument naming expiration',
          () async {
        final before = session.collectionArgs.length;
        for (final bad in [
          double.nan,
          double.infinity,
          double.negativeInfinity
        ]) {
          final r = await rejected(invoke(s, 'collection', [
            'c'.toJS,
            jsObject({'type': 't', 'expiration': bad})
          ]));

          expect(r.code, 'invalid_argument', reason: '$bad');
          expect(r.message, contains('expiration'), reason: '$bad');
        }
        expect(session.collectionArgs, hasLength(before),
            reason: 'no non-finite expiration reaches the session');
      });

      test('collection create maps data, id and sharedWith', () async {
        final item = (await resolved(invoke(c, 'create', [
          jsObject({
            'title': 'a',
            'n': 2,
            'tags': ['x']
          }),
          jsObject({
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

        final item = (await resolved(invoke(c, 'get', [
          jsObject({'id': 'i1'})
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
        await resolved(invoke(
            c, 'create', [_json('{"__proto__": {"polluted": true}, "a": 1}')]));

        final (data, _, _) =
            adapter.last! as (Map<String, dynamic>, Object?, Object?);
        expect(data.keys, containsAll(['__proto__', 'a']));
      });

      test('collection get defaults the owner to the session and resolves null',
          () async {
        await resolved(invoke(c, 'get', [
          jsObject({'id': 'i1'})
        ]));
        expect(adapter.last, ('i1', '@alice'));
        await resolved(invoke(c, 'get', [
          jsObject({'id': 'i1', 'owner': 'bob'})
        ]));
        expect(adapter.last, ('i1', '@bob'));
        adapter.missing = true;
        expect(
            await resolved(invoke(c, 'get', [
              jsObject({'id': 'gone'})
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

        final listed = (await resolved(invoke(c, 'list')))! as JSObject;
        final queried = (await resolved(invoke(c, 'query', [
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

        final r = await rejected(invoke(c, 'get', [
          jsObject({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
        expect(r.message, isNot(contains('internal')));
      });

      test('tooDeep from collection item preserves id and owner', () async {
        adapter.item = {...adapter.item, 'data': _nested(65)};

        final r = await rejected(invoke(c, 'get', [
          jsObject({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
        expect(r.field('id'), 'i1');
        expect(r.field('owner'), '@alice');
      });

      test('collection item data nested exactly 64 levels deep resolves',
          () async {
        adapter.item = {...adapter.item, 'data': _nested(64)};
        adapter.listing = (items: [adapter.item], unreadable: const []);

        final got = (await resolved(invoke(c, 'get', [
          jsObject({'id': 'i1'})
        ])))! as JSObject;
        final listed = (await resolved(invoke(c, 'list')))! as JSObject;

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

        final r = await rejected(invoke(c, 'get', [
          jsObject({'id': 'i1'})
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.tooDeep));
      });

      test('collection update, share and remove map their arguments', () async {
        await resolved(invoke(c, 'update', [
          jsObject({'id': 'i1'}),
          jsObject({'a': 1})
        ]));
        final (id, owner, data) =
            adapter.last! as (String, String, Map<String, dynamic>);
        expect((id, owner), ('i1', '@alice'));
        expect(data, {'a': 1});
        await resolved(invoke(c, 'share', [
          jsObject({'id': 'i1', 'owner': '@alice'}),
          ['@bob', '@carol'].jsify()
        ]));
        expect(adapter.last.toString(), '(i1, @alice, [@bob, @carol])');
        final removed = await resolved(invoke(c, 'remove', [
          jsObject({'id': 'i1'}),
          jsObject({'cascade': true})
        ]));
        expect(adapter.last, ('i1', '@alice', true));
        expect(removed, isNull);
        await resolved(invoke(c, 'remove', [
          jsObject({'id': 'i1'})
        ]));
        expect(adapter.last, ('i1', '@alice', false));
      });

      test('a collection failure rejects with its code and fields (T6.4)',
          () async {
        adapter.failure = JsCollectionsError(CollectionFailure.partialFailure,
            id: 'i1',
            owner: '@alice',
            causeType: 'AtKeyException',
            failures: [
              {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
            ]);

        final r = await rejected(invoke(c, 'share', [
          jsObject({'id': 'i1'}),
          ['@bob'].jsify()
        ]));

        expect(r.code, collectionErrorCode(CollectionFailure.partialFailure));
        expect(r.message, '1 key-level write(s) failed');
        expect((r.field('id'), r.field('owner'), r.field('kind')),
            ('i1', '@alice', 'AtKeyException'));
        expect(r.field('failures'), [
          {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
        ]);
      });

      test(
          'a collection rejection keeps code, message, id, owner, kind and failures',
          () async {
        final cases = <(JsCollectionsError, String, String, Object?)>[
          (
            JsCollectionsError(CollectionFailure.notFound,
                id: 'i1', owner: '@alice', causeType: 'StateError'),
            'item not found',
            'StateError',
            null
          ),
          (
            JsCollectionsError(CollectionFailure.notOwner,
                id: 'i1', owner: '@bob', collectionOwner: '@alice'),
            'item "i1" is owned by @bob, not @alice',
            '',
            null
          ),
          (
            JsCollectionsError(CollectionFailure.failed,
                id: 'i1', owner: '@alice', causeType: 'StateError'),
            'operation failed',
            'StateError',
            null
          ),
          (
            JsCollectionsError(CollectionFailure.partialFailure,
                id: 'i1',
                owner: '@alice',
                causeType: 'CollectionOpException',
                failures: [
                  {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
                ]),
            '1 key-level write(s) failed',
            'CollectionOpException',
            [
              {'op': 'update', 'recipient': '@bob', 'kind': 'Unknown'}
            ]
          ),
        ];
        for (final (failure, message, kind, failures) in cases) {
          adapter.failure = failure;
          final r = await rejected(invoke(c, 'list'));
          expect(r.code, collectionErrorCode(failure.kind));
          expect(r.message, message);
          expect(r.field('id'), failure.id);
          expect(r.field('owner'), failure.owner);
          expect(r.field('kind'), kind.isEmpty ? isNull : kind);
          expect(r.field('failures'), failures);
        }
      });

      test('a peer-chosen id and owner are bounded in a rejection', () async {
        final direction = String.fromCharCode(0x202e);
        adapter.failure = JsCollectionsError(CollectionFailure.notFound,
            id: 'i' * 600,
            owner: '@bob\n$direction${'x' * 600}',
            failures: [
              {
                'op': 'update',
                'recipient': '@bob\n$direction${'y' * 600}',
                'kind': 'Unknown',
              }
            ]);

        final r = await rejected(invoke(c, 'list'));

        final id = r.field('id')! as String;
        final owner = r.field('owner')! as String;
        final failure = (r.field('failures')! as List).single as Map;
        final recipient = failure['recipient']! as String;
        for (final field in [id, owner, recipient]) {
          expect(singleLine(field), field, reason: 'one line');
          expect(field.length, lessThanOrEqualTo(maxErrorMessageLength));
        }
        expect(failure['op'], 'update');
        expect(failure['kind'], 'Unknown');
      });

      test('a peer-chosen failure recipient is bounded in a rejection',
          () async {
        final direction = String.fromCharCode(0x202e);
        adapter.failure =
            JsCollectionsError(CollectionFailure.partialFailure, failures: [
          {
            'op': 'update',
            'recipient': '@bob\n$direction${'r' * 600}',
            'kind': 'Unknown',
          }
        ]);

        final r = await rejected(invoke(c, 'list'));

        final failure = (r.field('failures')! as List).single as Map;
        final recipient = failure['recipient']! as String;
        expect(singleLine(recipient), recipient, reason: 'one line');
        expect(recipient.length, lessThanOrEqualTo(maxErrorMessageLength));
        expect(failure['op'], 'update');
        expect(failure['kind'], 'Unknown');
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
          await resolved(invoke(c, 'list')),
          await resolved(invoke(c, 'query', [
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

      test("an unreadable record's id and owner are bounded in a listing",
          () async {
        final direction = String.fromCharCode(0x202e);
        adapter.listing = (
          items: const [],
          unreadable: [
            (
              id: 'u' * 600 + '\n$direction',
              owner: Atsign('@bob$direction'),
              kind: CollectionFailure.unreadable
            ),
          ]
        );

        final listing = (await resolved(invoke(c, 'list')))! as JSObject;
        final record =
            (listing['unreadable']! as JSArray).toDart.single! as JSObject;
        final id = record['id'].dartify()! as String;
        final owner = record['owner'].dartify()! as String;
        for (final field in [id, owner]) {
          expect(singleLine(field), field, reason: 'one line');
          expect(field.length, lessThanOrEqualTo(maxErrorMessageLength));
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
          adapter.failure = JsCollectionsError(kind);
          expect((await rejected(invoke(c, 'list'))).code,
              collectionErrorCode(kind));
        }
      });

      test('collection bad arguments reject naming the parameter', () async {
        for (final (promise, name) in [
          (invoke(c, 'get', ['i1'.toJS]), 'address'),
          (invoke(c, 'create', [5.toJS]), 'data'),
          (invoke(c, 'query', [5.toJS]), 'where'),
          (
            invoke(c, 'share', [
              jsObject({'id': 'i'}),
              'x'.toJS
            ]),
            'atSigns'
          ),
        ]) {
          final r = await rejected(promise);
          expect(r.code, 'invalid_argument');
          expect(r.message, contains(name));
        }
      });

      test('collection data that is an array or too deep rejects naming data',
          () async {
        JSObject nested(int levels) {
          var o = jsObject({});
          for (var i = 0; i < levels; i++) {
            o = jsObject({'n': o});
          }
          return o;
        }

        final cyclic = jsObject({});
        cyclic['self'] = cyclic;
        for (final (promise, message) in [
          (
            invoke(c, 'create', [
              <JSAny?>[1.toJS].toJS
            ]),
            'an object'
          ),
          (
            invoke(c, 'update', [
              jsObject({'id': 'i1'}),
              <JSAny?>[1.toJS].toJS
            ]),
            'an object'
          ),
          (invoke(c, 'create', [nested(100)]), 'levels deep'),
          (invoke(c, 'create', [cyclic]), 'levels deep'),
        ]) {
          final r = await rejected(promise);
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
        final off = invoke(c, 'watch', [
          ((JSAny? e) => events.add(e.dartify())).toJS,
          ((JSAny? e) => errors.add(e.dartify())).toJS
        ])! as JSFunction;

        adapter.onEvent!({'type': 'updated', 'id': 'i1', 'owner': '@alice'});
        adapter.onEvent!({'type': 'unknown', 'id': 'i2', 'owner': '@bob'});
        adapter.onError!(JsCollectionsError(CollectionFailure.failed));
        off.callAsFunction();

        expect(events, [
          {'type': 'updated', 'id': 'i1', 'owner': '@alice'},
          {'type': 'unknown', 'id': 'i2', 'owner': '@bob'}
        ]);
        expect(errors, [
          {
            'code': collectionErrorCode(CollectionFailure.failed),
            'message': 'operation failed'
          }
        ]);
        expect(adapter.cancelled, 1);
      });

      test('a peer-chosen watch event field is bounded', () async {
        final seen = <Object?>[];
        invoke(c, 'watch', [
          ((JSAny? event) => seen.add(event.dartify())).toJS,
        ]);
        final direction = String.fromCharCode(0x202e);
        final hostile = '${'n' * 600}\n$direction';

        adapter.onEvent!({
          'type': 'subItemUpdated',
          'id': hostile,
          'owner': hostile,
          'from': hostile,
          'ancestry': [
            {'id': 'a1', 'subName': hostile, 'owner': '@alice'},
          ],
          'data': {'n': 1},
        });

        final event = seen.single! as Map;
        for (final field in ['id', 'owner', 'from']) {
          final text = event[field]! as String;
          expect(text, isNot(contains('\n')),
              reason: '$field holds no newline');
          expect(text, isNot(contains(direction)),
              reason: '$field holds a direction character');
          expect(singleLine(text), text, reason: '$field is one line');
          expect(text.length, lessThanOrEqualTo(maxErrorMessageLength),
              reason: '$field takes the rejection bound');
        }
        final subName =
            ((event['ancestry']! as List).single as Map)['subName']! as String;
        expect(subName, isNot(contains('\n')),
            reason: 'subName holds no newline');
        expect(subName, isNot(contains(direction)),
            reason: 'subName holds a direction character');
        expect(singleLine(subName), subName, reason: 'subName is one line');
        expect(subName.length, lessThanOrEqualTo(maxErrorMessageLength),
            reason: 'subName takes the rejection bound');
        expect(event['data'], {'n': 1}, reason: 'the data is unchanged');
      });

      test('collection watch needs a function and never throws', () {
        final r = invoke(c, 'watch', [5.toJS])! as JSObject;

        expect(r['code'].dartify(), 'invalid_argument');
        expect(r['message'].dartify() as String, contains('onEvent'));
      });

      test('a watch cancel that fails is logged', () async {
        adapter.cancelFailure = StateError('cancel failed');
        final off = invoke(c, 'watch', [((JSAny? _) {}).toJS])! as JSFunction;

        final escaped = <Object>[];
        await runZonedGuarded(() async {
          off.callAsFunction();
          await pumpEventQueue();
        }, (error, stack) => escaped.add(error));

        expect(escaped, isEmpty,
            reason: 'the bridge catches the cancel failure');
        expect(logs.lines,
            contains('WARNING|BridgeEntry|Failed to cancel collection watch'));
      });

      test(
          'collection operations and watch reject with closed after session close',
          () async {
        await resolved(invoke(s, 'close'));

        for (final (method, args) in [
          (
            'create',
            <JSAny?>[
              jsObject({'a': 1})
            ]
          ),
          (
            'get',
            <JSAny?>[
              jsObject({'id': 'i1'})
            ]
          ),
          ('list', <JSAny?>[]),
          ('query', <JSAny?>[<JSAny?>[].toJS]),
          (
            'update',
            <JSAny?>[
              jsObject({'id': 'i1'}),
              jsObject({'a': 2})
            ]
          ),
          (
            'share',
            <JSAny?>[
              jsObject({'id': 'i1'}),
              ['bob'].jsify()
            ]
          ),
          (
            'remove',
            <JSAny?>[
              jsObject({'id': 'i1'})
            ]
          ),
        ]) {
          expect((await rejected(invoke(c, method, args))).code, 'closed',
              reason: method);
        }

        final watchRes =
            invoke(c, 'watch', [((JSAny? _) {}).toJS])! as JSObject;
        expect(watchRes['code'].dartify(), 'closed');
      });

      test('invalid address owner rejects with invalid_argument naming owner',
          () async {
        for (final (method, args) in [
          (
            'get',
            <JSAny?>[
              jsObject({'id': 'i1', 'owner': '@a@b-sentinel'})
            ]
          ),
          (
            'update',
            <JSAny?>[
              jsObject({'id': 'i1', 'owner': '@a@b-sentinel'}),
              jsObject({'a': 1})
            ]
          ),
          (
            'share',
            <JSAny?>[
              jsObject({'id': 'i1', 'owner': '@a@b-sentinel'}),
              ['@bob'].jsify()
            ]
          ),
          (
            'remove',
            <JSAny?>[
              jsObject({'id': 'i1', 'owner': '@a@b-sentinel'})
            ]
          ),
        ]) {
          final r = await rejected(invoke(c, method, args));
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
          _jsConstruct('Error', ['bad'.toJS]),
        ];
        for (final bad in nonPlain) {
          final optRes = await rejected(invoke(c, 'create', [
            jsObject({'a': 1}),
            bad
          ]));
          expect(optRes.code, 'invalid_argument');
          expect(optRes.message, contains('opts'));

          final dataRes = await rejected(invoke(c, 'create', [
            jsObject({'nested': bad})
          ]));
          expect(dataRes.code, 'invalid_argument');
          expect(dataRes.message, contains('data'));

          final clause = jsObject({'path': 'a', 'op': '=='});
          clause['value'] = bad;
          final whereRes = await rejected(invoke(c, 'query', [
            [clause].toJS
          ]));
          expect(whereRes.code, 'invalid_argument');
          expect(whereRes.message, contains('value'));
        }
        final errOpts = jsObject({});
        errOpts['id'] = _jsConstruct('Error', ['option'.toJS]);
        final optionValueRes = await rejected(invoke(c, 'create', [
          jsObject({'a': 1}),
          errOpts
        ]));
        expect(optionValueRes.code, 'invalid_argument');
        expect(optionValueRes.message, contains('id'));

        final arrOpts = await rejected(invoke(c, 'create', [
          jsObject({'a': 1}),
          <JSAny?>[].toJS
        ]));
        expect(arrOpts.code, 'invalid_argument');
        expect(arrOpts.message, contains('opts'));
        expect(adapter.calls, isEmpty,
            reason: 'no rejected argument reaches the collection');
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

          await resolved(
              invoke(s, 'notify', ['@bob:k.wavi@alice'.toJS, 'v'.toJS]));
          expect(session.keysSeen.last, '@bob:k.wavi@alice',
              reason: 'key text is read as a string, so no polluted field is');

          await resolved(invoke(s, 'collection', [
            'clean'.toJS,
            jsObject({'type': 't'})
          ]));
          expect(session.collectionArgs.last, ('clean', 't', null, null));

          await resolved(invoke(c, 'create', [
            jsObject({'a': 1}),
            jsObject({})
          ]));
          final (_, createdId, createdShared) =
              adapter.last! as (Map<String, dynamic>, String?, List<String>);
          expect(createdId, isNull);
          expect(createdShared, isEmpty);

          await resolved(invoke(c, 'get', [
            jsObject({'id': 'i1'})
          ]));
          expect(adapter.last, ('i1', '@alice'));

          await resolved(invoke(c, 'remove', [
            jsObject({'id': 'i1'}),
            jsObject({})
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
        expect((await resolved(invoke(s, 'otp'))).dartify(), 'Z9Y8X7');
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

        final result = await resolved(invoke(s, 'pendingEnrollments'));

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
        expect((await resolved(invoke(s, 'pendingEnrollments'))).dartify(),
            isEmpty);
      });

      test('a peer-chosen app or device name is bounded in pending enrollments',
          () async {
        session.pending = [
          (
            id: 'e1',
            appName: '${'a' * 300}\nsecond line',
            deviceName: 'Phone \u202Eevil',
            namespaces: {'tally\n\u202E${'n' * 300}': 'rw'}
          )
        ];

        final entries =
            (await resolved(invoke(s, 'pendingEnrollments'))).dartify() as List;
        final entry = entries.single as Map;
        final appName = entry['appName'] as String;
        final deviceName = entry['deviceName'] as String;
        final namespaces = entry['namespaces'] as Map;
        final namespace = namespaces.keys.single as String;

        expect(appName, isNot(contains('\n')));
        expect(deviceName, isNot(contains('\u202E')));
        expect(appName.length, lessThanOrEqualTo(maxErrorMessageLength));
        expect(deviceName.length, lessThanOrEqualTo(maxErrorMessageLength));
        expect(namespace, isNot(contains('\n')));
        expect(namespace, isNot(contains('\u202E')));
        expect(namespace.length, lessThanOrEqualTo(maxErrorMessageLength));
        expect(namespace, startsWith('tally'));
        expect(namespaces[namespace], 'rw');
        expect(entry['id'], 'e1');
      });

      test('approve and deny pass the id and resolve undefined', () async {
        final approved = await resolved(invoke(s, 'approve', ['e1'.toJS]));
        final denied = await resolved(invoke(s, 'deny', ['e2'.toJS]));

        expect(session.decided, ['approve e1', 'deny e2']);
        expect(approved, isNull);
        expect(denied, isNull);
      });

      test('approve takes the id alone, whatever else is passed', () async {
        await resolved(invoke(s, 'approve', [
          'e1'.toJS,
          jsObject({
            'namespaces': {'*': 'rw'}
          })
        ]));

        expect(session.decided, ['approve e1']);
      });

      test('approve and deny reject a non-string id', () async {
        for (final method in ['approve', 'deny']) {
          expect((await rejected(invoke(s, method, [jsObject({})]))).code,
              'invalid_argument');
          expect((await rejected(invoke(s, method, [5.toJS]))).code,
              'invalid_argument');
        }
        expect(session.decided, isEmpty);
      });

      test('each call rejects with unsupported without __manage', () async {
        session.failure = ManageAccessRequiredException();

        for (final (method, args) in [
          ('otp', <JSAny?>[]),
          ('pendingEnrollments', <JSAny?>[]),
          ('approve', <JSAny?>['e1'.toJS]),
          ('deny', <JSAny?>['e1'.toJS]),
        ]) {
          expect((await rejected(invoke(s, method, args))).code, 'unsupported',
              reason: method);
        }
      });

      test('an unknown id rejects with enrollment_denied', () async {
        session.failure = AtEnrollmentException('no enrollment e9');

        expect((await rejected(invoke(s, 'approve', ['e9'.toJS]))).code,
            'enrollment_denied');
      });
    });
  });

  group('keysTransport', () {
    test("a keys session with no caller transport dials the options' root", () {
      final options = KeysSessionOptions(
          atSign: '@alice',
          namespace: 'tally',
          keys: const {
            '@alice': {'k': 'v'}
          },
          rootDomain: 'root.example:64');

      final transport = keysTransport(options);

      expect((
        transport.root.rootDomain,
        transport.root.rootPort
      ), (
        'root.example',
        64
      ), reason: "the transport carries the options' root");
      final finderAtRoot = isA<HttpsSecondaryAddressFinder>()
          .having((f) => f.host, 'host', 'root.example')
          .having((f) => f.port, 'port', 64);
      expect(transport.finder, finderAtRoot,
          reason: 'Atsigns are looked up at that root over HTTPS');

      final lookup = transport.lookUps(
          atSign: '@alice', rootDomain: transport.root, authenticator: null);
      expect(lookup.secondaryAddressFinder, finderAtRoot,
          reason: 'the lookups factory falls back to that root as well');
    });
  });

  group('sessionOver', () {
    KeysSessionOptions options() =>
        KeysSessionOptions(atSign: '@alice', namespace: 'tally', keys: const {
          '@alice': {'k': 'v'}
        });

    test('a session that fails to build after opening is stopped', () async {
      final failure =
          ArgumentError('is not a valid namespace segment', 'namespace');
      var stops = 0;

      await expectLater(
          sessionOver(_ThrowingConnectionClient(failure), () async => stops++,
              options()),
          throwsA(same(failure)));
      expect(stops, 1);
    });

    test('a session that builds leaves what was opened running', () async {
      var stops = 0;

      final session =
          await sessionOver(PasskeyClient(), () async => stops++, options());
      expect(stops, 0);

      await session.close();
      expect(stops, 1);
    });
  });

  group('network changes', () {
    test('each online or offline event reaches the session', () async {
      final events = <void>[];
      final subscription = networkChanges().listen(events.add);
      await pumpEventQueue();

      web.window.dispatchEvent(web.Event('online'));
      web.window.dispatchEvent(web.Event('offline'));
      await pumpEventQueue();
      expect(events, hasLength(2));

      await subscription.cancel();
      web.window.dispatchEvent(web.Event('online'));
      await pumpEventQueue();
      expect(events, hasLength(2));
    });
  });
}
