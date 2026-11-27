import 'package:at_client_web/src/session/session_options.dart';
import 'package:test/test.dart';

import '../test_utils.dart' show classicalAtKeys;

Matcher _namingField(String field) => throwsA(isA<ArgumentError>()
    .having((e) => e.name, 'name', field)
    .having((e) => '${e.message}', 'message', isNot(contains('SECRET'))));

Map<String, dynamic> _keysJson() => classicalAtKeys().toJson();

KeysSessionOptions _keysOptions(
        {String atSign = '@alice',
        String namespace = 'MyApp',
        String? rootDomain,
        String? appName,
        String? appVersion,
        Map<String, dynamic>? keys}) =>
    KeysSessionOptions(
        atSign: atSign,
        namespace: namespace,
        keys: keys ?? _keysJson(),
        appName: appName,
        appVersion: appVersion,
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
      expect(() => _keysOptions(rootDomain: 'a b'), _namingField('rootDomain'));
    });

    test('a root domain is parsed by the options, host or host:port', () {
      final bare = _keysOptions(rootDomain: 'root.example.org').rootDomain!;
      expect((bare.rootDomain, bare.rootPort), ('root.example.org', 64));
      final ported =
          _keysOptions(rootDomain: 'root.example.org:9002').rootDomain!;
      expect((ported.rootDomain, ported.rootPort), ('root.example.org', 9002));
      expect(_keysOptions().rootDomain, isNull);
    });

    test('a root domain that does not parse names rootDomain, never its value',
        () {
      for (final bad in ['', 'h:0', 'h:65536', 'a:b:c:SECRET', 'SECRET/x:1']) {
        expect(() => _keysOptions(rootDomain: bad), _namingField('rootDomain'));
      }
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
              rootDomain: 'a b'),
          _namingField('atSign'));
      expect(
          () => KeysSessionOptions(
              atSign: '@alice',
              namespace: '',
              keys: {'aesPkamPublicKey': 5},
              rootDomain: 'a b'),
          _namingField('namespace'));
      expect(
          () => KeysSessionOptions(
              atSign: '@alice',
              namespace: 'app',
              keys: {'aesPkamPublicKey': 5},
              rootDomain: 'a b'),
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

    test(
        'appName and appVersion are optional on both session forms and blank '
        'means unset', () {
      final keys = _keysOptions(appName: '  Tally  ', appVersion: '  1.2.3  ');
      expect((keys.appName, keys.appVersion), ('Tally', '1.2.3'));

      final passkey = PasskeySessionOptions(
          atSign: '@alice',
          namespace: 'app',
          rpId: 'example.com',
          rpName: 'X',
          appName: '  Tally  ',
          appVersion: '  1.2.3  ');
      expect((passkey.appName, passkey.appVersion), ('Tally', '1.2.3'));

      final absent = _keysOptions();
      expect((absent.appName, absent.appVersion), (null, null));
      final blank = _keysOptions(appName: '   ', appVersion: '');
      expect((blank.appName, blank.appVersion), (null, null));
      final passkeyBlank = PasskeySessionOptions(
          atSign: '@alice',
          namespace: 'app',
          rpId: 'example.com',
          rpName: 'X',
          appName: '   ',
          appVersion: '');
      expect((passkeyBlank.appName, passkeyBlank.appVersion), (null, null));
    });

    test('options are matched exhaustively by kind', () {
      String kind(SessionOptions o) => switch (o) {
            KeysSessionOptions() => 'keys',
            PasskeySessionOptions() => 'passkey',
          };
      expect(kind(_keysOptions()), 'keys');
      expect(
          kind(PasskeySessionOptions(
              atSign: '@alice',
              namespace: 'app',
              rpId: 'example.com',
              rpName: 'X')),
          'passkey');
    });
  });
}
