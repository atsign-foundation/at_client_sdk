@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_client/at_client.dart' show AtEnrollmentException;
import 'package:at_client_wasm/src/js/bridge.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_client_wasm/src/session/setup_lock.dart';
import 'package:test/test.dart';

/// A [JsSession] that records each call and answers from [store].
class _FakeSession implements JsSession {
  final calls = <String>[];
  final keysSeen = <JsKey>[];
  final values = <Object>[];
  final store = <String, Object>{};
  final listeners = <void Function(JsNotification)>[];
  var closed = false;
  var unsubscribed = 0;
  var delivered = true;
  Object? failure;
  List<String> keyList = [];
  String? keysRegex;
  String? subscribedRegex;
  String passcode = 'Z9Y8X7';
  List<JsEnrollment> pending = [];
  final decided = <String>[];

  void _call(String name, [JsKey? key]) {
    if (closed) throw SessionClosedException();
    calls.add(name);
    if (key != null) keysSeen.add(key);
    if (failure case final error?) throw error;
  }

  @override
  Future<void> put(JsKey key, Object value) async {
    _call('put', key);
    values.add(value);
    store[key.key] = value;
  }

  @override
  Future<Object?> get(JsKey key) async {
    _call('get', key);
    return store[key.key];
  }

  @override
  Future<void> delete(JsKey key) async {
    _call('delete', key);
    store.remove(key.key);
  }

  @override
  Future<List<String>> keys([String? regex]) async {
    _call('keys');
    keysRegex = regex;
    return keyList;
  }

  @override
  Future<bool> notify(JsKey key, String value) async {
    _call('notify', key);
    values.add(value);
    return delivered;
  }

  @override
  void Function() subscribe(
      String regex, void Function(JsNotification) onEvent) {
    _call('subscribe');
    subscribedRegex = regex;
    listeners.add(onEvent);
    return () {
      unsubscribed++;
      listeners.remove(onEvent);
    };
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

typedef _Opened = ({
  BridgeOptions options,
  String? cram,
  String? appName,
  String? deviceName,
  String? otp,
});

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

JSObject _obj(Map<String, Object?> map) => map.jsify()! as JSObject;

JSAny? _call(JSObject target, String name, [List<JSAny?> args = const []]) =>
    switch (args.length) {
      0 => target.callMethod(name.toJS),
      1 => target.callMethod(name.toJS, args[0]),
      2 => target.callMethod(name.toJS, args[0], args[1]),
      3 => target.callMethod(name.toJS, args[0], args[1], args[2]),
      _ => target.callMethod(name.toJS, args[0], args[1], args[2], args[3]),
    };

void main() {
  late _FakeSession session;
  late List<_Opened> logins;
  late List<_Opened> onboards;
  late List<_Opened> enrolls;
  late bool secure;
  late bool prf;
  late Object? openFailure;
  late JSObject api;

  Future<JsSession> opened(List<_Opened> log, _Opened entry) async {
    log.add(entry);
    if (openFailure case final error?) throw error;
    return session;
  }

  setUp(() {
    session = _FakeSession();
    logins = [];
    onboards = [];
    enrolls = [];
    secure = true;
    prf = true;
    openFailure = null;
    api = createJSInteropWrapper(AtClientWebBridge(
        login: (o) async => opened(logins, (
              options: o,
              cram: null,
              appName: null,
              deviceName: null,
              otp: null
            )),
        onboard: (o, cram, deviceName) async => opened(onboards, (
              options: o,
              cram: cram,
              appName: null,
              deviceName: deviceName,
              otp: null
            )),
        enroll: (o, appName, deviceName, otp) async => opened(enrolls, (
              options: o,
              cram: null,
              appName: appName,
              deviceName: deviceName,
              otp: otp
            )),
        prfSupported: () async => prf,
        isSecureContext: () => secure,
        hostname: () => 'tally.example'));
  });

  Future<JSObject> create([Map<String, Object?>? opts]) async =>
      (await _resolved(_call(api, 'create', [
        _obj(opts ??
            {'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'})
      ])))! as JSObject;

  group('prfSupported', () {
    test('resolves what the environment reports', () async {
      expect((await _resolved(_call(api, 'prfSupported')))!.dartify(), isTrue);
      prf = false;
      expect((await _resolved(_call(api, 'prfSupported')))!.dartify(), isFalse);
    });

    test('is answered outside a secure context', () async {
      secure = false;
      expect((await _resolved(_call(api, 'prfSupported')))!.dartify(), isTrue);
    });
  });

  group('create', () {
    test('logs in with the options and returns a session', () async {
      final result = await create({
        'atSign': '@alice',
        'namespace': 'tally',
        'app': 'tallyapp',
        'rpId': 'example.org',
        'rpName': 'Tally'
      });

      final o = logins.single.options;
      expect((o.atSign, o.namespace, o.app, o.rpId, o.rpName),
          ('@alice', 'tally', 'tallyapp', 'example.org', 'Tally'));
      expect(result.has('put'), isTrue);
    });

    test('app defaults to the namespace and rpId to the hostname', () async {
      await create();

      final o = logins.single.options;
      expect((o.app, o.rpId), ('tally', 'tally.example'));
    });

    test('rejects with unsupported outside a secure context', () async {
      secure = false;

      final r = await _rejected(_call(api, 'create', [
        _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'})
      ]));

      expect(r.code, 'unsupported');
      expect(logins, isEmpty);
    });

    test('rejects with the W8 code of a typed exception', () async {
      openFailure = PasskeyLostException('@alice', 'PKAM refused');

      final r = await _rejected(_call(api, 'create', [
        _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'})
      ]));

      expect(r.code, 'passkey_lost');
      expect(r.message, contains('PKAM refused'));
    });

    test('a rejection is a plain object with only code and message', () async {
      openFailure = StateError('boom');

      final r = await _rejected(_call(api, 'create', [
        _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'})
      ]));

      final reason = r.reason! as JSObject;
      expect(r.code, 'internal');
      expect(reason.instanceOfString('Error'), isFalse);
      expect((reason.dartify()! as Map).keys,
          unorderedEquals(['code', 'message']));
    });

    test('options without an atSign or namespace reject', () async {
      final r = await _rejected(_call(api, 'create', [
        _obj({'rpName': 'T'})
      ]));

      expect(r.code, 'internal');
      expect(logins, isEmpty);
    });
  });

  group('onboard', () {
    Future<_Settled> onboard({Object? deviceName}) =>
        _settle(_call(api, 'onboard', [
          _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'}),
          'cram-secret'.toJS,
          if (deviceName != null) (deviceName as String).toJS
        ]));

    test('maps the options, cram and device name', () async {
      expect(await onboard(deviceName: 'Laptop'), isA<_Resolved>());

      final o = onboards.single;
      expect((o.options.atSign, o.options.app, o.options.rpId),
          ('@alice', 'tally', 'tally.example'));
      expect((o.cram, o.deviceName), ('cram-secret', 'Laptop'));
    });

    test('the device name is optional', () async {
      expect(await onboard(), isA<_Resolved>());

      expect(onboards.single.deviceName, isNull);
    });

    test('rejects with unsupported outside a secure context', () async {
      secure = false;

      expect(((await onboard()) as _Rejected).code, 'unsupported');
      expect(onboards, isEmpty);
    });

    test('rejects with the code of an onboarding failure', () async {
      openFailure = SetupLockTimeoutException('lock');

      expect(((await onboard()) as _Rejected).code, 'setup_lock_timeout');
    });
  });

  group('enroll', () {
    Future<_Settled> enroll() => _settle(_call(api, 'enroll', [
          _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'}),
          'tallyapp'.toJS,
          'Phone'.toJS,
          'ABC123'.toJS
        ]));

    test('maps the options, app name, device name and otp', () async {
      expect(await enroll(), isA<_Resolved>());

      final e = enrolls.single;
      expect((e.options.atSign, e.options.rpId), ('@alice', 'tally.example'));
      expect((e.appName, e.deviceName, e.otp), ('tallyapp', 'Phone', 'ABC123'));
    });

    test('rejects with unsupported outside a secure context', () async {
      secure = false;

      expect(((await enroll()) as _Rejected).code, 'unsupported');
      expect(enrolls, isEmpty);
    });

    test('rejects with enrollment_denied when the approver refuses', () async {
      openFailure = AtEnrollmentException('The enrollment: eid is denied');

      expect(((await enroll()) as _Rejected).code, 'enrollment_denied');
    });
  });

  group('argument errors', () {
    const sentinel = 'sentinel-value-7f3a';
    JSObject wrapped() => _obj({
          'inner': sentinel,
          'list': [sentinel]
        })
          ..['toString'] = (() => sentinel.toJS).toJS;
    final options =
        _obj({'atSign': '@alice', 'namespace': 'tally', 'rpName': 'Tally'});

    Future<void> expectNamed(JSAny? promise, String parameter,
        {String code = 'internal'}) async {
      final r = await _rejected(promise);
      expect(r.code, code);
      expect(r.message, contains(parameter));
      expect(r.message, isNot(contains(sentinel)));
    }

    test('onboard names cram and deviceName without their values', () async {
      await expectNamed(_call(api, 'onboard', [options, wrapped()]), 'cram');
      await expectNamed(
          _call(api, 'onboard', [options, 'c'.toJS, wrapped()]), 'deviceName');
    });

    test('enroll names appName, deviceName and otp without their values',
        () async {
      JSAny? enroll(List<JSAny?> rest) =>
          _call(api, 'enroll', [options, ...rest]);
      await expectNamed(enroll([wrapped(), 'd'.toJS, 'o'.toJS]), 'appName');
      await expectNamed(enroll(['a'.toJS, wrapped(), 'o'.toJS]), 'deviceName');
      await expectNamed(enroll(['a'.toJS, 'd'.toJS, wrapped()]), 'otp');
    });

    test('options name the parameter without its value', () async {
      await expectNamed(_call(api, 'create', [wrapped()]), 'namespace');
      await expectNamed(_call(api, 'create', [sentinel.toJS]), 'opts');
      await expectNamed(
          _call(api, 'create', [
            _obj({'atSign': wrapped(), 'namespace': 'n', 'rpName': 'r'})
          ]),
          'atSign');
    });

    test('session calls name the parameter without its value', () async {
      final s = await create();
      await expectNamed(
          _call(s, 'put', [
            _obj({'key': 'k'}),
            wrapped()
          ]),
          'value');
      await expectNamed(_call(s, 'put', [sentinel.toJS, 'v'.toJS]), 'key',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'get', [
            _obj({'key': wrapped()})
          ]),
          'key',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'delete', [
            _obj({'key': 'k', 'namespace': wrapped()})
          ]),
          'namespace',
          code: 'bad_key');
      await expectNamed(
          _call(s, 'get', [
            _obj({'key': 'k', 'public': sentinel})
          ]),
          'public',
          code: 'bad_key');
      await expectNamed(_call(s, 'keys', [wrapped()]), 'regex');
      await expectNamed(
          _call(s, 'notify', [
            _obj({'key': 'k'}),
            wrapped()
          ]),
          'value');
      await expectNamed(_call(s, 'approve', [wrapped()]), 'id');
    });
  });

  group('session', () {
    late JSObject s;

    setUp(() async => s = await create());

    test('put maps a string, bytes and the key fields', () async {
      final key = _obj({
        'key': 'note',
        'namespace': 'other',
        'sharedWith': '@bob',
        'sharedBy': '@carol'
      });

      await _resolved(_call(s, 'put', [key, 'hello'.toJS]));
      await _resolved(_call(s, 'put', [
        _obj({'key': 'blob'}),
        Uint8List.fromList([1, 2]).toJS
      ]));

      expect(session.values, [
        'hello',
        Uint8List.fromList([1, 2])
      ]);
      final first = session.keysSeen.first;
      expect((first.key, first.namespace, first.sharedWith, first.sharedBy),
          ('note', 'other', '@bob', '@carol'));
      final second = session.keysSeen.last;
      expect((second.namespace, second.sharedWith, second.sharedBy),
          (null, null, null));
    });

    test('put maps the public, cached and noNamespace flags', () async {
      await _resolved(_call(s, 'put', [
        _obj({'key': 'k', 'public': true, 'cached': true, 'noNamespace': true}),
        'v'.toJS
      ]));
      await _resolved(_call(s, 'put', [
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

    test('put rejects a value that is neither a string nor bytes', () async {
      final r = await _rejected(_call(s, 'put', [
        _obj({'key': 'k'}),
        5.toJS
      ]));

      expect(r.code, 'internal');
      expect(session.calls, isNot(contains('put')));
    });

    test('get returns a string, bytes and null for a missing key', () async {
      session.store['text'] = 'hi';
      session.store['blob'] = Uint8List.fromList([9, 8]);

      final text = await _resolved(_call(s, 'get', [
        _obj({'key': 'text'})
      ]));
      final blob = await _resolved(_call(s, 'get', [
        _obj({'key': 'blob'})
      ]));
      final none = await _resolved(_call(s, 'get', [
        _obj({'key': 'none'})
      ]));

      expect((text! as JSString).toDart, 'hi');
      expect((blob! as JSUint8Array).toDart, [9, 8]);
      expect(none, isNull);
    });

    test('delete removes the key', () async {
      session.store['k'] = 'v';

      await _resolved(_call(s, 'delete', [
        _obj({'key': 'k'})
      ]));

      expect(session.store, isEmpty);
    });

    test('keys passes the regex through and returns strings', () async {
      session.keyList = ['a.tally@alice', 'b.tally@alice'];

      final all = await _resolved(_call(s, 'keys'));
      expect(session.keysRegex, isNull);
      final some = await _resolved(_call(s, 'keys', ['^a'.toJS]));

      expect(session.keysRegex, '^a');
      expect(all.dartify(), ['a.tally@alice', 'b.tally@alice']);
      expect(some.dartify(), ['a.tally@alice', 'b.tally@alice']);
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

      test('a bad argument answers {code: internal, message} naming it', () {
        final e = failed(5.toJS);

        expect(e['code'].dartify(), 'internal');
        expect(e['message'].dartify() as String, contains('regex'));
      });
    });

    test('close stops the session and later calls reject with closed',
        () async {
      await _resolved(_call(s, 'close'));

      expect(session.closed, isTrue);
      final r = await _rejected(_call(s, 'get', [
        _obj({'key': 'k'})
      ]));
      expect(r.code, 'closed');
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
          expect(
              (await _rejected(_call(s, method, [_obj({})]))).code, 'internal');
          expect(
              (await _rejected(_call(s, method, [5.toJS]))).code, 'internal');
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
