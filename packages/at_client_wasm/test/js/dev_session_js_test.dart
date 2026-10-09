@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_commons/at_commons.dart' show KeyNotFoundException;
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

JSObject _options({Set<String> without = const {}}) => ({
      'atSign': '@alice',
      'app': 'wavi',
      'proxyHost': 'proxy.example',
      'proxyPort': 443,
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

  setUp(() {
    session = _FakeDevSession();
    opened = null;
    passphrase = null;
    installAtClientDev(opener: (options, prompt) async {
      opened = options;
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

  test('T2 a missing option rejects with an Error naming it', () async {
    final error = await _rejection(() => _call(_atClientDev, 'openSession',
        _options(without: {'proxyPort'}), _promptResolving('pw')));
    expect(error.instanceOfString('Error'), isTrue);
    expect((error['message'] as JSString).toDart, contains('proxyPort'));
    expect(opened, isNull);
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

  test('T9 proxyPreamble sends from:<atSign> and nothing else', () async {
    final executor = _FakeExecutor();
    await proxyPreamble('@alice')(executor);
    expect(executor.sent, ['from:@alice\n']);
  });
}
