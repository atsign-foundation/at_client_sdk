import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

void main() {
  group('ProxySecondaryAddressFinder', () {
    final finder = ProxySecondaryAddressFinder('proxy.example.com', 8443);

    test('answers with the fixed address whatever the atSign', () async {
      expect((await finder.findSecondary('@alice')).toString(),
          'proxy.example.com:8443');
      expect((await finder.findSecondary('@bob')).toString(),
          'proxy.example.com:8443');
    });

    test('ignores the timeout, having no network to bound', () async {
      final address =
          await finder.findSecondary('@alice', timeout: Duration.zero);
      expect(address.host, 'proxy.example.com');
      expect(address.port, 8443);
    });
  });
}
