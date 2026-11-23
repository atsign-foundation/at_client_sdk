import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/src/session/at_client_session.dart';
import 'package:at_client_web/src/session/keys_session_opener.dart';
import 'package:at_client_web/src/session/passkey_session_opener.dart';
import 'package:at_client_web/src/session/portal_session.dart';
import 'package:at_client_web/src/session/session_opener.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

import '../test_utils.dart' show classicalAtKeys;
import 'wire_fakes.dart' show Wire;

class _Client extends Fake implements AtClient {
  var stops = 0;

  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice', attempt: (_) async => AtConnectionState.online());

  @override
  Future<void> stop() async => stops++;

  @override
  String? getCurrentAtSign() => '@alice';
}

final SessionTransport _fakeTransport = (
  lookUps: Wire().lookUps,
  finder: FixedSecondaryAddressFinder('atserver.test', 1),
  root: AtRootDomain.atsignDomain,
);

Matcher _namingField(String field) => throwsA(isA<ArgumentError>()
    .having((e) => e.name, 'name', field)
    .having((e) => '${e.message}', 'message', isNot(contains('SECRET'))));

Map<String, dynamic> _keysJson() => classicalAtKeys().toJson();

KeysSessionOptions _keysOptions(
        {String atSign = '@alice',
        String namespace = 'MyApp',
        AtRootDomain? rootDomain,
        Map<String, dynamic>? keys}) =>
    KeysSessionOptions(
        atSign: atSign,
        namespace: namespace,
        keys: keys ?? _keysJson(),
        rootDomain: rootDomain);

void main() {
  group('options', () {
    test('keys options fold the namespace and keep the atSign in @ form', () {
      final o = _keysOptions(atSign: 'alice', namespace: 'MyApp');
      expect(o.atSign, '@alice');
      expect(o.namespace, 'myapp');
    });

    test('an invalid atSign names atSign and never echoes the value', () {
      expect(
          () => _keysOptions(atSign: 'SECRET atSign'), _namingField('atSign'));
    });

    test('an invalid namespace names namespace and never echoes the value', () {
      expect(() => _keysOptions(namespace: 'SECRET..ns'),
          _namingField('namespace'));
      expect(() => _keysOptions(namespace: ''), _namingField('namespace'));
    });

    test('a root that fails the transport rules names rootDomain', () {
      expect(() => _keysOptions(rootDomain: AtRootDomain('a b', 64)),
          _namingField('rootDomain'));
    });

    test('keys that are not a usable document name keys', () {
      expect(() => _keysOptions(keys: {'aesPkamPublicKey': 5}),
          _namingField('keys'));
    });

    test('validation runs in the order atSign, namespace, rootDomain, keys',
        () {
      expect(
          () => KeysSessionOptions(
              atSign: '!',
              namespace: '',
              keys: {'aesPkamPublicKey': 5},
              rootDomain: AtRootDomain('a b', 64)),
          _namingField('atSign'));
      expect(
          () => KeysSessionOptions(
              atSign: '@alice',
              namespace: '',
              keys: {'aesPkamPublicKey': 5},
              rootDomain: AtRootDomain('a b', 64)),
          _namingField('namespace'));
      expect(
          () => KeysSessionOptions(
              atSign: '@alice',
              namespace: 'app',
              keys: {'aesPkamPublicKey': 5},
              rootDomain: AtRootDomain('a b', 64)),
          _namingField('rootDomain'));
    });

    test('passkey options validate the atSign, namespace, rpId and rpName', () {
      final o = PasskeySessionOptions(
          atSign: 'alice', namespace: 'App', rpId: 'example.com', rpName: 'X');
      expect((o.atSign, o.namespace), ('@alice', 'app'));
      PasskeySessionOptions make(
              {String atSign = '@alice',
              String namespace = 'app',
              String rpId = 'example.com',
              String rpName = 'X'}) =>
          PasskeySessionOptions(
              atSign: atSign, namespace: namespace, rpId: rpId, rpName: rpName);
      expect(() => make(atSign: '!'), _namingField('atSign'));
      expect(() => make(namespace: ''), _namingField('namespace'));
      expect(() => make(rpId: ''), _namingField('rpId'));
      expect(() => make(rpName: ''), _namingField('rpName'));
    });

    test('options are matched exhaustively by kind', () {
      String kind(SessionOptions o) => switch (o) {
            KeysSessionOptions() => 'keys',
            PasskeySessionOptions() => 'passkey',
          };
      expect(kind(_keysOptions()), 'keys');
    });
  });

  group('KeysSessionOpener', () {
    test('opens through the given function with the folded namespace',
        () async {
      final client = _Client();
      late String seenApp;
      late String seenAtSign;
      final opener = KeysSessionOpener(
          transport: (_) => _fakeTransport,
          open: ({
            required atSign,
            required app,
            required keys,
            required transport,
          }) async {
            seenApp = app;
            seenAtSign = atSign;
            return client;
          });
      final opened = await opener.open(_keysOptions(namespace: 'MyApp'));
      expect(opened.client, same(client));
      expect((seenAtSign, seenApp), ('@alice', 'myapp'));
    });

    test('stop of the opened session stops the client', () async {
      final client = _Client();
      final opener = KeysSessionOpener(
          transport: (_) => _fakeTransport,
          open: ({
            required atSign,
            required app,
            required keys,
            required transport,
          }) async =>
              client);
      final opened = await opener.open(_keysOptions());
      await opened.stop();
      expect(client.stops, 1);
    });

    test('rejects options of another kind naming options', () {
      final opener = KeysSessionOpener(
          transport: (_) => _fakeTransport,
          open: ({
            required atSign,
            required app,
            required keys,
            required transport,
          }) async =>
              _Client());
      expect(
          opener.open(PasskeySessionOptions(
              atSign: '@alice',
              namespace: 'app',
              rpId: 'example.com',
              rpName: 'X')),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'options')));
    });
  });

  group('PasskeySessionOpener', () {
    test('opens through the login function and keeps its stop', () async {
      final client = _Client();
      var stopped = 0;
      PasskeySessionOptions? seen;
      final opener = PasskeySessionOpener(login: (options) async {
        seen = options;
        return OpenedSession(client, stop: () async => stopped++);
      });
      final options = PasskeySessionOptions(
          atSign: '@alice', namespace: 'App', rpId: 'example.com', rpName: 'X');
      final opened = await opener.open(options);
      expect(seen, same(options));
      expect(opened.client, same(client));
      await opened.stop();
      expect((stopped, client.stops), (1, 0));
    });

    test('rejects options of another kind naming options', () {
      final opener =
          PasskeySessionOpener(login: (_) async => OpenedSession(_Client()));
      expect(
          opener.open(_keysOptions()),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'options')));
    });
  });

  group('SessionOpener routing', () {
    test('a router sends each kind to its opener', () async {
      final calls = <String>[];
      final router = RoutingSessionOpener(
          keys: _Recording('keys', calls),
          passkey: _Recording('passkey', calls));
      await router.open(_keysOptions());
      await router.open(PasskeySessionOptions(
          atSign: '@alice',
          namespace: 'app',
          rpId: 'example.com',
          rpName: 'X'));
      expect(calls, ['keys', 'passkey']);
    });
  });

  group('openWrapped', () {
    KeysSessionOptions options() => KeysSessionOptions(
        atSign: '@alice', namespace: 'app', keys: _keysJson());

    test('a wrap that fails stops the opened session and rethrows its error',
        () async {
      final client = _Client();
      final opener = _Fixed(OpenedSession(client));
      final failure = StateError('wrap');
      await expectLater(
          openWrapped<void>(opener, options(), (_) => throw failure),
          throwsA(same(failure)));
      expect(client.stops, 1);
    });

    test('a stop that fails during that cleanup leaves the wrap error',
        () async {
      var stops = 0;
      final opener = _Fixed(OpenedSession(_Client(), stop: () async {
        stops++;
        throw StateError('stop');
      }));
      final failure = ArgumentError('wrap');
      await expectLater(
          openWrapped<void>(opener, options(), (_) => throw failure),
          throwsA(same(failure)));
      expect(stops, 1);
    });

    test('a wrap that succeeds leaves the session open', () async {
      final client = _Client();
      final wrapped = await openWrapped<AtClient>(
          _Fixed(OpenedSession(client)), options(), (o) => o.client);
      expect(wrapped, same(client));
      expect(client.stops, 0);
    });
  });

  group('OpenedSession', () {
    test('stop defaults to stopping the client', () async {
      final client = _Client();
      await OpenedSession(client).stop();
      expect(client.stops, 1);
    });

    test('the session close awaits the opener stop', () async {
      final client = _Client();
      final gate = Completer<void>();
      var stopped = false;
      final opened = OpenedSession(client, stop: () async {
        await gate.future;
        stopped = true;
      });
      final session =
          AtClientSession(client, namespace: 'app', stop: opened.stop);
      var closed = false;
      final closing = session.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      gate.complete();
      await closing;
      expect((stopped, closed, client.stops), (true, true, 0));
    });
  });
}

class _Recording implements SessionOpener {
  _Recording(this.name, this.calls);

  final String name;
  final List<String> calls;

  @override
  Future<OpenedSession> open(SessionOptions options) async {
    calls.add(name);
    return OpenedSession(_Client());
  }
}

class _Fixed implements SessionOpener {
  _Fixed(this.opened);

  final OpenedSession opened;

  @override
  Future<OpenedSession> open(SessionOptions options) async => opened;
}
