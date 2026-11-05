@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, KeyNotFoundException;
import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';

class _FakeDevSession implements DevSession {
  final values = <String, String>{};
  var closes = 0;
  Object? error;

  void _throwIfSet() {
    if (error case final e?) throw e;
  }

  @override
  Future<void> put(String key, String value) async {
    _throwIfSet();
    values[key] = value;
  }

  @override
  Future<String?> get(String key) async {
    _throwIfSet();
    return values[key];
  }

  @override
  Future<void> delete(String key) async {
    _throwIfSet();
    values.remove(key);
  }

  ({
    String to,
    String key,
    String namespace,
    String value,
    Duration? expiry
  })? notified;
  void Function(DevNotification)? listener;
  String? regex;
  var unsubscribes = 0;

  @override
  Future<void> notify(String to, String key, String namespace, String value,
      {Duration? expiry}) async {
    _throwIfSet();
    notified =
        (to: to, key: key, namespace: namespace, value: value, expiry: expiry);
  }

  @override
  void Function() onNotification(
      String regex, void Function(DevNotification) onEvent) {
    this.regex = regex;
    listener = onEvent;
    return () => unsubscribes++;
  }

  @override
  Future<void> close() async => closes++;
}

class _FakeExecutor implements AtCommandExecutor {
  final sent = <String>[];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return 'data:ok';
  }
}

JSObject _options({
  Set<String> without = const {},
  Map<String, Object?> extra = const {},
}) =>
    ({
      'atSign': '@alice',
      'app': 'wavi',
      'proxyHost': 'proxy.example',
      'proxyPort': 443,
      ...extra,
    }..removeWhere((k, _) => without.contains(k)))
        .jsify() as JSObject;

JSFunction _promptResolving(String passphrase) =>
    ((JSString _) => Future.value(passphrase.toJS).toJS).toJS;

final JSFunction _promptRejecting =
    ((JSString _) => Future<JSString>.error(StateError('cancelled')).toJS).toJS;

/// dart2wasm maps JS null and undefined both to Dart null.
const _isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

JSObject get _atClientDev => globalContext['atClientDev'] as JSObject;

Future<JSAny?> _call(JSObject target, String method, [JSAny? a, JSAny? b]) =>
    (target.callMethod<JSPromise>(method.toJS, a, b)).toDart;

/// Runs [action] expecting a rejection; returns the rejection value.
Future<JSObject> _rejection(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (e) {
    return e as JSObject;
  }
  fail('expected a rejection');
}

void main() {
  late _FakeDevSession session;
  DevSessionOptions? opened;
  PassphraseSecret? passphrase;
  Object? upload;

  setUp(() {
    session = _FakeDevSession();
    opened = null;
    passphrase = null;
    upload = null;
    installAtClientDev(opener: (options, prompt, [uploadAtKeys]) async {
      opened = options;
      upload = uploadAtKeys;
      passphrase = await prompt(options.atSign);
      return session;
    });
  });

  Future<JSObject> open() async => await _call(
          _atClientDev, 'openSession', _options(), _promptResolving('pw'))
      as JSObject;

  test('T1 atClientDev.openSession is a JS function', () {
    expect(_atClientDev['openSession'].typeofEquals('function'), isTrue);
  });

  test('T2 the four options reach the opener', () async {
    await open();
    expect(opened?.atSign, '@alice');
    expect(opened?.app, 'wavi');
    expect(opened?.proxyHost, 'proxy.example');
    expect(opened?.proxyPort, 443);
  });

  test('direct mode needs no proxy and defaults the root', () async {
    await _call(
        _atClientDev,
        'openSession',
        _options(without: {'proxyHost', 'proxyPort'}, extra: {'direct': true}),
        _promptResolving('pw'));
    expect(opened?.direct, isTrue);
    expect(opened?.root, AtRootDomain.atsignDomain);
  });

  test('direct mode takes a root override', () async {
    await _call(
        _atClientDev,
        'openSession',
        _options(
            without: {'proxyHost', 'proxyPort'},
            extra: {'direct': true, 'root': 'vip.ve.atsign.zone:64'}),
        _promptResolving('pw'));
    expect(opened?.root.rootDomain, 'vip.ve.atsign.zone');
    expect(opened?.root.rootPort, 64);
  });

  test('a malformed root rejects with an Error naming it', () async {
    final error = await _rejection(() => _call(_atClientDev, 'openSession',
        _options(extra: {'root': 'host:notaport'}), _promptResolving('pw')));
    expect((error['message'] as JSString).toDart, contains('root'));
    expect(opened, isNull);
  });

  group('devTransport', () {
    test('direct resolves atSigns through the root over HTTPS', () {
      final t = devTransport(DevSessionOptions(
          atSign: '@alice',
          app: 'wavi',
          direct: true,
          root: AtRootDomain('root.example', 64)));
      expect(t.finder, isA<HttpsSecondaryAddressFinder>());
      final finder = t.finder as HttpsSecondaryAddressFinder;
      expect((finder.host, finder.port), ('root.example', 64));
    });

    test('proxy sends every atSign to the proxy', () async {
      final t = devTransport(DevSessionOptions(
          atSign: '@alice',
          app: 'wavi',
          proxyHost: 'proxy.example',
          proxyPort: 443));
      final address = await t.finder.findSecondary('@bob');
      expect((address.host, address.port), ('proxy.example', 443));
    });
  });

  test('T2 a missing option rejects with an Error naming it', () async {
    final error = await _rejection(() => _call(_atClientDev, 'openSession',
        _options(without: {'proxyPort'}), _promptResolving('pw')));
    expect(error.instanceOfString('Error'), isTrue);
    expect((error['message'] as JSString).toDart, contains('proxyPort'));
    expect(opened, isNull);
  });

  test('T2 direct defaults to false and is read when present', () async {
    await open();
    expect(opened?.direct, isFalse);

    await _call(_atClientDev, 'openSession', _options(extra: {'direct': true}),
        _promptResolving('pw'));
    expect(opened?.direct, isTrue);
  });

  test('T2 a non-boolean direct rejects with an Error naming it', () async {
    final error = await _rejection(() => _call(_atClientDev, 'openSession',
        _options(extra: {'direct': 'yes'}), _promptResolving('pw')));
    expect((error['message'] as JSString).toDart, contains('direct'));
    expect(opened, isNull);
  });

  test('an upload function reaches the opener only when the page gives one',
      () async {
    await open();
    expect(upload, isNull);

    await (_atClientDev.callMethodVarArgs<JSPromise>('openSession'.toJS, [
      _options(),
      _promptResolving('pw'),
      ((JSString _) => Future.value('{}'.toJS).toJS).toJS,
    ])).toDart;
    expect(upload, isNotNull);
  });

  test('T3 the prompt resolution reaches the opener as a PassphraseSecret',
      () async {
    await open();
    expect(passphrase?.passphrase, 'pw');
  });

  test('T3 a rejected prompt rejects openSession', () async {
    final error = await _rejection(
        () => _call(_atClientDev, 'openSession', _options(), _promptRejecting));
    expect(error.instanceOfString('Error'), isTrue);
  });

  test('T4 put then get round-trips; a miss is null, not undefined', () async {
    final js = await open();
    await _call(js, 'put', 'k'.toJS, 'v'.toJS);
    expect((await _call(js, 'get', 'k'.toJS) as JSString).toDart, 'v');

    final miss = await _call(js, 'get', 'missing'.toJS);
    expect(miss, isNull);
    if (!_isWasm) expect(miss.isNull && !miss.isUndefined, isTrue);
  });

  test('T5 a Dart error rejects with an Error carrying its type', () async {
    final js = await open();
    session.error = StateError('boom');
    final error = await _rejection(() => _call(js, 'put', 'k'.toJS, 'v'.toJS));
    expect(error.instanceOfString('Error'), isTrue);
    final message = (error['message'] as JSString).toDart;
    expect(message, startsWith('StateError: '));
    expect(message, contains('boom'));
  });

  test('T5 an AtException rejects with its AT error code', () async {
    final js = await open();
    session.error = KeyNotFoundException('k.wavi@alice');
    final error = await _rejection(() => _call(js, 'put', 'k'.toJS, 'v'.toJS));
    expect((error['message'] as JSString).toDart,
        'KeyNotFoundException: k.wavi@alice');
    expect((error['code'] as JSString).toDart, 'AT0015');
  });

  test('T6 close twice resolves twice and closes the session once', () async {
    final js = await open();
    await _call(js, 'close');
    await _call(js, 'close');
    expect(session.closes, 1);
  });

  test('T7 notify reaches the session with its expiry in milliseconds',
      () async {
    final js = await open();
    await (js.callMethodVarArgs<JSPromise>('notify'.toJS, [
      '@bob'.toJS,
      'attalk'.toJS,
      'ai6bh'.toJS,
      'hi'.toJS,
      5000.toJS,
    ])).toDart;
    expect(session.notified, (
      to: '@bob',
      key: 'attalk',
      namespace: 'ai6bh',
      value: 'hi',
      expiry: Duration(milliseconds: 5000),
    ));
  });

  test('T7 notify without an expiry passes none', () async {
    final js = await open();
    await (js.callMethodVarArgs<JSPromise>('notify'.toJS,
        ['@bob'.toJS, 'attalk'.toJS, 'ai6bh'.toJS, 'hi'.toJS])).toDart;
    expect(session.notified?.expiry, isNull);
  });

  test(
      'T8 onNotification hands the page a plain event object and returns '
      'an unsubscribe function', () async {
    final js = await open();
    final events = <JSObject>[];
    final unsubscribe = js.callMethod<JSFunction>('onNotification'.toJS,
        r'attalk\.ai6bh@'.toJS, ((JSObject e) => events.add(e)).toJS);
    expect(session.regex, r'attalk\.ai6bh@');

    session.listener!((
      from: '@bob',
      key: '@alice:attalk.ai6bh@bob',
      value: 'yo',
      epochMillis: 42,
    ));
    final event = events.single;
    expect((event['from'] as JSString).toDart, '@bob');
    expect((event['key'] as JSString).toDart, '@alice:attalk.ai6bh@bob');
    expect((event['value'] as JSString).toDart, 'yo');
    expect((event['epochMillis'] as JSNumber).toDartInt, 42);

    unsubscribe.callAsFunction();
    expect(session.unsubscribes, 1);
  });

  test('T9 proxyPreamble sends from:<atSign> and nothing else', () async {
    final executor = _FakeExecutor();
    await proxyPreamble('@alice')(executor);
    expect(executor.sent, ['from:@alice\n']);
  });
}
