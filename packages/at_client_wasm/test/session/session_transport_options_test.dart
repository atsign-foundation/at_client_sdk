import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

SessionTransportOptions _options({String? proxyHost, int? proxyPort}) =>
    SessionTransportOptions(proxyHost: proxyHost, proxyPort: proxyPort);

Matcher _namingField(String field) =>
    throwsA(isA<ArgumentError>().having((e) => e.name, 'name', field));

final _sayingToBracketIpv6 = throwsA(isA<ArgumentError>().having(
    (e) => e.message, 'message', contains('in brackets, such as [::1]')));

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
        'when its host holds whitespace, a colon, a slash, ? or @, then it '
        'throws naming root', () {
      for (final domain in [
        'proxy:proxy example',
        'proxy:proxy.example:443',
        'proxy:proxy.example/ws',
        'proxy:proxy.example?',
        'proxy:localhost@other.example',
      ]) {
        expect(() => SessionTransportOptions(root: AtRootDomain(domain, 443)),
            _namingField('root'),
            reason: '"$domain" does not name a bare proxy host');
      }
    });

    test(
        'when its host is a bare IPv6 literal, or a host or bracketed IPv6 '
        'literal with a port, then it throws naming root', () {
      for (final domain in [
        'proxy:::1',
        'proxy:[::1]:443',
        'proxy:proxy.example:443',
      ]) {
        expect(() => SessionTransportOptions(root: AtRootDomain(domain, 443)),
            _namingField('root'),
            reason: '"$domain" does not name a bare proxy host');
      }
      expect(
          () => SessionTransportOptions(root: AtRootDomain('proxy:::1', 443)),
          _sayingToBracketIpv6,
          reason: 'the refusal says how to write an IPv6 proxy host');
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
        '[::1]:443',
        '[not:an:address]',
      ]) {
        expect(() => _options(proxyHost: host, proxyPort: 443),
            _namingField('proxyHost'),
            reason: '"$host" is not a bare host');
      }
    });

    test(
        'when it holds a character a URL reads as userinfo, query, fragment '
        'or path, then it throws naming proxyHost', () {
      for (final host in [
        'proxy.example?',
        'localhost@other.example',
        r'proxy.example\',
        'proxy.example#',
        'proxy.example%2f',
      ]) {
        expect(() => _options(proxyHost: host, proxyPort: 8443),
            _namingField('proxyHost'),
            reason: '"$host" would connect somewhere other than its own '
                'host and port');
      }
    });

    test('when it is a DNS name or IPv4 address, then it is the proxy', () {
      for (final host in ['vip.ve.atsign.zone', 'my-proxy_1', '127.0.0.1']) {
        expect(_options(proxyHost: host, proxyPort: 8443).proxy,
            (host: host, port: 8443));
      }
    });

    test(
        'when it is a Unicode hostname, then it throws naming proxyHost, and '
        'its punycode form is the proxy', () {
      expect(() => _options(proxyHost: 'bücher.example', proxyPort: 8443),
          _namingField('proxyHost'));
      expect(
          _options(proxyHost: 'xn--bcher-kva.example', proxyPort: 8443).proxy,
          (host: 'xn--bcher-kva.example', port: 8443));
    });

    test('when it is a bracketed IPv6 literal, then it selects the proxy', () {
      expect(_options(proxyHost: '[::1]', proxyPort: 8443).proxy,
          (host: '[::1]', port: 8443));
    });
  });

  group('Given a direct root', () {
    test(
        'when its host is empty or holds whitespace, a colon, a slash, ? or @, '
        'then it throws naming root', () {
      for (final domain in [
        '',
        ' ',
        'root example',
        'root.example:64',
        'root.example/x',
        'root.example?',
        'user@root.example',
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

    test('when its host is a bracketed IPv6 literal, then it is the root', () {
      final options =
          SessionTransportOptions(root: AtRootDomain('[2001:db8::1]', 64));

      expect(options.root.rootDomain, '[2001:db8::1]');
      expect(SessionTransportOptions(root: AtRootDomain('[::1]', 64)).proxy,
          isNull,
          reason: '[::1] is a direct root');
    });

    test(
        'when its host is a bare IPv6 literal, or a host or bracketed IPv6 '
        'literal with a port, then it throws naming root', () {
      for (final domain in ['::1', '[::1]:443', 'root.example:64']) {
        expect(() => SessionTransportOptions(root: AtRootDomain(domain, 64)),
            _namingField('root'),
            reason: '"$domain" is not a bare atDirectory host');
      }
      expect(() => SessionTransportOptions(root: AtRootDomain('::1', 64)),
          _sayingToBracketIpv6,
          reason: 'the refusal says how to write an IPv6 atDirectory host');
    });
  });

  test('a proxy: root naming a bracketed IPv6 literal selects that proxy', () {
    expect(
        SessionTransportOptions(root: AtRootDomain('proxy:[::1]', 8443)).proxy,
        (host: '[::1]', port: 8443));
  });
}
