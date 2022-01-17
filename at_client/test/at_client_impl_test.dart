import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  group('A group of at client impl create tests', () {
    test('test current atsign', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()..syncRegex = '.wavi';
      AtClient atClient = await AtClientImpl.create(
          atClientManager, atSign, 'wavi', preference);
      expect(atClient.getCurrentAtSign(), atSign);
    });
    test('test preference', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()..syncRegex = '.wavi';
      AtClient atClient = await AtClientImpl.create(
          atClientManager, atSign, 'wavi', preference);
      expect(atClient.getPreferences()!.syncRegex, '.wavi');
    });
  });
}
