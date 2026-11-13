import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

DevSessionOptions _options({String? proxyHost, int? proxyPort}) =>
    DevSessionOptions(
        atSign: '@alice',
        app: 'wavi',
        proxyHost: proxyHost,
        proxyPort: proxyPort);

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
}
