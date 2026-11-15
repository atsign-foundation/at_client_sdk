import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

SessionTransportOptions _options({String? proxyHost, int? proxyPort}) =>
    SessionTransportOptions(proxyHost: proxyHost, proxyPort: proxyPort);

Matcher _namingField(String field) =>
    throwsA(isA<ArgumentError>().having((e) => e.name, 'name', field));

void main() {
  test('no proxyHost opens direct', () {
    expect(_options().proxy, isNull);
  });

  test('a proxyHost with a proxyPort selects the proxy', () {
    expect(_options(proxyHost: 'proxy.example', proxyPort: 443).proxy,
        (host: 'proxy.example', port: 443));
  });

  test('a proxyHost without a proxyPort throws naming proxyPort', () {
    expect(
        () => _options(proxyHost: 'proxy.example'), _namingField('proxyPort'));
  });

  test('a proxyPort without a proxyHost throws naming proxyPort', () {
    expect(() => _options(proxyPort: 443), _namingField('proxyPort'));
  });

  test('an empty proxyHost throws naming proxyHost', () {
    expect(() => _options(proxyHost: '', proxyPort: 443),
        _namingField('proxyHost'));
    expect(() => _options(proxyHost: '  ', proxyPort: 443),
        _namingField('proxyHost'));
  });

  test('a proxyPort below 1 throws naming proxyPort', () {
    expect(() => _options(proxyHost: 'proxy.example', proxyPort: 0),
        _namingField('proxyPort'));
  });

  test('a proxyPort above 65535 throws naming proxyPort', () {
    expect(() => _options(proxyHost: 'proxy.example', proxyPort: 65536),
        _namingField('proxyPort'));
    expect(_options(proxyHost: 'proxy.example', proxyPort: 65535).proxy?.port,
        65535);
  });

  test('Transport options given a root and a proxy are refused', () {
    expect(
        () => SessionTransportOptions(
            root: AtRootDomain('root.example', 64),
            proxyHost: 'proxy.example',
            proxyPort: 443),
        _namingField('root'),
        reason: 'a proxy answers for every Atsign, so a root beside it '
            'would go unused');
  });

  group('Given a proxy: root given as the root', () {
    test('when it names no host, then it throws naming root', () {
      expect(() => SessionTransportOptions(root: AtRootDomain('proxy:', 443)),
          _namingField('root'),
          reason: 'a proxy: root needs a host to connect to');
      expect(() => SessionTransportOptions(root: AtRootDomain('proxy: ', 443)),
          _namingField('root'),
          reason: 'a blank proxy: host is no host');
    });

    test('when its port is outside 1-65535, then it throws naming root', () {
      expect(
          () => SessionTransportOptions(
              root: AtRootDomain('proxy:proxy.example', 0)),
          _namingField('root'),
          reason: 'port 0 is no proxy port');
      expect(
          () => SessionTransportOptions(
              root: AtRootDomain('proxy:proxy.example', 65536)),
          _namingField('root'),
          reason: 'port 65536 is no proxy port');
    });

    test(
        'when its host holds whitespace, a colon or a slash, then it throws '
        'naming root', () {
      for (final domain in [
        'proxy:proxy example',
        'proxy:proxy.example:443',
        'proxy:proxy.example/ws',
      ]) {
        expect(() => SessionTransportOptions(root: AtRootDomain(domain, 443)),
            _namingField('root'),
            reason: '"$domain" does not name a bare proxy host');
      }
    });
  });

  group('Given a proxyHost', () {
    test(
        'when it holds whitespace, a colon or a slash, then it throws naming '
        'proxyHost', () {
      for (final host in [
        'proxy example',
        'proxy.example:443',
        'proxy.example/ws',
        'https://proxy.example',
      ]) {
        expect(() => _options(proxyHost: host, proxyPort: 443),
            _namingField('proxyHost'),
            reason: '"$host" is not a bare host');
      }
    });
  });

  group('Given a direct root', () {
    test(
        'when its host is empty or holds whitespace, a colon or a slash, then '
        'it throws naming root', () {
      for (final domain in [
        '',
        ' ',
        'root example',
        'root.example:64',
        'root.example/x',
      ]) {
        expect(() => SessionTransportOptions(root: AtRootDomain(domain, 64)),
            _namingField('root'),
            reason: '"$domain" is not a bare atDirectory host');
      }
    });

    test('when its port is outside 1-65535, then it throws naming root', () {
      for (final port in [0, 65536]) {
        expect(
            () => SessionTransportOptions(
                root: AtRootDomain('root.example', port)),
            _namingField('root'),
            reason: 'port $port is no atDirectory port');
      }
    });

    test('when its host and port are well formed, then it is the root', () {
      final options =
          SessionTransportOptions(root: AtRootDomain('root.example', 6464));

      expect((options.root.rootDomain, options.root.rootPort),
          ('root.example', 6464));
      expect(options.proxy, isNull);
    });
  });
}
